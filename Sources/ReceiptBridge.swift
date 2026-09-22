import Foundation
import SwiftUI
import PDFKit
import WebKit

// Integration stage 3A: transfer the EXACT PDF returned by the existing,
// authenticated Moments POS /receipts/<id>/pdf REST route to iOS for preview.
// No printer jobs, checkout state changes, or copies of customer data.
struct ReceivedReceiptPDF: Identifiable {
    let id = UUID()
    let receiptID: Int
    let data: Data
    let pageCount: Int
}

struct ReceiptPDFPreview: View {
    let receipt: ReceivedReceiptPDF
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Text("Az eredeti nyugta PDF-je megérkezett az alkalmazásba. Ez még csak előnézet: most NEM küldjük nyomtatásra.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(12)
                ReceiptPDFView(data: receipt.data)
            }
            .navigationTitle("PDF ellenőrzés · #\(receipt.receiptID)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Bezárás") { dismiss() }
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
      document.addEventListener('click', async event => {
        const element = event.target instanceof Element ? event.target.closest('[data-pdf-path]') : null;
        if (!element) return;
        const path = element.dataset.pdfPath || '';
        const match = /^\/receipts\/(\d+)\/pdf$/.exec(path);
        if (!match) return;
        const config = window.MPC_POS_CONFIG;
        if (!config || typeof config.nonce !== 'string' || !config.nonce || typeof config.restUrl !== 'string') return;
        // Important: do not open the POS's legacy PDF popup inside the app.
        event.preventDefault();
        event.stopImmediatePropagation();
        if (busy) { send({kind: 'error', message: 'A nyugta betöltése még folyamatban van.'}); return; }
        busy = true;
        send({kind: 'started'});
        const controller = new AbortController();
        const timer = window.setTimeout(() => controller.abort(), 30000);
        try {
          const endpoint = new URL(config.restUrl + path, location.origin);
          if (endpoint.origin !== location.origin) throw new Error('Érvénytelen PDF-cím.');
          const response = await fetch(endpoint.toString(), {
            method: 'GET',
            headers: {'Accept': 'application/pdf', 'X-WP-Nonce': config.nonce},
            credentials: 'same-origin', cache: 'no-store', signal: controller.signal
          });
          if (!response.ok) {
            let message = 'A nyugta nem érhető el (' + response.status + ').';
            try { const detail = await response.json(); message = detail.message || message; } catch (_) { }
            throw new Error(message);
          }
          const contentType = (response.headers.get('content-type') || '').toLowerCase();
          if (!contentType.startsWith('application/pdf')) {
            throw new Error('Ez a bizonylat még HTML tesztblokk. Az eredeti archivált PDF szükséges a következő lépéshez.');
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
          send({kind: 'pdf', receiptID: Number(match[1]), base64: encoded});
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
