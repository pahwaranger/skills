import Testing
@testable import DiffBridge
import Theme

// MARK: — FileDiff.Status pill-mapping tests (Issue #50)
//
// Pure unit tests for the label and palette-color mapping on FileDiff.Status.
// These cover:
//   - The correct display label for each status (especially `.removed` → "Deleted")
//   - The correct palette ThemeColor for each status

struct FileDiffStatusPillLabelTests {

    @Test func addedStatusLabelIsAdded() {
        #expect(FileDiff.Status.added.pillLabel == "Added")
    }

    @Test func modifiedStatusLabelIsModified() {
        #expect(FileDiff.Status.modified.pillLabel == "Modified")
    }

    /// `.removed` status must map to "Deleted" (not "Removed"), per design spec.
    @Test func removedStatusLabelIsDeleted() {
        #expect(FileDiff.Status.removed.pillLabel == "Deleted")
    }
}

struct FileDiffStatusPillColorTests {

    @Test func addedStatusColorIsDiffAdded() {
        let color = FileDiff.Status.added.pillColor
        // Palette.Review.diffAdded light = #1a8a4a
        let expected = Palette.Review.diffAdded
        #expect(color.light == expected.light)
        #expect(color.dark  == expected.dark)
    }

    @Test func modifiedStatusColorIsUpdate() {
        let color = FileDiff.Status.modified.pillColor
        // Palette.Review.update light = #0a84ff
        let expected = Palette.Review.update
        #expect(color.light == expected.light)
        #expect(color.dark  == expected.dark)
    }

    @Test func removedStatusColorIsDiffRemoved() {
        let color = FileDiff.Status.removed.pillColor
        // Palette.Review.diffRemoved light = #e5484d
        let expected = Palette.Review.diffRemoved
        #expect(color.light == expected.light)
        #expect(color.dark  == expected.dark)
    }
}
