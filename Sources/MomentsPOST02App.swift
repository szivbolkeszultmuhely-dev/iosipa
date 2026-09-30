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
            // The Moments POS mark is baked into this full-screen image.
            // Using one centered composite avoids launch-screen image lookup issues
            // and keeps the mark geometrically centered on every iPhone size.
            Image("LaunchComposite")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()

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
        .background(Color(red: 0.18, green: 0.08, blue: 0.41))
        .defersSystemGestures(on: [])
        .persistentSystemOverlays(.visible)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Moments POS betöltése")
    }
}
