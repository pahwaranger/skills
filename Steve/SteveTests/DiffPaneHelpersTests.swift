import Testing
import Foundation
import StateEngine
@testable import AppCore

// MARK: — Toolbar toggle glyph tests (Issue #49)

/// Tests for the toolbar-specific toggle glyph helper.
/// The toolbar is only visible when ≥1 skill is checked, so it must NEVER show ☐.
/// - none/partial → ☑  (filled checked; distinct from sidebar header which shows ☐)
/// - all           → ☑
/// - new           → ⊟
struct ToolbarToggleGlyphTests {

    @Test func noneModeShouldReturnFilledCheckmark() {
        #expect(ReviewSidebarModel.toolbarToggleGlyph(for: .none) == "☑")
    }

    @Test func partialModeShouldReturnFilledCheckmark() {
        #expect(ReviewSidebarModel.toolbarToggleGlyph(for: .partial) == "☑")
    }

    @Test func allModeShouldReturnFilledCheckmark() {
        #expect(ReviewSidebarModel.toolbarToggleGlyph(for: .all) == "☑")
    }

    @Test func newModeShouldReturnMixedCheckmark() {
        #expect(ReviewSidebarModel.toolbarToggleGlyph(for: .new) == "⊟")
    }
}

// MARK: — Pane-header chip label tests (Issue #49)

/// Tests for the pure function that maps a SkillState to a chip label string.
/// Returns nil for up-to-date (chip is hidden for up-to-date skills).
struct PaneHeaderChipLabelTests {

    @Test func removedOnOriginChipLabelIsRemoved() {
        #expect(ReviewSidebarModel.chipLabel(for: .removedOnOrigin) == "Removed")
    }

    @Test func updateAvailableChipLabelIsUpdate() {
        #expect(ReviewSidebarModel.chipLabel(for: .updateAvailable) == "Update")
    }

    @Test func skippedChipLabelIsSkipped() {
        #expect(ReviewSidebarModel.chipLabel(for: .skipped) == "Skipped")
    }

    @Test func upToDateChipLabelIsNil() {
        #expect(ReviewSidebarModel.chipLabel(for: .upToDate) == nil)
    }
}
