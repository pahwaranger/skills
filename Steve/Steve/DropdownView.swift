import SwiftUI

// MARK: — Variant B dropdown (Slice 6)

/// The full menu-bar dropdown content — replaces the placeholder `MainView` in
/// the `MenuBarExtra`. Visual design locked to Variant B in the prototype.
///
/// Three zones (top → bottom):
///   1. Tinted status banner  — wording + tint from `StatusLine`
///   2. "Check for updates" button — triggers `appModel.triggerCheck()`
///   3. Skill list grouped by state, uppercase section labels, left-bar accents
///   4. Settings / Quit footer
struct DropdownView: View {
    let appModel: AppModel

    var body: some View {
        VStack(spacing: 0) {
            // Zone 1 — Status banner
            StatusBannerView(
                bannerType: StatusLine.bannerType(
                    isChecking: appModel.isChecking,
                    derivedState: appModel.lastDerivedState,
                    lastError: appModel.lastCheckError
                ),
                wording: StatusLine.wording(
                    isChecking: appModel.isChecking,
                    derivedState: appModel.lastDerivedState,
                    lastError: appModel.lastCheckError,
                    lastCheckDate: appModel.lastCheckDate
                )
            )

            Divider()

            // Zone 2 — Check for updates button
            CheckForUpdatesButton(isChecking: appModel.isChecking) {
                Task { await appModel.triggerCheck() }
            }

            // Zone 3 — Skill list (only when a state is available and sections are non-empty)
            let skillSections: [DropdownSection] = {
                if let derived = appModel.lastDerivedState {
                    return DropdownSections.build(from: derived)
                }
                return []
            }()
            if !skillSections.isEmpty {
                Divider()
                SkillListView(sections: skillSections, appModel: appModel)
            }

            // Footer divider only when there is a skill list above it; an empty dropdown
            // (no derived state yet) must not show a stray divider before the footer.
            if !skillSections.isEmpty {
                Divider()
            }

            // Zone 4 — Footer actions
            FooterActionsView(appModel: appModel)
        }
        .frame(width: 300)
        // Prevent the window growing taller than reasonable
        .fixedSize(horizontal: true, vertical: false)
        .background(.regularMaterial)
    }
}

// MARK: — Status banner

private struct StatusBannerView: View {
    let bannerType: StatusLine.BannerType
    let wording: String

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            // Circular icon — only shown for attention / error / checking
            if bannerType != .neutral {
                BannerIconView(type: bannerType)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(bannerTitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                Text(wording)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(bannerBackground)
    }

    private var bannerTitle: String {
        switch bannerType {
        case .attention: return "Attention required"
        case .checking:  return "Checking…"
        case .error:     return "Check failed"
        case .neutral:   return "All skills up to date"
        }
    }

    private var bannerBackground: Color {
        switch bannerType {
        case .attention: return Color(red: 1.0, green: 0.231, blue: 0.188).opacity(0.08) // #FF3B30
        case .error:     return Color(red: 1.0, green: 0.584, blue: 0).opacity(0.08)     // #FF9500
        case .checking:  return .clear
        case .neutral:   return .clear
        }
    }
}

private struct BannerIconView: View {
    let type: StatusLine.BannerType

    var body: some View {
        ZStack {
            Circle()
                .fill(iconBackground)
                .frame(width: 22, height: 22)
            Text(iconLabel)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(iconForeground)
        }
        .padding(.top, 1)
    }

    private var iconLabel: String {
        switch type {
        case .attention: return "!"
        case .error:     return "!"
        case .checking:  return "↺"
        case .neutral:   return "✓"
        }
    }

    private var iconBackground: Color {
        switch type {
        case .attention: return Color(red: 1.0, green: 0.231, blue: 0.188).opacity(0.12)
        case .error:     return Color(red: 1.0, green: 0.584, blue: 0).opacity(0.12)
        case .checking:  return Color.secondary.opacity(0.12)
        case .neutral:   return Color(red: 0.204, green: 0.780, blue: 0.349).opacity(0.12)
        }
    }

    private var iconForeground: Color {
        switch type {
        case .attention: return Color(red: 1.0, green: 0.231, blue: 0.188)   // #FF3B30
        case .error:     return Color(red: 1.0, green: 0.584, blue: 0)        // #FF9500
        case .checking:  return .secondary
        case .neutral:   return Color(red: 0.204, green: 0.780, blue: 0.349) // #34C759
        }
    }
}

// MARK: — Check for updates button

private struct CheckForUpdatesButton: View {
    let isChecking: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if isChecking {
                    ProgressView()
                        .controlSize(.mini)
                        .scaleEffect(0.8)
                }
                Text("↺  Check for updates")
                    .font(.system(size: 12.5))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5)
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(Color.primary.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(Color.primary.opacity(0.10), lineWidth: 1)
                )
        )
        .foregroundStyle(Color.accentColor)
        .disabled(isChecking)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
    }
}

// MARK: — Skill list

private struct SkillListView: View {
    let sections: [DropdownSection]
    let appModel: AppModel

    var body: some View {
        VStack(spacing: 0) {
            ForEach(sections, id: \.state) { section in
                // Uppercase section label (Variant B)
                Text(DropdownSections.label(for: section.state))
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(Color.secondary.opacity(0.7))
                    .kerning(0.6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.top, 6)
                    .padding(.bottom, 2)

                ForEach(section.skills, id: \.self) { skillName in
                    SkillRowView(skillName: skillName, state: section.state, appModel: appModel)
                }
            }
        }
    }
}

private struct SkillRowView: View {
    let skillName: SkillName
    let state: SkillState
    let appModel: AppModel

    @Environment(\.openWindow) private var openWindow
    @State private var isHovered = false

    var body: some View {
        Button(action: { handleTap() }) {
            HStack(spacing: 0) {
                // Left-bar accent (3 px, 6pt inset top/bottom) — Variant B
                Rectangle()
                    .fill(accentColor)
                    .frame(width: 3)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
                    .padding(.vertical, 6)
                    .padding(.leading, 9)
                    .padding(.trailing, 8)

                Text(skillName)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer()
            }
            .frame(height: 26)
            .background(isHovered ? Color.primary.opacity(0.05) : Color.clear)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    private var accentColor: Color {
        switch state {
        case .removedOnOrigin: return Color(red: 1.0, green: 0.231, blue: 0.188)   // #FF3B30
        case .updateAvailable: return Color(red: 1.0, green: 0.584, blue: 0)        // #FF9500
        case .skipped:         return Color(red: 0.557, green: 0.557, blue: 0.576) // #8E8E93
        case .upToDate:        return .clear
        }
    }

    private func handleTap() {
        switch state {
        case .upToDate:
            // Open the skill's GitHub directory in the browser.
            // Use AppModel's resolved default branch (from OriginClient.resolveDefaultBranch(),
            // called at launch and stored in `resolvedDefaultBranch`). Fall back to the
            // init-time `branch` value if resolution hasn't completed yet.
            // TODO(Slice 8–10): If the resolved branch is still nil (e.g. offline launch),
            // consider surfacing a toast / disabling the row rather than using the fallback.
            let resolvedBranch = appModel.resolvedDefaultBranch ?? appModel.branch
            let urlString = "https://github.com/\(appModel.owner)/\(appModel.repo)/tree/\(resolvedBranch)/skills/\(skillName)"
            if let url = URL(string: urlString) {
                NSWorkspace.shared.open(url)
            }

        case .removedOnOrigin, .updateAvailable, .skipped:
            // Set the focus skill on the shared AppModel channel, then open (or
            // raise) the Review window via the SwiftUI environment action.
            // `openWindow(id:)` opens the Window scene on first call and brings it
            // to the front on subsequent calls — no AppKit hacks needed.
            appModel.reviewFocusSkill = skillName
            openWindow(id: "review")
        }
    }
}

// MARK: — Footer (Settings + Quit)

private struct FooterActionsView: View {
    let appModel: AppModel

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            DropdownActionRow(label: "Settings…") {
                // Open (or raise) the Settings window.
                // `SettingsLink` is unreliable from `MenuBarExtra` context
                // (per prototypes/menu-bar-dropdown/NOTES.md / Steipete 2025).
                // `openWindow(id:)` opens the Window scene on first call and brings
                // it to the front on subsequent calls — the same pattern used for
                // the Review window (Slice 8). No AppKit hacks needed.
                openWindow(id: "settings")
            }
            DropdownActionRow(label: "Quit Steve") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(.vertical, 3)
    }
}

private struct DropdownActionRow: View {
    let label: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .frame(height: 26)
                .background(isHovered ? Color.primary.opacity(0.05) : Color.clear)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
