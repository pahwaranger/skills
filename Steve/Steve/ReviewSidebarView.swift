import SwiftUI
#if SWIFT_PACKAGE
import AppCore
import StateEngine
#endif

// MARK: — Review window sidebar (Slice 8, Variant D)

/// The sidebar panel of the Review window — Variant D from
/// `prototypes/review-diff/NOTES.md`.
///
/// Structure (top → bottom):
///   1. **Sticky action header**: tri-state select toggle + Update N + Skip N
///      Always visible, does not scroll.
///   2. **Scrollable skill list**: skills grouped by state in order
///      Removed → Update Available → Skipped → Up to Date, alpha within each group.
///      Non–up-to-date rows have individual Update + Skip buttons.
///
/// The sidebar scrolls to and pre-selects the `focusedSkillName` when the
/// Review window opens from a dropdown skill row.
struct ReviewSidebarView: View {

    // MARK: — Dependencies

    /// The sidebar model, owned by `ReviewWindowView` and passed in as a binding
    /// so selection mutations flow back up.
    @Binding var model: ReviewSidebarModel

    /// The name of the skill currently displayed in the diff pane (right-hand side).
    @Binding var selectedSkillName: SkillName?

    /// Called when an Update action should be performed for the given skill names.
    /// Single-skill rows pass `[skillName]`; the bulk header passes all selected names.
    let onUpdate: ([String]) -> Void

    /// Called when a Skip action should be performed for the given skill names.
    /// Single-skill rows pass `[skillName]`; the bulk header passes all selected names.
    let onSkip: ([String]) -> Void

    // MARK: — Body

    var body: some View {
        VStack(spacing: 0) {
            // ── Sticky action header ──────────────────────────────────────
            SidebarActionHeader(
                model: $model,
                onUpdate: { onUpdate(Array(model.selectedSkillNames)) },
                onSkip: { onSkip(Array(model.selectedSkillNames)) }
            )

            Divider()

            // ── Scrollable skill list ─────────────────────────────────────
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0, pinnedViews: []) {
                        ForEach(model.sections, id: \.state) { section in
                            SidebarGroupHeader(
                                label: ReviewSidebarModel.label(for: section.state),
                                state: section.state
                            )
                            ForEach(section.skills, id: \.self) { skillName in
                                let state = skillState(for: skillName)
                                let isActionable = state != .upToDate
                                let isSelected   = selectedSkillName == skillName
                                let isChecked    = model.selectedSkillNames.contains(skillName)

                                SidebarSkillRow(
                                    skillName: skillName,
                                    state: state,
                                    isActionable: isActionable,
                                    isSelected: isSelected,
                                    isChecked: isChecked,
                                    onSelect: {
                                        selectedSkillName = skillName
                                    },
                                    onToggle: {
                                        model.toggleSkill(skillName)
                                    },
                                    onUpdate: {
                                        // Single-skill Update: wired in Slice 10.
                                        onUpdate([skillName])
                                    },
                                    onSkip: {
                                        // Single-skill Skip: wired in Slice 10.
                                        onSkip([skillName])
                                    }
                                )
                                .id(skillName)
                            }
                        }
                    }
                }
                // Scroll to and pre-select the focused skill on first appearance.
                .onAppear {
                    if let focused = selectedSkillName {
                        withAnimation {
                            proxy.scrollTo(focused, anchor: .center)
                        }
                    }
                }
                .onChange(of: selectedSkillName) { _, newValue in
                    if let focused = newValue {
                        withAnimation {
                            proxy.scrollTo(focused, anchor: .center)
                        }
                    }
                }
            }
        }
    }

    /// Looks up the `SkillState` for `skillName` from the model's sections.
    private func skillState(for skillName: SkillName) -> SkillState {
        for section in model.sections {
            if section.skills.contains(skillName) { return section.state }
        }
        return .upToDate
    }
}

// MARK: — Sticky action header

private struct SidebarActionHeader: View {
    @Binding var model: ReviewSidebarModel
    let onUpdate: () -> Void
    let onSkip: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            // 3-state select toggle: ☐ / ☑ / ⊟
            Button(action: { model.cycleSelection() }) {
                Text(selectIcon)
                    .font(.system(size: 15))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .help(selectTooltip)

            Spacer()

            // Update N button — wired in Slice 10
            Button(action: onUpdate) {
                Text(model.selectedCount > 0 ? "Update \(model.selectedCount)" : "Update")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(model.selectedCount == 0)

            // Skip N button — wired in Slice 10
            Button(action: onSkip) {
                Text(model.selectedCount > 0 ? "Skip \(model.selectedCount)" : "Skip")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(model.selectedCount == 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var selectIcon: String {
        switch model.selectionMode {
        case .none, .partial: return "☐"
        case .all:            return "☑"
        case .new:            return "⊟"
        }
    }

    private var selectTooltip: String {
        switch model.selectionMode {
        case .none, .partial: return "Select all actionable"
        case .all:            return "Select new only"
        case .new:            return "Deselect all"
        }
    }
}

// MARK: — Group header

private struct SidebarGroupHeader: View {
    let label: String
    let state: SkillState

    var body: some View {
        Text(label)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(stateColor)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 2)
    }

    private var stateColor: Color {
        switch state {
        case .removedOnOrigin: return Color(red: 1.0, green: 0.231, blue: 0.188)  // #FF3B30
        case .updateAvailable: return Color(red: 0.0,  green: 0.478, blue: 1.0)    // #007AFF
        case .skipped:         return Color(red: 1.0, green: 0.584, blue: 0)       // #FF9500
        case .upToDate:        return .secondary
        }
    }
}

// MARK: — Skill row

private struct SidebarSkillRow: View {
    let skillName: SkillName
    let state: SkillState
    let isActionable: Bool
    let isSelected: Bool
    let isChecked: Bool
    let onSelect: () -> Void
    let onToggle: () -> Void
    let onUpdate: () -> Void
    let onSkip: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 6) {
            // Checkbox — only shown for actionable skills
            if isActionable {
                Button(action: onToggle) {
                    Image(systemName: isChecked ? "checkmark.square.fill" : "square")
                        .font(.system(size: 13))
                        .foregroundStyle(isChecked ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.plain)
                .frame(width: 18)
            } else {
                Spacer().frame(width: 18)
            }

            // Skill name (tappable — selects for diff pane)
            Text(skillName)
                .font(.system(size: 13))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { onSelect() }

            // Per-row Update / Skip — only on non–up-to-date skills, shown on hover
            if isActionable && (isHovered || isSelected) {
                HStack(spacing: 4) {
                    Button("Update", action: onUpdate)
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    Button("Skip", action: onSkip)
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                }
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(rowBackground)
        .onHover { isHovered = $0 }
    }

    private var rowBackground: Color {
        if isSelected { return Color.accentColor.opacity(0.12) }
        if isHovered  { return Color.primary.opacity(0.05) }
        return .clear
    }
}
