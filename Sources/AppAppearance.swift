import SwiftUI
import Combine

/// Native-shell appearance only. The embedded WordPress cashier is deliberately
/// left untouched so its existing HTML/CSS keeps the validated cashier design.
enum MomentsAppearanceMode: String, CaseIterable, Identifiable {
    case moments
    case contrast
    case system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .moments: return "Moments"
        case .contrast: return "Kontrasztos"
        case .system: return "Rendszer"
        }
    }

    var symbol: String {
        switch self {
        case .moments: return "sparkles"
        case .contrast: return "circle.lefthalf.filled"
        case .system: return "iphone"
        }
    }
}

final class MomentsPreferences: ObservableObject {
    private enum Key {
        static let appearance = "MomentsPOS.Appearance"
        static let largeText = "MomentsPOS.LargeText"
        static let autoScanPrinter = "MomentsPOS.AutoScanPrinter"
        static let showLoader = "MomentsPOS.ShowBrandedLoader"
    }

    @Published var appearance: MomentsAppearanceMode {
        didSet { UserDefaults.standard.set(appearance.rawValue, forKey: Key.appearance) }
    }

    @Published var largeText: Bool {
        didSet { UserDefaults.standard.set(largeText, forKey: Key.largeText) }
    }

    @Published var autoScanPrinter: Bool {
        didSet { UserDefaults.standard.set(autoScanPrinter, forKey: Key.autoScanPrinter) }
    }

    @Published var showBrandedLoader: Bool {
        didSet { UserDefaults.standard.set(showBrandedLoader, forKey: Key.showLoader) }
    }

    init() {
        let defaults = UserDefaults.standard
        if let raw = defaults.string(forKey: Key.appearance),
           let saved = MomentsAppearanceMode(rawValue: raw) {
            appearance = saved
        } else {
            appearance = .moments
        }

        largeText = defaults.object(forKey: Key.largeText) as? Bool ?? false
        autoScanPrinter = defaults.object(forKey: Key.autoScanPrinter) as? Bool ?? true
        showBrandedLoader = defaults.object(forKey: Key.showLoader) as? Bool ?? true
    }
}

final class MomentsAppUIState: ObservableObject {
    @Published var settingsPresented = false
}

struct MomentsPalette {
    let background: Color
    let surface: Color
    let surfaceAlt: Color
    let field: Color
    let text: Color
    let secondaryText: Color
    let border: Color
    let accent: Color
    let accent2: Color
    let header: Color
    let tabBar: Color
    let good: Color
    let warning: Color
    let tabBarScheme: ColorScheme

    static func make(mode: MomentsAppearanceMode, colorScheme: ColorScheme) -> MomentsPalette {
        switch mode {
        case .moments:
            return MomentsPalette(
                background: Color(red: 0.969, green: 0.953, blue: 0.992),
                surface: .white,
                surfaceAlt: Color(red: 0.941, green: 0.914, blue: 0.984),
                field: Color(red: 0.987, green: 0.979, blue: 0.998),
                text: Color(red: 0.145, green: 0.090, blue: 0.235),
                secondaryText: Color(red: 0.405, green: 0.365, blue: 0.490),
                border: Color(red: 0.855, green: 0.812, blue: 0.925),
                accent: Color(red: 0.376, green: 0.145, blue: 0.690),
                accent2: Color(red: 0.914, green: 0.176, blue: 0.773),
                header: Color(red: 0.165, green: 0.055, blue: 0.330),
                tabBar: Color(red: 0.945, green: 0.925, blue: 0.975),
                good: Color(red: 0.130, green: 0.580, blue: 0.380),
                warning: Color(red: 0.820, green: 0.490, blue: 0.120),
                tabBarScheme: .light
            )

        case .contrast:
            if colorScheme == .dark {
                return MomentsPalette(
                    background: .black,
                    surface: Color(red: 0.075, green: 0.075, blue: 0.075),
                    surfaceAlt: Color(red: 0.125, green: 0.125, blue: 0.125),
                    field: Color(red: 0.095, green: 0.095, blue: 0.095),
                    text: .white,
                    secondaryText: Color.white.opacity(0.72),
                    border: Color.white.opacity(0.34),
                    accent: .white,
                    accent2: .white,
                    header: .black,
                    tabBar: .black,
                    good: .green,
                    warning: .orange,
                    tabBarScheme: .dark
                )
            }
            return MomentsPalette(
                background: .white,
                surface: .white,
                surfaceAlt: Color(red: 0.955, green: 0.955, blue: 0.955),
                field: .white,
                text: .black,
                secondaryText: Color.black.opacity(0.68),
                border: Color.black.opacity(0.38),
                accent: .black,
                accent2: .black,
                header: .white,
                tabBar: .white,
                good: Color(red: 0.000, green: 0.420, blue: 0.190),
                warning: Color(red: 0.690, green: 0.330, blue: 0.000),
                tabBarScheme: .light
            )

        case .system:
            return MomentsPalette(
                background: Color(uiColor: .systemGroupedBackground),
                surface: Color(uiColor: .secondarySystemGroupedBackground),
                surfaceAlt: Color(uiColor: .tertiarySystemGroupedBackground),
                field: Color(uiColor: .secondarySystemBackground),
                text: Color(uiColor: .label),
                secondaryText: Color(uiColor: .secondaryLabel),
                border: Color(uiColor: .separator),
                accent: Color(red: 0.376, green: 0.145, blue: 0.690),
                accent2: Color(red: 0.914, green: 0.176, blue: 0.773),
                header: Color(uiColor: .systemBackground),
                tabBar: Color(uiColor: .systemBackground),
                good: .green,
                warning: .orange,
                tabBarScheme: colorScheme
            )
        }
    }
}

struct MomentsThemeReader<Content: View>: View {
    @EnvironmentObject private var preferences: MomentsPreferences
    @Environment(\.colorScheme) private var colorScheme
    let content: (MomentsPalette) -> Content

    init(@ViewBuilder content: @escaping (MomentsPalette) -> Content) {
        self.content = content
    }

    var body: some View {
        content(MomentsPalette.make(mode: preferences.appearance, colorScheme: colorScheme))
    }
}
