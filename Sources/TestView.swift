import SwiftUI
import UIKit

struct TestView: View {
    @EnvironmentObject private var printer: T02Printer
    @EnvironmentObject private var preferences: MomentsPreferences
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let theme = MomentsPalette.make(mode: preferences.appearance, colorScheme: colorScheme)

        VStack(spacing: 0) {
            MomentsHeader(
                title: "T02 próba",
                subtitle: "Közvetlen Bluetooth diagnosztika és tesztnyomat",
                systemImage: "printer.fill"
            )

            ScrollView {
                VStack(spacing: 14) {
                    MomentsCard {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text("Bluetooth kapcsolat")
                                        .font(.headline)
                                        .foregroundStyle(theme.text)
                                    MomentsStatusPill(
                                        ready: printer.isReady,
                                        text: printer.isReady ? "T02 nyomtatásra kész" : printer.status
                                    )
                                }
                                Spacer()
                                Image(systemName: printer.isReady ? "checkmark.circle.fill" : "antenna.radiowaves.left.and.right")
                                    .font(.system(size: 28, weight: .semibold))
                                    .foregroundStyle(printer.isReady ? theme.good : theme.accent)
                            }

                            Button {
                                if printer.isScanning { printer.stopScan() }
                                else { printer.scan() }
                            } label: {
                                Label(
                                    printer.isScanning ? "Keresés leállítása" : "T02 keresése",
                                    systemImage: printer.isScanning ? "stop.fill" : "dot.radiowaves.left.and.right"
                                )
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(MomentsPrimaryButtonStyle())
                            .disabled(printer.isPrinting)

                            if printer.devices.isEmpty && !printer.isReady {
                                Text("Első alkalommal engedélyezd az iPhone Bluetooth-hozzáférését. A T02-nek bekapcsolva és a közelben kell lennie.")
                                    .font(.caption)
                                    .foregroundStyle(theme.secondaryText)
                            }

                            ForEach(printer.devices) { device in
                                Button {
                                    printer.connect(to: device.id)
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(device.name)
                                                .fontWeight(.bold)
                                            Text("Jelerősség: \(device.rssi) dBm")
                                                .font(.caption)
                                        }
                                        Spacer()
                                        Image(systemName: "link.circle.fill")
                                            .font(.title3)
                                    }
                                    .foregroundStyle(theme.text)
                                    .padding(11)
                                    .background(theme.surfaceAlt)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                }
                                .buttonStyle(.plain)
                                .disabled(printer.isPrinting)
                            }

                            if printer.isReady {
                                Button {
                                    printer.disconnect()
                                } label: {
                                    Label("Kapcsolat bontása", systemImage: "xmark.circle")
                                }
                                .buttonStyle(.bordered)
                                .tint(theme.secondaryText)
                            }
                        }
                    }

                    MomentsCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Tesztnyomat", systemImage: "doc.text.image")
                                .font(.headline)
                                .foregroundStyle(theme.text)

                            Text("Egy rövid, 384 képpont széles tesztképet küldünk a T02-re. Ez nem adóügyi bizonylat.")
                                .font(.subheadline)
                                .foregroundStyle(theme.secondaryText)

                            Button {
                                printer.printTest()
                            } label: {
                                HStack {
                                    if printer.isPrinting { ProgressView().tint(.white) }
                                    Image(systemName: "printer.fill")
                                    Text(printer.isPrinting ? "Adatküldés…" : "TESZT nyomtatása")
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(MomentsPrimaryButtonStyle())
                            .disabled(!printer.isReady || printer.isPrinting)
                        }
                    }

                    MomentsCard {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Label("Hibakeresési napló", systemImage: "terminal.fill")
                                    .font(.headline)
                                    .foregroundStyle(theme.text)
                                Spacer()
                                Button {
                                    UIPasteboard.general.string = printer.logText
                                } label: {
                                    Image(systemName: "doc.on.doc")
                                }
                                .tint(theme.accent)
                                .accessibilityLabel("Napló másolása")
                            }

                            ScrollView {
                                Text(printer.logText)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(theme.text)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(minHeight: 150, maxHeight: 250)
                            .padding(10)
                            .background(theme.field)
                            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                        }
                    }
                }
                .padding(14)
            }
            .background(theme.background)
        }
        .background(theme.background.ignoresSafeArea())
        .onAppear {
            if preferences.autoScanPrinter { printer.startIfPossible() }
        }
    }
}
