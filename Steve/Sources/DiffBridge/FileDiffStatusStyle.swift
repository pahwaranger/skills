// When compiled via SPM, Theme is a separate module.
// When compiled directly into the Xcode app target, Theme.swift is compiled
// in the same unit, so no import is needed (and none is possible).
#if SWIFT_PACKAGE
import Theme
#endif

// MARK: — FileDiff.Status pill mapping (Issue #50)
//
// Pure, SPM-testable helpers that map a FileDiff.Status to the display
// label and palette ThemeColor used by the FileStatusPill view.
//
// Keeping this in DiffBridge (rather than the app target) ensures the
// mapping is unit-testable with `swift test` without Xcode.

public extension FileDiff.Status {

    /// The human-readable label shown in the file-card status pill.
    ///
    /// Note: `.removed` maps to `"Deleted"` (not "Removed") per design spec.
    var pillLabel: String {
        switch self {
        case .added:    return "Added"
        case .modified: return "Modified"
        case .removed:  return "Deleted"
        }
    }

    /// The palette color used for both the pill tint background (at 12% opacity)
    /// and the pill foreground text.
    var pillColor: ThemeColor {
        switch self {
        case .added:    return Palette.Review.diffAdded
        case .modified: return Palette.Review.update
        case .removed:  return Palette.Review.diffRemoved
        }
    }
}
