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
    @EnvironmentObject private var preferences: MomentsPreferences
    @Environment(\.colorScheme) private var colorScheme

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
        let theme = MomentsPalette.make(mode: preferences.appearance, colorScheme: colorScheme)

        VStack(spacing: 0) {
            MomentsHeader(
                title: "Vonalkódok",
                subtitle: total > 0 ? "\(total) nyomtatható termék" : "Termékcímkék közvetlenül a T02-re",
                systemImage: "barcode.viewfinder"
            )

            ScrollView {
                LazyVStack(spacing: 12) {
                    printerPanel(theme)
                    searchPanel(theme)

                    if isLoading && products.isEmpty {
                        MomentsCard {
                            HStack(spacing: 12) {
                                ProgressView().tint(theme.accent)
                                Text("Vonalkódos termékek betöltése…")
                                    .foregroundStyle(theme.text)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    } else if let errorMessage, products.isEmpty {
                        MomentsCard {
                            VStack(spacing: 12) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 30))
                                    .foregroundStyle(theme.warning)
                                Text(errorMessage)
                                    .font(.subheadline)
                                    .foregroundStyle(theme.text)
                                    .multilineTextAlignment(.center)
                                Button("Újrapróbálom") { loadProducts(reset: true) }
                                    .buttonStyle(MomentsPrimaryButtonStyle())
                            }
                            .frame(maxWidth: .infinity)
                        }
                    } else if products.isEmpty {
                        MomentsCard {
                            VStack(spacing: 9) {
                                Image(systemName: "barcode")
                                    .font(.system(size: 34, weight: .medium))
                                    .foregroundStyle(theme.accent)
                                Text(loadedSearch.isEmpty
                                     ? "Nincs még nyomtatható kasszavonalkód."
                                     : "Nincs találat erre a keresésre.")
                                    .foregroundStyle(theme.text)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    } else {
                        ForEach(products) { product in
                            productCard(product, theme: theme)
                        }

                        if page < pages {
                            Button {
                                loadProducts(reset: false)
                            } label: {
                                HStack(spacing: 8) {
                                    if isLoading { ProgressView().tint(.white) }
                                    Text(isLoading ? "Betöltés…" : "További termékek betöltése")
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(MomentsPrimaryButtonStyle())
                            .disabled(isLoading)
                        }

                        Text("\(total) vonalkódos termék")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(theme.secondaryText)
                            .padding(.vertical, 5)
                    }
                }
                .padding(14)
            }
            .background(theme.background)
            .refreshable { loadProducts(reset: true) }
        }
        .background(theme.background.ignoresSafeArea())
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
            if preferences.autoScanPrinter { printer.startIfPossible() }
            if !firstLoadRequested {
                firstLoadRequested = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    loadProducts(reset: true)
                }
            }
        }
    }

    private func printerPanel(_ theme: MomentsPalette) -> some View {
        MomentsCard {
            VStack(alignment: .leading, spacing: 11) {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("T02 nyomtató")
                            .font(.headline)
                            .foregroundStyle(theme.text)
                        MomentsStatusPill(
                            ready: printer.isReady,
                            text: printer.isReady ? "Nyomtatásra kész" : printer.status
                        )
                    }
                    Spacer()
                    Image(systemName: printer.isReady ? "printer.fill" : "printer")
                        .font(.system(size: 25, weight: .semibold))
                        .foregroundStyle(printer.isReady ? theme.good : theme.accent)
                }

                if !printer.isReady {
                    Button {
                        printer.scan()
                    } label: {
                        Label(printer.isScanning ? "Keresés…" : "T02 keresése", systemImage: "dot.radiowaves.left.and.right")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(MomentsPrimaryButtonStyle())
                    .disabled(printer.isScanning || printer.isPrinting)

                    ForEach(printer.devices) { device in
                        Button {
                            printer.connect(to: device.id)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(device.name).fontWeight(.semibold)
                                    Text("Jelerősség: \(device.rssi) dBm")
                                        .font(.caption)
                                }
                                Spacer()
                                Image(systemName: "link")
                            }
                            .foregroundStyle(theme.text)
                            .padding(10)
                            .background(theme.surfaceAlt)
                            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(printer.isPrinting)
                    }
                }
            }
        }
    }

    private func searchPanel(_ theme: MomentsPalette) -> some View {
        MomentsCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Termék keresése")
                    .font(.headline)
                    .foregroundStyle(theme.text)

                HStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(theme.secondaryText)
                        TextField("Név, SKU vagy vonalkód", text: $searchText)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .foregroundStyle(theme.text)
                            .onSubmit { loadProducts(reset: true) }
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 10)
                    .background(theme.field)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(theme.border, lineWidth: 1)
                    )

                    Button {
                        loadProducts(reset: true)
                    } label: {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 16, weight: .bold))
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(MomentsPrimaryButtonStyle())
                    .disabled(isLoading)
                }

                if !loadedSearch.isEmpty {
                    HStack {
                        Label(loadedSearch, systemImage: "line.3.horizontal.decrease.circle")
                            .font(.caption)
                            .foregroundStyle(theme.secondaryText)
                        Spacer()
                        Button("Szűrés törlése") {
                            searchText = ""
                            loadProducts(reset: true)
                        }
                        .font(.caption.weight(.semibold))
                        .tint(theme.accent)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func productCard(_ product: BarcodeLabelProduct, theme: MomentsPalette) -> some View {
        MomentsCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    if let url = URL(string: product.image), !product.image.isEmpty {
                        AsyncImage(url: url) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            ZStack {
                                theme.surfaceAlt
                                Image(systemName: "photo")
                                    .foregroundStyle(theme.secondaryText)
                            }
                        }
                        .frame(width: 62, height: 62)
                        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                    } else {
                        ZStack {
                            theme.surfaceAlt
                            Image(systemName: "cube.box.fill")
                                .foregroundStyle(theme.accent)
                        }
                        .frame(width: 62, height: 62)
                        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                    }

                    VStack(alignment: .leading, spacing: 5) {
                        Text(product.name)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(theme.text)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(product.barcode)
                            .font(.system(.footnote, design: .monospaced).weight(.bold))
                            .foregroundStyle(theme.accent)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(theme.surfaceAlt)
                            .clipShape(Capsule())

                        HStack(spacing: 8) {
                            if !product.sku.isEmpty { Text("SKU: \(product.sku)") }
                            if !product.formattedPrice.isEmpty { Text(product.formattedPrice) }
                        }
                        .font(.caption)
                        .foregroundStyle(theme.secondaryText)
                    }
                    Spacer(minLength: 0)
                }

                Divider().overlay(theme.border)

                HStack(spacing: 12) {
                    Stepper(value: quantityBinding(for: product.id), in: 1...100) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Címkedarab")
                                .font(.caption)
                                .foregroundStyle(theme.secondaryText)
                            Text("\(quantity(for: product.id)) db")
                                .font(.subheadline.weight(.bold).monospacedDigit())
                                .foregroundStyle(theme.text)
                        }
                    }
                    .tint(theme.accent)

                    Button {
                        print(product)
                    } label: {
                        Label("Nyomtatás", systemImage: "printer.fill")
                    }
                    .buttonStyle(MomentsPrimaryButtonStyle())
                    .disabled(!printer.isReady || printer.isPrinting)
                }
            }
        }
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
