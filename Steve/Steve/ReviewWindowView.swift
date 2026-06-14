import SwiftUI
// DiffBridge types are compiled directly into the app target from
// Sources/DiffBridge/DiffBridge.swift — no module import needed here.
#if SWIFT_PACKAGE
import AppCore
import StateEngine
import Installer
#endif

// MARK: — Review window (Slice 8 + 9a + 9b)

/// The full Review window content — sidebar + diff pane.
///
/// This view is hosted in a `Window` scene in `SteveApp.swift`.
/// The `focusedSkillName` is passed via the `ReviewWindowModel` environment
/// so the sidebar can scroll to it on first open and pre-select it.
///
/// Slice 9a: The diff pane now hosts a WKWebView diff renderer using diff2html
/// (vendored/offline). Split/unified toggle is wired through the Swift↔JS bridge.
/// Slice 9b: File-card affordances, binary placeholders, up-to-date placeholder,
/// and a materialising toolbar appear in the diff pane.
struct ReviewWindowView: View {

    let appModel: AppModel

    // MARK: — State

    /// Sidebar selection/grouping model — rebuilt whenever `appModel.lastDerivedState` changes.
    @State private var sidebarModel: ReviewSidebarModel = ReviewSidebarModel(skills: [])

    /// The skill currently shown in the diff pane.
    @State private var selectedSkillName: SkillName?

    /// Split / Unified toggle state for the diff renderer.
    @State private var diffViewMode: DiffViewMode = .split

    /// Whether to show the "origin has changed" reload-required alert.
    @State private var showSHAMovedAlert: Bool = false

    // MARK: — Body

    var body: some View {
        HSplitView {
            // ── Left: Sidebar ────────────────────────────────────────────
            ReviewSidebarView(
                model: $sidebarModel,
                selectedSkillName: $selectedSkillName,
                onUpdate: { skillNames in performUpdate(skillNames) },
                onSkip: { skillNames in performSkip(skillNames) }
            )
            .frame(minWidth: 200, idealWidth: 240, maxWidth: 300)

            // ── Right: Diff pane ─────────────────────────────────────────
            DiffPane(
                selectedSkillName: selectedSkillName,
                selectedSkillState: skillState(for: selectedSkillName),
                viewMode: $diffViewMode,
                checkedCount: sidebarModel.selectedCount,
                selectionMode: sidebarModel.selectionMode,
                onCycleSelection: { sidebarModel.cycleSelection() },
                onDismissSelection: { sidebarModel.selectedSkillNames = [] },
                onBulkUpdate: { performUpdate(Array(sidebarModel.selectedSkillNames)) },
                onBulkSkip: { performSkip(Array(sidebarModel.selectedSkillNames)) },
                githubURL: githubURL(for: selectedSkillName),
                appModel: appModel
            )
            .frame(minWidth: 400, maxWidth: .infinity)
        }
        .frame(minWidth: 680, minHeight: 440)
        // Rebuild the sidebar model whenever the derived state updates.
        // Note: background checks update lastDerivedState but do NOT alter reviewSession.
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
            // Capture the immutable origin snapshot for this review session (Slice 10 / ADR 0006).
            // Must be called before any Update/Skip buttons are accessible.
            appModel.openReviewSession()
            rebuildSidebarModel(from: appModel.lastDerivedState)
            // Consume any focus skill that was set before the view appeared
            // (i.e. first open: the dropdown set reviewFocusSkill before the
            // window existed, so onChange fired into the void).
            if let skillName = appModel.reviewFocusSkill {
                applyFocusSkill(skillName)
                appModel.reviewFocusSkill = nil
            }
        }
        .alert("Origin Changed", isPresented: $showSHAMovedAlert) {
            Button("Reload") {
                // Re-check to refresh the window with the new origin content.
                Task { await appModel.triggerCheck() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Origin has changed since you opened this window — reload to re-review.")
        }
    }

    // MARK: — Update / Skip actions

    /// Performs a bulk Update for the given skill names.
    /// Validates the origin SHA first; shows the reload alert if origin has moved.
    private func performUpdate(_ skillNames: [String]) {
        Task {
            let outcome = await appModel.performUpdate(skillNames: skillNames)
            if outcome == .shaMovedReloadRequired {
                showSHAMovedAlert = true
            } else {
                // Clear the selection after a successful commit.
                sidebarModel.selectedSkillNames = []
                // Re-derive state to reflect the newly installed skills.
                await appModel.triggerCheck()
            }
        }
    }

    /// Performs a bulk Skip for the given skill names.
    /// Validates the origin SHA first; shows the reload alert if origin has moved.
    private func performSkip(_ skillNames: [String]) {
        Task {
            let outcome = await appModel.performSkip(skillNames: skillNames)
            if outcome == .shaMovedReloadRequired {
                showSHAMovedAlert = true
            } else {
                sidebarModel.selectedSkillNames = []
                await appModel.triggerCheck()
            }
        }
    }

    // MARK: — Private helpers

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

    /// Looks up the `SkillState` for the currently selected skill.
    private func skillState(for name: SkillName?) -> SkillState? {
        guard let name else { return nil }
        return appModel.lastDerivedState?.states[name]
    }

    /// Builds the GitHub directory URL for a skill, using the resolved default branch.
    private func githubURL(for skillName: SkillName?) -> URL? {
        guard let skillName else { return nil }
        let branch = appModel.resolvedDefaultBranch ?? appModel.branch
        let urlString = "https://github.com/\(appModel.owner)/\(appModel.repo)/tree/\(branch)/skills/\(skillName)"
        return URL(string: urlString)
    }
}

// MARK: — Diff pane (Slice 9a + 9b)

/// The right-hand diff pane: pane header (skill label + Split/Unified toggle) above
/// collapsible file cards (Slice 9b) containing WKWebView diff renderers.
///
/// `selectedSkillName` drives which diff is shown.
/// `selectedSkillState` gates the up-to-date placeholder vs. file cards.
/// `checkedCount` gates the materialising toolbar.
///
/// The actual per-skill diff data is placeholder until the Installer slice provides it.
/// TODO(Slice N): replace `placeholderDiff(for:)` with real diff data from the Installer.
private struct DiffPane: View {

    let selectedSkillName: SkillName?
    let selectedSkillState: SkillState?
    @Binding var viewMode: DiffViewMode
    let checkedCount: Int
    let selectionMode: ReviewSidebarModel.SelectionMode
    let onCycleSelection: () -> Void
    let onDismissSelection: () -> Void
    let onBulkUpdate: () -> Void
    let onBulkSkip: () -> Void
    let githubURL: URL?
    let appModel: AppModel

    var body: some View {
        VStack(spacing: 0) {
            // ── Materialising toolbar (Slice 9b / Slice 10) ───────────────
            if checkedCount > 0 {
                MaterialisingToolbar(
                    checkedCount: checkedCount,
                    selectionMode: selectionMode,
                    onCycleSelection: onCycleSelection,
                    onDismiss: onDismissSelection,
                    onUpdate: onBulkUpdate,
                    onSkip: onBulkSkip
                )
                Divider()
            }

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

            // ── Content ───────────────────────────────────────────────────
            if let name = selectedSkillName {
                if selectedSkillState == .upToDate {
                    // Up-to-date placeholder (Slice 9b)
                    UpToDatePlaceholder(skillName: name, githubURL: githubURL)
                } else {
                    // File cards (Slice 9b) — each file in the diff is collapsible.
                    FileCardsView(
                        skillName: name,
                        rawDiff: placeholderDiff(for: name),
                        viewMode: $viewMode
                    )
                    // TODO(Slice N): replace placeholderDiff(for:) with real diff
                    // data sourced from the Installer / DerivedState once that
                    // pipeline delivers per-file unified diffs.
                }
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
            }
        }
    }
}

// MARK: — Materialising toolbar (Slice 9b / Slice 10)

/// A sticky blue toolbar that materialises when ≥1 skill is checked.
/// Disappears when selection is cleared.
/// Update and Skip are wired to the parent's action callbacks (Slice 10).
private struct MaterialisingToolbar: View {

    let checkedCount: Int
    let selectionMode: ReviewSidebarModel.SelectionMode
    let onCycleSelection: () -> Void
    let onDismiss: () -> Void
    let onUpdate: () -> Void
    let onSkip: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            // 3-state select toggle: ☐ / ☑ / ⊟ — mirrors SidebarActionHeader.
            // Forwards the same model action (cycleSelection) so sidebar and toolbar
            // stay in sync.
            Button(action: onCycleSelection) {
                Text(selectIcon)
                    .font(.system(size: 15))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .help(selectTooltip)

            Text("\(checkedCount) selected")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)

            Spacer()

            // Skip — wired in Slice 10
            Button("Skip", action: onSkip)
            .buttonStyle(ToolbarSecondaryButtonStyle())
            .controlSize(.small)

            // Update — wired in Slice 10
            Button("Update", action: onUpdate)
            .buttonStyle(ToolbarPrimaryButtonStyle())
            .controlSize(.small)

            // Dismiss selection
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .help("Clear selection")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Color.accentColor)
    }

    private var selectIcon: String {
        switch selectionMode {
        case .none, .partial: return "☐"
        case .all:            return "☑"
        case .new:            return "⊟"
        }
    }

    private var selectTooltip: String {
        switch selectionMode {
        case .none, .partial: return "Select all actionable"
        case .all:            return "Select new only"
        case .new:            return "Deselect all"
        }
    }
}

// MARK: — Toolbar button styles

private struct ToolbarPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(.white.opacity(configuration.isPressed ? 0.8 : 1.0))
            .clipShape(RoundedRectangle(cornerRadius: 5))
    }
}

private struct ToolbarSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(.white.opacity(configuration.isPressed ? 0.3 : 0.2))
            .clipShape(RoundedRectangle(cornerRadius: 5))
    }
}

// MARK: — Up-to-date placeholder (Slice 9b)

/// Shown when the selected skill is up-to-date: nothing to sync.
/// Includes a link to the skill's GitHub directory (using the resolved default branch).
private struct UpToDatePlaceholder: View {
    let skillName: SkillName
    let githubURL: URL?

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 40))
                .foregroundStyle(Color.secondary)

            VStack(spacing: 4) {
                Text("Up to date — nothing to sync")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)

                Text(skillName)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            if let url = githubURL {
                Link("View on GitHub ↗", destination: url)
                    .font(.system(size: 12))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.windowBackground)
    }
}

// MARK: — File cards view (Slice 9b)

/// Renders a scrollable list of collapsible file cards for a skill's diff.
/// Each card shows: filename, status pill, ±N line counts, and the diff renderer.
/// Binary files get a "Binary — no preview" body instead of the diff renderer.
/// Cards are open by default; clicking the header collapses/expands.
private struct FileCardsView: View {

    let skillName: SkillName
    let rawDiff: String
    @Binding var viewMode: DiffViewMode

    /// Set of filenames whose cards are collapsed (open by default).
    @State private var collapsed: Set<String> = []

    /// Parsed per-file metadata from the raw diff string.
    private var fileDiffs: [FileDiff] {
        UnifiedDiffParser.parse(rawDiff)
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: []) {
                ForEach(fileDiffs, id: \.filename) { file in
                    FileCard(
                        file: file,
                        rawDiff: rawDiff,
                        viewMode: $viewMode,
                        isCollapsed: collapsed.contains(file.filename),
                        onToggle: { toggleCollapse(file.filename) }
                    )
                    Divider()
                }

                if fileDiffs.isEmpty {
                    // Safety net: diff string produced no parseable file headers.
                    // Render the whole diff as-is via the existing renderer.
                    DiffRendererView(diff: rawDiff, viewMode: $viewMode)
                }
            }
        }
        .background(.windowBackground)
    }

    private func toggleCollapse(_ filename: String) {
        if collapsed.contains(filename) {
            collapsed.remove(filename)
        } else {
            collapsed.insert(filename)
        }
    }
}

// MARK: — File card (Slice 9b)

/// A single collapsible file section: header + optional body.
/// The header shows: ▼/▶ chevron, filename, status pill, and ±N line counts.
/// The body is either a diff renderer (text) or a "Binary — no preview" notice.
private struct FileCard: View {

    let file: FileDiff
    /// The full diff string; we pass the whole thing through to the renderer, which
    /// handles multi-file diffs correctly. In a future slice, this will be the
    /// per-file slice; for now the renderer ignores the other files or renders all.
    let rawDiff: String
    @Binding var viewMode: DiffViewMode
    let isCollapsed: Bool
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ── Card header ───────────────────────────────────────────────
            Button(action: onToggle) {
                HStack(spacing: 6) {
                    // Collapse/expand chevron
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 14)

                    // Filename (just the last path component for display brevity,
                    // but keep full relative path in the model)
                    let displayName = file.filename.split(separator: "/").last.map(String.init) ?? file.filename
                    Text(displayName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    // Status pill
                    FileStatusPill(status: file.status)

                    Spacer(minLength: 4)

                    // Line count badges
                    if !file.isBinary {
                        if file.addedLines > 0 {
                            Text("+\(file.addedLines)")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(Color(red: 0.133, green: 0.545, blue: 0.133))
                        }
                        if file.removedLines > 0 {
                            Text("−\(file.removedLines)")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(Color(red: 0.78, green: 0.082, blue: 0.082))
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.04))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // ── Card body ─────────────────────────────────────────────────
            if !isCollapsed {
                if file.isBinary {
                    BinaryFileNotice(filename: file.filename)
                } else {
                    // Per-file diff slice fed to the renderer.
                    // TODO(Slice N): pass only this file's diff slice once the
                    // Installer provides per-file slices. For now, the full diff
                    // is passed so diff2html renders all files. File cards are the
                    // chrome; diff2html handles multiple files fine.
                    DiffRendererView(diff: rawDiff, viewMode: $viewMode)
                        .frame(minHeight: 120)
                }
            }
        }
    }
}

// MARK: — File status pill (Slice 9b)

/// A coloured badge showing "Added" / "Modified" / "Deleted".
private struct FileStatusPill: View {
    let status: FileDiff.Status

    var body: some View {
        Text(label)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color)
            .clipShape(Capsule())
    }

    private var label: String {
        switch status {
        case .added:    return "Added"
        case .removed:  return "Deleted"
        case .modified: return "Modified"
        }
    }

    private var color: Color {
        switch status {
        case .added:    return Color(red: 0.133, green: 0.545, blue: 0.133)
        case .removed:  return Color(red: 0.78,  green: 0.082, blue: 0.082)
        case .modified: return Color(red: 0.0,   green: 0.478, blue: 1.0)
        }
    }
}

// MARK: — Binary file notice (Slice 9b)

/// Shown in the body of a file card when the file is binary.
/// No crash, no garbage — just a clean notice.
private struct BinaryFileNotice: View {
    let filename: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.zipper")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            Text("Binary — no preview")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.windowBackground)
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
