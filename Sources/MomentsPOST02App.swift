import SwiftUI
import Combine
import Foundation
import UIKit

@main
struct MomentsPOST02App: App {
    @StateObject private var printer = T02Printer()
    @StateObject private var posWeb = POSWebModel()
    @StateObject private var preferences = MomentsPreferences()
    @StateObject private var appUI = MomentsAppUIState()

    @State private var showLaunchOverlay = true
    @State private var launchStartedAt = Date()

    var body: some Scene {
        WindowGroup {
            MomentsThemeReader { theme in
                ZStack {
                    theme.background.ignoresSafeArea()

                    TabView {
                        POSWebScreen(model: posWeb)
                            .tabItem { Label("Kassza", systemImage: "creditcard.fill") }

                        TestView()
                            .tabItem { Label("T02 próba", systemImage: "printer.fill") }

                        BarcodeLabelsView(posWeb: posWeb)
                            .tabItem { Label("Vonalkódok", systemImage: "barcode.viewfinder") }
                    }
                    .tint(theme.accent)
                    .toolbarBackground(theme.tabBar, for: .tabBar)
                    .toolbarBackground(.visible, for: .tabBar)
                    .toolbarColorScheme(theme.tabBarScheme, for: .tabBar)
                    .background(
                        MomentsTabBarStyleApplier(
                            mode: preferences.appearance,
                            colorScheme: theme.tabBarScheme
                        )
                        .frame(width: 0, height: 0)
                    )
                    // Explicitly keep all screen-edge system gestures owned by iOS.
                    // The POS app never needs immersive edge-gesture priority.
                    .defersSystemGestures(on: [])
                    .persistentSystemOverlays(.visible)
                    .environmentObject(printer)
                    .environmentObject(preferences)
                    .environmentObject(appUI)
                    .dynamicTypeSize(preferences.largeText ? .large : .medium)

                    if showLaunchOverlay && preferences.showBrandedLoader {
                        MomentsLaunchOverlay()
                            .transition(.opacity)
                            .zIndex(100)
                    }
                }
                .environmentObject(preferences)
                .environmentObject(appUI)
                .onAppear {
                    launchStartedAt = Date()
                    posWeb.loadIfNeeded()
                    if preferences.autoScanPrinter {
                        printer.startIfPossible()
                    }
                    if !preferences.showBrandedLoader {
                        showLaunchOverlay = false
                    }
                }
                .onChange(of: preferences.autoScanPrinter) { enabled in
                    if enabled { printer.startIfPossible() }
                }
                .onChange(of: preferences.showBrandedLoader) { enabled in
                    if !enabled { showLaunchOverlay = false }
                }
                .onReceive(posWeb.$initialPageReady.removeDuplicates()) { ready in
                    guard ready, showLaunchOverlay, preferences.showBrandedLoader else { return }
                    let elapsed = Date().timeIntervalSince(launchStartedAt)
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
                .sheet(isPresented: $appUI.settingsPresented) {
                    MomentsSettingsView(printer: printer, posWeb: posWeb)
                        .environmentObject(preferences)
                }
            }
            .environmentObject(preferences)
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
                // Asset-catalog image generated directly from the supplied Moments POS icon.
                // This avoids bundle-path / filename lookup differences on signed IPA builds.
                Image("SplashLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 224, height: 224)
                    .clipShape(RoundedRectangle(cornerRadius: 44, style: .continuous))
                    .shadow(color: .black.opacity(0.24), radius: 22, x: 0, y: 12)

                ProgressView()
                    .tint(Color(red: 0.96, green: 0.22, blue: 0.83))
                    .scaleEffect(1.08)

                Text("Kassza betöltése…")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.82))
            }
            .padding(.bottom, 14)
        }
        .defersSystemGestures(on: [])
        .persistentSystemOverlays(.visible)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Moments POS betöltése")
    }
}
