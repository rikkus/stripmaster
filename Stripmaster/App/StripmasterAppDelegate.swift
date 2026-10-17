#if os(macOS)
import AppKit

/// Small macOS-only launch helper.
///
/// DocumentGroup normally presents the open panel when launched with no
/// documents. The UI tests (and `--new-document` for manual checks) ask the
/// document controller for an untitled document instead, then dismiss the
/// launch panel so the editor is immediately visible.
@MainActor
final class StripmasterAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("--new-document") || arguments.contains("--ui-testing") else {
            return
        }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            self?.dismissLaunchPanels()
            NSDocumentController.shared.newDocument(nil)
        }
    }

    private func dismissLaunchPanels() {
        for window in NSApp.windows {
            if let panel = window as? NSOpenPanel {
                panel.cancel(nil)
            }
        }
    }
}
#endif
