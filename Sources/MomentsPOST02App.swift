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

    init() {
        // Product thumbnails and other native URL loads can reuse a reasonably sized
        // on-device cache between screens and app launches. WKWebView keeps its own
        // persistent website cache separately.
        URLCache.shared = URLCache(
            memoryCapacity: 32 * 1024 * 1024,
            diskCapacity: 128 * 1024 * 1024,
            diskPath: "MomentsPOSURLCache"
        )
    }

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
                    // Start the cashier immediately. Bluetooth discovery is deliberately
                    // deferred so WebKit gets the first CPU/network burst at launch.
                    posWeb.loadIfNeeded()
                    if preferences.autoScanPrinter {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.85) {
                            printer.startIfPossible()
                        }
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
                    // No artificial minimum splash duration: as soon as the cashier DOM
                    // is usable, reveal it. The native launch screen already covers startup.
                    guard ready, showLaunchOverlay, preferences.showBrandedLoader else { return }
                    withAnimation(.easeOut(duration: 0.16)) {
                        showLaunchOverlay = false
                    }
                }
                .task {
                    // Safety net only. A slow remote resource must not hold the whole UI.
                    try? await Task.sleep(nanoseconds: 2_500_000_000)
                    guard showLaunchOverlay else { return }
                    withAnimation(.easeOut(duration: 0.16)) {
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
            Color(red: 0.18, green: 0.08, blue: 0.41)
                .ignoresSafeArea()

            // Guaranteed logo: PNG bytes are embedded in the executable itself.
            // ZStack centers the mark independently of screen size / safe area.
            if let logo = MomentsEmbeddedLaunchLogo.image {
                Image(uiImage: logo)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 290, maxHeight: 290)
                    .padding(.horizontal, 54)
            }

            VStack(spacing: 10) {
                Spacer()
                ProgressView()
                    .tint(Color(red: 0.96, green: 0.22, blue: 0.83))
                    .scaleEffect(1.08)
                Text("Kassza betöltése…")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.86))
            }
            .padding(.bottom, 76)
        }
        .defersSystemGestures(on: [])
        .persistentSystemOverlays(.visible)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Moments POS betöltése")
    }
}
