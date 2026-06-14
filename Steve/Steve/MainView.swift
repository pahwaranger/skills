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
    }
}
