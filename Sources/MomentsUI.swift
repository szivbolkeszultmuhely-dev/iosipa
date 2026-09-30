import SwiftUI

struct MomentsHeader: View {
    let title: String
    let subtitle: String?
    let systemImage: String
    var reloadAction: (() -> Void)? = nil

    @EnvironmentObject private var appUI: MomentsAppUIState

    var body: some View {
        MomentsThemeReader { theme in
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(Color.white.opacity(0.13))
                    Image(systemName: systemImage)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.72))
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 6)

                if let reloadAction {
                    Button(action: reloadAction) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 17, weight: .semibold))
                            .frame(width: 38, height: 38)
                            .background(Color.white.opacity(0.12))
                            .clipShape(Circle())
                    }
                    .foregroundStyle(.white)
                    .accessibilityLabel("Újratöltés")
                }

                Button {
                    appUI.settingsPresented = true
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 38, height: 38)
                        .background(Color.white.opacity(0.12))
                        .clipShape(Circle())
                }
                .foregroundStyle(.white)
                .accessibilityLabel("Beállítások")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                LinearGradient(
                    colors: [theme.header, theme.accent.opacity(0.86)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
        }
    }
}

struct MomentsCard<Content: View>: View {
    @EnvironmentObject private var preferences: MomentsPreferences
    @Environment(\.colorScheme) private var colorScheme
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        let theme = MomentsPalette.make(mode: preferences.appearance, colorScheme: colorScheme)
        content
            .padding(14)
            .background(theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(theme.border.opacity(0.75), lineWidth: 1)
            )
            .shadow(
                color: preferences.appearance == .moments ? theme.accent.opacity(0.08) : .clear,
                radius: 10, x: 0, y: 5
            )
    }
}

struct MomentsPrimaryButtonStyle: ButtonStyle {
    @EnvironmentObject private var preferences: MomentsPreferences
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        let theme = MomentsPalette.make(mode: preferences.appearance, colorScheme: colorScheme)
        configuration.label
            .font(.subheadline.weight(.bold))
            .foregroundStyle(preferences.appearance == .contrast ? theme.background : .white)
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background(
                Group {
                    if preferences.appearance == .moments {
                        LinearGradient(
                            colors: [theme.accent, theme.accent2],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    } else {
                        LinearGradient(
                            colors: [theme.accent, theme.accent],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .opacity(configuration.isPressed ? 0.76 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
    }
}

struct MomentsStatusPill: View {
    let ready: Bool
    let text: String

    var body: some View {
        MomentsThemeReader { theme in
            HStack(spacing: 7) {
                Circle()
                    .fill(ready ? theme.good : theme.warning)
                    .frame(width: 8, height: 8)
                Text(text)
                    .font(.caption.weight(.semibold))
                    .lineLimit(2)
            }
            .foregroundStyle(theme.text)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(theme.surfaceAlt)
            .clipShape(Capsule())
        }
    }
}

struct MomentsSettingsView: View {
    @ObservedObject var printer: T02Printer
    @ObservedObject var posWeb: POSWebModel

    @EnvironmentObject private var preferences: MomentsPreferences
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let theme = MomentsPalette.make(mode: preferences.appearance, colorScheme: colorScheme)

        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    MomentsCard {
                        VStack(alignment: .leading, spacing: 14) {
                            Label("Megjelenés", systemImage: "paintpalette.fill")
                                .font(.headline)
                                .foregroundStyle(theme.text)

                            Picker("Megjelenés", selection: $preferences.appearance) {
                                ForEach(MomentsAppearanceMode.allCases) { mode in
                                    Label(mode.title, systemImage: mode.symbol).tag(mode)
                                }
                            }
                            .pickerStyle(.segmented)

                            Text(appearanceHelp)
                                .font(.caption)
                                .foregroundStyle(theme.secondaryText)

                            Toggle("Nagyobb natív betűméret", isOn: $preferences.largeText)
                                .tint(theme.accent2)
                                .foregroundStyle(theme.text)
                        }
                    }

                    MomentsCard {
                        VStack(alignment: .leading, spacing: 13) {
                            Label("Indítás", systemImage: "play.square.stack.fill")
                                .font(.headline)
                                .foregroundStyle(theme.text)

                            Toggle("Márkázott betöltőanimáció", isOn: $preferences.showBrandedLoader)
                                .tint(theme.accent2)
                                .foregroundStyle(theme.text)

                            Text("A rövid natív iOS indulóképernyő ettől függetlenül megjelenhet; ez az utána látható Moments betöltőréteget kapcsolja.")
                                .font(.caption)
                                .foregroundStyle(theme.secondaryText)
                        }
                    }

                    MomentsCard {
                        VStack(alignment: .leading, spacing: 13) {
                            Label("T02 nyomtató", systemImage: "printer.fill")
                                .font(.headline)
                                .foregroundStyle(theme.text)

                            Toggle("T02 keresése appindításkor", isOn: $preferences.autoScanPrinter)
                                .tint(theme.accent2)
                                .foregroundStyle(theme.text)

                            MomentsStatusPill(
                                ready: printer.isReady,
                                text: printer.isReady ? "T02 kapcsolódva" : printer.status
                            )

                            if !printer.isReady {
                                Button {
                                    printer.scan()
                                } label: {
                                    Label("T02 keresése most", systemImage: "dot.radiowaves.left.and.right")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(MomentsPrimaryButtonStyle())
                                .disabled(printer.isScanning || printer.isPrinting)
                            }
                        }
                    }

                    MomentsCard {
                        VStack(alignment: .leading, spacing: 11) {
                            Label("Rendszer", systemImage: "info.circle.fill")
                                .font(.headline)
                                .foregroundStyle(theme.text)

                            settingsRow("Moments POS", value: appVersion)
                            settingsRow("WordPress kassza", value: posWeb.initialPageReady ? "Kapcsolódva" : "Nincs betöltve")
                            settingsRow("T02", value: printer.isReady ? "Nyomtatásra kész" : "Nincs kapcsolat")
                        }
                    }

                    ReliabilitySettingsSections(printer: printer, posWeb: posWeb)
                }
                .padding(16)
            }
            .background(theme.background.ignoresSafeArea())
            .navigationTitle("Beállítások")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Kész") { dismiss() }
                        .fontWeight(.semibold)
                        .tint(theme.accent)
                }
            }
        }
    }

    private var appearanceHelp: String {
        switch preferences.appearance {
        case .moments:
            return "Színesebb, lila–pink Moments megjelenés a natív felületeken. A Kassza webes belsejét nem módosítja."
        case .contrast:
            return "Egyszerű, erős fekete–fehér kontraszt a natív részeken."
        case .system:
            return "A natív felület az iPhone világos/sötét rendszermegjelenését követi."
        }
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "–"
        return "v\(version) (\(build))"
    }

    @ViewBuilder
    private func settingsRow(_ label: String, value: String) -> some View {
        MomentsThemeReader { theme in
            HStack(alignment: .top) {
                Text(label).foregroundStyle(theme.secondaryText)
                Spacer()
                Text(value)
                    .fontWeight(.semibold)
                    .foregroundStyle(theme.text)
                    .multilineTextAlignment(.trailing)
            }
            .font(.subheadline)
        }
    }
}
