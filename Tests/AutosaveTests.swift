import Foundation

@MainActor
private final class AutosaveCounter {
    var value = 0
}

@MainActor
func runAutosaveTests(_ t: TestLog) async {
    let counter = AutosaveCounter()
    let signal = AutosaveSignal(delay: .milliseconds(25))
    signal.onSignal = { counter.value += 1 }

    // A burst of changes produces one signal.
    for _ in 0..<5 {
        signal.schedule()
    }
    t.expect(signal.isPending)
    try? await Task.sleep(for: .milliseconds(80))
    t.equal(counter.value, 1, "rapid changes are coalesced")
    t.equal(signal.signalCount, 1)
    t.expect(!signal.isPending)

    // A flush signals immediately and does not double-fire.
    signal.schedule()
    signal.flush()
    t.equal(counter.value, 2, "flush fires without waiting")
    t.expect(!signal.isPending)
    try? await Task.sleep(for: .milliseconds(50))
    t.equal(counter.value, 2, "the cancelled delayed signal does not fire")

    // Cancelling suppresses the signal entirely.
    signal.schedule()
    signal.cancel()
    t.expect(!signal.isPending)
    try? await Task.sleep(for: .milliseconds(50))
    t.equal(counter.value, 2)

    // Flushing with nothing pending is a no-op.
    signal.flush()
    t.equal(counter.value, 2)

    // A single change still triggers after the delay.
    signal.schedule()
    try? await Task.sleep(for: .milliseconds(80))
    t.equal(counter.value, 3)
    t.equal(signal.signalCount, 3)
}
