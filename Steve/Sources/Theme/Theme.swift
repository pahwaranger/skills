// Theme.swift
// Pure, testable color primitives and named palette constants.
// No SwiftUI/AppKit import — this target is SPM-testable.

// MARK: - RGBA

/// A platform-agnostic RGBA color value where each component is 0–255.
public struct RGBA: Equatable, Sendable {
    public let red: UInt8
    public let green: UInt8
    public let blue: UInt8
    public let alpha: UInt8

    public init(red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8 = 0xff) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }
}

// MARK: - Hex initialiser

public enum HexColorError: Error {
    case invalidFormat(String)
}

public extension RGBA {
    /// Parse a 6-digit hex string (`#rrggbb` or `rrggbb`).
    init(hex: String) throws {
        var s = hex
        if s.hasPrefix("#") { s = String(s.dropFirst()) }
        guard s.count == 6, let value = UInt32(s, radix: 16) else {
            throw HexColorError.invalidFormat(hex)
        }
        red   = UInt8((value >> 16) & 0xff)
        green = UInt8((value >>  8) & 0xff)
        blue  = UInt8( value        & 0xff)
        alpha = 0xff
    }
}

// MARK: - ThemeColor

/// A paired light/dark color constant.
public struct ThemeColor: Sendable {
    public let light: RGBA
    public let dark: RGBA

    public init(light: RGBA, dark: RGBA) {
        self.light = light
        self.dark = dark
    }

    /// Returns the appropriate `RGBA` for the given appearance.
    public func rgba(isDark: Bool) -> RGBA {
        isDark ? dark : light
    }
}

// MARK: - Palette

/// Named palette constants drawn from locked prototype hex values.
/// Two distinct palettes as per design intent:
///   - `Palette.Review`  — sourced from `prototypes/review-diff/app/src/styles.css`
///   - `Palette.Dropdown` — sourced from `prototypes/menu-bar-dropdown/index.html`
public enum Palette {

    // MARK: Review surface palette

    public enum Review {
        /// State: removed  light #e5484d / dark #ff6369  (`--state-removed`)
        public static let removed = ThemeColor(
            light: .init(red: 0xe5, green: 0x48, blue: 0x4d),
            dark:  .init(red: 0xff, green: 0x63, blue: 0x69)
        )

        /// State: update   light #0a84ff / dark #3b9eff  (`--state-update`)
        public static let update = ThemeColor(
            light: .init(red: 0x0a, green: 0x84, blue: 0xff),
            dark:  .init(red: 0x3b, green: 0x9e, blue: 0xff)
        )

        /// State: skipped  light #c4620c / dark #f0883e  (`--state-skipped`)
        public static let skipped = ThemeColor(
            light: .init(red: 0xc4, green: 0x62, blue: 0x0c),
            dark:  .init(red: 0xf0, green: 0x88, blue: 0x3e)
        )

        /// State: up-to-date  light #86868b / dark #98989d  (`--state-uptodate`)
        public static let upToDate = ThemeColor(
            light: .init(red: 0x86, green: 0x86, blue: 0x8b),
            dark:  .init(red: 0x98, green: 0x98, blue: 0x9d)
        )

        /// Diff added lines  light #1a8a4a / dark #4cc38a
        public static let diffAdded = ThemeColor(
            light: .init(red: 0x1a, green: 0x8a, blue: 0x4a),
            dark:  .init(red: 0x4c, green: 0xc3, blue: 0x8a)
        )

        /// Diff removed lines  light #e5484d / dark #ff6369
        /// (same hue as `removed` state; kept distinct for semantic clarity)
        public static let diffRemoved = ThemeColor(
            light: .init(red: 0xe5, green: 0x48, blue: 0x4d),
            dark:  .init(red: 0xff, green: 0x63, blue: 0x69)
        )
    }

    // MARK: Dropdown palette

    public enum Dropdown {
        /// Section-label gray  light #8E8E93 (`--t3`) / dark white@42% (`rgba(255,255,255,0.42)`)
        /// 0.42 × 255 = 107.1 → 107
        public static let sectionLabel = ThemeColor(
            light: .init(red: 0x8e, green: 0x8e, blue: 0x93),
            dark:  .init(red: 0xff, green: 0xff, blue: 0xff, alpha: 107)
        )

        /// Left-bar accent: removed  #FF3B30 (`--cr`), same light/dark
        public static let removed = ThemeColor(
            light: .init(red: 0xff, green: 0x3b, blue: 0x30),
            dark:  .init(red: 0xff, green: 0x3b, blue: 0x30)
        )

        /// Left-bar accent: update  #FF9500 (`--cu`), same light/dark
        public static let update = ThemeColor(
            light: .init(red: 0xff, green: 0x95, blue: 0x00),
            dark:  .init(red: 0xff, green: 0x95, blue: 0x00)
        )

        /// Left-bar accent: skipped  #8E8E93 (`--cs`), same light/dark
        public static let skipped = ThemeColor(
            light: .init(red: 0x8e, green: 0x8e, blue: 0x93),
            dark:  .init(red: 0x8e, green: 0x8e, blue: 0x93)
        )
    }
}
