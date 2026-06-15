import SwiftUI
import ServiceManagement
#if SWIFT_PACKAGE
import AppCore
import DiffBridge
#endif

// MARK: — Settings window (Variant C, Slice 11)
//
// Layout: two captioned Form sections —
//   "Syncing"  — Automatic checks + Minutes between checks (nested, disabled-not-hidden when off)
//   "General"  — Launch at login + Default diff view
//
// Design locked to Variant C (prototypes/settings/NOTES.md):
//   • Minutes between checks stays VISIBLE but DISABLED when Automatic checks is off.
//   • Section footer caption switches between on/off states (via SettingsStore.syncingCaption).
//   • Section header is always the constant word "Syncing".

struct SettingsView: View {

    // MARK: — Owned state

    /// Persisted settings — backed by the real UserDefaults.standard in production.
    @State private var settings: SettingsStore = SettingsStore()

    /// Launch-at-login manager — production uses SMAppService.
    private let launchManager: LaunchAtLoginManaging = SMAppServiceLaunchManager.shared

    var body: some View {
        Form {
            // ── Syncing section ─────────────────────────────────────────────────────────────────
            Section {
                // Automatic checks toggle
                Toggle("Automatic checks", isOn: Binding(
                    get: { settings.automaticChecksEnabled },
                    set: { settings.automaticChecksEnabled = $0 }
                ))

                // Minutes between checks — nested under Automatic checks;
                // visible but DISABLED (greyed out) when auto checks is off (Variant C).
                HStack {
                    // Indent to show nesting under the toggle above
                    Spacer()
                        .frame(width: 18)

                    // Stepper with numeric text field; step=1 per Variant C spec (ticket #46).
                    Stepper(value: Binding(
                        get: { settings.minutesBetweenChecks },
                        set: { settings.minutesBetweenChecks = $0 }
                    ), in: 1...1440, step: 1) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                TextField("60", value: Binding(
                                    get: { settings.minutesBetweenChecks },
                                    set: { settings.minutesBetweenChecks = $0 }
                                ), format: .number)
                                .frame(width: 52)
                                .multilineTextAlignment(.trailing)
                                .disabled(!settings.isIntervalEnabled)

                                Text("min")
                                    .foregroundStyle(settings.isIntervalEnabled ? .primary : .secondary)
                            }
                            Text("Minutes between checks")
                                .foregroundStyle(settings.isIntervalEnabled ? .primary : .secondary)
                            Text("How often Steve looks at Origin for changes.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .disabled(!settings.isIntervalEnabled)
                }
            } header: {
                // Header is the CONSTANT word "Syncing" in both on/off states (Variant C).
                Text("Syncing")
            } footer: {
                // Caption text switches via SettingsStore.syncingCaption (pure, unit-tested).
                Text(settings.syncingCaption)
            }

            // ── General section ────────────────────────────────────────────────────────────────
            Section {
                // Launch at login
                Toggle("Launch at login", isOn: Binding(
                    get: { settings.launchAtLogin },
                    set: { newValue in
                        settings.launchAtLogin = newValue
                        applyLaunchAtLogin(newValue)
                    }
                ))

                // Default diff view — Split / Unified segmented picker
                Picker("Default diff view", selection: Binding(
                    get: { settings.defaultDiffView },
                    set: { settings.defaultDiffView = $0 }
                )) {
                    Text("Split").tag(DiffViewMode.split)
                    Text("Unified").tag(DiffViewMode.unified)
                }
                .pickerStyle(.segmented)
            } header: {
                Text("General")
            } footer: {
                Text("How diffs open in the Review tab. You can still switch per-review.")
            }
        }
        .formStyle(.grouped)
        .padding(8)
        .frame(width: 400)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: — Private helpers

    private func applyLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try launchManager.register()
            } else {
                try launchManager.unregister()
            }
        } catch {
            // In local-development signing, SMAppService may fail if the app
            // isn't code-signed. Log and proceed — the setting is still persisted
            // and the toggle reflects intent; the OS call is best-effort here.
            print("[Steve] LaunchAtLogin \(enabled ? "register" : "unregister") failed: \(error)")
        }
    }
}
