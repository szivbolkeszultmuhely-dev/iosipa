import SwiftUI

@main
struct MomentsPOST02App: App {
    // One printer instance for the whole app. The proven T02Printer and
    // T02Raster (1.0.4) are intentionally unchanged in this release.
    @StateObject private var printer = T02Printer()
    @StateObject private var posWeb = POSWebModel()

    var body: some Scene {
        WindowGroup {
            TabView {
                POSWebScreen(model: posWeb)
                    .tabItem { Label("Kassza", systemImage: "creditcard") }

                TestView()
                    .tabItem { Label("T02 próba", systemImage: "printer") }
            }
            .environmentObject(printer)
        }
    }
}
