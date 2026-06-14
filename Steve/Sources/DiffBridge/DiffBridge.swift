import Foundation

// MARK: — DiffBridge
//
// Swift↔JS message types for the WKWebView diff renderer.
//
// Swift → JS: RenderCommand, ToggleViewModeCommand
// JS → Swift: BridgeEvent
//
// These types live in an SPM target so their JSON serialisation is
// unit-testable without a running WKWebView.

// MARK: — DiffViewMode

/// The two rendering modes exposed by diff2html.
public enum DiffViewMode: String, Codable, Sendable, Equatable, CaseIterable {
    case split   = "split"
    case unified = "unified"
}

// MARK: — Swift → JS messages

/// Sent from Swift to the web view to (re-)render a diff.
///
/// Maps to `diff2html`'s `outputFormat`:
/// - `.split`   → `"side-by-side"` (two columns labelled Installed / Origin)
/// - `.unified` → `"line-by-line"` (single column)
///
/// JSON shape:
/// ```json
/// {
///   "type": "render",
///   "diff": "<unified diff string>",
///   "viewMode": "split" | "unified",
///   "installedLabel": "Installed",
///   "originLabel": "Origin"
/// }
/// ```
public struct RenderCommand: Codable, Sendable, Equatable {

    /// Discriminator — always `"render"`.
    public let type: String

    /// The raw unified diff string to pass to diff2html.
    public let diff: String

    /// The rendering mode (split / unified).
    public let viewMode: DiffViewMode

    /// Label for the left (base / Installed / S) column in split view.
    public let installedLabel: String

    /// Label for the right (head / Origin / O) column in split view.
    public let originLabel: String

    public init(
        diff: String,
        viewMode: DiffViewMode,
        installedLabel: String,
        originLabel: String
    ) {
        self.type           = "render"
        self.diff           = diff
        self.viewMode       = viewMode
        self.installedLabel = installedLabel
        self.originLabel    = originLabel
    }

    // Use explicit coding keys to guarantee the exact JSON field names
    // the JavaScript side expects.
    private enum CodingKeys: String, CodingKey {
        case type, diff, viewMode, installedLabel, originLabel
    }
}

/// Sent from Swift to the web view to switch between split and unified view
/// WITHOUT re-rendering (no new diff string is needed — the JS side re-calls
/// diff2html on its cached diff string with the new output format).
///
/// JSON shape:
/// ```json
/// { "type": "toggleViewMode", "viewMode": "split" | "unified" }
/// ```
public struct ToggleViewModeCommand: Codable, Sendable, Equatable {

    /// Discriminator — always `"toggleViewMode"`.
    public let type: String

    /// The new rendering mode.
    public let viewMode: DiffViewMode

    public init(viewMode: DiffViewMode) {
        self.type     = "toggleViewMode"
        self.viewMode = viewMode
    }

    private enum CodingKeys: String, CodingKey {
        case type, viewMode
    }
}

// MARK: — JS → Swift events

/// Events posted from JavaScript to the `WKScriptMessageHandler`.
///
/// JSON shapes:
/// - ready:             `{"type":"ready"}`
/// - viewModeChanged:   `{"type":"viewModeChanged","viewMode":"split"|"unified"}`
/// - error:             `{"type":"error","message":"<description>"}`
public enum BridgeEvent: Sendable, Equatable {
    case ready
    case viewModeChanged(DiffViewMode)
    case error(String)
}

// MARK: BridgeEvent: Codable

extension BridgeEvent: Codable {

    private enum EventType: String, Decodable {
        case ready
        case viewModeChanged
        case error
    }

    private enum CodingKeys: String, CodingKey {
        case type, viewMode, message
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type      = try container.decode(EventType.self, forKey: .type)

        switch type {
        case .ready:
            self = .ready

        case .viewModeChanged:
            let mode = try container.decode(DiffViewMode.self, forKey: .viewMode)
            self = .viewModeChanged(mode)

        case .error:
            let message = try container.decode(String.self, forKey: .message)
            self = .error(message)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .ready:
            try container.encode("ready", forKey: .type)

        case .viewModeChanged(let mode):
            try container.encode("viewModeChanged", forKey: .type)
            try container.encode(mode, forKey: .viewMode)

        case .error(let message):
            try container.encode("error", forKey: .type)
            try container.encode(message, forKey: .message)
        }
    }
}
