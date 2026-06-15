import Foundation
#if SWIFT_PACKAGE
import DiffBridge
#endif

/// Persists the four user-configurable settings across app restarts via `UserDefaults`.
///
/// Inject a custom `UserDefaults` suite in tests to keep persistence isolated
/// (never pollutes real app prefs, fully repeatable).
///
/// **Settings and defaults (per ticket #21):**
/// - `launchAtLogin`        — default: `true`
/// - `automaticChecksEnabled` — default: `true`
/// - `minutesBetweenChecks` — default: `60`
/// - `defaultDiffView`      — default: `.split`
///
/// The store is a plain `struct`. `@unchecked Sendable` is safe: `UserDefaults` is
/// documented as thread-safe for individual key reads/writes, and each method here
/// performs only one atomic get/set. The struct itself holds only immutable state
/// (the `defaults` reference never changes after init).
public struct SettingsStore: @unchecked Sendable {

    // MARK: — UserDefaults keys

    private enum Keys {
        static let launchAtLogin            = "settings.launchAtLogin"
        static let automaticChecksEnabled   = "settings.automaticChecksEnabled"
        static let minutesBetweenChecks     = "settings.minutesBetweenChecks"
        static let defaultDiffView          = "settings.defaultDiffView"
    }

    // MARK: — Backing store

    // `UserDefaults` is documented as thread-safe for individual key reads/writes.
    // We use `@unchecked Sendable` on the struct so Swift 6 strict-concurrency
    // doesn't flag this stored property.
    private let defaults: UserDefaults

    // MARK: — Init

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: — Launch at login

    /// Whether the app should launch at login (default: `true`).
    public var launchAtLogin: Bool {
        get {
            if defaults.object(forKey: Keys.launchAtLogin) == nil {
                return true // default
            }
            return defaults.bool(forKey: Keys.launchAtLogin)
        }
        set {
            defaults.set(newValue, forKey: Keys.launchAtLogin)
        }
    }

    // MARK: — Automatic checks

    /// Whether the periodic Scheduler timer is enabled (default: `true`).
    public var automaticChecksEnabled: Bool {
        get {
            if defaults.object(forKey: Keys.automaticChecksEnabled) == nil {
                return true // default
            }
            return defaults.bool(forKey: Keys.automaticChecksEnabled)
        }
        set {
            defaults.set(newValue, forKey: Keys.automaticChecksEnabled)
        }
    }

    // MARK: — Minutes between checks

    /// How many minutes between automatic checks (default: `60`).
    public var minutesBetweenChecks: Int {
        get {
            let stored = defaults.integer(forKey: Keys.minutesBetweenChecks)
            return stored == 0 ? 60 : stored // default to 60 when not set
        }
        set {
            defaults.set(newValue, forKey: Keys.minutesBetweenChecks)
        }
    }

    // MARK: — Default diff view

    /// The initial diff view mode when the Review window opens (default: `.split`).
    public var defaultDiffView: DiffViewMode {
        get {
            guard let raw = defaults.string(forKey: Keys.defaultDiffView),
                  let mode = DiffViewMode(rawValue: raw)
            else { return .split } // default
            return mode
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.defaultDiffView)
        }
    }

    // MARK: — Derived state

    /// `true` when the interval stepper/field should be interactive.
    /// `false` (greyed out / disabled) when `automaticChecksEnabled` is `false`,
    /// per Variant C design: the interval row stays visible but disabled so the
    /// user can see the stored value without re-entering it.
    public var isIntervalEnabled: Bool {
        automaticChecksEnabled
    }

    // MARK: — Syncing caption (Variant C, ticket #46)

    /// Returns the below-card Syncing section caption for the current `automaticChecksEnabled` state.
    ///
    /// Pure computed property — no side-effects, fully unit-testable.
    /// - ON:  explains the interval-based check cadence.
    /// - OFF: explains on-demand-only mode, with the exact menu item name in curly quotes.
    public var syncingCaption: String {
        if automaticChecksEnabled {
            return "Steve checks Origin on this interval and flags changes in the menu bar."
        } else {
            return "Off \u{2014} Steve only checks when you choose \u{201C}Check for updates\u{201D} from the menu."
        }
    }
}
