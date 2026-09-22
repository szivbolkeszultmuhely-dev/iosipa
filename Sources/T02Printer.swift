import Foundation
import Combine
import CoreBluetooth

/// First-stage hardware test only. No POS login, no live receipt, no cloud service.
/// All CoreBluetooth callbacks run on the main queue.
final class T02Printer: NSObject, ObservableObject {
    struct Device: Identifiable {
        let id: UUID
        let name: String
        let rssi: Int
    }

    @Published private(set) var devices: [Device] = []
    @Published private(set) var status = "Bluetooth előkészítése…"
    @Published private(set) var isScanning = false
    @Published private(set) var isPrinting = false
    @Published private(set) var connectedName: String?
    @Published private(set) var logText = ""

    var isReady: Bool {
        guard let peripheral = peripheral else { return false }
        return peripheral.state == .connected && writeCharacteristic != nil
    }

    private var central: CBCentralManager!
    private var discovered: [UUID: CBPeripheral] = [:]
    private var peripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?
    private var notifyCharacteristic: CBCharacteristic?
    private let writeUUID = CBUUID(string: "FF02")
    private let notifyUUID = CBUUID(string: "FF03")
    private let expectedServiceUUID = CBUUID(string: "FF00")
    private var pendingServices = 0
    private var connectionGeneration = 0
    private var printGeneration = 0
    private var stream = Data()
    private var streamOffset = 0
    private var needsWriteResponse = false
    private let savedIDKey = "MomentsPOST02.LastPrinterID"
    private let stamp = DateFormatter()

    override init() {
        super.init()
        stamp.dateFormat = "HH:mm:ss"
        central = CBCentralManager(delegate: self, queue: .main)
        note("Natív CoreBluetooth próba. Nem szükséges Bluetooth-párosítás az iOS Beállításokban.")
    }

    func startIfPossible() {
        if central.state == .poweredOn && !isReady && !isScanning && devices.isEmpty { scan() }
    }

    func scan() {
        guard central.state == .poweredOn else {
            fail("A Bluetooth nem érhető el. Ellenőrizd az iPhone engedélyeit.")
            return
        }
        if let old = peripheral, old.state == .connected { central.cancelPeripheralConnection(old) }
        writeCharacteristic = nil
        notifyCharacteristic = nil
        connectedName = nil
        devices.removeAll()
        discovered.removeAll()
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        isScanning = true
        status = "T02 keresése…"
        note("Bluetooth-keresés elindítva (minden BLE-szolgáltatás).")
        DispatchQueue.main.asyncAfter(deadline: .now() + 12) { [weak self] in
            guard let self = self, self.isScanning else { return }
            self.stopScan()
            self.status = self.devices.isEmpty ? "Nem látható T02: ellenőrizd a bekapcsolást." : "Válaszd ki a T02-t a listából."
        }
    }

    func stopScan() {
        central.stopScan()
        isScanning = false
    }

    func connect(to id: UUID) {
        guard let candidate = discovered[id], central.state == .poweredOn else {
            fail("Az eszköz már nem látható. Nyomd meg a T02 keresése gombot.")
            return
        }
        stopScan()
        if let old = peripheral, old.state == .connected, old.identifier != id {
            central.cancelPeripheralConnection(old)
        }
        if isPrinting { abortPrint("Nyomtatás megszakítva: új csatlakozás.") }
        connectionGeneration += 1
        let generation = connectionGeneration
        peripheral = candidate
        candidate.delegate = self
        writeCharacteristic = nil
        notifyCharacteristic = nil
        connectedName = nil
        pendingServices = 0
        status = "Kapcsolódás: \(candidate.name ?? "T02")…"
        note("Kapcsolódás kezdete: \(candidate.name ?? "névtelen") [\(id)].")
        central.connect(candidate, options: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in
            guard let self = self, self.connectionGeneration == generation, !self.isReady else { return }
            self.connectionGeneration += 1
            self.fail("20 másodpercig nem jött létre a nyomtatásra kész kapcsolat.")
            self.central.cancelPeripheralConnection(candidate)
        }
    }

    func disconnect() {
        guard let candidate = peripheral else { return }
        connectionGeneration += 1
        central.cancelPeripheralConnection(candidate)
        writeCharacteristic = nil
        notifyCharacteristic = nil
        connectedName = nil
        if isPrinting { abortPrint("Nyomtatás megszakadt: kapcsolat bontva.") }
        status = "Kapcsolat bontva."
        note(status)
    }

    func printTest() {
        guard isReady else { fail("Előbb csatlakozz a T02-höz."); return }
        guard !isPrinting else { return }
        do {
            stream = try T02Raster.makeTestJob()
        } catch {
            fail("A tesztkép előállítása sikertelen: \(error.localizedDescription)")
            return
        }
        streamOffset = 0
        isPrinting = true
        printGeneration += 1
        let generation = printGeneration
        note("Tesztnyomat: \(stream.count) bájt, 384 pixel szélesség.")
        status = "Tesztadatok küldése…"
        sendNextChunk()
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
            guard let self = self, self.isPrinting, self.printGeneration == generation else { return }
            self.abortPrint("Az adatküldés 30 másodpercen belül nem fejeződött be.")
        }
    }

    private func sendNextChunk() {
        guard isPrinting else { return }
        guard let candidate = peripheral, candidate.state == .connected,
              let characteristic = writeCharacteristic else {
            abortPrint("Megszakadt a Bluetooth-kapcsolat. Nem küldjük újra automatikusan.")
            return
        }
        guard streamOffset < stream.count else {
            isPrinting = false
            stream.removeAll()
            note("Az összes adat elküldve. Ez nem bizonyítja, hogy a nyomtató ténylegesen kinyomtatta.")
            status = "Adatok elküldve. Ellenőrizd a teljes papírnyomatot!"
            return
        }
        if !needsWriteResponse && !candidate.canSendWriteWithoutResponse {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) { [weak self] in self?.sendNextChunk() }
            return
        }
        let writeType: CBCharacteristicWriteType = needsWriteResponse ? .withResponse : .withoutResponse
        let maxBytes = candidate.maximumWriteValueLength(for: writeType)
        guard maxBytes > 0 else { abortPrint("A BLE adatcsomag mérete 0; nem tudunk küldeni."); return }
        let count = min(96, maxBytes, stream.count - streamOffset)
        let data = stream.subdata(in: streamOffset..<(streamOffset + count))
        candidate.writeValue(data, for: characteristic, type: writeType)
        streamOffset += count
        if needsWriteResponse { return } // continue only after CoreBluetooth acknowledges
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.045) { [weak self] in self?.sendNextChunk() }
    }

    private func abortPrint(_ message: String) {
        printGeneration += 1
        isPrinting = false
        stream.removeAll()
        streamOffset = 0
        fail(message)
    }

    private func note(_ message: String) {
        let line = "[\(stamp.string(from: Date()))] \(message)\n"
        logText += line
        if logText.count > 14000 { logText = String(logText.suffix(12000)) }
    }

    private func fail(_ message: String) {
        status = message
        note("HIBA: \(message)")
    }
}

extension T02Printer: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ manager: CBCentralManager) {
        switch manager.state {
        case .poweredOn:
            status = "Bluetooth bekapcsolva."
            note(status)
            startIfPossible()
        case .poweredOff: fail("A Bluetooth ki van kapcsolva.")
        case .unauthorized: fail("A Bluetooth-hozzáférés nincs engedélyezve a Moments T02 tesztnek.")
        case .unsupported: fail("Az eszköz nem támogatja a szükséges Bluetooth LE funkciót.")
        default: status = "Bluetooth inicializálása…"
        }
    }

    func centralManager(_ manager: CBCentralManager, didDiscover candidate: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let advertisedName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let name = candidate.name ?? advertisedName ?? ""
        let upper = name.uppercased()
        guard upper.contains("T02") || upper.contains("AIMO") else { return }
        discovered[candidate.identifier] = candidate
        let entry = Device(id: candidate.identifier, name: name, rssi: RSSI.intValue)
        if let idx = devices.firstIndex(where: { $0.id == entry.id }) { devices[idx] = entry }
        else { devices.append(entry); note("Eszköz megjelent: \(name), RSSI \(RSSI) dBm.") }
    }

    func centralManager(_ manager: CBCentralManager, didConnect candidate: CBPeripheral) {
        guard candidate.identifier == peripheral?.identifier else { return }
        note("Natív Bluetooth-kapcsolat létrejött; szolgáltatások keresése…")
        status = "Kapcsolódott; BLE-szolgáltatások keresése…"
        candidate.delegate = self
        candidate.discoverServices(nil)
    }

    func centralManager(_ manager: CBCentralManager, didFailToConnect candidate: CBPeripheral, error: Error?) {
        guard candidate.identifier == peripheral?.identifier else { return }
        connectionGeneration += 1
        fail("Csatlakozás sikertelen: \(error?.localizedDescription ?? "ismeretlen hiba")")
    }

    func centralManager(_ manager: CBCentralManager, didDisconnectPeripheral candidate: CBPeripheral, error: Error?) {
        guard candidate.identifier == peripheral?.identifier else { return }
        connectionGeneration += 1
        connectedName = nil
        writeCharacteristic = nil
        notifyCharacteristic = nil
        if isPrinting { abortPrint("Megszakadt a nyomtatás: \(error?.localizedDescription ?? "ismeretlen hiba")") }
        else { status = "A T02 lecsatlakozott."; note(status) }
    }
}

extension T02Printer: CBPeripheralDelegate {
    func peripheral(_ candidate: CBPeripheral, didDiscoverServices error: Error?) {
        guard candidate.identifier == peripheral?.identifier else { return }
        guard error == nil, let services = candidate.services, !services.isEmpty else {
            fail("Nem sikerült lekérni a BLE-szolgáltatásokat: \(error?.localizedDescription ?? "nincsenek szolgáltatások")")
            return
        }
        note("Szolgáltatások: \(services.map { $0.uuid.uuidString }.joined(separator: ", ")).")
        if !services.contains(where: { $0.uuid == expectedServiceUUID }) {
            note("Nincs FF00; minden szolgáltatás alatt megkeressük az FF02 írási csatornát.")
        }
        pendingServices = services.count
        for service in services { candidate.discoverCharacteristics(nil, for: service) }
    }

    func peripheral(_ candidate: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard candidate.identifier == peripheral?.identifier else { return }
        pendingServices = max(0, pendingServices - 1)
        if let error = error {
            note("A(z) \(service.uuid) jellemzői nem olvashatók: \(error.localizedDescription)")
        } else if let chars = service.characteristics {
            note("\(service.uuid) jellemzők: \(chars.map { $0.uuid.uuidString }.joined(separator: ", ")).")
            for char in chars {
                if char.uuid == writeUUID && writeCharacteristic == nil {
                    if char.properties.contains(.writeWithoutResponse) || char.properties.contains(.write) {
                        writeCharacteristic = char
                        needsWriteResponse = !char.properties.contains(.writeWithoutResponse)
                        note("FF02 írható. Írás: \(needsWriteResponse ? "visszaigazolással" : "visszaigazolás nélkül").")
                    }
                }
                if char.uuid == notifyUUID && char.properties.contains(.notify) {
                    notifyCharacteristic = char
                    candidate.setNotifyValue(true, for: char)
                }
            }
        }
        if writeCharacteristic != nil {
            connectionGeneration += 1
            connectedName = candidate.name ?? "T02"
            UserDefaults.standard.set(candidate.identifier.uuidString, forKey: savedIDKey)
            status = "T02 nyomtatásra kész: \(connectedName ?? "T02")."
            note(status)
        } else if pendingServices == 0 {
            fail("Kapcsolódott, de az FF02 írási csatorna hiányzik. Küldd el a naplót!")
        }
    }

    func peripheralIsReady(toSendWriteWithoutResponse candidate: CBPeripheral) {
        guard candidate.identifier == peripheral?.identifier, !needsWriteResponse else { return }
        if isPrinting { sendNextChunk() }
    }

    func peripheral(_ candidate: CBPeripheral, didWriteValueFor char: CBCharacteristic, error: Error?) {
        guard candidate.identifier == peripheral?.identifier, needsWriteResponse,
              char.uuid == writeUUID, isPrinting else { return }
        if let error = error { abortPrint("Bluetooth írási hiba: \(error.localizedDescription)"); return }
        sendNextChunk()
    }

    func peripheral(_ candidate: CBPeripheral, didUpdateValueFor char: CBCharacteristic, error: Error?) {
        guard candidate.identifier == peripheral?.identifier, char.uuid == notifyUUID else { return }
        if let error = error { note("Értesítési hiba: \(error.localizedDescription)"); return }
        if let data = char.value {
            note("Nyomtató státusza: \(data.map { String(format: "%02X", $0) }.joined(separator: " ")).")
        }
    }
}
