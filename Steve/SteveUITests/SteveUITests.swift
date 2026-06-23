import XCTest

// MARK: — Steve XCUITest suite (Fixture mode F4)
//
// Launches Steve.app with --fixtures and asserts the four Review window surfaces:
//   (a) The four sidebar group headers exist (Removed / Updates / Skipped / Up-to-date)
//   (b) Selecting `diagnose` shows file cards with the three status pills
//   (c) The pane-header state chip is present
//   (d) Checking a skill row reveals the materialising toolbar
//
// OUT OF SCOPE: the system menu bar dropdown. The dropdown lives in the system menu-bar
// extra, which is outside the app's accessibility tree. It is covered by F3 previews
// and F5 manual capture — not assertable via XCUITest.
//
// Screenshots are attached as XCTAttachment (.keepAlways) AND written as PNGs to
// STEVE_SCREENSHOT_DIR (defaults to $TMPDIR/SteveUITests-screenshots/).

@MainActor
final class SteveUITests: XCTestCase {

    private var app: XCUIApplication!
    private var screenshotDir: URL!

    // MARK: — Setup / teardown

    override func setUpWithError() throws {
        continueAfterFailure = false

        // Resolve the screenshot output directory.
        let dir: URL
        if let envPath = ProcessInfo.processInfo.environment["STEVE_SCREENSHOT_DIR"] {
            dir = URL(fileURLWithPath: envPath)
        } else {
            dir = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("SteveUITests-screenshots", isDirectory: true)
        }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        screenshotDir = dir

        app = XCUIApplication()
        app.launchArguments = ["--fixtures"]
        app.launch()

        // Wait for the Review window to appear (fixture mode auto-opens it).
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 10), "Steve window did not appear")
    }

    override func tearDownWithError() throws {
        app.terminate()
        app = nil
    }

    // MARK: — (a) Sidebar group headers

    func testSidebarGroupHeaders() throws {
        // Fixture scenario seeds: removed, updateAvailable, skipped, upToDate skills.
        // The sidebar shows exactly these four group header labels.
        let expectedGroups = ["removed", "updates", "skipped", "up to date"]
        for group in expectedGroups {
            let header = app.staticTexts.matching(
                NSPredicate(format: "identifier == %@", "sidebar.group.\(group)")
            ).firstMatch
            XCTAssertTrue(
                header.waitForExistence(timeout: 5),
                "Expected sidebar group header '\(group)' not found"
            )
        }
        attachScreenshot(named: "a_sidebar_group_headers")
    }

    // MARK: — (b) File cards + status pills for `diagnose`

    func testDiagnoseFileCardsAndStatusPills() throws {
        // `diagnose` is pre-selected in fixture mode (auto-opened by FixtureAutoOpenModifier).
        // Wait for at least one file card to appear.
        // File card buttons appear with identifiers like "filecard.diagnose/SKILL.md".
        let anyFileCard = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "filecard.")
        ).firstMatch
        XCTAssertTrue(
            anyFileCard.waitForExistence(timeout: 10),
            "No file cards found for selected skill 'diagnose'"
        )

        // The file card button accessibility label includes the status pill text,
        // e.g. "SKILL.md, Modified, +1, −1" — check that at least one card has
        // a pill label (Modified / Added / Deleted) in its label.
        // This is what macOS accessibility actually exposes for SwiftUI Button children.
        let allFileCards = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "filecard.")
        )
        var foundPill = false
        for i in 0..<allFileCards.count {
            let label = allFileCards.element(boundBy: i).label
            if label.contains("Modified") || label.contains("Added") || label.contains("Deleted") {
                foundPill = true
                break
            }
        }
        XCTAssertTrue(foundPill, "No status pills found in file card labels")
        attachScreenshot(named: "b_file_cards_status_pills")
    }

    // MARK: — (c) Pane-header state chip

    func testPaneHeaderStateChip() throws {
        // The state chip appears next to the skill name in the pane header for actionable skills.
        // diagnose is updateAvailable in the fixture scenario → chip label "Update".
        //
        // macOS accessibility merges the chip text into the pane header container's label.
        // The pane header appears as an `otherElement` with id="pane.header" and
        // label="Update" (the chip's label text). Check it directly:
        let paneHeader = app.otherElements.matching(
            NSPredicate(format: "identifier == %@", "pane.header")
        ).firstMatch
        XCTAssertTrue(
            paneHeader.waitForExistence(timeout: 10),
            "Pane-header element not found"
        )
        // The chip label (Update / Removed / Skipped) should appear in the pane header's label.
        let headerLabel = paneHeader.label
        let hasChip = ["update", "removed", "skipped"].contains(headerLabel.lowercased())
        XCTAssertTrue(
            hasChip,
            "Pane-header state chip not found in label '\(headerLabel)'"
        )
        attachScreenshot(named: "c_state_chip")
    }

    // MARK: — (d) Materialising toolbar on skill row check

    func testMaterialisingToolbarAppearsOnCheck() throws {
        // The materialising toolbar appears when ≥1 skill row is checked.
        //
        // macOS accessibility exposes the SidebarSkillRow HStack with identifier
        // "sidebar.skill.diagnose" as a button (its label is "Square" = unchecked checkbox).
        // Tapping it calls onToggle which adds diagnose to selectedSkillNames.
        let checkbox = app.buttons.matching(
            NSPredicate(format: "identifier == %@", "sidebar.skill.diagnose")
        ).firstMatch
        XCTAssertTrue(
            checkbox.waitForExistence(timeout: 10),
            "Checkbox button for diagnose skill row not found"
        )
        checkbox.tap()

        // After tapping, the materialising toolbar materialises. Its child buttons
        // all share the identifier "toolbar.materialising" (SwiftUI propagates the
        // HStack identifier to its Button children on macOS accessibility).
        let toolbar = app.buttons.matching(
            NSPredicate(format: "identifier == %@", "toolbar.materialising")
        ).firstMatch
        XCTAssertTrue(
            toolbar.waitForExistence(timeout: 5),
            "Materialising toolbar did not appear after checking a skill"
        )
        attachScreenshot(named: "d_materialising_toolbar")
    }

    // MARK: — Screenshot helpers

    private func attachScreenshot(named name: String) {
        let screenshot = app.screenshot()

        // 1. Attach to XCTest result (keepAlways so CI preserves it)
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        // 2. Write PNG to the known output directory
        let pngData = screenshot.pngRepresentation
        let dest = screenshotDir.appendingPathComponent("\(name).png")
        do {
            try pngData.write(to: dest)
        } catch {
            // Non-fatal: test still passes even if disk write fails.
            XCTContext.runActivity(named: "Screenshot write warning") { _ in
                let note = XCTAttachment(string: "Could not write \(name).png: \(error)")
                note.lifetime = .keepAlways
                add(note)
            }
        }
    }
}
