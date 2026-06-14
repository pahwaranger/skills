import Foundation
import StateEngine
// SMAppService wired in Slice 11

/// Injectable clock so tests can drive time without wall-clock waits.
public protocol SchedulerClock: Sendable {
    func sleep(for duration: TimeInterval) async throws
}

/// Manages when checks fire and exposes observable state for the menu-bar icon.
/// Depends on an injected `performCheck` closure so the full pipeline
/// (OriginClient → CacheStore → StateEngine) is exercised outside this actor.
public actor CheckScheduler {
    public private(set) var isChecking: Bool = false
    public private(set) var lastDerivedState: DerivedState?

    private let performCheck: @Sendable () async -> DerivedState?
    private let clock: any SchedulerClock
    private let interval: TimeInterval
    private let automaticChecksEnabled: Bool

    public init(
        performCheck: @escaping @Sendable () async -> DerivedState?,
        clock: any SchedulerClock,
        interval: TimeInterval = 3600,
        automaticChecksEnabled: Bool = true
    ) {
        self.performCheck = performCheck
        self.clock = clock
        self.interval = interval
        self.automaticChecksEnabled = automaticChecksEnabled
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
            try? await clock.sleep(for: interval)
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
        lastDerivedState = await performCheck()
        isChecking = false
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
