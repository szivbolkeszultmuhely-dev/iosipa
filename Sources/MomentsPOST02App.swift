import SwiftUI
import Combine
import Foundation

@main
struct MomentsPOST02App: App {
    // One printer instance for the whole app. The validated T02 printing
    // implementation is intentionally untouched by this visual-only release.
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
                // Start timing from the first rendered native frame. The POS
                // web view loads underneath the branded overlay.
                launchStartedAt = Date()
                posWeb.loadIfNeeded()
            }
            .onReceive(posWeb.$initialPageReady.removeDuplicates()) { ready in
                guard ready, showLaunchOverlay else { return }
                // Avoid a distracting flash on fast/cached launches.
                let elapsed = Date().timeIntervalSince(launchStartedAt)
                let remaining = max(0, 0.85 - elapsed)
                DispatchQueue.main.asyncAfter(deadline: .now() + remaining) {
                    guard showLaunchOverlay else { return }
                    withAnimation(.easeOut(duration: 0.32)) {
                        showLaunchOverlay = false
                    }
                }
            }
            .task {
                // Never trap the user behind the splash if the website is slow
                // or temporarily unavailable; the existing POS error UI remains
                // accessible after this fallback timeout.
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                guard showLaunchOverlay else { return }
                withAnimation(.easeOut(duration: 0.32)) {
                    showLaunchOverlay = false
                }
            }
        }
    }
}

private struct MomentsLaunchOverlay: View {
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
                Image("LaunchLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 224, height: 224)
                    .shadow(color: .black.opacity(0.24), radius: 22, x: 0, y: 12)

                ProgressView()
                    .tint(Color(red: 0.96, green: 0.22, blue: 0.83))
                    .scaleEffect(1.08)

                Text("Betöltés…")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.82))
            }
            .padding(.bottom, 14)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Moments POS betöltése")
    }
}
