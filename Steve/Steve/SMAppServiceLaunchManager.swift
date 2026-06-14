import ServiceManagement
#if SWIFT_PACKAGE
import AppCore
#endif

/// Production implementation of `LaunchAtLoginManaging` that delegates to
/// `SMAppService.mainApp` for local-development signing.
///
/// This wraps the real OS call and lives in the app target so it can import
/// `ServiceManagement` without polluting the pure-Swift AppCore package.
/// Tests use a mock conformer instead — no OS interaction required.
final class SMAppServiceLaunchManager: LaunchAtLoginManaging, @unchecked Sendable {

    static let shared = SMAppServiceLaunchManager()
    private init() {}

    var isRegistered: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func register() throws {
        try SMAppService.mainApp.register()
    }

    func unregister() throws {
        try SMAppService.mainApp.unregister()
    }
}
