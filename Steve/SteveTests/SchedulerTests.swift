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
            return nil
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
        performCheck: { expected },
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
            return nil
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
            return nil
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
            return nil
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
            return nil
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
            return nil
        },
        clock: InstantClock()
    )

    await scheduler.start()

    #expect(counter.value == 1)
}
