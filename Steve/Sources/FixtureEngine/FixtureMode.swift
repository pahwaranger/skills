import Foundation

/// Determines whether the app is running in fixture mode.
///
/// Fixture mode is opt-in, triggered by either:
/// - `--fixtures` in `ProcessInfo.arguments` (command-line launch)
/// - `STEVE_FIXTURES=1` in `ProcessInfo.environment` (env-var launch)
///
/// When active, the app boots with `AppModel.fixtureMode(scenario:)` instead of
/// the real model, giving a reproducible sandbox for UI development and testing (ADR 0009).
public enum FixtureMode {
    /// True iff `--fixtures` is in `ProcessInfo.arguments` or `STEVE_FIXTURES=1`
    /// is in `ProcessInfo.environment`. False in production and normal test runs.
    public static var isActive: Bool {
        ProcessInfo.processInfo.arguments.contains("--fixtures")
            || ProcessInfo.processInfo.environment["STEVE_FIXTURES"] == "1"
    }
}
