import Testing
import Foundation
@testable import DiffBridge

// MARK: — DiffBridge serialisation tests
//
// These tests cover the Swift↔JS bridge message types defined in the DiffBridge
// SPM target.  They intentionally test only JSON encode/decode round-trips and
// exact field names — WKWebView rendering is not unit-tested.

// MARK: — RenderCommand (Swift → JS)

struct RenderCommandTests {

    // MARK: Encoding

    @Test func encodesViewModeSplit() throws {
        let cmd = RenderCommand(
            diff: "--- a/foo\n+++ b/foo\n@@ -1 +1 @@\n-old\n+new\n",
            viewMode: .split,
            installedLabel: "Installed",
            originLabel: "Origin"
        )
        let data = try JSONEncoder().encode(cmd)
        let obj  = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(obj["type"]           as? String == "render")
        #expect(obj["viewMode"]       as? String == "split")
        #expect(obj["installedLabel"] as? String == "Installed")
        #expect(obj["originLabel"]    as? String == "Origin")
        #expect((obj["diff"] as? String)?.isEmpty == false)
    }

    @Test func encodesViewModeUnified() throws {
        let cmd = RenderCommand(
            diff: "--- a\n+++ b\n",
            viewMode: .unified,
            installedLabel: "Installed",
            originLabel: "Origin"
        )
        let data = try JSONEncoder().encode(cmd)
        let obj  = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(obj["viewMode"] as? String == "unified")
    }

    @Test func typeFieldIsAlwaysRender() throws {
        let cmd = RenderCommand(diff: "", viewMode: .unified,
                                installedLabel: "A", originLabel: "B")
        let data = try JSONEncoder().encode(cmd)
        let obj  = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(obj["type"] as? String == "render")
    }

    // MARK: Round-trip

    @Test func roundTripSplitCommand() throws {
        let original = RenderCommand(
            diff: "--- a/SKILL.md\n+++ b/SKILL.md\n@@ -1,3 +1,3 @@\n line1\n-old\n+new\n line3\n",
            viewMode: .split,
            installedLabel: "Installed",
            originLabel: "Origin"
        )
        let data    = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RenderCommand.self, from: data)

        #expect(decoded.diff           == original.diff)
        #expect(decoded.viewMode       == original.viewMode)
        #expect(decoded.installedLabel == original.installedLabel)
        #expect(decoded.originLabel    == original.originLabel)
    }

    @Test func roundTripUnifiedCommand() throws {
        let original = RenderCommand(
            diff: "--- a\n+++ b\n@@ -0,0 +1 @@\n+added\n",
            viewMode: .unified,
            installedLabel: "Installed",
            originLabel: "Origin"
        )
        let data    = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RenderCommand.self, from: data)
        #expect(decoded.viewMode == .unified)
    }

    // MARK: View-mode toggle command

    @Test func encodesToggleViewMode() throws {
        let cmd = ToggleViewModeCommand(viewMode: .split)
        let data = try JSONEncoder().encode(cmd)
        let obj  = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(obj["type"]     as? String == "toggleViewMode")
        #expect(obj["viewMode"] as? String == "split")
    }

    @Test func roundTripToggleViewMode() throws {
        for mode in [DiffViewMode.split, .unified] {
            let original = ToggleViewModeCommand(viewMode: mode)
            let data     = try JSONEncoder().encode(original)
            let decoded  = try JSONDecoder().decode(ToggleViewModeCommand.self, from: data)
            #expect(decoded.viewMode == mode)
        }
    }
}

// MARK: — BridgeEvent (JS → Swift)

struct BridgeEventTests {

    // MARK: ready event

    @Test func decodesReadyEvent() throws {
        let json = """
        {"type":"ready"}
        """
        let event = try JSONDecoder().decode(BridgeEvent.self, from: Data(json.utf8))
        #expect(event == .ready)
    }

    // MARK: viewModeChanged event

    @Test func decodesViewModeChangedSplit() throws {
        let json = """
        {"type":"viewModeChanged","viewMode":"split"}
        """
        let event = try JSONDecoder().decode(BridgeEvent.self, from: Data(json.utf8))
        #expect(event == .viewModeChanged(.split))
    }

    @Test func decodesViewModeChangedUnified() throws {
        let json = """
        {"type":"viewModeChanged","viewMode":"unified"}
        """
        let event = try JSONDecoder().decode(BridgeEvent.self, from: Data(json.utf8))
        #expect(event == .viewModeChanged(.unified))
    }

    // MARK: error event

    @Test func decodesErrorEvent() throws {
        let json = """
        {"type":"error","message":"render failed"}
        """
        let event = try JSONDecoder().decode(BridgeEvent.self, from: Data(json.utf8))
        if case .error(let msg) = event {
            #expect(msg == "render failed")
        } else {
            Issue.record("Expected .error, got \(event)")
        }
    }

    // MARK: unknown type is rejected

    @Test func unknownEventTypeThrows() throws {
        let json = """
        {"type":"bogus"}
        """
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(BridgeEvent.self, from: Data(json.utf8))
        }
    }

    // MARK: Round-trips for encodable events

    @Test func roundTripReadyEvent() throws {
        let encoded = try JSONEncoder().encode(BridgeEvent.ready)
        let decoded = try JSONDecoder().decode(BridgeEvent.self, from: encoded)
        #expect(decoded == .ready)
    }

    @Test func roundTripErrorEvent() throws {
        let original = BridgeEvent.error("something went wrong")
        let encoded  = try JSONEncoder().encode(original)
        let decoded  = try JSONDecoder().decode(BridgeEvent.self, from: encoded)
        #expect(decoded == original)
    }

    // MARK: JSON field names

    @Test func readyEventHasTypeField() throws {
        let data = try JSONEncoder().encode(BridgeEvent.ready)
        let obj  = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(obj["type"] as? String == "ready")
    }

    @Test func viewModeChangedEventHasCorrectFields() throws {
        let data = try JSONEncoder().encode(BridgeEvent.viewModeChanged(.unified))
        let obj  = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(obj["type"]     as? String == "viewModeChanged")
        #expect(obj["viewMode"] as? String == "unified")
    }

    @Test func errorEventHasMessageField() throws {
        let data = try JSONEncoder().encode(BridgeEvent.error("oops"))
        let obj  = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(obj["type"]    as? String == "error")
        #expect(obj["message"] as? String == "oops")
    }
}

// MARK: — DiffViewMode

struct DiffViewModeTests {

    @Test func splitRawValue() {
        #expect(DiffViewMode.split.rawValue   == "split")
    }

    @Test func unifiedRawValue() {
        #expect(DiffViewMode.unified.rawValue == "unified")
    }

    @Test func initFromRawValueSplit() {
        #expect(DiffViewMode(rawValue: "split") == .split)
    }

    @Test func initFromRawValueUnified() {
        #expect(DiffViewMode(rawValue: "unified") == .unified)
    }

    @Test func initFromRawValueUnknownIsNil() {
        #expect(DiffViewMode(rawValue: "bogus") == nil)
    }
}
