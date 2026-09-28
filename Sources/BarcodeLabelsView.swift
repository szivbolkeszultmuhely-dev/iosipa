import SwiftUI
import WebKit

struct BarcodeLabelProduct: Identifiable, Decodable, Hashable {
    let id: Int
    let name: String
    let sku: String
    let barcode: String
    let price: Double?
    let formattedPrice: String
    let image: String
    let variation: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, sku, barcode, price, image, variation
        case formattedPrice = "formatted_price"
    }
}

struct BarcodeLabelPage: Decodable {
    let items: [BarcodeLabelProduct]
    let page: Int
    let perPage: Int
    let pages: Int
    let total: Int

    enum CodingKeys: String, CodingKey {
        case items, page, pages, total
        case perPage = "per_page"
    }
}

enum BarcodeLabelAPIError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let text): return text
        }
    }
}

extension POSWebModel {
    /// Fetch through the already authenticated POS WKWebView. This deliberately
    /// reuses its WordPress cookie + REST nonce instead of storing WP credentials
    /// in native code.
    func fetchBarcodeLabelProducts(
        search: String,
        page: Int,
        perPage: Int = 50,
        completion: @escaping (Result<BarcodeLabelPage, Error>) -> Void
    ) {
        loadIfNeeded()

        let script = """
        const config = window.MPC_POS_CONFIG;
        if (!config || typeof config.nonce !== 'string' || !config.nonce ||
            typeof config.restUrl !== 'string' || !config.restUrl) {
            return JSON.stringify({
                ok: false,
                status: 401,
                payload: {message: 'Előbb nyisd meg a Kassza fület, és jelentkezz be a Moments POS-ba.'}
            });
        }
        const query = new URLSearchParams();
        query.set('page', String(pageNumber));
        query.set('per_page', String(perPageValue));
        if (String(searchTerm || '').trim()) query.set('search', String(searchTerm).trim());

        const response = await fetch(config.restUrl + '/label-products?' + query.toString(), {
            method: 'GET',
            headers: {'Accept': 'application/json', 'X-WP-Nonce': config.nonce},
            credentials: 'same-origin',
            cache: 'no-store'
        });
        let payload = {};
        try { payload = await response.json(); }
        catch (_) { payload = {message: 'A szerver nem értelmezhető választ adott.'}; }

        return JSON.stringify({ok: response.ok, status: response.status, payload});
        """

        webView.callAsyncJavaScript(
            script,
            arguments: [
                "searchTerm": search,
                "pageNumber": max(1, page),
                "perPageValue": min(100, max(1, perPage))
            ],
            in: nil,
            in: .page
        ) { result in
            DispatchQueue.main.async {
                switch result {
                case .failure(let error):
                    completion(.failure(BarcodeLabelAPIError.message(
                        "A terméklista nem tölthető be: \(error.localizedDescription)"
                    )))
                case .success(let value):
                    guard let json = value as? String,
                          let data = json.data(using: .utf8),
                          let envelope = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let ok = envelope["ok"] as? Bool,
                          let payload = envelope["payload"] as? [String: Any] else {
                        completion(.failure(BarcodeLabelAPIError.message(
                            "A terméklista válasza nem értelmezhető."
                        )))
                        return
                    }

                    if !ok {
                        let message = payload["message"] as? String
                            ?? "A vonalkódcímkék terméklistája nem érhető el."
                        completion(.failure(BarcodeLabelAPIError.message(message)))
                        return
                    }

                    do {
                        let payloadData = try JSONSerialization.data(withJSONObject: payload)
                        let page = try JSONDecoder().decode(BarcodeLabelPage.self, from: payloadData)
                        completion(.success(page))
                    } catch {
                        completion(.failure(BarcodeLabelAPIError.message(
                            "A terméklista feldolgozása sikertelen: \(error.localizedDescription)"
                        )))
                    }
                }
            }
        }
    }
}

struct BarcodeLabelsView: View {
    @ObservedObject var posWeb: POSWebModel
    @EnvironmentObject private var printer: T02Printer

    @State private var products: [BarcodeLabelProduct] = []
    @State private var quantities: [Int: Int] = [:]
    @State private var searchText = ""
    @State private var loadedSearch = ""
    @State private var page = 1
    @State private var pages = 1
    @State private var total = 0
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var printMessage: String?
    @State private var firstLoadRequested = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                printerPanel
                Divider()
                searchPanel

                if isLoading && products.isEmpty {
                    Spacer()
                    ProgressView("Vonalkódos termékek betöltése…")
                    Spacer()
                } else if let errorMessage, products.isEmpty {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle).foregroundStyle(.orange)
                        Text(errorMessage)
                            .font(.subheadline)
                            .multilineTextAlignment(.center)
                        Button("Újrapróbálom") { loadProducts(reset: true) }
                            .buttonStyle(.borderedProminent)
                    }
                    .padding(24)
                    Spacer()
                } else if products.isEmpty {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "barcode")
                            .font(.largeTitle).foregroundStyle(.secondary)
                        Text(loadedSearch.isEmpty
                             ? "Nincs még nyomtatható kasszavonalkód."
                             : "Nincs találat erre a keresésre.")
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(products) { product in
                                productCard(product)
                            }

                            if page < pages {
                                Button {
                                    loadProducts(reset: false)
                                } label: {
                                    if isLoading {
                                        ProgressView()
                                    } else {
                                        Text("További termékek betöltése")
                                    }
                                }
                                .buttonStyle(.bordered)
                                .padding(.vertical, 8)
                                .disabled(isLoading)
                            }

                            Text("\(total) vonalkódos termék")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.bottom, 14)
                        }
                        .padding(12)
                    }
                    .refreshable { loadProducts(reset: true) }
                }
            }
            .navigationTitle("Vonalkódok")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Vonalkódnyomtatás", isPresented: Binding(
                get: { printMessage != nil },
                set: { if !$0 { printMessage = nil } }
            )) {
                Button("OK") { printMessage = nil }
            } message: {
                Text(printMessage ?? "")
            }
            .onAppear {
                posWeb.loadIfNeeded()
                printer.startIfPossible()
                if !firstLoadRequested {
                    firstLoadRequested = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        loadProducts(reset: true)
                    }
                }
            }
        }
    }

    private var printerPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle()
                    .fill(printer.isReady ? Color.green : Color.orange)
                    .frame(width: 9, height: 9)
                Text(printer.isReady ? "T02 nyomtatásra kész" : printer.status)
                    .font(.footnote)
                    .lineLimit(2)
                Spacer()
                if !printer.isReady {
                    Button(printer.isScanning ? "Keresés…" : "T02 keresése") {
                        printer.scan()
                    }
                    .buttonStyle(.bordered)
                    .disabled(printer.isScanning || printer.isPrinting)
                }
            }

            if !printer.isReady {
                ForEach(printer.devices) { device in
                    Button("Csatlakozás: \(device.name)") {
                        printer.connect(to: device.id)
                    }
                    .buttonStyle(.bordered)
                    .disabled(printer.isPrinting)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var searchPanel: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                TextField("Terméknév, SKU vagy vonalkód", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit { loadProducts(reset: true) }

                Button("Keresés") { loadProducts(reset: true) }
                    .buttonStyle(.borderedProminent)
                    .disabled(isLoading)
            }

            if !loadedSearch.isEmpty {
                HStack {
                    Text("Szűrés: \(loadedSearch)")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Törlés") {
                        searchText = ""
                        loadProducts(reset: true)
                    }
                    .font(.caption)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func productCard(_ product: BarcodeLabelProduct) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                if let url = URL(string: product.image), !product.image.isEmpty {
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Color.secondary.opacity(0.12)
                    }
                    .frame(width: 54, height: 54)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(product.name)
                        .font(.subheadline.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(product.barcode)
                        .font(.system(.footnote, design: .monospaced).weight(.semibold))
                    HStack(spacing: 8) {
                        if !product.sku.isEmpty {
                            Text("SKU: \(product.sku)")
                        }
                        if !product.formattedPrice.isEmpty {
                            Text(product.formattedPrice)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 12) {
                Stepper(
                    value: quantityBinding(for: product.id),
                    in: 1...100
                ) {
                    Text("\(quantity(for: product.id)) db")
                        .font(.subheadline.monospacedDigit())
                        .frame(minWidth: 46, alignment: .leading)
                }

                Button {
                    print(product)
                } label: {
                    Label("Nyomtatás", systemImage: "printer.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!printer.isReady || printer.isPrinting)
            }
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func quantity(for id: Int) -> Int {
        min(100, max(1, quantities[id] ?? 1))
    }

    private func quantityBinding(for id: Int) -> Binding<Int> {
        Binding(
            get: { quantity(for: id) },
            set: { quantities[id] = min(100, max(1, $0)) }
        )
    }

    private func print(_ product: BarcodeLabelProduct) {
        let count = quantity(for: product.id)
        do {
            let job = try T02BarcodeLabelRaster.makeJob(code: product.barcode, quantity: count)
            printer.printLabelRaster(job, quantity: count)
        } catch {
            printMessage = error.localizedDescription
        }
    }

    private func loadProducts(reset: Bool) {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        let requestedPage = reset ? 1 : page + 1
        let requestedSearch = reset ? searchText.trimmingCharacters(in: .whitespacesAndNewlines) : loadedSearch

        posWeb.fetchBarcodeLabelProducts(search: requestedSearch, page: requestedPage, perPage: 50) { result in
            isLoading = false
            switch result {
            case .failure(let error):
                if reset { products = [] }
                errorMessage = error.localizedDescription
            case .success(let response):
                if reset {
                    products = response.items
                    loadedSearch = requestedSearch
                } else {
                    let existing = Set(products.map(\.id))
                    products.append(contentsOf: response.items.filter { !existing.contains($0.id) })
                }
                page = response.page
                pages = response.pages
                total = response.total
                for item in response.items where quantities[item.id] == nil {
                    quantities[item.id] = 1
                }
            }
        }
    }
}
