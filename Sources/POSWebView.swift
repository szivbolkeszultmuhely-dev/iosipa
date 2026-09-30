import SwiftUI
import WebKit
import UIKit
import Combine
import PDFKit

/// Stage 2A: display the EXISTING authenticated WordPress POS in the native app.
/// Preserves the WordPress cashier and intercepts only its authenticated PDF
/// preview button within this app. The original WordPress plugin is unchanged.
final class POSWebModel: NSObject, ObservableObject {
    static let posURL = URL(string: "https://szivbolkeszult.hu/moments-pos-kassza/")!
    private static let allowedHosts: Set<String> = ["szivbolkeszult.hu", "www.szivbolkeszult.hu"]

    @Published private(set) var isLoading = false
    @Published private(set) var initialPageReady = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var pdfIsLoading = false
    @Published private(set) var pdfError: String?
    @Published var receivedPDF: ReceivedReceiptPDF?

    private var hasLoaded = false

    // Keep the same WKWebView and persistent cookies when switching tabs.
    // Creating a fresh WKWebView on every tab switch could lose form state.
    lazy var webView: WKWebView = {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore.default()
        config.allowsInlineMediaPlayback = true
        config.userContentController.add(self, name: "momentsPDF")
        config.userContentController.add(self, name: "momentsReady")
        config.suppressesIncrementalRendering = false
        config.userContentController.addUserScript(
            WKUserScript(source: ReceiptBridge.userScript,
                         injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        )
        // Signal as soon as the DOM is usable instead of waiting for every remote
        // image/font/resource to finish. This lets the branded loader disappear sooner.
        let readyScript = """
        (() => {
          const signalReady = () => {
            try { window.webkit.messageHandlers.momentsReady.postMessage('dom-ready'); } catch (_) {}
          };
          if (document.readyState === 'loading') {
            document.addEventListener('DOMContentLoaded', signalReady, { once: true });
          } else {
            signalReady();
          }
        })();
        """
        config.userContentController.addUserScript(
            WKUserScript(source: readyScript, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        )

        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = self
        view.uiDelegate = self
        // This app is a dedicated POS shell, not a general web browser.
        // WKWebView's browser-style edge swipes can compete with iOS system
        // gestures (including notification/banner interactions), so keep them off.
        view.allowsBackForwardNavigationGestures = false
        view.scrollView.keyboardDismissMode = .interactive
        // Do not make the embedded web view more aggressive than a normal Safari page
        // about owning touches. iOS system overlays / notification gestures stay primary.
        view.scrollView.panGestureRecognizer.cancelsTouchesInView = false
        view.scrollView.panGestureRecognizer.delaysTouchesBegan = false
        return view
    }()

    func loadIfNeeded() {
        guard !hasLoaded else { return }
        hasLoaded = true
        webView.load(URLRequest(
            url: Self.posURL,
            cachePolicy: .useProtocolCachePolicy,
            timeoutInterval: 15
        ))
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

    func isOurWebsite(_ url: URL) -> Bool {
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

extension POSWebModel: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard message.webView === webView else { return }

        if message.name == "momentsReady" {
            if let url = webView.url, isOurWebsite(url) {
                initialPageReady = true
            }
            return
        }

        guard message.name == "momentsPDF",
              let url = webView.url, isOurWebsite(url),
              let payload = message.body as? [String: Any],
              let kind = payload["kind"] as? String else { return }
        switch kind {
        case "started":
            pdfIsLoading = true
            pdfError = nil
        case "error":
            pdfIsLoading = false
            let message = payload["message"] as? String ?? "A PDF átvétele sikertelen."
            pdfError = String(message.prefix(300))
        case "pdf":
            pdfIsLoading = false
            guard let receiptID = payload["receiptID"] as? Int, receiptID > 0,
                  let encoded = payload["base64"] as? String,
                  encoded.count <= 8_400_000,
                  let bytes = Data(base64Encoded: encoded),
                  bytes.count <= 6 * 1024 * 1024,
                  bytes.starts(with: Data("%PDF-".utf8)),
                  let document = PDFDocument(data: bytes),
                  document.pageCount > 0, !document.isLocked else {
                pdfError = "A kapott fájl nem érvényes PDF. Nem kerül nyomtatásra."
                return
            }
            let intent = payload["intent"] as? String ?? "preview"
            receivedPDF = ReceivedReceiptPDF(receiptID: receiptID, data: bytes,
                                             pageCount: document.pageCount,
                                             printImmediately: intent == "print")
        default:
            break
        }
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
        initialPageReady = true
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
        initialPageReady = true
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
        initialPageReady = true
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
    @EnvironmentObject private var preferences: MomentsPreferences
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let theme = MomentsPalette.make(mode: preferences.appearance, colorScheme: colorScheme)

        VStack(spacing: 0) {
            MomentsHeader(
                title: "Moments POS · Kassza",
                subtitle: "Eredeti PDF és közvetlen T02-nyomtatás a kasszából.",
                systemImage: "creditcard.fill",
                reloadAction: { model.reload() }
            )

            // Keep a fixed-height loading lane so navigation never pushes the cashier
            // content up/down. The thin indicator appears without layout jumping.
            ZStack {
                theme.surface
                if model.isLoading {
                    ProgressView()
                        .progressViewStyle(.linear)
                        .tint(theme.accent2)
                        .padding(.horizontal, 8)
                }
            }
            .frame(height: 4)

            if model.pdfIsLoading {
                HStack(spacing: 8) {
                    ProgressView().tint(theme.accent)
                    Text("Az eredeti PDF átvétele…")
                }
                .font(.footnote.weight(.medium))
                .foregroundStyle(theme.text)
                .padding(8)
                .frame(maxWidth: .infinity)
                .background(theme.surfaceAlt)
            }

            if let pdfError = model.pdfError {
                Text(pdfError)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity)
                    .background(theme.surface)
            }

            if let errorMessage = model.errorMessage {
                VStack(spacing: 10) {
                    Text(errorMessage)
                        .font(.subheadline)
                        .foregroundStyle(theme.text)
                        .multilineTextAlignment(.center)
                    HStack(spacing: 14) {
                        Button("Újratöltés") { model.reload() }
                            .buttonStyle(MomentsPrimaryButtonStyle())
                        Button("Megnyitás Safariban") { model.openInSafari() }
                            .buttonStyle(.bordered)
                            .tint(theme.accent)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity)
                .background(theme.surface)
            }

            // IMPORTANT: the WordPress cashier itself is not restyled.
            // Only the native shell around the validated web cashier changes.
            POSWebContainer(model: model)
        }
        .background(theme.background)
        .onAppear { model.loadIfNeeded() }
        .sheet(item: $model.receivedPDF) { receipt in
            ReceiptPDFPreview(receipt: receipt)
        }
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
