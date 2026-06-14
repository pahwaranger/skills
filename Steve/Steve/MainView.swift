import SwiftUI

struct MainView: View {
    let appModel: AppModel

    var body: some View {
        TabView {
            ReviewView()
                .tabItem { Label("Review", systemImage: "list.bullet") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gear") }
        }
        .frame(width: 420, height: 520)
        // Reference observable state so SwiftUI tracks AppModel for re-renders.
        // isChecking drives the pulsing menu-bar icon; lastDerivedState drives the colour.
        .overlay(alignment: .topTrailing) {
            if appModel.isChecking {
                ProgressView()
                    .controlSize(.small)
                    .padding(8)
            }
        }
    }
}
