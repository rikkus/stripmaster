import SwiftUI

struct StripmasterDocumentFocusKey: FocusedValueKey {
    typealias Value = StripmasterDocument
}

struct StripmasterViewportFocusKey: FocusedValueKey {
    typealias Value = CGSize
}

extension FocusedValues {
    var stripmasterDocument: StripmasterDocument? {
        get { self[StripmasterDocumentFocusKey.self] }
        set { self[StripmasterDocumentFocusKey.self] = newValue }
    }

    var stripmasterViewport: CGSize? {
        get { self[StripmasterViewportFocusKey.self] }
        set { self[StripmasterViewportFocusKey.self] = newValue }
    }
}

/// Commands for the active document window.
///
/// Undo/redo deliberately replace the system menu items and use the persisted
/// edit history rather than UndoManager, which is only used to nudge SwiftUI's
/// autosave.
struct StripmasterCommands: Commands {
    @FocusedValue(\.stripmasterDocument) private var document
    @FocusedValue(\.stripmasterViewport) private var viewport

    var body: some Commands {
        CommandGroup(replacing: .undoRedo) {
            Button(document?.undoLabel.map { "Undo \($0)" } ?? "Undo") {
                _ = document?.undo()
            }
            .keyboardShortcut("z", modifiers: .command)
            .disabled(document?.canUndo != true)

            Button(document?.redoLabel.map { "Redo \($0)" } ?? "Redo") {
                _ = document?.redo()
            }
            .keyboardShortcut("z", modifiers: [.command, .shift])
            .disabled(document?.canRedo != true)
        }

        CommandMenu("Board") {
            Button("Fit to Window") {
                if let document, let viewport, viewport.width > 1 {
                    _ = document.fitView(viewport: viewport)
                }
            }
            .keyboardShortcut("0", modifiers: .command)
            .disabled(document == nil || viewport == nil)

            Button("Rotate 90°") {
                if let document {
                    _ = document.rotateView(viewport: viewport)
                }
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(document == nil)

            Button(document?.view.side == .bottom ? "Show Component Side" : "Show Copper Side") {
                _ = document?.flipView()
            }
            .keyboardShortcut("f", modifiers: [.command, .shift])
            .disabled(document == nil)

            Divider()

            Button("Zoom In") {
                zoom(by: 1.25)
            }
            .keyboardShortcut("=", modifiers: .command)
            .disabled(document == nil)

            Button("Zoom Out") {
                zoom(by: 0.8)
            }
            .keyboardShortcut("-", modifiers: .command)
            .disabled(document == nil)

        }
    }

    private func zoom(by factor: CGFloat) {
        guard let document, let viewport, viewport.width > 1 else { return }
        let fallback = document.metrics.fitZoom(
            viewport: viewport,
            orientation: document.view.orientation,
            padding: BoardZoom.fitPadding
        )
        _ = document.zoomView(by: factor, viewport: viewport, fallbackZoom: fallback)
    }
}
