import SwiftUI

@main
struct SteveApp: App {
    var body: some Scene {
        MenuBarExtra("Steve", systemImage: "arrow.triangle.2.circlepath") {
            MainView()
        }
        .menuBarExtraStyle(.window)
    }
}
