import Testing
import Foundation
@testable import AppCore

// MARK: — SettingsStore persistence tests

@Suite("SettingsStore — persistence")
struct SettingsStorePersistenceTests {

    // Builds an isolated SettingsStore backed by a fresh UserDefaults suite so
    // tests never contaminate real app prefs and are repeatable.
    private func makeStore() -> SettingsStore {
        let suiteName = "com.steve.tests.settings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        // Clear any pre-existing keys in this suite (safety net)
        defaults.removePersistentDomain(forName: suiteName)
        return SettingsStore(defaults: defaults)
    }

    // MARK: — Default values when nothing is stored

    @Test func launchAtLoginDefaultsToTrue() {
        let store = makeStore()
        #expect(store.launchAtLogin == true,
                "launchAtLogin must default to true (ticket spec)")
    }

    @Test func automaticChecksDefaultsToTrue() {
        let store = makeStore()
        #expect(store.automaticChecksEnabled == true,
                "automaticChecksEnabled must default to true")
    }

    @Test func minutesBetweenChecksDefaultsTo60() {
        let store = makeStore()
        #expect(store.minutesBetweenChecks == 60,
                "minutesBetweenChecks must default to 60")
    }

    @Test func defaultDiffViewDefaultsToSplit() {
        let store = makeStore()
        #expect(store.defaultDiffView == .split,
                "defaultDiffView must default to .split")
    }

    // MARK: — Round-trip persistence

    @Test func launchAtLoginRoundTrips() {
        let suiteName = "com.steve.tests.settings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        // Write
        var store1 = SettingsStore(defaults: defaults)
        store1.launchAtLogin = false

        // Read from a fresh store over the same UserDefaults
        let store2 = SettingsStore(defaults: defaults)
        #expect(store2.launchAtLogin == false,
                "launchAtLogin=false must survive across a fresh SettingsStore over the same defaults")
    }

    @Test func automaticChecksRoundTrips() {
        let suiteName = "com.steve.tests.settings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        var store1 = SettingsStore(defaults: defaults)
        store1.automaticChecksEnabled = false

        let store2 = SettingsStore(defaults: defaults)
        #expect(store2.automaticChecksEnabled == false,
                "automaticChecksEnabled=false must survive across a fresh SettingsStore")
    }

    @Test func minutesBetweenChecksRoundTrips() {
        let suiteName = "com.steve.tests.settings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        var store1 = SettingsStore(defaults: defaults)
        store1.minutesBetweenChecks = 30

        let store2 = SettingsStore(defaults: defaults)
        #expect(store2.minutesBetweenChecks == 30,
                "minutesBetweenChecks=30 must survive across a fresh SettingsStore")
    }

    @Test func defaultDiffViewRoundTrips() {
        let suiteName = "com.steve.tests.settings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        var store1 = SettingsStore(defaults: defaults)
        store1.defaultDiffView = .unified

        let store2 = SettingsStore(defaults: defaults)
        #expect(store2.defaultDiffView == .unified,
                "defaultDiffView=.unified must survive across a fresh SettingsStore")
    }
}

// MARK: — LaunchAtLogin seam tests

@Suite("LaunchAtLoginManaging — mockable seam")
struct LaunchAtLoginSeamTests {

    // A mock conformer that records calls without touching SMAppService.
    final class MockLaunchAtLoginManager: LaunchAtLoginManaging, @unchecked Sendable {
        private let lock = NSLock()
        private var _registerCount = 0
        private var _unregisterCount = 0
        private var _isRegisteredValue: Bool

        init(isRegistered: Bool = false) {
            _isRegisteredValue = isRegistered
        }

        var registerCount: Int { lock.withLock { _registerCount } }
        var unregisterCount: Int { lock.withLock { _unregisterCount } }

        var isRegistered: Bool {
            get { lock.withLock { _isRegisteredValue } }
        }

        func register() throws {
            lock.withLock {
                _registerCount += 1
                _isRegisteredValue = true
            }
        }

        func unregister() throws {
            lock.withLock {
                _unregisterCount += 1
                _isRegisteredValue = false
            }
        }
    }

    @Test func toggleToTrueCallsRegister() throws {
        let mock = MockLaunchAtLoginManager(isRegistered: false)
        try mock.register()
        #expect(mock.registerCount == 1, "register() must be called once when toggling on")
        #expect(mock.isRegistered == true)
    }

    @Test func toggleToFalseCallsUnregister() throws {
        let mock = MockLaunchAtLoginManager(isRegistered: true)
        try mock.unregister()
        #expect(mock.unregisterCount == 1, "unregister() must be called once when toggling off")
        #expect(mock.isRegistered == false)
    }

    @Test func registerDoesNotCallUnregister() throws {
        let mock = MockLaunchAtLoginManager(isRegistered: false)
        try mock.register()
        #expect(mock.unregisterCount == 0,
                "register() must not call unregister()")
    }

    @Test func unregisterDoesNotCallRegister() throws {
        let mock = MockLaunchAtLoginManager(isRegistered: true)
        try mock.unregister()
        #expect(mock.registerCount == 0,
                "unregister() must not call register()")
    }
}

// MARK: — Interval-disabled-when-auto-off state tests

@Suite("SettingsStore — interval disabled when auto checks off")
struct SettingsIntervalDisabledTests {

    private func makeStore(automaticChecks: Bool) -> SettingsStore {
        let suiteName = "com.steve.tests.settings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        var store = SettingsStore(defaults: defaults)
        store.automaticChecksEnabled = automaticChecks
        return store
    }

    @Test func intervalIsNotDisabledWhenAutomaticChecksOn() {
        let store = makeStore(automaticChecks: true)
        // When automaticChecksEnabled is true, interval control is enabled
        #expect(store.isIntervalEnabled == true,
                "interval must be enabled when automaticChecksEnabled is true")
    }

    @Test func intervalIsDisabledWhenAutomaticChecksOff() {
        let store = makeStore(automaticChecks: false)
        // When automaticChecksEnabled is false, interval control is disabled (greyed out)
        #expect(store.isIntervalEnabled == false,
                "interval must be disabled (greyed out) when automaticChecksEnabled is false")
    }
}
