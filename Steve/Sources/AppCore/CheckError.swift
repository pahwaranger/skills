import Foundation

/// The error kind from the most-recent failed check.
/// Drives status-line wording (#15) and banner tint.
///
/// - `networkError`:  network/timeout/5xx — transient; retry next tick
/// - `rateLimited`:   GitHub 403 — back off until `resetAt`
/// - `originNotFound`: 404/private — slow retry
/// - `fetchFailed`:   tarball corrupt / extraction error — retry next tick
public enum CheckError: Sendable, Equatable {
    case networkError
    case rateLimited(resetAt: Date)
    case originNotFound
    case fetchFailed

    public static func == (lhs: CheckError, rhs: CheckError) -> Bool {
        switch (lhs, rhs) {
        case (.networkError, .networkError):           return true
        case (.rateLimited(let a), .rateLimited(let b)): return a == b
        case (.originNotFound, .originNotFound):       return true
        case (.fetchFailed, .fetchFailed):             return true
        default:                                       return false
        }
    }
}
