import Foundation
import SwiftUI
import LocalAuthentication
import Combine

struct POSSystemStatus: Codable {
    let pluginVersion: String
    let apiSchemaVersion: Int
    let minimumAppVersion: String
    let recommendedAppVersion: String
    let wordpressVersion: String
    let woocommerceVersion: String
    let currency: String
    let https: Bool
    let cryptoReady: Bool
    let providerID: String
    let providerReady: Bool
    let testMode: Bool
    let uploadsWritable: Bool
    let serverTime: String
    let operatorName: String

    enum CodingKeys: String, CodingKey {
        case pluginVersion = "plugin_version"
        case apiSchemaVersion = "api_schema_version"
        case minimumAppVersion = "minimum_app_version"
        case recommendedAppVersion = "recommended_app_version"
        case wordpressVersion = "wordpress_version"
        case woocommerceVersion = "woocommerce_version"
        case currency, https
        case cryptoReady = "crypto_ready"
        case providerID = "provider_id"
        case providerReady = "provider_ready"
        case testMode = "test_mode"
        case uploadsWritable = "uploads_writable"
        case serverTime = "server_time"
        case operatorName = "operator"
    }

    var coreReady: Bool {
        apiSchemaVersion == 2 && currency == "HUF" && https && cryptoReady && providerReady && uploadsWritable
    }
}

struct POSRecentReceipt: Codable, Identifiable {
    let id: Int
    let receiptNumber: String
    let paymentMethod: String
    let grossTotal: Double
    let status: String
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, status
        case receiptNumber = "receipt_number"
        case paymentMethod = "payment_method"
        case grossTotal = "gross_total"
        case createdAt = "created_at"
    }

    var statusText: String {
        switch status {
        case "issued": return "Kiállítva"
        case "stock_warning": return "Készlet ellenőrzendő"
        case "test": return "Teszt"
        case "uncertain": return "Ellenőrzendő"
        case "processing": return "Feldolgozás alatt"
        case "document_created": return "Készlet rendezendő"
        case "failed": return "Sikertelen"
        case "cancelled": return "Sztornózva"
        default: return status
        }
    }
}

struct OperationEvent: Codable, Identifiable {
    let id: UUID
    let date: Date
    let title: String
    let detail: String
    let success: Bool
}

final class OperationLogStore: ObservableObject {
    static let shared = OperationLogStore()
    @Published private(set) var events: [OperationEvent] = []

    private let key = "MomentsPOS.OperationLog.v1"
    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([OperationEvent].self, from: data) {
            events = Array(decoded.prefix(20))
        }
    }

    func add(_ title: String, detail: String = "", success: Bool = true) {
        let event = OperationEvent(id: UUID(), date: Date(), title: title, detail: detail, success: success)
        events.insert(event, at: 0)
        events = Array(events.prefix(20))
        if let data = try? JSONEncoder().encode(events) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

struct SigningStatus {
    let expirationDate: Date?

    var daysRemaining: Int? {
        guard let expirationDate else { return nil }
        return max(0, Int(ceil(expirationDate.timeIntervalSinceNow / 86400.0)))
    }

    var warningText: String? {
        guard let daysRemaining, daysRemaining <= 2 else { return nil }
        if daysRemaining == 0 { return "Az alkalmazás aláírása ma lejár. Frissítsd SideStore-ban." }
        if daysRemaining == 1 { return "Az alkalmazás aláírása kb. 1 napon belül lejár. Frissítsd SideStore-ban." }
        return "Az alkalmazás aláírása kb. 2 napon belül lejár. Frissítsd SideStore-ban."
    }

    static func current() -> SigningStatus {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .isoLatin1),
              let start = text.range(of: "<?xml"),
              let end = text.range(of: "</plist>", range: start.lowerBound..<text.endIndex) else {
            return SigningStatus(expirationDate: nil)
        }
        let plistText = String(text[start.lowerBound..<end.upperBound])
        guard let plistData = plistText.data(using: .utf8),
              let object = try? PropertyListSerialization.propertyList(from: plistData, options: [], format: nil),
              let dict = object as? [String: Any],
              let expiration = dict["ExpirationDate"] as? Date else {
            return SigningStatus(expirationDate: nil)
        }
        return SigningStatus(expirationDate: expiration)
    }
}

final class AppLockManager: ObservableObject {
    @Published private(set) var isLocked = false
    @Published private(set) var message = "Face ID szükséges."
    private var backgroundedAt: Date?
    private var authenticating = false

    func prepare(enabled: Bool) {
        guard enabled else { isLocked = false; return }
        if !isLocked {
            isLocked = true
            authenticate()
        }
    }

    func sceneChanged(_ phase: ScenePhase, enabled: Bool) {
        switch phase {
        case .background:
            backgroundedAt = Date()
        case .active:
            guard enabled else { isLocked = false; return }
            if let backgroundedAt, Date().timeIntervalSince(backgroundedAt) >= 5 * 60 {
                isLocked = true
            }
            if isLocked { authenticate() }
            self.backgroundedAt = nil
        default:
            break
        }
    }

    func authenticate() {
        guard isLocked, !authenticating else { return }
        authenticating = true
        let context = LAContext()
        context.localizedCancelTitle = "Mégsem"
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            authenticating = false
            isLocked = false
            message = "Az iPhone-on nincs használható Face ID / készülékkód, ezért az appzár nem aktiválható."
            OperationLogStore.shared.add("Appzár nem aktiválható", detail: error?.localizedDescription ?? "Nincs készülékazonosítás", success: false)
            return
        }
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Moments POS megnyitása") { [weak self] success, authError in
            DispatchQueue.main.async {
                guard let self else { return }
                self.authenticating = false
                if success {
                    self.isLocked = false
                    self.message = "Face ID szükséges."
                    OperationLogStore.shared.add("Appzár feloldva", detail: "Face ID / készülékkód")
                } else {
                    self.message = authError?.localizedDescription ?? "A feloldás nem sikerült."
                }
            }
        }
    }
}

func momentsVersionAtLeast(_ current: String, _ minimum: String) -> Bool {
    current.compare(minimum, options: .numeric) != .orderedAscending
}
