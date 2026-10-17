import Foundation
import Observation
import SwiftUI
import UniformTypeIdentifiers

/// The live SwiftUI document.
///
/// All editing, history and geometry behaviour lives in the UI-free
/// `StripmasterDocumentState`; this class is the bridge to SwiftUI's document
/// machinery. Every successful change goes through one of the wrapper methods
/// so the debounced autosave signal is always raised, including for view-only
/// changes such as panning, zooming, rotating and flipping.
@Observable
@MainActor
final class StripmasterDocument: Document {
    typealias Reader = FileWrapperDocumentReader<StripmasterFile>
    typealias Writer = FileWrapperDocumentWriter<StripmasterFile>

    private(set) var state: StripmasterDocumentState

    @ObservationIgnored private let configuration: URLDocumentConfiguration
    @ObservationIgnored private let autosave: AutosaveSignal
    @ObservationIgnored private weak var undoManager: UndoManager?
    @ObservationIgnored private var pendingDirtyRegistration = false

    /// True for a document that started life with New rather than Open.
    @ObservationIgnored let isNewDocument: Bool
    /// True when the document is new and the template was not chosen by an
    /// explicit creation source. The editor offers the size picker in that case.
    @ObservationIgnored let offersInitialTemplateChoice: Bool
    /// The template chosen at creation, for the editor's first-run affordance.
    @ObservationIgnored let creationTemplate: BoardTemplate

    @MainActor
    init(configuration: URLDocumentConfiguration, context: DocumentCreationContext) {
        self.configuration = configuration
        self.isNewDocument = configuration.fileURL == nil
        self.creationTemplate = LaunchTemplateSelection.template(for: context)
        self.offersInitialTemplateChoice = isNewDocument && !LaunchTemplateSelection.wasExplicit(context)
        self.state = StripmasterDocumentState(template: creationTemplate)

        let autosave = AutosaveSignal()
        self.autosave = autosave
        autosave.onSignal = { [weak self] in
            self?.registerAutosaveSignal()
        }
    }

    // MARK: - Observable pass-throughs

    var board: Stripboard { state.board }
    var history: EditHistory { state.history }
    var view: BoardViewState { state.view }
    var connectivity: Connectivity { state.connectivity }
    var dimensions: BoardDimensions { state.dimensions }
    var metrics: BoardMetrics { state.metrics }
    var canUndo: Bool { state.canUndo }
    var canRedo: Bool { state.canRedo }
    var undoLabel: String? { state.undoLabel }
    var redoLabel: String? { state.redoLabel }
    var isUntouched: Bool { state.isUntouched }

    var fileURL: URL? { configuration.fileURL }

    // MARK: - Autosave

    /// The editor's `UndoManager` is the signal SwiftUI uses to decide a document
    /// has unsaved changes. Our real undo stack is the history; this registration
    /// exists only to drive SwiftUI's autosave, and the app replaces the standard
    /// Undo/Redo commands with history-backed ones.
    func attach(undoManager: UndoManager?) {
        if self.undoManager !== undoManager {
            self.undoManager = undoManager
        }
        if pendingDirtyRegistration, undoManager != nil {
            registerAutosaveSignal()
        }
    }

    /// Flush a pending debounce, e.g. when the window disappears or the app
    /// backgrounds. The registration itself is what marks the document dirty.
    func flushAutosave() {
        autosave.flush()
    }

    private func noteChange() {
        autosave.schedule()
    }

    private func registerAutosaveSignal() {
        guard let undoManager else {
            pendingDirtyRegistration = true
            return
        }
        pendingDirtyRegistration = false
        // The closure body is intentionally empty: the app's undo/redo menu
        // actions use the persisted edit history, not UndoManager. Registering
        // an action is what tells SwiftUI there are unsaved changes.
        undoManager.registerUndo(withTarget: self) { _ in }
        undoManager.setActionName("Board Change")
    }

    // MARK: - Editing

    @discardableResult
    func setCut(_ hole: GridPoint, _ isCut: Bool) -> Bool {
        let changed = state.setCut(hole, isCut)
        if changed { noteChange() }
        return changed
    }

    @discardableResult
    func setSoldered(_ hole: GridPoint, _ isSoldered: Bool) -> Bool {
        let changed = state.setSoldered(hole, isSoldered)
        if changed { noteChange() }
        return changed
    }

    @discardableResult
    func addJumper(kind: JumperKind, route: [GridPoint]) -> Jumper? {
        let jumper = state.addJumper(kind: kind, route: route)
        if jumper != nil { noteChange() }
        return jumper
    }

    @discardableResult
    func removeJumper(id: UUID) -> Bool {
        let changed = state.removeJumper(id: id)
        if changed { noteChange() }
        return changed
    }

    @discardableResult
    func placeComponent(
        spec: ComponentSpec,
        at hole: GridPoint,
        axis: GridAxis? = nil,
        span: Int? = nil,
        flipped: Bool = false
    ) -> PlacedComponent? {
        let component = state.placeComponent(
            spec: spec,
            at: hole,
            axis: axis,
            span: span,
            flipped: flipped
        )
        if component != nil { noteChange() }
        return component
    }

    @discardableResult
    func placeComponent(_ component: PlacedComponent) -> PlacedComponent? {
        let placed = state.placeComponent(component)
        if placed != nil { noteChange() }
        return placed
    }

    @discardableResult
    func updateComponent(_ component: PlacedComponent) -> Bool {
        let changed = state.updateComponent(component)
        if changed { noteChange() }
        return changed
    }

    @discardableResult
    func moveComponent(id: UUID, to anchor: GridPoint) -> Bool {
        let changed = state.moveComponent(id: id, to: anchor)
        if changed { noteChange() }
        return changed
    }

    @discardableResult
    func rotateComponent(id: UUID) -> Bool {
        let changed = state.rotateComponent(id: id)
        if changed { noteChange() }
        return changed
    }

    @discardableResult
    func stretchComponent(id: UUID, span: Int) -> Bool {
        let changed = state.stretchComponent(id: id, span: span)
        if changed { noteChange() }
        return changed
    }

    @discardableResult
    func flipComponent(id: UUID) -> Bool {
        let changed = state.flipComponent(id: id)
        if changed { noteChange() }
        return changed
    }

    @discardableResult
    func removeComponent(id: UUID) -> Bool {
        let changed = state.removeComponent(id: id)
        if changed { noteChange() }
        return changed
    }

    @discardableResult
    func selectTemplate(_ template: BoardTemplate) -> Bool {
        let changed = state.selectTemplate(template)
        if changed { noteChange() }
        return changed
    }

    @discardableResult
    func undo() -> Bool {
        let changed = state.undo()
        if changed { noteChange() }
        return changed
    }

    @discardableResult
    func redo() -> Bool {
        let changed = state.redo()
        if changed { noteChange() }
        return changed
    }

    // MARK: - View changes (never part of edit history)

    @discardableResult
    func ensureInitialFit(viewport: CGSize) -> Bool {
        let changed = state.ensureInitialFit(viewport: viewport)
        if changed { noteChange() }
        return changed
    }

    @discardableResult
    func fitView(viewport: CGSize) -> Bool {
        let changed = state.fitView(viewport: viewport)
        if changed { noteChange() }
        return changed
    }

    @discardableResult
    func rotateView(viewport: CGSize?) -> Bool {
        let changed = state.rotateView(viewport: viewport)
        if changed { noteChange() }
        return changed
    }

    @discardableResult
    func flipView() -> Bool {
        let changed = state.flipView()
        if changed { noteChange() }
        return changed
    }

    @discardableResult
    func panView(by delta: CGSize) -> Bool {
        let changed = state.panView(by: delta)
        if changed { noteChange() }
        return changed
    }

    @discardableResult
    func zoomView(
        to targetZoom: CGFloat,
        around anchor: CGPoint,
        viewport: CGSize,
        fallbackZoom: CGFloat
    ) -> Bool {
        let changed = state.zoomView(
            to: targetZoom,
            around: anchor,
            viewport: viewport,
            fallbackZoom: fallbackZoom
        )
        if changed { noteChange() }
        return changed
    }

    @discardableResult
    func zoomView(by factor: CGFloat, viewport: CGSize, fallbackZoom: CGFloat) -> Bool {
        let changed = state.zoomView(
            by: factor,
            viewport: viewport,
            fallbackZoom: fallbackZoom
        )
        if changed { noteChange() }
        return changed
    }

    // MARK: - Document

    nonisolated static var readableContentTypes: [UTType] { [.stripmasterBoard] }
    nonisolated static var writableContentTypes: [UTType] { [.stripmasterBoard] }

    nonisolated func reader(configuration: sending DocumentReadConfiguration) -> sending Reader {
        FileWrapperDocumentReader(configuration) { fileWrapper in
            guard let data = fileWrapper.regularFileContents else {
                throw StripmasterDocumentError.missingFileContents
            }
            return try StripmasterFileCodec.decode(data)
        }
    }

    nonisolated func writer(configuration: sending DocumentWriteConfiguration) -> sending Writer {
        FileWrapperDocumentWriter(configuration) { snapshot, _ in
            let data = try StripmasterFileCodec.encode(snapshot)
            return FileWrapper(regularFileWithContents: data)
        }
    }

    @MainActor
    func snapshot(contentType: UTType) async throws -> sending StripmasterFile {
        StripmasterFile(state: state)
    }

    @MainActor
    func apply(snapshot: sending StripmasterFile, previous: sending StripmasterFile?) async throws {
        autosave.cancel()
        pendingDirtyRegistration = false
        state = snapshot.state
    }
}
