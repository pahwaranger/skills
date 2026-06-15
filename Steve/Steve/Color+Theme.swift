import SwiftUI
import AppKit

// MARK: - Color(light:dark:)

extension Color {
    /// Creates a `Color` that resolves to `light` under Aqua and `dark` under Dark Aqua.
    /// Backed by `NSColor`'s dynamic appearance-keyed provider.
    init(light: Color, dark: Color) {
        self = Color(NSColor(name: nil) { appearance in
            switch appearance.bestMatch(from: [.aqua, .darkAqua]) {
            case .darkAqua:
                return NSColor(dark)
            default:
                return NSColor(light)
            }
        })
    }

    /// Creates a `Color` from a `ThemeColor`, resolving via system appearance.
    init(_ themeColor: ThemeColor) {
        self.init(
            light: Color(themeColor.light),
            dark:  Color(themeColor.dark)
        )
    }
}

// MARK: - Color from RGBA

extension Color {
    /// Creates a `Color` from a platform-agnostic `RGBA` value.
    init(_ rgba: RGBA) {
        self.init(
            .sRGB,
            red:     Double(rgba.red)   / 255,
            green:   Double(rgba.green) / 255,
            blue:    Double(rgba.blue)  / 255,
            opacity: Double(rgba.alpha) / 255
        )
    }
}
