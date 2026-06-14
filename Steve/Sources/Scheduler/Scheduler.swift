import Foundation
#if SWIFT_PACKAGE
import StateEngine
#endif
// SMAppService wired in Slice 11

/// Injectable clock so tests can drive time without wall-clock waits.
public protocol SchedulerClock: Sendable {
    func sleep(for duration: TimeInterval) async throws
}

/// The result a `performCheck` closure returns to the scheduler, giving it
/// enough information to choose the next sleep interval without leaking
/// domain errors into the scheduling layer.
public enum CheckResult: Sendable {
    /// The check succeeded (or was a benign no-op). Carries the optional
    /// `DerivedState` that the check produced — may be `nil` when no state
    /// update is needed (e.g. the origin was unchanged).
    case ok(DerivedState?)
    /// The origin returned a 404 / was private — a configuration problem that
    /// warrants slow-retry backoff rather than the normal cadence.
    case originNotFound
    /// A transient, non-destructive failure (network error, rate limit).
    /// The scheduler preserves the current cadence (including any 404 slow-retry
    /// backoff) and keeps `lastDerivedState` unchanged.
    case transientError
}

/// A snapshot of the scheduler's observable state, emitted on the
/// `stateUpdates` stream at the start and end of EVERY check (launch, timer
/// tick, and manual trigger). The `@MainActor` `AppModel` consumes these to keep
/// its `@Observable` properties live without polling — an actor → main-actor hop
/// that carries only `Sendable` value types, so there is no data race.
public struct SchedulerState: Equatable, Sendable {
    public let isChecking: Bool
    public let lastDerivedState: DerivedState?

    public init(isChecking: Bool, lastDerivedState: DerivedState?) {
        self.isChecking = isChecking
        self.lastDerivedState = lastDerivedState
    }
}

/// Manages when checks fire and exposes observable state for the menu-bar icon.
/// Depends on an injected `performCheck` closure so the full pipeline
/// (OriginClient → CacheStore → StateEngine) is exercised outside this actor.
public actor CheckScheduler {
    public private(set) var isChecking: Bool = false
    public private(set) var lastDerivedState: DerivedState?

    private let performCheck: @Sendable () async -> CheckResult
    private let clock: any SchedulerClock
    private let interval: TimeInterval
    private let slowRetryInterval: TimeInterval
    private let automaticChecksEnabled: Bool

    /// Emits a `SchedulerState` at the start and end of every check so observers
    /// (the main-actor `AppModel`) update on EVERY check, not just the launch one.
    public nonisolated let stateUpdates: AsyncStream<SchedulerState>
    private let stateContinuation: AsyncStream<SchedulerState>.Continuation

    /// When `true` the last check returned `originNotFound`; the timer loop
    /// will sleep for `slowRetryInterval` instead of `interval`.
    private var lastOutcomeWas404: Bool = false

    public init(
        performCheck: @escaping @Sendable () async -> CheckResult,
        clock: any SchedulerClock,
        interval: TimeInterval = 3600,
        slowRetryInterval: TimeInterval = 21600,   // 6 hours
        automaticChecksEnabled: Bool = true
    ) {
        self.performCheck = performCheck
        self.clock = clock
        self.interval = interval
        self.slowRetryInterval = slowRetryInterval
        self.automaticChecksEnabled = automaticChecksEnabled
        (self.stateUpdates, self.stateContinuation) = AsyncStream.makeStream(
            bufferingPolicy: .bufferingNewest(8)
        )
    }

    /// Fires an immediate check on app launch, then schedules periodic checks.
    /// Returns after the launch check completes; the timer loop runs in the background.
    public func start() async {
        await runCheck()
        if automaticChecksEnabled {
            Task { await self.runTimerLoop() }
        }
    }

    private func runTimerLoop() async {
        while !Task.isCancelled {
            let sleepDuration = lastOutcomeWas404 ? slowRetryInterval : interval
            try? await clock.sleep(for: sleepDuration)
            // Single-flight: if a manual check is already in-flight, skip this tick.
            guard !isChecking else { continue }
            await runCheck()
        }
    }

    /// Manual trigger (wired to "Check for updates" in Slice 6).
    /// Silently ignored if a check is already in flight.
    public func triggerCheck() async {
        guard !isChecking else { return }
        await runCheck()
    }

    // MARK: — Private

    private func runCheck() async {
        isChecking = true
        emitState()                       // isChecking → true (drives the pulsing icon)
        let result = await performCheck()
        switch result {
        case .ok(let derivedState):
            lastDerivedState = derivedState
            lastOutcomeWas404 = false
        case .originNotFound:
            lastOutcomeWas404 = true
        case .transientError:
            // Non-destructive: preserve current cadence (including 404 backoff)
            // and do not overwrite lastDerivedState with a failed result.
            break
        }
        isChecking = false
        emitState()                       // isChecking → false + latest lastDerivedState
    }

    /// Publish the current observable state to the `stateUpdates` stream so the
    /// main-actor `AppModel` reflects it after every check (and mid-check).
    private func emitState() {
        stateContinuation.yield(
            SchedulerState(isChecking: isChecking, lastDerivedState: lastDerivedState)
        )
    }

    /// Finish the `stateUpdates` stream so consuming tasks terminate cleanly.
    public func finishStateUpdates() {
        stateContinuation.finish()
    }
}

/// Pure value describing the two independent axes of the menu-bar icon state.
public struct MenuBarIconState: Equatable, Sendable {
    /// Drives base colour: `false` → monochrome, `true` → system red (#FF3B30).
    public let attention: Bool
    /// When `true`, the icon pulses in its current base colour.
    public let pulsing: Bool

    public init(attention: Bool, pulsing: Bool) {
        self.attention = attention
        self.pulsing = pulsing
    }
}
