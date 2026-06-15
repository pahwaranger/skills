import Testing
@testable import Theme

// MARK: - RGBA + ThemeColor tests

struct RGBATests {
    @Test func hexDecoderParsesOpaqueHex() throws {
        let c = try RGBA(hex: "#e5484d")
        #expect(c.red == 0xe5)
        #expect(c.green == 0x48)
        #expect(c.blue == 0x4d)
        #expect(c.alpha == 0xff)
    }

    @Test func hexDecoderParsesWithoutHash() throws {
        let c = try RGBA(hex: "0a84ff")
        #expect(c.red == 0x0a)
        #expect(c.green == 0x84)
        #expect(c.blue == 0xff)
    }

    @Test func hexDecoderRejectsInvalidLength() {
        #expect(throws: (any Error).self) {
            try RGBA(hex: "#abc")
        }
    }
}

struct ThemeColorTests {
    @Test func returnsLightRGBAWhenNotDark() throws {
        let tc = ThemeColor(light: try RGBA(hex: "#ffffff"), dark: try RGBA(hex: "#000000"))
        let result = tc.rgba(isDark: false)
        #expect(result.red == 0xff)
        #expect(result.green == 0xff)
        #expect(result.blue == 0xff)
    }

    @Test func returnsDarkRGBAWhenDark() throws {
        let tc = ThemeColor(light: try RGBA(hex: "#ffffff"), dark: try RGBA(hex: "#000000"))
        let result = tc.rgba(isDark: true)
        #expect(result.red == 0x00)
        #expect(result.green == 0x00)
        #expect(result.blue == 0x00)
    }
}

// MARK: - Review palette exact hex tests

struct ReviewPaletteTests {
    @Test func reviewRemovedLightHex() throws {
        let c = Palette.Review.removed.rgba(isDark: false)
        #expect(c == (try RGBA(hex: "#e5484d")))
    }

    @Test func reviewRemovedDarkHex() throws {
        let c = Palette.Review.removed.rgba(isDark: true)
        #expect(c == (try RGBA(hex: "#ff6369")))
    }

    @Test func reviewUpdateLightHex() throws {
        let c = Palette.Review.update.rgba(isDark: false)
        #expect(c == (try RGBA(hex: "#0a84ff")))
    }

    @Test func reviewUpdateDarkHex() throws {
        let c = Palette.Review.update.rgba(isDark: true)
        #expect(c == (try RGBA(hex: "#3b9eff")))
    }

    @Test func reviewSkippedLightHex() throws {
        let c = Palette.Review.skipped.rgba(isDark: false)
        #expect(c == (try RGBA(hex: "#c4620c")))
    }

    @Test func reviewSkippedDarkHex() throws {
        let c = Palette.Review.skipped.rgba(isDark: true)
        #expect(c == (try RGBA(hex: "#f0883e")))
    }

    @Test func reviewUpToDateLightHex() throws {
        let c = Palette.Review.upToDate.rgba(isDark: false)
        #expect(c == (try RGBA(hex: "#86868b")))
    }

    @Test func reviewUpToDateDarkHex() throws {
        let c = Palette.Review.upToDate.rgba(isDark: true)
        #expect(c == (try RGBA(hex: "#98989d")))
    }

    @Test func reviewDiffAddedLightHex() throws {
        let c = Palette.Review.diffAdded.rgba(isDark: false)
        #expect(c == (try RGBA(hex: "#1a8a4a")))
    }

    @Test func reviewDiffAddedDarkHex() throws {
        let c = Palette.Review.diffAdded.rgba(isDark: true)
        #expect(c == (try RGBA(hex: "#4cc38a")))
    }

    @Test func reviewDiffRemovedLightHex() throws {
        let c = Palette.Review.diffRemoved.rgba(isDark: false)
        #expect(c == (try RGBA(hex: "#e5484d")))
    }

    @Test func reviewDiffRemovedDarkHex() throws {
        let c = Palette.Review.diffRemoved.rgba(isDark: true)
        #expect(c == (try RGBA(hex: "#ff6369")))
    }
}

// MARK: - Dropdown palette exact hex tests

struct DropdownPaletteTests {
    @Test func dropdownSectionLabelLightHex() throws {
        let c = Palette.Dropdown.sectionLabel.rgba(isDark: false)
        #expect(c == (try RGBA(hex: "#8E8E93")))
    }

    // Dark variant: white @ 42% opacity → r=255 g=255 b=255 a=107
    // 0.42 * 255 = 107.1 → rounds to 107
    @Test func dropdownSectionLabelDarkIsWhiteAt42Percent() throws {
        let c = Palette.Dropdown.sectionLabel.rgba(isDark: true)
        #expect(c.red == 0xff)
        #expect(c.green == 0xff)
        #expect(c.blue == 0xff)
        #expect(c.alpha == 107)
    }

    @Test func dropdownRemovedLightHex() throws {
        let c = Palette.Dropdown.removed.rgba(isDark: false)
        #expect(c == (try RGBA(hex: "#FF3B30")))
    }

    @Test func dropdownRemovedDarkHex() throws {
        let c = Palette.Dropdown.removed.rgba(isDark: true)
        #expect(c == (try RGBA(hex: "#FF3B30")))
    }

    @Test func dropdownUpdateLightHex() throws {
        let c = Palette.Dropdown.update.rgba(isDark: false)
        #expect(c == (try RGBA(hex: "#FF9500")))
    }

    @Test func dropdownUpdateDarkHex() throws {
        let c = Palette.Dropdown.update.rgba(isDark: true)
        #expect(c == (try RGBA(hex: "#FF9500")))
    }

    @Test func dropdownSkippedLightHex() throws {
        let c = Palette.Dropdown.skipped.rgba(isDark: false)
        #expect(c == (try RGBA(hex: "#8E8E93")))
    }

    @Test func dropdownSkippedDarkHex() throws {
        let c = Palette.Dropdown.skipped.rgba(isDark: true)
        #expect(c == (try RGBA(hex: "#8E8E93")))
    }
}
