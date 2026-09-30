import SwiftUI

struct ReliabilitySettingsSections: View {
    @ObservedObject var printer: T02Printer
    @ObservedObject var posWeb: POSWebModel
    @ObservedObject private var operations = OperationLogStore.shared
    @EnvironmentObject private var preferences: MomentsPreferences
    @Environment(\.colorScheme) private var colorScheme

    @State private var showRetryConfirm = false
    @State private var showDiscardConfirm = false

    var body: some View {
        let theme = MomentsPalette.make(mode: preferences.appearance, colorScheme: colorScheme)
        Group {
            MomentsCard {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Biztonság és aláírás", systemImage: "lock.shield.fill")
                        .font(.headline)
                        .foregroundStyle(theme.text)

                    Toggle("Face ID / készülékkód appzár", isOn: $preferences.faceIDLock)
                        .tint(theme.accent2)
                        .foregroundStyle(theme.text)

                    Text("Bekapcsolva induláskor, illetve legalább 5 perc háttérben töltött idő után újra feloldást kér.")
                        .font(.caption)
                        .foregroundStyle(theme.secondaryText)

                    Divider().overlay(theme.border)

                    if let date = SigningStatus.current().expirationDate {
                        settingsRow("SideStore aláírás lejár", value: date.formatted(date: .abbreviated, time: .shortened), theme: theme)
                        if let days = SigningStatus.current().daysRemaining {
                            settingsRow("Hátralévő idő", value: "kb. \(days) nap", theme: theme)
                        }
                    } else {
                        settingsRow("SideStore aláírás", value: "Lejárat nem olvasható", theme: theme)
                    }

                    if let warning = SigningStatus.current().warningText {
                        Label(warning, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(theme.warning)
                    }
                }
            }

            if let pending = printer.pendingRetry {
                MomentsCard {
                    VStack(alignment: .leading, spacing: 11) {
                        Label("Félbeszakadt nyomtatás", systemImage: "exclamationmark.arrow.triangle.2.circlepath")
                            .font(.headline)
                            .foregroundStyle(theme.warning)
                        Text(pending.label)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(theme.text)
                        Text("Az előző küldés részben már kinyomtathatott. Újrapróbálás előtt nézd meg a papírt; az app soha nem próbálkozik automatikusan újra.")
                            .font(.caption)
                            .foregroundStyle(theme.secondaryText)

                        HStack {
                            Button("Kézi újrapróbálás") { showRetryConfirm = true }
                                .buttonStyle(MomentsPrimaryButtonStyle())
                                .disabled(!printer.isReady || printer.isPrinting)
                            Button("Elvetés", role: .destructive) { showDiscardConfirm = true }
                                .buttonStyle(.bordered)
                        }
                    }
                }
            }

            MomentsCard {
                VStack(alignment: .leading, spacing: 11) {
                    HStack {
                        Label("Rendszerállapot", systemImage: "stethoscope")
                            .font(.headline)
                            .foregroundStyle(theme.text)
                        Spacer()
                        Button {
                            posWeb.refreshReliabilityStatus()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .tint(theme.accent)
                    }

                    if let status = posWeb.systemStatus {
                        settingsRow("Plugin", value: "v\(status.pluginVersion)", theme: theme)
                        settingsRow("API séma", value: "\(status.apiSchemaVersion)", theme: theme)
                        settingsRow("WooCommerce", value: status.woocommerceVersion, theme: theme)
                        settingsRow("Nyugtaszolgáltató", value: status.providerReady ? "Rendben" : "Nincs kész", theme: theme)
                        settingsRow("HTTPS", value: status.https ? "Rendben" : "Hiba", theme: theme)
                        settingsRow("Titkosítás", value: status.cryptoReady ? "Rendben" : "Hiba", theme: theme)
                        settingsRow("Archív tárhely", value: status.uploadsWritable ? "Írható" : "Hiba", theme: theme)
                        settingsRow("Kompatibilitás", value: posWeb.compatibilityWarning == nil ? "Rendben" : "Frissítés kell", theme: theme)

                        if let warning = posWeb.compatibilityWarning {
                            Text(warning)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(theme.warning)
                        }
                    } else if let error = posWeb.systemStatusError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(theme.warning)
                    } else {
                        HStack(spacing: 8) {
                            ProgressView().tint(theme.accent)
                            Text("Rendszerállapot betöltése…")
                                .font(.caption)
                                .foregroundStyle(theme.secondaryText)
                        }
                    }
                }
            }

            MomentsCard {
                VStack(alignment: .leading, spacing: 10) {
                    DisclosureGroup {
                        if posWeb.recentReceipts.isEmpty {
                            Text("Még nincs betöltött tranzakció.")
                                .font(.caption)
                                .foregroundStyle(theme.secondaryText)
                        } else {
                            ForEach(posWeb.recentReceipts.prefix(20)) { receipt in
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack {
                                        Text(receipt.receiptNumber.isEmpty ? "#\(receipt.id)" : receipt.receiptNumber)
                                            .font(.caption.weight(.bold))
                                        Spacer()
                                        Text(receipt.grossTotal, format: .currency(code: "HUF").precision(.fractionLength(0)))
                                            .font(.caption.weight(.semibold))
                                    }
                                    Text("\(receipt.createdAt) · \(receipt.statusText)")
                                        .font(.caption2)
                                        .foregroundStyle(theme.secondaryText)
                                }
                                .padding(.vertical, 4)
                                Divider().overlay(theme.border.opacity(0.6))
                            }
                        }
                    } label: {
                        Label("Utolsó 20 kasszatranzakció", systemImage: "clock.arrow.circlepath")
                            .font(.headline)
                            .foregroundStyle(theme.text)
                    }

                    DisclosureGroup {
                        if operations.events.isEmpty {
                            Text("Még nincs natív app-esemény.")
                                .font(.caption)
                                .foregroundStyle(theme.secondaryText)
                        } else {
                            ForEach(operations.events.prefix(20)) { event in
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: event.success ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                        .foregroundStyle(event.success ? theme.good : theme.warning)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(event.title).font(.caption.weight(.semibold)).foregroundStyle(theme.text)
                                        if !event.detail.isEmpty {
                                            Text(event.detail).font(.caption2).foregroundStyle(theme.secondaryText)
                                        }
                                        Text(event.date.formatted(date: .abbreviated, time: .shortened))
                                            .font(.caption2).foregroundStyle(theme.secondaryText)
                                    }
                                }
                                .padding(.vertical, 3)
                            }
                        }
                    } label: {
                        Label("Natív üzemi napló", systemImage: "list.bullet.rectangle.portrait")
                            .font(.headline)
                            .foregroundStyle(theme.text)
                    }
                }
            }
        }
        .onAppear { posWeb.refreshReliabilityStatus() }
        .confirmationDialog("Biztosan újraküldöd a teljes nyomtatást?", isPresented: $showRetryConfirm, titleVisibility: .visible) {
            Button("Igen, küldés a T02-re") { printer.retryPendingPrint() }
            Button("Mégsem", role: .cancel) { }
        } message: {
            Text("A korábbi próbálkozás részben nyomtathatott. Ellenőrizd a papírt a duplikált nyomat elkerüléséhez.")
        }
        .confirmationDialog("Elveted a félbeszakadt nyomtatási feladatot?", isPresented: $showDiscardConfirm, titleVisibility: .visible) {
            Button("Elvetés", role: .destructive) { printer.discardPendingRetry() }
            Button("Mégsem", role: .cancel) { }
        }
    }

    @ViewBuilder
    private func settingsRow(_ label: String, value: String, theme: MomentsPalette) -> some View {
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

struct AppLockOverlay: View {
    @ObservedObject var manager: AppLockManager
    @EnvironmentObject private var preferences: MomentsPreferences
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let theme = MomentsPalette.make(mode: preferences.appearance, colorScheme: colorScheme)
        ZStack {
            theme.background.ignoresSafeArea()
            VStack(spacing: 18) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 52, weight: .semibold))
                    .foregroundStyle(theme.accent)
                Text("Moments POS zárolva")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(theme.text)
                Text(manager.message)
                    .font(.subheadline)
                    .foregroundStyle(theme.secondaryText)
                    .multilineTextAlignment(.center)
                Button {
                    manager.authenticate()
                } label: {
                    Label("Feloldás", systemImage: "faceid")
                }
                .buttonStyle(MomentsPrimaryButtonStyle())
            }
            .padding(28)
        }
    }
}
