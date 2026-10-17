import Darwin
import Foundation

/// A deliberately tiny assertion harness.
///
/// The functional suite is a plain executable, like the ljoss model tests: it
/// needs no test host, simulator, or Xcode build, and it compiles in a couple of
/// seconds with the toolchain's `swiftc`.
@MainActor
final class TestLog {
    private(set) var checks = 0
    private(set) var failures: [String] = []
    private var groupName = ""

    func group(_ name: String, _ body: @MainActor () -> Void) {
        groupName = name
        let before = failures.count
        print("… \(name)")
        body()
        report(name: name, newFailures: failures.count - before)
    }

    func groupAsync(_ name: String, _ body: @MainActor () async -> Void) async {
        groupName = name
        let before = failures.count
        print("… \(name)")
        await body()
        report(name: name, newFailures: failures.count - before)
    }

    private func report(name: String, newFailures: Int) {
        if newFailures == 0 {
            print("  ✓ \(name)")
        } else {
            print("  ✗ \(name): \(newFailures) failure(s)")
        }
        groupName = ""
    }

    func expect(
        _ condition: @autoclosure () -> Bool,
        _ message: @autoclosure () -> String = "condition was false",
        file: StaticString = #fileID,
        line: UInt = #line
    ) {
        checks += 1
        if !condition() {
            record(message(), file: file, line: line)
        }
    }

    func equal<T: Equatable>(
        _ actual: @autoclosure () -> T,
        _ expected: @autoclosure () -> T,
        _ note: @autoclosure () -> String = "",
        file: StaticString = #fileID,
        line: UInt = #line
    ) {
        checks += 1
        let actualValue = actual()
        let expectedValue = expected()
        if actualValue != expectedValue {
            let suffix = note().isEmpty ? "" : " — \(note())"
            record("expected \(String(describing: expectedValue)), got \(String(describing: actualValue))\(suffix)", file: file, line: line)
        }
    }

    func notEqual<T: Equatable>(
        _ actual: @autoclosure () -> T,
        _ unexpected: @autoclosure () -> T,
        _ note: @autoclosure () -> String = "",
        file: StaticString = #fileID,
        line: UInt = #line
    ) {
        checks += 1
        let actualValue = actual()
        if actualValue == unexpected() {
            let suffix = note().isEmpty ? "" : " — \(note())"
            record("did not expect \(String(describing: actualValue))\(suffix)", file: file, line: line)
        }
    }

    func isNil<T>(
        _ value: @autoclosure () -> T?,
        _ note: @autoclosure () -> String = "",
        file: StaticString = #fileID,
        line: UInt = #line
    ) {
        checks += 1
        if value() != nil {
            let suffix = note().isEmpty ? "" : " — \(note())"
            record("expected nil\(suffix)", file: file, line: line)
        }
    }

    func isNotNil<T>(
        _ value: @autoclosure () -> T?,
        _ note: @autoclosure () -> String = "",
        file: StaticString = #fileID,
        line: UInt = #line
    ) {
        checks += 1
        if value() == nil {
            let suffix = note().isEmpty ? "" : " — \(note())"
            record("expected a value\(suffix)", file: file, line: line)
        }
    }

    func close(
        _ actual: Double,
        _ expected: Double,
        accuracy: Double = 1e-9,
        _ note: @autoclosure () -> String = "",
        file: StaticString = #fileID,
        line: UInt = #line
    ) {
        checks += 1
        if !actual.isFinite || abs(actual - expected) > accuracy {
            let suffix = note().isEmpty ? "" : " — \(note())"
            record("expected \(expected) ± \(accuracy), got \(actual)\(suffix)", file: file, line: line)
        }
    }

    func close(
        _ actual: CGFloat,
        _ expected: CGFloat,
        accuracy: CGFloat = 1e-9,
        _ note: @autoclosure () -> String = "",
        file: StaticString = #fileID,
        line: UInt = #line
    ) {
        close(Double(actual), Double(expected), accuracy: Double(accuracy), note(), file: file, line: line)
    }

    func throwsError<T>(
        _ body: () throws -> T,
        _ note: @autoclosure () -> String = "",
        file: StaticString = #fileID,
        line: UInt = #line
    ) {
        checks += 1
        do {
            _ = try body()
            record("expected an error\(note().isEmpty ? "" : " — \(note())")", file: file, line: line)
        } catch {
            // Expected.
        }
    }

    private func record(_ message: String, file: StaticString, line: UInt) {
        failures.append("[\(groupName)] \(file):\(line): \(message)")
    }

    func finish(startedAt: Date) -> Bool {
        let duration = Date().timeIntervalSince(startedAt)
        print("")
        if failures.isEmpty {
            print("\(checks) checks passed in \(String(format: "%.2f", duration))s.")
            return true
        }
        print("\(failures.count) failure(s) in \(checks) checks:")
        for failure in failures {
            print("  ✗ \(failure)")
        }
        return false
    }
}

@MainActor
func runAllFunctionalTests() async -> Bool {
    let log = TestLog()
    let started = Date()

    log.group("Templates") { runTemplateTests(log) }
    log.group("Grid and hole naming") { runGridTests(log) }
    log.group("Component catalogue") { runCatalogueTests(log) }
    log.group("Board view and fit") { runViewStateTests(log) }
    log.group("Individual components") { runComponentTests(log) }
    log.group("Jumper drafting") { runJumperDraftTests(log) }
    log.group("Connectivity graph") { runConnectivityTests(log) }
    log.group("Editing and undo history") { runHistoryTests(log) }
    log.group("Document persistence") { runPersistenceTests(log) }
    await log.groupAsync("Autosave debounce") { await runAutosaveTests(log) }

    let passed = log.finish(startedAt: started)
    if !passed {
        exit(1)
    }
    return passed
}
