import SwiftUI

@main
struct MomentsPOST02App: App {
    @StateObject private var printer = T02Printer()

    var body: some Scene {
        WindowGroup {
            TestView()
                .environmentObject(printer)
        }
    }
}
