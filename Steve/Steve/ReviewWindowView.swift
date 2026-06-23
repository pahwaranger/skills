import SwiftUI
// DiffBridge types are compiled directly into the app target from
// Sources/DiffBridge/DiffBridge.swift — no module import needed here.
#if SWIFT_PACKAGE
import AppCore
import StateEngine
import Installer
import DiffBridge
import Theme
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

    /// Reads installed files for a given skill name.
    /// Defaults to the real `~/.claude/skills/<name>/` provider; injectable for fixture mode.
    var installedFilesProvider: (String) -> [String: Data] = DiffPane.defaultInstalledFilesProvider

    // MARK: — State

    /// Sidebar selection/grouping model — rebuilt whenever `appModel.lastDerivedState` changes.
    @State private var sidebarModel: ReviewSidebarModel = ReviewSidebarModel(skills: [])

    /// The skill currently shown in the diff pane.
    @State private var selectedSkillName: SkillName?

    /// Split / Unified toggle state for the diff renderer.
    /// Initialised from the persisted `defaultDiffView` setting on first appear (Slice 11).
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
                actionableCount: actionableCount,
                onCycleSelection: { sidebarModel.cycleSelection() },
                onDismissSelection: { sidebarModel.selectedSkillNames = [] },
                onBulkUpdate: { performUpdate(Array(sidebarModel.selectedSkillNames)) },
                onBulkSkip: { performSkip(Array(sidebarModel.selectedSkillNames)) },
                githubURL: githubURL(for: selectedSkillName),
                appModel: appModel,
                installedFilesProvider: installedFilesProvider
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
        // `consumeReviewFocusSkill()` atomically reads and clears the channel so
        // a second open of the same window does not re-select a stale skill.
        .onChange(of: appModel.reviewFocusSkill) { _, skillName in
            guard let skillName = appModel.consumeReviewFocusSkill() else { return }
            applyFocusSkill(skillName)
        }
        .onAppear {
            // Apply the persisted default diff view as the initial mode (Slice 11).
            // Read directly from SettingsStore(defaults: .standard) so this always
            // reflects the latest saved preference when the window opens.
            diffViewMode = SettingsStore().defaultDiffView

            // Capture the immutable origin snapshot for this review session (Slice 10 / ADR 0006).
            // Must be called before any Update/Skip buttons are accessible.
            appModel.openReviewSession()
            rebuildSidebarModel(from: appModel.lastDerivedState)
            // Consume any focus skill that was set before the view appeared
            // (i.e. first open: the dropdown set reviewFocusSkill before the
            // window existed, so onChange fired into the void).
            if let skillName = appModel.consumeReviewFocusSkill() {
                applyFocusSkill(skillName)
            }
        }
        .onDisappear {
            // Clear the review session when the window closes (Slice 10 / ADR 0006 Fix 1).
            // This ensures that the NEXT open captures a fresh origin snapshot rather than
            // seeing a stale SHA from before the window was closed. Without this call,
            // openReviewSession() would not overwrite an existing session — so after origin
            // moves and the user reopens, they'd see the old SHA forever.
            appModel.closeReviewSession()
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

    /// Number of actionable (non-up-to-date) skills in the current derived state.
    /// Threaded into `DiffPane` to gate the "All caught up!" empty state.
    private var actionableCount: Int {
        guard let states = appModel.lastDerivedState?.states else { return 0 }
        return states.values.filter { $0 != .upToDate }.count
    }

    /// Builds the GitHub directory URL for a skill, using the resolved default branch.
    private func githubURL(for skillName: SkillName?) -> URL? {
        guard let skillName else { return nil }
        let branch = appModel.resolvedDefaultBranch ?? appModel.branch
        let urlString = "https://github.com/\(appModel.owner)/\(appModel.repo)/tree/\(branch)/skills/\(skillName)"
        return URL(string: urlString)
    }

    /// The default production provider: reads files from `~/.claude/skills/<name>/`.
    /// Exposed as a `static` so `MainWindowView` can reference it without knowing about `DiffPane`.
    nonisolated static func defaultInstalledFilesProvider(_ skillName: String) -> [String: Data] {
        DiffPane.defaultInstalledFilesProvider(skillName)
    }
}

// MARK: — Diff pane (Slice 9a + 9b + 41)

/// The right-hand diff pane: pane header (skill label + Split/Unified toggle) above
/// collapsible file cards (Slice 9b) containing WKWebView diff renderers.
///
/// `selectedSkillName` drives which diff is shown.
/// `selectedSkillState` gates the up-to-date placeholder vs. file cards.
/// `checkedCount` gates the materialising toolbar.
///
/// Real per-skill diff is computed from the installed files (via `installedFilesProvider`)
/// vs. the origin snapshot in `appModel.reviewSession?.skillFiles`.
private struct DiffPane: View {

    let selectedSkillName: SkillName?
    let selectedSkillState: SkillState?
    @Binding var viewMode: DiffViewMode
    let checkedCount: Int
    let selectionMode: ReviewSidebarModel.SelectionMode
    /// Number of actionable (non-up-to-date) skills across all sections.
    /// Used to gate the "All caught up!" empty state.
    let actionableCount: Int
    let onCycleSelection: () -> Void
    let onDismissSelection: () -> Void
    let onBulkUpdate: () -> Void
    let onBulkSkip: () -> Void
    let githubURL: URL?
    let appModel: AppModel

    /// Reads the installed files for a given skill name.
    /// Defaults to reading from `~/.claude/skills/<name>/`; injectable for tests.
    var installedFilesProvider: (String) -> [String: Data] = Self.defaultInstalledFilesProvider

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
                    // State chip: shown for actionable skills only (hidden when up-to-date)
                    if let chipText = selectedSkillState.flatMap({ ReviewSidebarModel.chipLabel(for: $0) }) {
                        SkillStateChip(label: chipText, state: selectedSkillState ?? .upToDate)
                    }
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
            .accessibilityIdentifier("pane.header")
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.windowBackground)

            Divider()

            // ── Content ───────────────────────────────────────────────────
            if actionableCount == 0 {
                // "All caught up!" — zero actionable skills across all sections
                AllCaughtUpPlaceholder()
            } else if let name = selectedSkillName {
                if selectedSkillState == .upToDate {
                    // Up-to-date placeholder (per-skill; there are still other actionable skills)
                    UpToDatePlaceholder(githubURL: githubURL)
                } else {
                    // File cards (Slice 9b) — each file in the diff is collapsible.
                    // Real installed-vs-origin diff (Slice 41).
                    let rawDiff = realDiff(for: name)
                    if rawDiff.isEmpty {
                        // No differences detected — show the up-to-date placeholder.
                        UpToDatePlaceholder(githubURL: githubURL)
                    } else {
                        FileCardsView(
                            skillName: name,
                            rawDiff: rawDiff,
                            viewMode: $viewMode
                        )
                    }
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

    // MARK: — Real diff computation (Slice 41)

    /// Computes the real installed-vs-origin unified diff for `skillName`.
    ///
    /// - Installed files: read via `installedFilesProvider` (defaults to `~/.claude/skills/<name>/`).
    /// - Origin files: from `appModel.reviewSession?.skillFiles[skillName]` — the same
    ///   immutable snapshot that `performUpdate`/`performSkip` commit (ADR 0006/0007).
    ///
    /// Returns an empty string when there are no differences (skill is up-to-date).
    private func realDiff(for skillName: String) -> String {
        let installed = installedFilesProvider(skillName)
        let origin    = appModel.reviewSession?.skillFiles[skillName] ?? [:]
        return UnifiedDiffGenerator.generate(installed: installed, origin: origin, skillName: skillName)
    }

    /// Default production provider: reads files directly from `~/.claude/skills/<name>/`.
    nonisolated static func defaultInstalledFilesProvider(_ skillName: String) -> [String: Data] {
        let skillsDir = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".claude/skills/\(skillName)", directoryHint: .isDirectory)
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: skillsDir, includingPropertiesForKeys: nil
        ) else { return [:] }
        var result: [String: Data] = [:]
        for url in entries {
            if let data = try? Data(contentsOf: url) {
                result[url.lastPathComponent] = data
            }
        }
        return result
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
        .accessibilityIdentifier("toolbar.materialising")
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background {
            // Translucent blue: locked #0a84ff @ 0.92 over ultraThinMaterial.
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                Color(Palette.Review.update).opacity(0.92)
            }
        }
    }

    private var selectIcon: String {
        ReviewSidebarModel.toolbarToggleGlyph(for: selectionMode)
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
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(.white.opacity(configuration.isPressed ? 0.12 : 0.20))
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(.white.opacity(0.6), lineWidth: 1.5)
            )
    }
}

private struct ToolbarSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(.clear)
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(.white.opacity(configuration.isPressed ? 0.55 : 0.35), lineWidth: 1.5)
            )
    }
}

// MARK: — Up-to-date placeholder (Slice 9b)

/// Shown when the selected skill is up-to-date: nothing to sync.
/// Includes a link to the skill's GitHub directory (using the resolved default branch).
private struct UpToDatePlaceholder: View {
    let githubURL: URL?

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 40))
                .foregroundStyle(Color.secondary)

            VStack(spacing: 4) {
                Text("Up to date")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)

                Text("Nothing to sync for this skill.")
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

// MARK: — All caught up empty state (Issue #49)

/// Shown when there are ZERO actionable skills — everything is up to date.
/// Distinct from UpToDatePlaceholder (which is per-skill while other skills
/// are still actionable). Gated on actionableCount == 0 in DiffPane.
private struct AllCaughtUpPlaceholder: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.green)

            VStack(spacing: 4) {
                Text("All caught up!")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)

                Text("Nothing left to review.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.windowBackground)
    }
}

// MARK: — Pane-header state chip (Issue #49)

/// A colored capsule chip shown in the pane header next to the skill name.
/// Displays "Removed" / "Update" / "Skipped" using the locked palette colors.
/// Hidden for up-to-date skills (the parent view only renders this for actionable skills).
private struct SkillStateChip: View {
    let label: String
    let state: SkillState

    var body: some View {
        Text(label)
            .font(.system(size: 10, weight: .bold))
            .tracking(0.03 * 10)   // ~0.03em at 10pt
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(chipColor)
            .clipShape(Capsule())
            .accessibilityIdentifier("chip.state.\(label.lowercased())")
    }

    private var chipColor: Color {
        switch state {
        case .removedOnOrigin: return Color(Palette.Review.removed)
        case .updateAvailable: return Color(Palette.Review.update)
        case .skipped:         return Color(Palette.Review.skipped)
        case .upToDate:        return Color(Palette.Review.upToDate)
        }
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
///
/// The renderer receives `file.rawSlice` — only the portion of the unified diff
/// that belongs to this file — so each card shows only its own hunk (Issue #44).
private struct FileCard: View {

    let file: FileDiff
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

                    // Line count badges (Issue #50): palette colors, non-zero only, right-aligned.
                    if !file.isBinary {
                        if file.addedLines > 0 {
                            Text("+\(file.addedLines)")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(Color(Palette.Review.diffAdded))
                        }
                        if file.removedLines > 0 {
                            Text("−\(file.removedLines)")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(Color(Palette.Review.diffRemoved))
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
            .accessibilityIdentifier("filecard.\(file.filename)")

            // ── Card body ─────────────────────────────────────────────────
            if !isCollapsed {
                if file.isBinary {
                    BinaryFileNotice(filename: file.filename)
                } else {
                    // Per-file slice: each card renders only its own hunk (Issue #44).
                    DiffRendererView(diff: file.rawSlice, viewMode: $viewMode)
                        .frame(minHeight: 120)
                }
            }
        }
    }
}

// MARK: — File status pill (Issue #50)

/// A tinted badge showing "Added" / "Modified" / "Deleted".
///
/// Uses a light ~12% tint background with saturated colored text (not white-on-solid).
/// Label and color are driven by `FileDiff.Status.pillLabel` / `.pillColor` — the
/// same pure helpers that are unit-tested in `FileDiffStatusMappingTests`.
private struct FileStatusPill: View {
    let status: FileDiff.Status

    var body: some View {
        let themeColor = Color(status.pillColor)
        Text(status.pillLabel)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(themeColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(themeColor.opacity(0.12))
            .clipShape(Capsule())
            .accessibilityIdentifier("pill.\(status.pillLabel.lowercased())")
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

// MARK: — SwiftUI Previews (route b, #if DEBUG)

#if DEBUG

#if SWIFT_PACKAGE
import FixtureEngine
#endif

#Preview("Sidebar — all groups", traits: .fixedLayout(width: 260, height: 500)) {
    let appModel = AppModel.directSeed(from: FixtureScenario.default)
    return ReviewSidebarView(
        model: .constant(ReviewSidebarModel(from: appModel.lastDerivedState ?? DerivedState(states: [:], attention: false, selfHealed: []))),
        selectedSkillName: .constant("diagnose"),
        onUpdate: { _ in },
        onSkip: { _ in }
    )
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(.windowBackgroundColor))
}

#Preview("DiffPane — rich diff (diagnose)", traits: .fixedLayout(width: 600, height: 500)) {
    let appModel = AppModel.directSeed(from: FixtureScenario.default)
    return DiffPane(
        selectedSkillName: "diagnose",
        selectedSkillState: .updateAvailable,
        viewMode: .constant(.split),
        checkedCount: 0,
        selectionMode: .none,
        actionableCount: 3,
        onCycleSelection: {},
        onDismissSelection: {},
        onBulkUpdate: {},
        onBulkSkip: {},
        githubURL: URL(string: "https://github.com/test/test/tree/main/skills/diagnose"),
        appModel: appModel,
        installedFilesProvider: { skillName in
            // Return mock installed files for the preview
            switch skillName {
            case "diagnose":
                return [
                    "SKILL.md": Data("# diagnose\nOld installed SKILL.md.".utf8),
                    "legacy.md": Data("# legacy content".utf8)
                ]
            default:
                return [:]
            }
        }
    )
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(.windowBackgroundColor))
}

#Preview("DiffPane — all deleted (to-prd)", traits: .fixedLayout(width: 600, height: 400)) {
    let appModel = AppModel.directSeed(from: FixtureScenario.default)
    return DiffPane(
        selectedSkillName: "to-prd",
        selectedSkillState: .removedOnOrigin,
        viewMode: .constant(.split),
        checkedCount: 0,
        selectionMode: .none,
        actionableCount: 3,
        onCycleSelection: {},
        onDismissSelection: {},
        onBulkUpdate: {},
        onBulkSkip: {},
        githubURL: nil,
        appModel: appModel,
        installedFilesProvider: { skillName in
            switch skillName {
            case "to-prd":
                return ["SKILL.md": Data("# to-prd\nInstalled version.".utf8)]
            default:
                return [:]
            }
        }
    )
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(.windowBackgroundColor))
}

#Preview("DiffPane — up-to-date (handoff)", traits: .fixedLayout(width: 600, height: 400)) {
    let appModel = AppModel.directSeed(from: FixtureScenario.default)
    return DiffPane(
        selectedSkillName: "handoff",
        selectedSkillState: .upToDate,
        viewMode: .constant(.split),
        checkedCount: 0,
        selectionMode: .none,
        actionableCount: 3,
        onCycleSelection: {},
        onDismissSelection: {},
        onBulkUpdate: {},
        onBulkSkip: {},
        githubURL: URL(string: "https://github.com/test/test/tree/main/skills/handoff"),
        appModel: appModel,
        installedFilesProvider: { _ in [:] }
    )
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(.windowBackgroundColor))
}

#endif // DEBUG

