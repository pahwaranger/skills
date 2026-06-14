import SwiftUI
#if SWIFT_PACKAGE
import AppCore
import StateEngine
#endif

// MARK: — Review window (Slice 8)

/// The full Review window content — sidebar + diff pane.
///
/// This view is hosted in a `Window` scene in `SteveApp.swift`.
/// The `focusedSkillName` is passed via the `ReviewWindowModel` environment
/// so the sidebar can scroll to it on first open and pre-select it.
///
/// Diff pane content (Slices 9a/9b) and bulk Update/Skip wiring (Slice 10)
/// are not implemented here — see TODO comments.
struct ReviewWindowView: View {

    let appModel: AppModel

    // MARK: — State

    /// Sidebar selection/grouping model — rebuilt whenever `appModel.lastDerivedState` changes.
    @State private var sidebarModel: ReviewSidebarModel = ReviewSidebarModel(skills: [])

    /// The skill currently shown in the diff pane.
    @State private var selectedSkillName: SkillName?

    // MARK: — Body

    var body: some View {
        HSplitView {
            // ── Left: Sidebar ────────────────────────────────────────────
            ReviewSidebarView(
                model: $sidebarModel,
                selectedSkillName: $selectedSkillName
            )
            .frame(minWidth: 200, idealWidth: 240, maxWidth: 300)

            // ── Right: Diff pane ─────────────────────────────────────────
            DiffPanePlaceholder(selectedSkillName: selectedSkillName)
                .frame(minWidth: 400, maxWidth: .infinity)
        }
        .frame(minWidth: 680, minHeight: 440)
        // Rebuild the sidebar model whenever the derived state updates.
        .onChange(of: appModel.lastDerivedState) { _, newState in
            rebuildSidebarModel(from: newState)
        }
        // Consume the focus-skill handoff set by the dropdown row action.
        // The property is cleared immediately after reading so a second open
        // of the same window does not re-select a stale skill.
        .onChange(of: appModel.reviewFocusSkill) { _, skillName in
            guard let skillName else { return }
            applyFocusSkill(skillName)
            appModel.reviewFocusSkill = nil
        }
        .onAppear {
            rebuildSidebarModel(from: appModel.lastDerivedState)
            // Consume any focus skill that was set before the view appeared
            // (i.e. first open: the dropdown set reviewFocusSkill before the
            // window existed, so onChange fired into the void).
            if let skillName = appModel.reviewFocusSkill {
                applyFocusSkill(skillName)
                appModel.reviewFocusSkill = nil
            }
        }
    }

    /// Rebuilds the sidebar model from the current derived state.
    /// Preserves the existing selection and focused skill where possible.
    private func rebuildSidebarModel(from derivedState: DerivedState?) {
        guard let derivedState else {
            sidebarModel = ReviewSidebarModel(skills: [])
            return
        }
        var newModel = ReviewSidebarModel(from: derivedState)
        // Preserve selection across rebuilds (e.g. a background check fires mid-review).
        newModel.selectedSkillNames = sidebarModel.selectedSkillNames
        sidebarModel = newModel
        // Auto-select the first non–up-to-date skill if nothing is selected yet.
        if selectedSkillName == nil {
            let firstActionable = sidebarModel.sections
                .first(where: { $0.state != .upToDate })?
                .skills.first
            selectedSkillName = firstActionable ?? sidebarModel.sections.first?.skills.first
        }
    }

    /// Navigates the sidebar to `skillName`: updates the diff-pane selection and,
    /// if the skill is actionable, pre-checks it in the sidebar multi-select.
    private func applyFocusSkill(_ skillName: SkillName) {
        selectedSkillName = skillName
        // Pre-check actionable skills so the bulk Update/Skip controls are pre-armed.
        if let state = appModel.lastDerivedState?.states[skillName], state != .upToDate {
            sidebarModel.selectedSkillNames.insert(skillName)
        }
    }
}

// MARK: — Diff pane placeholder

/// Placeholder for the diff pane content.
/// Slices 9a/9b will replace this with the real WKWebView diff renderer.
private struct DiffPanePlaceholder: View {
    let selectedSkillName: SkillName?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            if let name = selectedSkillName {
                Text("\(name)")
                    .font(.system(size: 14, weight: .semibold))
                Text("Diff pane — Slices 9a/9b")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                Text("Select a skill to review")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.windowBackground)
        // TODO(Slice 9a): Replace with WKWebView diff renderer (split / unified toggle).
        // TODO(Slice 9b): Handle non-text files with "Binary — no preview" card.
    }
}
