import SwiftUI
// DiffBridge types are compiled directly into the app target from
// Sources/DiffBridge/DiffBridge.swift — no module import needed here.
#if SWIFT_PACKAGE
import AppCore
import StateEngine
#endif

// MARK: — Review window (Slice 8 + 9a)

/// The full Review window content — sidebar + diff pane.
///
/// This view is hosted in a `Window` scene in `SteveApp.swift`.
/// The `focusedSkillName` is passed via the `ReviewWindowModel` environment
/// so the sidebar can scroll to it on first open and pre-select it.
///
/// Slice 9a: The diff pane now hosts a WKWebView diff renderer using diff2html
/// (vendored/offline). Split/unified toggle is wired through the Swift↔JS bridge.
/// Slice 9b (file-card affordances, binary placeholders) is a future slice.
struct ReviewWindowView: View {

    let appModel: AppModel

    // MARK: — State

    /// Sidebar selection/grouping model — rebuilt whenever `appModel.lastDerivedState` changes.
    @State private var sidebarModel: ReviewSidebarModel = ReviewSidebarModel(skills: [])

    /// The skill currently shown in the diff pane.
    @State private var selectedSkillName: SkillName?

    /// Split / Unified toggle state for the diff renderer.
    @State private var diffViewMode: DiffViewMode = .split

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
            DiffPane(
                selectedSkillName: selectedSkillName,
                viewMode: $diffViewMode
            )
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

// MARK: — Diff pane (Slice 9a)

/// The right-hand diff pane: pane header (skill label + Split/Unified toggle) above
/// a WKWebView diff renderer powered by diff2html (vendored offline).
///
/// `selectedSkillName` drives which diff is shown.  The actual per-skill diff
/// data is placeholder until the Installer slice provides it.
/// TODO(Slice N): replace `placeholderDiff(for:)` with real diff data from the Installer.
private struct DiffPane: View {

    let selectedSkillName: SkillName?
    @Binding var viewMode: DiffViewMode

    var body: some View {
        VStack(spacing: 0) {
            // ── Pane header ───────────────────────────────────────────────
            HStack(spacing: 8) {
                if let name = selectedSkillName {
                    Text(name)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                }
                Spacer()
                // Split / Unified segmented control
                Picker("", selection: $viewMode) {
                    Text("Split").tag(DiffViewMode.split)
                    Text("Unified").tag(DiffViewMode.unified)
                }
                .pickerStyle(.segmented)
                .frame(width: 130)
                .labelsHidden()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.windowBackground)

            Divider()

            // ── Diff renderer ─────────────────────────────────────────────
            if let name = selectedSkillName {
                DiffRendererView(
                    diff: placeholderDiff(for: name),
                    viewMode: $viewMode
                )
                // TODO(Slice N): replace placeholderDiff(for:) with real diff
                // data sourced from the Installer / DerivedState once that
                // pipeline delivers per-file unified diffs.
            } else {
                // Nothing selected — show a neutral placeholder.
                VStack(spacing: 12) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)
                    Text("Select a skill to review")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.windowBackground)
                // TODO(Slice 9b): Handle non-text files with "Binary — no preview" card.
            }
        }
    }
}

// MARK: — Placeholder diff data (Slice 9a sample)
//
// A representative multi-file unified diff for the `grill-with-docs` skill,
// matching the fake data described in the prototype spec (PROMPT.md).
// This is replaced by real diff data once the Installer pipeline delivers it.
// TODO(Slice N): remove once real diff data is wired from DerivedState / Installer.

private func placeholderDiff(for skillName: SkillName) -> String {
    switch skillName {
    case "grill-with-docs":
        return grillWithDocsSampleDiff
    default:
        // Generic single-file modified diff for any other skill.
        return genericSampleDiff(skillName: skillName)
    }
}

private let grillWithDocsSampleDiff = """
--- a/grill-with-docs/SKILL.md
+++ b/grill-with-docs/SKILL.md
@@ -1,12 +1,14 @@
 # grill-with-docs

-A disciplined grilling session that stress-tests a plan against the existing domain model.
+A disciplined grilling session that challenges your plan against the existing
+domain model, sharpens terminology, and updates documentation inline as decisions
+crystallise.

 ## When to use

-Use when you want to stress-test a plan before committing to it.
+Use when you want to challenge a plan, tighten its vocabulary, or record
+decisions into CONTEXT.md / ADRs before committing.

 ## Steps

 1. Load the domain model (CONTEXT.md + ADRs).
 2. Identify terminology mismatches.
 3. Surface contradictions with prior decisions.
-4. Propose a fix.
+4. Propose a fix and update the docs inline.
+5. Confirm the updated wording with the user before saving.
--- a/grill-with-docs/CONTEXT-FORMAT.md
+++ b/grill-with-docs/CONTEXT-FORMAT.md
@@ -8,6 +8,10 @@
 - Every concept should have exactly one canonical term.
 - ADR titles must be imperative sentences.
 - Decisions must reference the forces they balance.
+- Terms introduced in one ADR must be used consistently in all subsequent ADRs.
+- If a term is redefined, the old ADR must be superseded, not silently amended.

 ## Format rules

 - Sections: `# Title`, `## Section`, `### Subsection`.
--- /dev/null
+++ b/grill-with-docs/EXAMPLES.md
@@ -0,0 +1,18 @@
+# Examples — grill-with-docs
+
+## Example 1: Mismatched terminology
+
+**Plan says:** "update the skill manifest"
+**CONTEXT.md says:** skills have no manifest — they are directories.
+**Grill output:** rename to "update the skill directory" and amend ADR 0001.
+
+## Example 2: Contradicting a prior decision
+
+**Plan says:** "store the diff in the Cache"
+**ADR 0002 says:** the Cache only stores Origin snapshots, never computed artefacts.
+**Grill output:** move the diff to a transient in-memory store; update ADR 0002 to
+clarify the boundary.
+
+## Example 3: Missing force documentation
+
+**Plan says:** "use WKWebView for the diff renderer" with no forces recorded.
+**Grill output:** write ADR 0004 recording the forces (offline, native macOS, diff2html).
"""

private func genericSampleDiff(skillName: String) -> String {
    return """
    --- a/\(skillName)/SKILL.md
    +++ b/\(skillName)/SKILL.md
    @@ -1,5 +1,7 @@
     # \(skillName)

    -Original description of this skill.
    +Updated description of this skill with new wording that clarifies the
    +intended use and scope.

     ## When to use

    -Use when you need this skill.
    +Use when you need this skill — especially in multi-agent or AFK contexts.
    """
}
