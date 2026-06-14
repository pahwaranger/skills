import SwiftUI
import WebKit
// DiffBridge types (DiffViewMode, RenderCommand, ToggleViewModeCommand, BridgeEvent)
// are compiled directly into the app target from Sources/DiffBridge/DiffBridge.swift.
// No module import is needed when building with Xcode (they share the same module).
// When building with SPM (swift build/test), DiffBridge is a separate module — but
// DiffRendererView.swift is not part of the SPM package (it's app-target-only),
// so no import guard is required here.

// MARK: — DiffRendererView
//
// Hosts a WKWebView that renders a unified diff string via diff2html.
// diff2html is vendored locally (see Steve/DiffRenderer/) — no CDN at runtime.
//
// Swift→JS bridge: RenderCommand / ToggleViewModeCommand (serialised to JSON,
//   delivered via evaluateJavaScript("handleCommand('...')")).
// JS→Swift bridge: BridgeEvent posted as JSON via
//   window.webkit.messageHandlers.bridge.postMessage(jsonString).
//
// The testable seam (message serialisation) lives in the DiffBridge SPM target.

struct DiffRendererView: NSViewRepresentable {

    /// The raw unified diff string to render.
    let diff: String

    /// Current view mode (split / unified).
    @Binding var viewMode: DiffViewMode

    // MARK: — NSViewRepresentable

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()

        // Register "bridge" as the JS→Swift message handler name.
        // The Coordinator conforms to WKScriptMessageHandler.
        config.userContentController.add(context.coordinator, name: "bridge")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        context.coordinator.webView = webView

        loadHTMLTemplate(in: webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let coordinator = context.coordinator

        // Detect which change triggered the update.
        let diffChanged     = diff    != coordinator.lastSentDiff
        let modeChanged     = viewMode != coordinator.lastSentViewMode

        if diffChanged {
            coordinator.lastSentDiff     = diff
            coordinator.lastSentViewMode = viewMode
            coordinator.sendRender(diff: diff, viewMode: viewMode)
        } else if modeChanged {
            coordinator.lastSentViewMode = viewMode
            coordinator.sendToggleViewMode(viewMode)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    // MARK: — HTML template loading

    private func loadHTMLTemplate(in webView: WKWebView) {
        // Load the offline HTML template from the app bundle.
        // The template, diff2html JS, and CSS are in Steve/DiffRenderer/
        // and must be added to the Xcode target's "Copy Bundle Resources" phase.
        guard let url = Bundle.main.url(
            forResource: "diff-renderer",
            withExtension: "html",
            subdirectory: "DiffRenderer"
        ) else {
            // Fall back to a bare resource lookup (Xcode sometimes flattens subdirectories).
            if let flatURL = Bundle.main.url(forResource: "diff-renderer", withExtension: "html") {
                let baseURL = flatURL.deletingLastPathComponent()
                webView.loadFileURL(flatURL, allowingReadAccessTo: baseURL)
            }
            return
        }
        // Allow reading sibling files (diff2html JS/CSS) from the same directory.
        let baseURL = url.deletingLastPathComponent()
        webView.loadFileURL(url, allowingReadAccessTo: baseURL)
    }
}

// MARK: — Coordinator

extension DiffRendererView {

    /// Coordinates WKScriptMessageHandler callbacks and tracks last-sent state.
    final class Coordinator: NSObject, WKScriptMessageHandler {

        weak var webView: WKWebView?

        /// Diff string most recently sent to JS; avoids re-sending on unrelated SwiftUI updates.
        var lastSentDiff: String = ""

        /// View mode most recently sent to JS.
        var lastSentViewMode: DiffViewMode = .split

        /// Whether the web page has signalled it is ready to receive commands.
        private var isReady = false

        /// Commands queued while the page is still loading (before the "ready" event).
        private var pendingCommand: (() -> Void)?

        // MARK: WKScriptMessageHandler

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard message.name == "bridge",
                  let body = message.body as? String,
                  let data = body.data(using: .utf8)
            else { return }

            guard let event = try? JSONDecoder().decode(BridgeEvent.self, from: data) else { return }

            switch event {
            case .ready:
                isReady = true
                // Flush any command that was queued before the page became ready.
                pendingCommand?()
                pendingCommand = nil

            case .viewModeChanged:
                // The JS side confirms the toggle completed — no additional action needed.
                break

            case .error(let message):
                // Surface JS-side render errors to the console for debugging.
                // TODO(Slice 9b): propagate to error UI in the diff pane header.
                print("[DiffRendererView] JS error: \(message)")
            }
        }

        // MARK: — Swift → JS helpers

        /// Send a full RenderCommand to the JS side.
        func sendRender(diff: String, viewMode: DiffViewMode) {
            let cmd = RenderCommand(
                diff: diff,
                viewMode: viewMode,
                installedLabel: "Installed",
                originLabel: "Origin"
            )
            enqueueCommand(cmd)
        }

        /// Send a ToggleViewModeCommand to the JS side.
        func sendToggleViewMode(_ viewMode: DiffViewMode) {
            let cmd = ToggleViewModeCommand(viewMode: viewMode)
            enqueueCommand(cmd)
        }

        // MARK: — Private

        private func enqueueCommand<T: Encodable>(_ command: T) {
            guard let data = try? JSONEncoder().encode(command),
                  let json = String(data: data, encoding: .utf8)
            else { return }

            // Escape the JSON string for safe embedding in a JS string literal.
            // evaluateJavaScript wraps our JSON in a JS function call:
            //   handleCommand('<escaped-json>')
            let escaped = json
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'",  with: "\\'")

            let js = "handleCommand('\(escaped)')"

            let evaluate: () -> Void = { [weak self] in
                self?.webView?.evaluateJavaScript(js) { _, error in
                    if let error {
                        print("[DiffRendererView] evaluateJavaScript error: \(error)")
                    }
                }
            }

            if isReady {
                evaluate()
            } else {
                // Page is still loading; queue the command to run on the "ready" event.
                pendingCommand = evaluate
            }
        }
    }
}
