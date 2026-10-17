import Foundation

/// Coalesces a burst of changes into a single autosave signal after a brief
/// pause. The SwiftUI document registers one undo action when this fires;
/// SwiftUI's document machinery uses that undo registration to notice that the
/// document has unsaved changes and to autosave it.
///
/// The sleeper is injectable so the debounce behaviour itself can be tested
/// without waiting on wall-clock time in the functional suite.
@MainActor
final class AutosaveSignal {
    typealias Sleeper = @Sendable (Duration) async throws -> Void

    private let delay: Duration
    private let sleeper: Sleeper
    private var task: Task<Void, Never>?
    private(set) var isPending = false
    private(set) var signalCount = 0

    var onSignal: (@MainActor () -> Void)?

    init(
        delay: Duration = .milliseconds(350),
        sleeper: @escaping Sleeper = { duration in
            try await Task.sleep(for: duration)
        }
    ) {
        self.delay = delay
        self.sleeper = sleeper
    }

    deinit {
        task?.cancel()
    }

    /// Called after every edit or view change.
    func schedule() {
        task?.cancel()
        isPending = true
        let delay = delay
        let sleeper = sleeper
        task = Task { @MainActor [weak self] in
            do {
                try await sleeper(delay)
            } catch {
                return
            }
            guard !Task.isCancelled, let self, self.isPending else { return }
            self.isPending = false
            self.signalCount += 1
            self.onSignal?()
        }
    }

    /// Fires the signal now. Used when a window closes or the app backgrounds.
    func flush() {
        task?.cancel()
        task = nil
        guard isPending else { return }
        isPending = false
        signalCount += 1
        onSignal?()
    }

    func cancel() {
        task?.cancel()
        task = nil
        isPending = false
    }
}
