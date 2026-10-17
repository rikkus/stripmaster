import CoreGraphics
import Foundation

/// The complete serialisable model of an open document: board, edit history,
/// and the remembered view.
///
/// It has no SwiftUI dependencies, so every editing, history, view-fit and
/// persistence behaviour can be exercised by the functional test runner.
struct StripmasterDocumentState: Equatable, Codable, Sendable {
    var board: Stripboard
    var history: EditHistory
    var view: BoardViewState
    var createdAt: Date
    var modifiedAt: Date

    init(
        template: BoardTemplate = .default,
        now: Date = .now
    ) {
        self.board = Stripboard(template: template)
        self.history = EditHistory()
        self.view = BoardViewState()
        self.createdAt = now
        self.modifiedAt = now
    }

    init(
        board: Stripboard,
        history: EditHistory = EditHistory(),
        view: BoardViewState = BoardViewState(),
        createdAt: Date = .now,
        modifiedAt: Date = .now
    ) {
        self.board = board
        self.history = history
        self.view = view
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }

    private enum CodingKeys: String, CodingKey {
        case board
        case history
        case view
        case createdAt
        case modifiedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let board = try container.decodeIfPresent(Stripboard.self, forKey: .board) ?? Stripboard()
        let history = try container.decodeIfPresent(EditHistory.self, forKey: .history) ?? EditHistory()
        let view = try container.decodeIfPresent(BoardViewState.self, forKey: .view) ?? BoardViewState()
        let createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now
        let modifiedAt = try container.decodeIfPresent(Date.self, forKey: .modifiedAt) ?? createdAt
        self.init(
            board: board,
            history: history,
            view: view,
            createdAt: createdAt,
            modifiedAt: modifiedAt
        )
        self = sanitized()
    }

    var dimensions: BoardDimensions { board.dimensions }
    var metrics: BoardMetrics { board.metrics }
    var connectivity: Connectivity { Connectivity(board: board) }

    /// True only for a brand-new, unedited board. Viewing it does not stop it
    /// being pristine, which is what lets a new document choose a template.
    var isUntouched: Bool {
        board.isPristine && history.entries.isEmpty
    }

    var canUndo: Bool { history.canUndo }
    var canRedo: Bool { history.canRedo }
    var undoLabel: String? { history.undoLabel }
    var redoLabel: String? { history.redoLabel }

    var sideDescription: String { board.template.displayName + " · " + view.side.description }

    // MARK: - Board edits

    @discardableResult
    mutating func setCut(_ hole: GridPoint, _ isCut: Bool, at date: Date = .now) -> Bool {
        guard board.isCut(hole) != isCut else { return false }
        return perform(.setCut(hole: hole, isCut: isCut), at: date)
    }

    @discardableResult
    mutating func toggleCut(_ hole: GridPoint, at date: Date = .now) -> Bool {
        setCut(hole, !board.isCut(hole), at: date)
    }

    @discardableResult
    mutating func setSoldered(_ hole: GridPoint, _ isSoldered: Bool, at date: Date = .now) -> Bool {
        guard board.isSoldered(hole) != isSoldered else { return false }
        return perform(.setSoldered(hole: hole, isSoldered: isSoldered), at: date)
    }

    @discardableResult
    mutating func toggleSoldered(_ hole: GridPoint, at date: Date = .now) -> Bool {
        setSoldered(hole, !board.isSoldered(hole), at: date)
    }

    @discardableResult
    mutating func addJumper(
        kind: JumperKind,
        route: [GridPoint],
        id: UUID = UUID(),
        at date: Date = .now
    ) -> Jumper? {
        let jumper = Jumper(id: id, kind: kind, route: route)
        guard jumper.isValid(dimensions: dimensions) else { return nil }
        guard addJumper(jumper, at: date) else { return nil }
        return jumper
    }

    @discardableResult
    mutating func addJumper(_ jumper: Jumper, at date: Date = .now) -> Bool {
        guard jumper.isValid(dimensions: dimensions) else { return false }
        guard board.jumper(id: jumper.id) == nil else { return false }
        return perform(.addJumper(jumper), at: date)
    }

    @discardableResult
    mutating func removeJumper(id: UUID, at date: Date = .now) -> Bool {
        guard let index = board.jumpers.firstIndex(where: { $0.id == id }) else { return false }
        let jumper = board.jumpers[index]
        return perform(.removeJumper(jumper, index: index), at: date)
    }

    @discardableResult
    mutating func placeComponent(
        _ component: PlacedComponent,
        at date: Date = .now
    ) -> PlacedComponent? {
        guard let normalised = component.normalised(dimensions: dimensions) else { return nil }
        guard board.component(id: normalised.id) == nil else { return nil }
        guard perform(.addComponent(normalised), at: date) else { return nil }
        return normalised
    }

    @discardableResult
    mutating func placeComponent(
        spec: ComponentSpec,
        at hole: GridPoint,
        axis: GridAxis? = nil,
        span: Int? = nil,
        flipped: Bool = false,
        id: UUID = UUID(),
        at date: Date = .now
    ) -> PlacedComponent? {
        var candidate = PlacedComponent(
            id: id,
            reference: spec.reference,
            anchor: hole,
            axis: axis ?? .horizontal,
            span: span ?? ComponentPlacement.defaultSpan(for: spec),
            flipped: flipped
        )
        if axis == nil {
            let spans = ComponentPlacement.suggestedSpans(for: spec)
            for candidateAxis in GridAxis.allCases {
                for candidateSpan in spans {
                    candidate.axis = candidateAxis
                    candidate.span = candidateSpan
                    if let normalised = candidate.normalised(dimensions: dimensions) {
                        candidate = normalised
                        break
                    }
                }
                if candidate.isValid(dimensions: dimensions) { break }
            }
        } else if let normalised = candidate.normalised(dimensions: dimensions) {
            candidate = normalised
        }
        return placeComponent(candidate, at: date)
    }

    @discardableResult
    mutating func removeComponent(id: UUID, at date: Date = .now) -> Bool {
        guard let index = board.componentIndex(id: id) else { return false }
        let component = board.components[index]
        return perform(.removeComponent(component, index: index), at: date)
    }

    @discardableResult
    mutating func updateComponent(_ updated: PlacedComponent, at date: Date = .now) -> Bool {
        guard let old = board.component(id: updated.id) else { return false }
        guard let normalised = updated.normalised(dimensions: dimensions) else { return false }
        guard normalised != old else { return false }
        return perform(.updateComponent(before: old, after: normalised), at: date)
    }

    @discardableResult
    mutating func moveComponent(id: UUID, to anchor: GridPoint, at date: Date = .now) -> Bool {
        guard let old = board.component(id: id),
              let moved = old.moved(to: anchor, dimensions: dimensions)
        else { return false }
        return updateComponent(moved, at: date)
    }

    @discardableResult
    mutating func rotateComponent(id: UUID, at date: Date = .now) -> Bool {
        guard let old = board.component(id: id),
              let rotated = old.rotated(dimensions: dimensions)
        else { return false }
        return updateComponent(rotated, at: date)
    }

    @discardableResult
    mutating func stretchComponent(id: UUID, span: Int, at date: Date = .now) -> Bool {
        guard let old = board.component(id: id), let spec = old.spec else { return false }
        var updated = old
        updated.span = ComponentPlacement.clamp(span: span, for: spec)
        return updateComponent(updated, at: date)
    }

    @discardableResult
    mutating func flipComponent(id: UUID, at date: Date = .now) -> Bool {
        guard let old = board.component(id: id) else { return false }
        var updated = old
        updated.flipped.toggle()
        return updateComponent(updated, at: date)
    }

    /// Shared path for recording and applying one edit.
    @discardableResult
    private mutating func perform(_ edit: BoardEdit, at date: Date) -> Bool {
        var candidate = board
        guard candidate.apply(edit) else { return false }
        board = candidate
        history.record(edit, date: date)
        modifiedAt = date
        return true
    }

    // MARK: - History

    @discardableResult
    mutating func undo(at date: Date = .now) -> Bool {
        var candidateHistory = history
        guard let edit = candidateHistory.undo() else { return false }
        var candidateBoard = board
        _ = candidateBoard.revert(edit)
        history = candidateHistory
        board = candidateBoard
        modifiedAt = date
        return true
    }

    @discardableResult
    mutating func redo(at date: Date = .now) -> Bool {
        var candidateHistory = history
        guard let edit = candidateHistory.redo() else { return false }
        var candidateBoard = board
        _ = candidateBoard.apply(edit)
        history = candidateHistory
        board = candidateBoard
        modifiedAt = date
        return true
    }

    // MARK: - Board template

    /// Choosing a template is a document-creation action, not an edit: it is
    /// only allowed while the board is untouched, and it starts a fresh history.
    @discardableResult
    mutating func selectTemplate(_ template: BoardTemplate, at date: Date = .now) -> Bool {
        guard isUntouched else { return false }
        guard board.template != template || view.zoom != nil else { return false }
        board = Stripboard(template: template)
        history = EditHistory()
        view.zoom = nil
        view.panX = 0
        view.panY = 0
        view.updatedAt = date
        modifiedAt = date
        return true
    }

    // MARK: - View (never recorded in edit history)

    @discardableResult
    mutating func ensureInitialFit(
        viewport: CGSize,
        padding: CGFloat = BoardZoom.fitPadding,
        at date: Date = .now
    ) -> Bool {
        guard view.ensureInitialFit(
            viewport: viewport,
            metrics: metrics,
            padding: padding,
            at: date
        ) else { return false }
        modifiedAt = date
        return true
    }

    @discardableResult
    mutating func fitView(
        viewport: CGSize,
        padding: CGFloat = BoardZoom.fitPadding,
        at date: Date = .now
    ) -> Bool {
        let before = view
        view.fit(to: viewport, metrics: metrics, padding: padding, at: date)
        guard view != before else { return false }
        modifiedAt = date
        return true
    }

    @discardableResult
    mutating func rotateView(
        viewport: CGSize?,
        padding: CGFloat = BoardZoom.fitPadding,
        at date: Date = .now
    ) -> Bool {
        let before = view
        view.rotateClockwise(viewport: viewport, metrics: metrics, padding: padding, at: date)
        guard view != before else { return false }
        modifiedAt = date
        return true
    }

    @discardableResult
    mutating func flipView(at date: Date = .now) -> Bool {
        let before = view
        view.flipSide(at: date)
        guard view != before else { return false }
        modifiedAt = date
        return true
    }

    @discardableResult
    mutating func panView(by delta: CGSize, at date: Date = .now) -> Bool {
        let before = view
        view.pan(by: delta, at: date)
        guard view != before else { return false }
        modifiedAt = date
        return true
    }

    @discardableResult
    mutating func zoomView(
        to targetZoom: CGFloat,
        around anchor: CGPoint,
        viewport: CGSize,
        fallbackZoom: CGFloat,
        at date: Date = .now
    ) -> Bool {
        let before = view
        guard view.zoom(
            to: targetZoom,
            around: anchor,
            viewport: viewport,
            fallbackZoom: fallbackZoom,
            at: date
        ) else { return false }
        guard view != before else { return false }
        modifiedAt = date
        return true
    }

    @discardableResult
    mutating func zoomView(
        by factor: CGFloat,
        viewport: CGSize,
        fallbackZoom: CGFloat,
        at date: Date = .now
    ) -> Bool {
        let target = (view.zoomValue ?? fallbackZoom) * factor
        return zoomView(
            to: target,
            around: CGPoint(x: viewport.width / 2, y: viewport.height / 2),
            viewport: viewport,
            fallbackZoom: fallbackZoom,
            at: date
        )
    }

    // MARK: - Loading

    /// Repairs anything invalid while preserving as much as possible.
    func sanitized() -> StripmasterDocumentState {
        var copy = self
        copy.board = board.sanitized()
        copy.history = history.sanitized()
        copy.view = view.sanitized()
        return copy
    }
}
