import Foundation
import SwiftUI
import PDFKit
import WebKit

// Integration stage 3B: same authenticated original PDF, now optionally
// printable after explicit confirmation. No checkout state changes, no new receipts.
struct ReceivedReceiptPDF: Identifiable {
    let id = UUID()
    let receiptID: Int
    let data: Data
    let pageCount: Int
    /// True only when the user pressed the POS checkout/archive T02 button.
    let printImmediately: Bool
}

struct ReceiptPDFPreview: View {
    let receipt: ReceivedReceiptPDF
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var printer: T02Printer
    @State private var isPreparing = false
    @State private var showConfirmation = false
    @State private var printError: String?
    @State private var autoPrintStarted = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Text(receipt.printImmediately
                     ? "Kasszából indított nyomtatás: a PDF automatikusan a T02-re kerül, amint a nyomtató csatlakozott."
                     : "Az archivált nyugta eredeti PDF-je. A nyomtatás csak külön megerősítés után indul.")
                    .font(.footnote).foregroundStyle(.secondary).padding(10)
                ReceiptPDFView(data: receipt.data)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                VStack(spacing: 10) {
                    if !printer.isReady {
                        HStack {
                            Text(printer.status).font(.footnote).lineLimit(2)
                            Spacer(minLength: 8)
                            Button(printer.isScanning ? "Keresés…" : "T02 keresése") { printer.scan() }
                                .disabled(printer.isScanning || printer.isPrinting)
                        }
                        ForEach(printer.devices) { device in
                            Button("Csatlakozás: \(device.name)") { printer.connect(to: device.id) }
                                .buttonStyle(.bordered).disabled(printer.isPrinting)
                        }
                    }
                    if let printError {
                        Text(printError).font(.footnote).foregroundStyle(.red)
                    }
                    Button {
                        showConfirmation = true
                    } label: {
                        HStack {
                            if isPreparing || printer.isPrinting { ProgressView().tint(.white) }
                            Image(systemName: "printer.fill")
                            Text(isPreparing ? "PDF előkészítése…" :
                                 printer.isPrinting ? "Nyomtatási adatok küldése…" : "Nyugta nyomtatása · T02")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!printer.isReady || isPreparing || printer.isPrinting)
                    Text(printer.status)
                        .font(.caption).foregroundStyle(.secondary).lineLimit(3)
                    if !printer.isPrinting {
                        Text("Küldés után ellenőrizd, hogy a teljes nyugta olvashatóan kijött-e. Hibánál ne indíts automatikus újranyomtatást.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .padding(12)
            }
            .navigationTitle("Nyugta PDF · #\(receipt.receiptID)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Bezárás") { dismiss() }.disabled(isPreparing)
                }
            }
            .alert("Nyugta nyomtatása", isPresented: $showConfirmation) {
                Button("Küldés a T02-re") { sendPDFToPrinter() }
                Button("Mégsem", role: .cancel) { }
            } message: {
                Text("A már archivált #\(receipt.receiptID) nyugta teljes PDF-jét küldjük ki. Nem keletkezik új nyugta.")
            }
            .onAppear {
                printer.startIfPossible()
                attemptAutomaticPrint()
            }
            .onChange(of: printer.status) { _ in
                attemptAutomaticPrint()
            }
        }
    }

    // A tap on the checkout's native T02 button is the user's print approval.
    // The page fetches the original PDF once; this view starts sending once and
    // never retries automatically when the printer or network has a problem.
    private func attemptAutomaticPrint() {
        guard receipt.printImmediately, !autoPrintStarted, printer.isReady,
              !printer.isPrinting else { return }
        autoPrintStarted = true
        sendPDFToPrinter()
    }

    private func sendPDFToPrinter() {
        guard !isPreparing, !printer.isPrinting, printer.isReady else { return }
        isPreparing = true
        printError = nil
        let pdfBytes = receipt.data
        let receiptID = receipt.receiptID
        // Rasterizing a long PDF can take time. Never block the cashier UI.
        DispatchQueue.global(qos: .userInitiated).async {
            let outcome = Result { try T02PDFRaster.makeJob(fromPDF: pdfBytes) }
            DispatchQueue.main.async {
                isPreparing = false
                switch outcome {
                case .success(let job):
                    guard printer.isReady && !printer.isPrinting else {
                        printError = "A T02 időközben lecsatlakozott vagy foglalt. Nem küldtünk nyomtatási adatot."
                        return
                    }
                    printer.printReceiptRaster(job, receiptID: receiptID)
                case .failure(let error):
                    printError = error.localizedDescription
                }
            }
        }
    }
}

private struct ReceiptPDFView: UIViewRepresentable {
    let data: Data

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.backgroundColor = .systemGroupedBackground
        pdfView.autoScales = true
        pdfView.displayDirection = .vertical
        pdfView.displaysAsBook = false
        pdfView.document = PDFDocument(data: data)
        return pdfView
    }

    func updateUIView(_ view: PDFView, context: Context) { }
}

enum ReceiptBridge {
    // Runs inside the POS document only. The same-origin fetch uses the same
    // authenticated browser session and the nonce already used by the POS.
    // The existing PDF button is intercepted ONLY within this native app;
    // Safari and the standard WordPress site are not changed.
    static let userScript = #"""
    (() => {
      'use strict';
      if (window.__momentsNativePDFBridgeInstalled) return;
      if (!['szivbolkeszult.hu', 'www.szivbolkeszult.hu'].includes(location.hostname)) return;
      if (location.protocol !== 'https:') return;
      if (!window.webkit?.messageHandlers?.momentsPDF) return;
      window.__momentsNativePDFBridgeInstalled = true;
      let busy = false;
      const send = message => window.webkit.messageHandlers.momentsPDF.postMessage(message);

      // The WordPress page still contains its legacy beacio/Web Bluetooth
      // connection bar. That bar reports the WEB connection (always false in
      // WKWebView), not the app's proven native CoreBluetooth connection.
      // Hide the entire legacy bar only INSIDE our native iOS application;
      // outside the app, the WordPress plugin is unchanged.
      // Native printer selection stays available in the app's T02 tab and in
      // the native receipt preview when the printer is disconnected.
      const legacyConnectBar = document.querySelector('.t02-connect-bar');
      if (legacyConnectBar) {
        legacyConnectBar.hidden = true;
        legacyConnectBar.style.setProperty('display', 'none', 'important');
      }

      // Capture before the WordPress button handlers. Only two explicit user
      // actions trigger native printing: checkout success and receipt history.
      document.addEventListener('click', async event => {
        const clicked = event.target instanceof Element ? event.target : null;
        if (!clicked) return;
        let path = '';
        let intent = 'preview';
        let requiredID = null;
        let handled = false;

        const successPrint = clicked.closest('#print-receipt');
        const historyPrint = clicked.closest('[data-t02-receipt-id]');
        const pdfLink = clicked.closest('[data-pdf-path]');
        if (successPrint) {
          handled = true;
          intent = 'print';
          path = document.getElementById('open-receipt-pdf')?.dataset.pdfPath || '';
        } else if (historyPrint) {
          handled = true;
          intent = 'print';
          requiredID = Number(historyPrint.dataset.t02ReceiptId || 0);
          // The existing WordPress history card places its PDF link beside the
          // print button. Do not invent a PDF path from a separately supplied ID.
          path = historyPrint.parentElement?.querySelector('[data-pdf-path]')?.dataset.pdfPath || '';
        } else if (pdfLink) {
          handled = true;
          path = pdfLink.dataset.pdfPath || '';
        }
        if (!handled) return;
        event.preventDefault();
        event.stopImmediatePropagation();

        if (busy) {
          send({kind: 'error', message: 'A nyugta betöltése még folyamatban van.'});
          return;
        }
        const match = /^\/receipts\/(\d+)\/pdf$/.exec(path);
        if (!match || (requiredID !== null && requiredID !== Number(match[1]))) {
          send({kind: 'error', message: 'Ehhez az eladáshoz még nem érhető el a nyugta PDF-je. Ellenőrizd a nyugtanaplót; ne állíts ki új bizonylatot.'});
          return;
        }
        const config = window.MPC_POS_CONFIG;
        if (!config || typeof config.nonce !== 'string' || !config.nonce || typeof config.restUrl !== 'string') {
          send({kind: 'error', message: 'A kassza bejelentkezése lejárt. A nyugtanapló ellenőrzése után jelentkezz be újra.'});
          return;
        }
        busy = true;
        send({kind: 'started'});
        const controller = new AbortController();
        const timer = window.setTimeout(() => controller.abort(), 30000);
        try {
          // Use only the POS's existing authenticated, same-origin PDF endpoint.
          // No new issueReceipt call: printing must never create a new receipt.
          const endpoint = new URL(config.restUrl + path, location.origin);
          if (endpoint.origin !== location.origin) throw new Error('Érvénytelen PDF-cím.');
          const response = await fetch(endpoint.toString(), {
            method: 'GET',
            headers: {'Accept': 'application/pdf', 'X-WP-Nonce': config.nonce},
            credentials: 'same-origin', cache: 'no-store', signal: controller.signal
          });
          if (!response.ok) {
            let message = 'A nyugta PDF-je nem érhető el (' + response.status + ').';
            try { const detail = await response.json(); message = detail.message || message; } catch (_) { }
            throw new Error(message);
          }
          const contentType = (response.headers.get('content-type') || '').toLowerCase();
          if (!contentType.startsWith('application/pdf')) {
            throw new Error('Tesztmódban nincs eredeti Billingo PDF. Éles nyugta csak sikeres kiállítás után nyomtatható; próbanyomathoz használd a T02 próba fület.');
          }
          const blob = await response.blob();
          if (blob.size < 5 || blob.size > 6 * 1024 * 1024) {
            throw new Error('A PDF mérete nem megfelelő (maximum 6 MB).');
          }
          const encoded = await new Promise((resolve, reject) => {
            const reader = new FileReader();
            reader.onerror = () => reject(new Error('Nem olvasható a PDF.'));
            reader.onload = () => {
              const value = String(reader.result || '');
              const split = value.indexOf(',');
              if (split < 0) reject(new Error('PDF adatátadási hiba.'));
              else resolve(value.slice(split + 1));
            };
            reader.readAsDataURL(blob);
          });
          send({kind: 'pdf', receiptID: Number(match[1]), base64: encoded, intent});
        } catch (error) {
          send({kind: 'error', message: error?.message || 'A PDF átvétele sikertelen.'});
        } finally {
          window.clearTimeout(timer);
          busy = false;
        }
      }, true);
    })();
    """#
}
