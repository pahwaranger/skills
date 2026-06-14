import Foundation

/// Protocol seam for launch-at-login registration, making toggle logic unit-testable
/// without touching the real `SMAppService` system call.
///
/// Production: `SMAppServiceLaunchManager` wraps `SMAppService.mainApp`.
/// Tests: a mock conformer records `register()`/`unregister()` calls without
/// any OS interaction.
public protocol LaunchAtLoginManaging: Sendable {
    /// Whether the app is currently registered for launch at login.
    var isRegistered: Bool { get }
    /// Register the app for launch at login (enable).
    func register() throws
    /// Unregister the app from launch at login (disable).
    func unregister() throws
}
