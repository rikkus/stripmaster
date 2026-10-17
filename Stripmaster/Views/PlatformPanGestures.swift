#if os(macOS)
import AppKit
import SwiftUI

/// Turns two-finger trackpad scrolling into panning while the pointer is over
/// the board. This is the usual way a canvas pans on macOS.
struct ScrollWheelPanInstaller: NSViewRepresentable {
    let onPan: (CGSize) -> Void

    func makeNSView(context: Context) -> ScrollWheelPanView {
        let view = ScrollWheelPanView()
        view.onPan = onPan
        return view
    }

    func updateNSView(_ nsView: ScrollWheelPanView, context: Context) {
        nsView.onPan = onPan
    }

    static func dismantleNSView(_ nsView: ScrollWheelPanView, coordinator: ()) {
        nsView.stopMonitoring()
    }
}

final class ScrollWheelPanView: NSView {
    var onPan: ((CGSize) -> Void)?
    private var monitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            removeMonitor()
        } else {
            installMonitor()
        }
    }

    private func installMonitor() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel]) { [weak self] event in
            guard let self,
                  let window = self.window,
                  event.window === window,
                  event.modifierFlags.contains(.command) == false
            else { return event }

            let location = self.convert(event.locationInWindow, from: nil)
            guard self.bounds.contains(location) else { return event }

            let factor: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 10
            let delta = CGSize(
                width: event.scrollingDeltaX * factor,
                height: event.scrollingDeltaY * factor
            )
            guard delta.width != 0 || delta.height != 0 else { return event }
            self.onPan?(delta)
            return nil
        }
    }

    func stopMonitoring() {
        removeMonitor()
    }

    private func removeMonitor() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}
#endif
