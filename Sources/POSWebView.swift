import SwiftUI
import WebKit
import UIKit
import Combine

/// Stage 2A: display the EXISTING authenticated WordPress POS in the native app.
/// Does not generate receipts, intercept POS buttons or alter the verified
/// T02 raster protocol. PDF printing is a separate, later integration step.
final class POSWebModel: NSObject, ObservableObject {
    static let posURL = URL(string: "https://szivbolkeszult.hu/moments-pos-kassza/")!
    private static let allowedHosts: Set<String> = ["szivbolkeszult.hu", "www.szivbolkeszult.hu"]

    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private var hasLoaded = false

    // Keep the same WKWebView and persistent cookies when switching tabs.
    // Creating a fresh WKWebView on every tab switch could lose form state.
    lazy var webView: WKWebView = {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore.default()
        config.allowsInlineMediaPlayback = true

        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = self
        view.uiDelegate = self
        view.allowsBackForwardNavigationGestures = true
        view.scrollView.keyboardDismissMode = .interactive
        return view
    }()

    func loadIfNeeded() {
        guard !hasLoaded else { return }
        hasLoaded = true
        webView.load(URLRequest(url: Self.posURL, cachePolicy: .useProtocolCachePolicy))
    }

    func reload() {
        errorMessage = nil
        if webView.url == nil {
            hasLoaded = false
            loadIfNeeded()
        } else {
            webView.reload()
        }
    }

    func openInSafari() {
        UIApplication.shared.open(Self.posURL)
    }

    private func isOurWebsite(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased() else { return false }
        return Self.allowedHosts.contains(host)
    }

    private func present(_ alert: UIAlertController, completionIfUnavailable: () -> Void) {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let scene = scenes.first(where: { $0.activationState == .foregroundActive }),
              let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController else {
            completionIfUnavailable()
            return
        }
        var top = root
        while let presented = top.presentedViewController { top = presented }
        top.present(alert, animated: true)
    }
}

extension POSWebModel: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        isLoading = true
        errorMessage = nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isLoading = false
        errorMessage = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        navigationError(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        navigationError(error)
    }

    private func navigationError(_ error: Error) {
        // -999: a previous request was cancelled by a newer navigation.
        if (error as NSError).code == NSURLErrorCancelled { return }
        isLoading = false
        errorMessage = "Nem sikerült betölteni a kasszát: \(error.localizedDescription)"
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }
        // Normal navigation and WordPress login stay within our HTTPS domain.
        if isOurWebsite(url) {
            decisionHandler(.allow)
            return
        }
        // These are needed by some pages for internal downloads or empty tabs.
        if url.scheme == "about" || url.scheme == "blob" {
            decisionHandler(.allow)
            return
        }
        // Do not silently load third-party sites within the logged-in POS webview.
        if ["https", "http", "mailto", "tel"].contains(url.scheme?.lowercased() ?? "") {
            UIApplication.shared.open(url)
        }
        decisionHandler(.cancel)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        isLoading = false
        errorMessage = "A kassza nézete váratlanul leállt. Koppints az Újratöltés gombra."
    }
}

extension POSWebModel: WKUIDelegate {
    // WordPress may open logout links or PDFs in a new tab. For same-domain
    // targets, reuse the POS webview; unrelated domains open in Safari.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard navigationAction.targetFrame == nil,
              let url = navigationAction.request.url else { return nil }
        if isOurWebsite(url) {
            webView.load(navigationAction.request)
        } else if ["https", "http"].contains(url.scheme?.lowercased() ?? "") {
            UIApplication.shared.open(url)
        }
        return nil
    }

    // iOS presents its normal, user-controlled permission prompt for the
    // web-based barcode scanner. Camera access is NOT granted automatically.
    @available(iOS 15.0, *)
    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedBy frame: WKFrameInfo, type: WKMediaCaptureType,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        decisionHandler(.prompt)
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let alert = UIAlertController(title: "Moments POS", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
        present(alert, completionIfUnavailable: completionHandler)
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let alert = UIAlertController(title: "Moments POS", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Mégsem", style: .cancel) { _ in completionHandler(false) })
        alert.addAction(UIAlertAction(title: "Rendben", style: .default) { _ in completionHandler(true) })
        present(alert, completionIfUnavailable: { completionHandler(false) })
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String,
                 defaultText: String?, initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (String?) -> Void) {
        let alert = UIAlertController(title: "Moments POS", message: prompt, preferredStyle: .alert)
        alert.addTextField { field in field.text = defaultText }
        alert.addAction(UIAlertAction(title: "Mégsem", style: .cancel) { _ in completionHandler(nil) })
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
            completionHandler(alert.textFields?.first?.text)
        })
        present(alert, completionIfUnavailable: { completionHandler(nil) })
    }
}

struct POSWebScreen: View {
    @ObservedObject var model: POSWebModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Moments POS · Kassza").font(.headline)
                    Text("1/3: a webes kassza megjelenítése. A valódi PDF-nyomtatás még nincs bekötve.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                Button { model.reload() } label: {
                    Image(systemName: "arrow.clockwise").font(.title3)
                }
                .accessibilityLabel("Kassza újratöltése")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            if model.isLoading { ProgressView().frame(maxWidth: .infinity) }

            if let errorMessage = model.errorMessage {
                VStack(spacing: 10) {
                    Text(errorMessage).font(.subheadline).multilineTextAlignment(.center)
                    HStack(spacing: 14) {
                        Button("Újratöltés") { model.reload() }
                            .buttonStyle(.borderedProminent)
                        Button("Megnyitás Safariban") { model.openInSafari() }
                            .buttonStyle(.bordered)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity)
            }

            POSWebContainer(model: model)
        }
        .onAppear { model.loadIfNeeded() }
    }
}

private struct POSWebContainer: UIViewRepresentable {
    let model: POSWebModel

    func makeUIView(context: Context) -> WKWebView {
        model.loadIfNeeded()
        return model.webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        // Preserve the logged-in page and unfinished POS forms on tab changes.
    }
}
