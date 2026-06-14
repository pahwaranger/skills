import Testing
import Foundation
import StateEngine
import Scheduler

// MARK: — Test helpers

/// Thread-safe counter for tracking how many times performCheck was called.
final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = 0
    var value: Int { lock.withLock { _value } }
    func increment() { lock.withLock { _value += 1 } }
}

/// A SchedulerClock whose `sleep` returns instantly, so tests don't wall-clock wait.
struct InstantClock: SchedulerClock {
    func sleep(for duration: TimeInterval) async throws {}
}

/// A clock where each `sleep` call blocks until `releaseOne()` is called for that
/// specific sleep. Releases are tracked by index so each tick is individually controlled.
final class GatedClock: SchedulerClock, @unchecked Sendable {
    private let lock = NSLock()
    private var _sleepCount = 0   // how many sleeps have started
    private var _releaseCount = 0 // how many have been released

    /// How many sleeps have started so far.
    var sleepCount: Int { lock.withLock { _sleepCount } }

    /// Release the next pending sleep (one at a time).
    func releaseOne() { lock.withLock { _releaseCount += 1 } }

    func sleep(for duration: TimeInterval) async throws {
        let myIndex = lock.withLock { () -> Int in
            _sleepCount += 1
            return _sleepCount  // 1-based index for this sleep
        }
        while lock.withLock({ _releaseCount < myIndex }) && !Task.isCancelled {
            await Task.yield()
        }
    }
}

// MARK: — isChecking tracks in-flight state

@Test func isCheckingIsTrueDuringCheckAndFalseAfter() async {
    // Gate the performCheck so we can observe isChecking = true while it's parked.
    final class CheckGate: @unchecked Sendable {
        private let lock = NSLock()
        private var _started = false
        private var _released = false
        var started: Bool { lock.withLock { _started } }
        func markStarted() { lock.withLock { _started = true } }
        func release() { lock.withLock { _released = true } }
        var isReleased: Bool { lock.withLock { _released } }
    }
    let gate = CheckGate()

    // Disable automatic checks so the timer loop doesn't immediately re-enter.
    let scheduler = CheckScheduler(
        performCheck: {
            gate.markStarted()
            while !gate.isReleased && !Task.isCancelled { await Task.yield() }
            return .ok(nil)
        },
        clock: InstantClock(),
        automaticChecksEnabled: false
    )

    // Launch start() in a child task so we can observe while it's blocked.
    async let startTask: Void = scheduler.start()

    // Wait until performCheck has begun (isChecking must be true).
    while !gate.started { await Task.yield() }
    let checkingDuring = await scheduler.isChecking
    #expect(checkingDuring == true)

    // Release the check and let start() finish.
    gate.release()
    await startTask

    let checkingAfter = await scheduler.isChecking
    #expect(checkingAfter == false)
}

// MARK: — lastDerivedState holds the result after start()

@Test func startExposesLastDerivedStateAfterCheck() async {
    let expected = DerivedState(
        states: ["alpha": .updateAvailable],
        attention: true,
        selfHealed: []
    )
    let scheduler = CheckScheduler(
        performCheck: { .ok(expected) },
        clock: InstantClock()
    )

    await scheduler.start()

    let result = await scheduler.lastDerivedState
    #expect(result == expected)
}

// MARK: — Single-flight: triggerCheck during in-flight is ignored

@Test func triggerCheckDuringInFlightIsIgnored() async {
    final class CheckGate: @unchecked Sendable {
        private let lock = NSLock()
        private var _started = false
        private var _released = false
        var started: Bool { lock.withLock { _started } }
        func markStarted() { lock.withLock { _started = true } }
        func release() { lock.withLock { _released = true } }
        var isReleased: Bool { lock.withLock { _released } }
    }
    let gate = CheckGate()
    let counter = Counter()

    let scheduler = CheckScheduler(
        performCheck: {
            counter.increment()
            gate.markStarted()
            while !gate.isReleased && !Task.isCancelled { await Task.yield() }
            return .ok(nil)
        },
        clock: InstantClock()
    )

    // Start the first check (in-flight, gated).
    async let firstCheck: Void = scheduler.start()
    while !gate.started { await Task.yield() }

    // Trigger while in-flight — must be ignored, not queued.
    await scheduler.triggerCheck()

    #expect(counter.value == 1)  // only the original check ran

    gate.release()
    await firstCheck
}

// MARK: — Periodic check fires after the interval

@Test func periodicCheckFiresAfterInterval() async {
    // GatedClock's sleeps block until individually released, so we control each tick.
    let clock = GatedClock()
    let counter = Counter()

    let scheduler = CheckScheduler(
        performCheck: {
            counter.increment()
            return .ok(nil)
        },
        clock: clock
    )

    // start() fires the launch check (counter → 1) then returns.
    // The timer loop is running in the background, parked in the first clock.sleep.
    await scheduler.start()
    #expect(counter.value == 1)

    // Wait for the timer loop to enter its first sleep.
    while clock.sleepCount < 1 { await Task.yield() }

    // Release that one sleep → timer loop wakes → fires second check.
    clock.releaseOne()

    // Yield until the second check completes.
    while counter.value < 2 { await Task.yield() }

    #expect(counter.value == 2)
}

// MARK: — Automatic checks disabled: no periodic check after start()

@Test func automaticChecksDisabledSuppressesTimerLoop() async {
    let clock = GatedClock()
    let counter = Counter()

    let scheduler = CheckScheduler(
        performCheck: {
            counter.increment()
            return .ok(nil)
        },
        clock: clock,
        automaticChecksEnabled: false
    )

    await scheduler.start()
    #expect(counter.value == 1)  // launch check ran

    // Even if we release a sleep slot, it should never be consumed.
    clock.releaseOne()
    for _ in 0..<100 { await Task.yield() }

    // No timer loop → still only the launch check.
    #expect(counter.value == 1)
    // No sleeps were started.
    #expect(clock.sleepCount == 0)
}

// MARK: — MenuBarIconState: all four combinations of the two independent axes

@Test func iconIdleAndStill() {
    let state = MenuBarIconState(attention: false, pulsing: false)
    #expect(state.attention == false)
    #expect(state.pulsing == false)
}

@Test func iconAttentionAndStill() {
    let state = MenuBarIconState(attention: true, pulsing: false)
    #expect(state.attention == true)
    #expect(state.pulsing == false)
}

@Test func iconIdleAndPulsing() {
    let state = MenuBarIconState(attention: false, pulsing: true)
    #expect(state.attention == false)
    #expect(state.pulsing == true)
}

@Test func iconAttentionAndPulsing() {
    // A check running during attention: red + pulsing.
    let state = MenuBarIconState(attention: true, pulsing: true)
    #expect(state.attention == true)
    #expect(state.pulsing == true)
}

// MARK: — Timer tick during in-flight manual check is also ignored

@Test func timerTickDuringManualCheckIsIgnored() async {
    let clock = GatedClock()
    let counter = Counter()

    // Per-call gate: each performCheck invocation waits for its own release slot.
    final class SequencedGate: @unchecked Sendable {
        private let lock = NSLock()
        private var _callCount = 0     // how many calls have started
        private var _releaseCount = 0  // how many have been released

        var callCount: Int { lock.withLock { _callCount } }
        func releaseOne() { lock.withLock { _releaseCount += 1 } }

        func waitForRelease() async {
            let myIndex = lock.withLock { () -> Int in
                _callCount += 1
                return _callCount
            }
            while lock.withLock({ _releaseCount < myIndex }) && !Task.isCancelled {
                await Task.yield()
            }
        }
    }
    let gate = SequencedGate()

    let scheduler = CheckScheduler(
        performCheck: {
            counter.increment()
            await gate.waitForRelease()
            return .ok(nil)
        },
        clock: clock
    )

    // start() fires the launch check and blocks inside gate.waitForRelease (call #1).
    async let startTask: Void = scheduler.start()
    while gate.callCount < 1 { await Task.yield() }

    // Release call #1 → launch check completes, start() returns, timer loop begins.
    gate.releaseOne()
    await startTask
    #expect(counter.value == 1)

    // Timer loop is parked in clock.sleep. Trigger a manual check.
    async let manualTask: Void = scheduler.triggerCheck()
    while gate.callCount < 2 { await Task.yield() }
    // Manual check is in-flight (call #2).

    // Now release the timer sleep. Because a check is in-flight, the tick must be ignored.
    clock.releaseOne()
    for _ in 0..<200 { await Task.yield() }

    // Timer tick dropped; still only 2 checks.
    #expect(counter.value == 2)

    // Clean up: release the manual check.
    gate.releaseOne()
    await manualTask
}

// MARK: — Tracer bullet: start() fires an immediate check

@Test func startFiresImmediateCheck() async {
    let counter = Counter()
    let scheduler = CheckScheduler(
        performCheck: {
            counter.increment()
            return .ok(nil)
        },
        clock: InstantClock()
    )

    await scheduler.start()

    #expect(counter.value == 1)
}

// MARK: — 404 slow-retry backoff helpers

/// A GatedClock that also captures the duration passed to each sleep call.
final class CapturingGatedClock: SchedulerClock, @unchecked Sendable {
    private let lock = NSLock()
    private var _sleepCount = 0
    private var _releaseCount = 0
    private var _durations: [TimeInterval] = []

    var sleepCount: Int { lock.withLock { _sleepCount } }
    var durations: [TimeInterval] { lock.withLock { _durations } }

    func releaseOne() { lock.withLock { _releaseCount += 1 } }

    func sleep(for duration: TimeInterval) async throws {
        let myIndex = lock.withLock { () -> Int in
            _sleepCount += 1
            _durations.append(duration)
            return _sleepCount
        }
        while lock.withLock({ _releaseCount < myIndex }) && !Task.isCancelled {
            await Task.yield()
        }
    }
}

// MARK: — After originNotFound, timer loop sleeps for slowRetryInterval

@Test func afterOriginNotFoundTimerUsesSlowRetryInterval() async {
    let clock = CapturingGatedClock()
    let counter = Counter()
    let normalInterval: TimeInterval = 3600
    let slowInterval: TimeInterval = 21600  // 6h

    // First check returns originNotFound; subsequent checks succeed.
    let callCount = Counter()
    let scheduler = CheckScheduler(
        performCheck: {
            callCount.increment()
            counter.increment()
            return callCount.value == 1 ? .originNotFound : .ok(nil)
        },
        clock: clock,
        interval: normalInterval,
        slowRetryInterval: slowInterval
    )

    // Launch check fires (call #1 → originNotFound). Timer loop starts, parked in first sleep.
    await scheduler.start()
    while clock.sleepCount < 1 { await Task.yield() }

    // The first sleep after a 404 must use the slow retry interval.
    let firstSleepDuration = clock.durations[0]
    #expect(firstSleepDuration == slowInterval, "Expected slow interval after 404, got \(firstSleepDuration)")

    // Release that sleep → timer loop wakes and fires second check (success).
    clock.releaseOne()
    while counter.value < 2 { await Task.yield() }
    while clock.sleepCount < 2 { await Task.yield() }

    // After a successful check, the interval must revert to normal.
    let secondSleepDuration = clock.durations[1]
    #expect(secondSleepDuration == normalInterval, "Expected normal interval after success, got \(secondSleepDuration)")
}

// MARK: — After success following 404, normal cadence is restored

@Test func successAfter404RestoresNormalCadence() async {
    let clock = CapturingGatedClock()
    let callCount = Counter()
    let normalInterval: TimeInterval = 3600
    let slowInterval: TimeInterval = 21600

    // Sequence: 404, success, success
    let scheduler = CheckScheduler(
        performCheck: {
            callCount.increment()
            switch callCount.value {
            case 1: return .originNotFound
            default: return .ok(nil)
            }
        },
        clock: clock,
        interval: normalInterval,
        slowRetryInterval: slowInterval
    )

    await scheduler.start()
    while clock.sleepCount < 1 { await Task.yield() }
    // Slow retry after 404
    #expect(clock.durations[0] == slowInterval)

    // Release → second check (success) runs
    clock.releaseOne()
    while clock.sleepCount < 2 { await Task.yield() }
    // Normal interval restored
    #expect(clock.durations[1] == normalInterval)

    clock.releaseOne()
}

// MARK: — Manual triggerCheck still works during slow-retry backoff

@Test func manualTriggerWorksDuringSlowRetryBackoff() async {
    let clock = CapturingGatedClock()
    let callCount = Counter()
    let normalInterval: TimeInterval = 3600
    let slowInterval: TimeInterval = 21600

    // First check → 404, so timer backs off to slowInterval.
    let scheduler = CheckScheduler(
        performCheck: {
            callCount.increment()
            return callCount.value == 1 ? .originNotFound : .ok(nil)
        },
        clock: clock,
        interval: normalInterval,
        slowRetryInterval: slowInterval
    )

    // Launch check (404) runs, timer loop parks in slow-retry sleep.
    await scheduler.start()
    while clock.sleepCount < 1 { await Task.yield() }
    #expect(clock.durations[0] == slowInterval)

    // Manual trigger fires while the timer is sleeping (not in-flight).
    await scheduler.triggerCheck()
    #expect(callCount.value == 2)

    // Clean up: release the pending slow-retry sleep.
    clock.releaseOne()
}

// MARK: — Manual trigger during backoff preserves single-flight

@Test func manualTriggerDuringBackoffPreservesSingleFlight() async {
    let clock = CapturingGatedClock()
    let callCount = Counter()

    final class CheckGate: @unchecked Sendable {
        private let lock = NSLock()
        private var _started = false
        private var _released = false
        var started: Bool { lock.withLock { _started } }
        func markStarted() { lock.withLock { _started = true } }
        func release() { lock.withLock { _released = true } }
        var isReleased: Bool { lock.withLock { _released } }
    }
    let gate = CheckGate()

    let scheduler = CheckScheduler(
        performCheck: {
            callCount.increment()
            if callCount.value == 2 {
                gate.markStarted()
                while !gate.isReleased && !Task.isCancelled { await Task.yield() }
            }
            return callCount.value == 1 ? .originNotFound : .ok(nil)
        },
        clock: clock,
        interval: 3600,
        slowRetryInterval: 21600
    )

    // Launch check → 404, timer parks in slow-retry sleep.
    await scheduler.start()
    while clock.sleepCount < 1 { await Task.yield() }

    // Manual trigger fires (check #2 in-flight, gated).
    async let manualTask: Void = scheduler.triggerCheck()
    while !gate.started { await Task.yield() }

    // A second manual trigger while #2 is in-flight must be ignored.
    await scheduler.triggerCheck()
    #expect(callCount.value == 2)

    gate.release()
    await manualTask

    // Clean up.
    clock.releaseOne()
}
