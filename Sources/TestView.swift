import SwiftUI
import UIKit

struct TestView: View {
    @EnvironmentObject private var printer: T02Printer

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("AIMO T02 · natív teszt")
                            .font(.title2.bold())
                        Text("1. lépés / 6 · Közvetlen Bluetooth, külső nyomtatóapp nélkül.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.bottom, 4)

                    GroupBox("Bluetooth") {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 8) {
                                Circle().fill(printer.isReady ? Color.green : Color.orange)
                                    .frame(width: 10, height: 10)
                                Text(printer.status).font(.subheadline)
                            }
                            Button(printer.isScanning ? "Keresés leállítása" : "T02 keresése") {
                                if printer.isScanning { printer.stopScan() }
                                else { printer.scan() }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(printer.isPrinting)

                            if printer.devices.isEmpty {
                                Text("A nyomtatókat itt soroljuk fel. Első alkalommal engedélyezd az iPhone Bluetooth-hozzáférést.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            ForEach(printer.devices) { device in
                                Button {
                                    printer.connect(to: device.id)
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading) {
                                            Text(device.name).fontWeight(.semibold)
                                            Text("Jelerősség: \(device.rssi) dBm")
                                                .font(.caption).foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Image(systemName: "link")
                                    }
                                }
                                .buttonStyle(.bordered)
                                .disabled(printer.isPrinting)
                            }
                            if printer.isReady {
                                Button("Kapcsolat bontása") { printer.disconnect() }
                                    .buttonStyle(.bordered)
                                    .tint(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 6)
                    }

                    GroupBox("Tesztnyomat") {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("A nyomtatóra egy rövid, 384 képpont széles tesztképet küldünk. Nem adóügyi bizonylat.")
                                .font(.subheadline)
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
                            .buttonStyle(.borderedProminent)
                            .tint(Color(red: 0.32, green: 0.48, blue: 0.40))
                            .disabled(!printer.isReady || printer.isPrinting)
                            Text("Sikeres adatküldés után is nézd meg, hogy a teljes minta valóban kijött-e a papírra.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    GroupBox("Hibakeresési napló") {
                        VStack(alignment: .leading, spacing: 10) {
                            ScrollView {
                                Text(printer.logText)
                                    .font(.system(size: 11, design: .monospaced))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(minHeight: 160, maxHeight: 260)
                            Button("Napló másolása") { UIPasteboard.general.string = printer.logText }
                                .buttonStyle(.bordered)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding()
            }
            .navigationTitle("Moments POS")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { printer.startIfPossible() }
        }
    }
}
