import SwiftUI
import Combine
import Foundation
import UIKit

@main
struct MomentsPOST02App: App {
    @StateObject private var printer = T02Printer()
    @StateObject private var posWeb = POSWebModel()

    @State private var showLaunchOverlay = true
    @State private var launchStartedAt = Date()

    var body: some Scene {
        WindowGroup {
            ZStack {
                TabView {
                    POSWebScreen(model: posWeb)
                        .tabItem { Label("Kassza", systemImage: "creditcard") }

                    TestView()
                        .tabItem { Label("T02 próba", systemImage: "printer") }

                    BarcodeLabelsView(posWeb: posWeb)
                        .tabItem { Label("Vonalkódok", systemImage: "barcode.viewfinder") }
                }
                .environmentObject(printer)

                if showLaunchOverlay {
                    MomentsLaunchOverlay()
                        .transition(.opacity)
                        .zIndex(100)
                }
            }
            .onAppear {
                launchStartedAt = Date()
                posWeb.loadIfNeeded()
            }
            .onReceive(posWeb.$initialPageReady.removeDuplicates()) { ready in
                guard ready, showLaunchOverlay else { return }
                let elapsed = Date().timeIntervalSince(launchStartedAt)
                // Keep the branded splash visible long enough to be perceived,
                // even when the POS page comes from cache immediately.
                let remaining = max(0, 1.20 - elapsed)
                DispatchQueue.main.asyncAfter(deadline: .now() + remaining) {
                    guard showLaunchOverlay else { return }
                    withAnimation(.easeOut(duration: 0.30)) {
                        showLaunchOverlay = false
                    }
                }
            }
            .task {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                guard showLaunchOverlay else { return }
                withAnimation(.easeOut(duration: 0.30)) {
                    showLaunchOverlay = false
                }
            }
        }
    }
}

private struct MomentsLaunchOverlay: View {
    private var splashImage: UIImage? {
        guard let path = Bundle.main.path(forResource: "SplashLogo", ofType: "jpg") else { return nil }
        return UIImage(contentsOfFile: path)
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.18, green: 0.08, blue: 0.41),
                    Color(red: 0.35, green: 0.17, blue: 0.68),
                    Color(red: 0.16, green: 0.07, blue: 0.36)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 24) {
                if let splashImage {
                    Image(uiImage: splashImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 224, height: 224)
                        .clipShape(RoundedRectangle(cornerRadius: 44, style: .continuous))
                        .shadow(color: .black.opacity(0.24), radius: 22, x: 0, y: 12)
                } else {
                    // Fallback should never normally be needed, but prevents an
                    // empty splash even if a resource is accidentally omitted.
                    Image(systemName: "creditcard.fill")
                        .font(.system(size: 96))
                        .foregroundStyle(.white)
                }

                ProgressView()
                    .tint(Color(red: 0.96, green: 0.22, blue: 0.83))
                    .scaleEffect(1.08)

                Text("Kassza betöltése…")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.82))
            }
            .padding(.bottom, 14)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Moments POS betöltése")
    }
}
