import SwiftUI

@main
struct SteveApp: App {
    // The composition root: wires OriginClient → Cache → StateEngine → CheckScheduler.
    // Instantiated once at app launch; AppModel is passed into views so they can
    // read scheduler state for the menu-bar icon.
    private let appModel = AppModel(
        owner: "pahwaranger",
        repo: "skills",
        branch: "master",
        transport: URLSessionTransport()
    )

    var body: some Scene {
        MenuBarExtra("Steve", systemImage: "arrow.triangle.2.circlepath") {
            MainView(appModel: appModel)
                .task {
                    await appModel.start()
                }
        }
        .menuBarExtraStyle(.window)
    }
}
