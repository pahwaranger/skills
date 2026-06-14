import Foundation
#if SWIFT_PACKAGE
import StateEngine
#endif

/// Pure functions that map app state → status-line wording and banner type.
///
/// Implements the 8 wordings documented in issue #15 ("Slice 6: Menu-bar dropdown").
/// All logic is in one pure namespace so it is unit-testable without any SwiftUI.
public enum StatusLine {

    // MARK: — Banner type

    /// The visual tint of the Variant B banner.
    public enum BannerType: Equatable {
        /// A check is in flight — neutral spinner tint.
        case checking
        /// Attention: ≥1 pending change (update, removed).
        case attention
        /// Error occurred during the last check.
        case error
        /// All skills up-to-date (or only skipped).
        case neutral
    }

    /// Derives the banner type from app state — drives the tint colour in the view.
    public static func bannerType(
        isChecking: Bool,
        derivedState: DerivedState?,
        lastError: CheckError?
    ) -> BannerType {
        if isChecking { return .checking }
        if lastError != nil { return .error }
        if let state = derivedState, state.attention { return .attention }
        return .neutral
    }

    // MARK: — Status line wording

    /// Maps the current observable app state to one of the 8 documented wordings.
    ///
    /// Priority order (first match wins):
    /// 1. Checking in flight → "Checking origin…"
    /// 2. Error states (4 variants)
    /// 3. Pending changes present → "N updates available · M removed · K skipped"
    /// 4. No pending, some skipped → "Up to date · K skipped"
    /// 5. Fully clean with known check date → "Up to date · checked <relative-time>"
    /// 6. Fully clean, no date → "Up to date"
    public static func wording(
        isChecking: Bool,
        derivedState: DerivedState?,
        lastError: CheckError?,
        lastCheckDate: Date?
    ) -> String {
        // 1. Checking
        if isChecking { return "Checking origin…" }

        // 2. Error states
        if let error = lastError {
            return errorWording(error, lastCheckDate: lastCheckDate)
        }

        // 3–6. Derive from DerivedState
        guard let state = derivedState else { return "Up to date" }

        let updates  = state.states.values.filter { $0 == .updateAvailable }.count
        let removed  = state.states.values.filter { $0 == .removedOnOrigin }.count
        let skipped  = state.states.values.filter { $0 == .skipped }.count

        // 3. Pending changes (attention = true)
        if state.attention {
            var parts: [String] = []
            if updates > 0  { parts.append("\(updates) update\(updates == 1 ? "" : "s") available") }
            if removed > 0  { parts.append("\(removed) removed") }
            if skipped > 0  { parts.append("\(skipped) skipped") }
            return parts.joined(separator: " · ")
        }

        // 4. No pending, some skipped
        if skipped > 0 {
            return "Up to date · \(skipped) skipped"
        }

        // 5. Fully clean with known date
        if let date = lastCheckDate {
            return "Up to date · checked \(relativeTimeString(since: date))"
        }

        // 6. Fully clean, no date
        return "Up to date"
    }

    // MARK: — Private helpers

    private static func errorWording(_ error: CheckError, lastCheckDate: Date?) -> String {
        let checkedSuffix: String
        if let date = lastCheckDate {
            checkedSuffix = " · checked \(relativeTimeString(since: date))"
        } else {
            checkedSuffix = ""
        }

        switch error {
        case .networkError:
            return "Couldn't reach origin\(checkedSuffix)"
        case .rateLimited(let resetAt):
            let remaining = max(0, resetAt.timeIntervalSinceNow)
            let hours   = Int(remaining) / 3600
            let minutes = (Int(remaining) % 3600) / 60
            let countdown = String(format: "%d:%02d", hours, minutes)
            return "GitHub rate limit reached · retries \(countdown)"
        case .originNotFound:
            return "Origin not found — check repo"
        case .fetchFailed:
            return "Origin fetch failed\(checkedSuffix)"
        }
    }

    /// Returns a concise relative-time string like "just now", "2m ago", "3h ago".
    /// Used in status-line wordings 4, 5, 6 (the "checked X" suffix).
    static func relativeTimeString(since date: Date) -> String {
        let seconds = -date.timeIntervalSinceNow
        if seconds < 90 {
            return "just now"
        } else if seconds < 3600 {
            let minutes = Int(seconds / 60)
            return "\(minutes)m ago"
        } else {
            let hours = Int(seconds / 3600)
            return "\(hours)h ago"
        }
    }
}
