import SwiftUI

/// The interactive board. Rendering lives in `BoardRenderer`; this view owns the
/// gestures that edit the model and the short-lived preview state.
struct BoardCanvasView: View {
    let document: StripmasterDocument
    @Binding var tool: EditorTool
    @Binding var selectedComponentID: UUID?
    let viewport: CGSize

    @State private var active: ActiveGesture?
    @State private var preview: BoardPreview = .none
    @State private var hoveredHole: GridPoint?
    @State private var magnifyBaselineZoom: CGFloat?
    @State private var isMagnifying = false
    @State private var dragHasBegun = false
    @State private var suppressDragUntilEnded = false
    @State private var lastMagnifyEnd = Date.distantPast

    private var metrics: BoardMetrics { document.metrics }
    private var board: Stripboard { document.board }

    private var effectiveZoom: CGFloat {
        document.view.effectiveZoom(viewport: viewport, metrics: metrics)
    }

    private var hiddenComponentID: UUID? {
        if case .move(let original, _, _) = active {
            return original.id
        }
        return nil
    }

    private var transform: BoardViewTransform {
        BoardViewTransform(
            viewportSize: viewport,
            metrics: metrics,
            view: document.view,
            fallbackZoom: effectiveZoom
        )
    }

    var body: some View {
        Canvas(rendersAsynchronously: false) { context, _ in
            let renderer = BoardRenderer(
                board: document.board,
                connectivity: document.connectivity,
                view: document.view,
                viewport: viewport,
                selectedComponentID: selectedComponentID,
                hiddenComponentID: hiddenComponentID,
                hoveredHole: hoveredHole,
                tool: tool,
                preview: preview,
                fallbackZoom: effectiveZoom
            )
            renderer.draw(in: &context)
        }
        .contentShape(Rectangle())
        .gesture(dragGesture)
        .simultaneousGesture(magnifyGesture)
        .onContinuousHover { phase in
            switch phase {
            case .active(let location):
                let hole = transform.hole(at: location, tolerance: 0.55)
                if hole != hoveredHole {
                    hoveredHole = hole
                }
            case .ended:
                if hoveredHole != nil {
                    hoveredHole = nil
                }
            }
        }
        #if os(macOS)
        .background {
            ScrollWheelPanInstaller { delta in
                _ = document.panView(by: delta)
            }
        }
        #endif
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("board.canvas")
        .accessibilityLabel("Stripboard")
        .accessibilityValue(accessibilityValue)
        .accessibilityHint(tool.help)
    }

    private var accessibilityValue: String {
        let nets = document.connectivity.netCount
        return [
            board.template.accessibilityName,
            document.view.orientation.displayName,
            document.view.side.accessibilityDescription,
            "\(nets) nets",
            "\(board.cutHoles.count) cuts",
            "\(board.solderedHoles.count) soldered",
            "\(board.components.count) components",
        ].joined(separator: ", ")
    }

    // MARK: - Gesture state

    private enum ActiveGesture {
        case pan(startLocation: CGPoint, lastLocation: CGPoint)
        case paint(tool: EditorTool, holes: Set<GridPoint>, lastPoint: CGPoint)
        case jumper(JumperDraft)
        case move(original: PlacedComponent, startPoint: CGPoint, candidate: PlacedComponent?)
        case place(spec: ComponentSpec, anchor: GridPoint, candidate: PlacedComponent?)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                if isMagnifying {
                    suppressDragUntilEnded = true
                    return
                }
                guard !suppressDragUntilEnded else { return }
                dragHasBegun = true
                if active == nil {
                    beginGesture(at: value.startLocation)
                }
                guard active != nil else { return }
                updateGesture(at: value.location)
            }
            .onEnded { value in
                defer { dragHasBegun = false }
                if suppressDragUntilEnded {
                    suppressDragUntilEnded = false
                    cancelActiveGesture()
                    return
                }
                if isMagnifying {
                    suppressDragUntilEnded = true
                    return
                }
                // A drag ending immediately after a pinch is the tail of that
                // gesture, not a deliberate tap.
                if active == nil, Date().timeIntervalSince(lastMagnifyEnd) < 0.3 {
                    return
                }
                if active == nil {
                    beginGesture(at: value.startLocation)
                }
                guard active != nil else { return }
                updateGesture(at: value.location)
                commitGesture()
            }
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture(minimumScaleDelta: 0.01)
            .onChanged { value in
                if magnifyBaselineZoom == nil {
                    if active != nil || dragHasBegun {
                        suppressDragUntilEnded = true
                    }
                    isMagnifying = true
                    cancelActiveGesture()
                    dragHasBegun = false
                    magnifyBaselineZoom = effectiveZoom
                }
                guard let baseline = magnifyBaselineZoom else { return }
                _ = document.zoomView(
                    to: baseline * value.magnification,
                    around: value.startLocation,
                    viewport: viewport,
                    fallbackZoom: baseline
                )
            }
            .onEnded { _ in
                isMagnifying = false
                magnifyBaselineZoom = nil
                lastMagnifyEnd = Date()
            }
    }

    private func beginGesture(at location: CGPoint) {
        guard viewport.width > 1, viewport.height > 1 else { return }
        let transform = transform

        switch tool {
        case .select:
            if document.view.side == .top,
               let component = component(at: location, transform: transform) {
                selectedComponentID = component.id
                active = .move(original: component, startPoint: location, candidate: component)
                preview = .component(component, valid: true)
            } else {
                selectedComponentID = nil
                active = .pan(startLocation: location, lastLocation: location)
                preview = .none
            }

        case .pan:
            active = .pan(startLocation: location, lastLocation: location)
            preview = .none

        case .cut, .uncut, .solder, .unsolder:
            guard let hole = transform.hole(at: location, tolerance: 0.6) else { return }
            active = .paint(tool: tool, holes: [hole], lastPoint: location)
            preview = .paint(tool: tool, holes: [hole])

        case .jumper(let kind):
            guard document.view.side == .top,
                  let hole = transform.hole(at: location, tolerance: 0.6),
                  var draft = JumperDraft(kind: kind, start: hole, dimensions: board.dimensions)
            else { return }
            draft.move(to: hole)
            active = .jumper(draft)
            preview = .jumper(kind: kind, route: draft.path)

        case .place(let reference):
            guard document.view.side == .top,
                  let spec = ComponentCatalogue.spec(for: reference),
                  let hole = transform.hole(at: location, tolerance: 0.75)
            else { return }
            let candidate = PlacedComponent.autoPlaced(
                spec: spec,
                at: hole,
                dimensions: board.dimensions
            )
            active = .place(spec: spec, anchor: hole, candidate: candidate)
            preview = candidate.map { .component($0, valid: true) } ?? .none
        }
    }

    private func updateGesture(at location: CGPoint) {
        guard let active else { return }
        let transform = transform

        switch active {
        case .pan(let startLocation, let lastLocation):
            let delta = CGSize(
                width: location.x - lastLocation.x,
                height: location.y - lastLocation.y
            )
            _ = document.panView(by: delta)
            self.active = .pan(startLocation: startLocation, lastLocation: location)

        case .paint(let paintTool, var holes, let lastPoint):
            let newHoles = holesAlong(from: lastPoint, to: location, transform: transform)
            holes.formUnion(newHoles)
            self.active = .paint(tool: paintTool, holes: holes, lastPoint: location)
            preview = .paint(tool: paintTool, holes: holes)

        case .jumper(var draft):
            if let target = clampedHole(at: location, transform: transform) {
                draft.move(to: target)
            }
            self.active = .jumper(draft)
            preview = .jumper(kind: draft.kind, route: draft.path)

        case .move(let original, let startPoint, _):
            let candidate = movedCandidate(original: original, startPoint: startPoint, location: location, transform: transform)
            self.active = .move(original: original, startPoint: startPoint, candidate: candidate)
            if let candidate {
                preview = .component(candidate, valid: candidate.isValid(dimensions: board.dimensions))
            } else {
                preview = .none
            }

        case .place(let spec, let anchor, _):
            let candidate = placementCandidate(spec: spec, anchor: anchor, location: location, transform: transform)
            self.active = .place(spec: spec, anchor: anchor, candidate: candidate)
            if let candidate {
                preview = .component(candidate, valid: candidate.isValid(dimensions: board.dimensions))
            } else {
                preview = .none
            }
        }
    }

    private func commitGesture() {
        guard let active else {
            preview = .none
            return
        }
        self.active = nil
        defer { preview = .none }

        switch active {
        case .pan:
            break

        case .paint(let paintTool, let holes, _):
            let ordered = holes.sorted()
            for hole in ordered {
                switch paintTool {
                case .cut:
                    _ = document.setCut(hole, true)
                case .uncut:
                    _ = document.setCut(hole, false)
                case .solder:
                    _ = document.setSoldered(hole, true)
                case .unsolder:
                    _ = document.setSoldered(hole, false)
                default:
                    break
                }
            }

        case .jumper(let draft):
            guard let jumper = draft.makeJumper() else { return }
            _ = document.addJumper(kind: jumper.kind, route: jumper.route)

        case .move(_, _, let candidate):
            guard let candidate,
                  candidate.isValid(dimensions: board.dimensions),
                  board.component(id: candidate.id) != nil
            else { return }
            _ = document.updateComponent(candidate)

        case .place(let spec, let anchor, let candidate):
            if let candidate, candidate.isValid(dimensions: board.dimensions) {
                if let placed = document.placeComponent(candidate) {
                    selectedComponentID = placed.id
                    tool = .select
                }
            } else {
                // A click without a useful drag falls back to an automatic fit.
                if let placed = document.placeComponent(spec: spec, at: anchor) {
                    selectedComponentID = placed.id
                    tool = .select
                }
            }
        }
    }

    private func cancelActiveGesture() {
        active = nil
        preview = .none
    }

    // MARK: - Geometry helpers

    private func component(at location: CGPoint, transform: BoardViewTransform) -> PlacedComponent? {
        let boardPoint = transform.viewToBoard(location)
        return board.component(hitTest: boardPoint, metrics: metrics)
    }

    private func clampedHole(at location: CGPoint, transform: BoardViewTransform) -> GridPoint? {
        let boardPoint = transform.viewToBoard(location)
        guard boardPoint.x > -1, boardPoint.y > -1,
              boardPoint.x < metrics.boardSize.width + 1,
              boardPoint.y < metrics.boardSize.height + 1
        else { return nil }
        let column = Int(((boardPoint.x - metrics.margin)).rounded())
        let row = Int(((boardPoint.y - metrics.margin)).rounded())
        return GridPoint(
            column: min(max(column, 0), board.columns - 1),
            row: min(max(row, 0), board.rows - 1)
        )
    }

    private func holesAlong(
        from start: CGPoint,
        to end: CGPoint,
        transform: BoardViewTransform
    ) -> Set<GridPoint> {
        let distance = hypot(end.x - start.x, end.y - start.y)
        let step = max(2, transform.zoom * 0.3)
        let count = max(1, Int(ceil(distance / step)))
        var holes = Set<GridPoint>()
        for index in 0...count {
            let fraction = CGFloat(index) / CGFloat(count)
            let point = CGPoint(
                x: start.x + (end.x - start.x) * fraction,
                y: start.y + (end.y - start.y) * fraction
            )
            if let hole = transform.hole(at: point, tolerance: 0.75) {
                holes.insert(hole)
            }
        }
        return holes
    }

    private func movedCandidate(
        original: PlacedComponent,
        startPoint: CGPoint,
        location: CGPoint,
        transform: BoardViewTransform
    ) -> PlacedComponent? {
        let startBoard = transform.viewToBoard(startPoint)
        let currentBoard = transform.viewToBoard(location)
        let columnDelta = Int((currentBoard.x - startBoard.x).rounded())
        let rowDelta = Int((currentBoard.y - startBoard.y).rounded())
        guard columnDelta != 0 || rowDelta != 0 else { return original }
        var candidate = original
        candidate.anchor = original.anchor.offset(columns: columnDelta, rows: rowDelta)
        return candidate
    }

    private func placementCandidate(
        spec: ComponentSpec,
        anchor: GridPoint,
        location: CGPoint,
        transform: BoardViewTransform
    ) -> PlacedComponent? {
        guard let target = clampedHole(at: location, transform: transform) else { return nil }
        let columnDelta = target.column - anchor.column
        let rowDelta = target.row - anchor.row
        guard columnDelta != 0 || rowDelta != 0 else {
            return PlacedComponent.autoPlaced(spec: spec, at: anchor, dimensions: board.dimensions)
        }

        var candidate = PlacedComponent(
            reference: spec.reference,
            anchor: anchor,
            axis: .horizontal,
            span: ComponentPlacement.defaultSpan(for: spec)
        )

        if spec.layout == .twoLead {
            if abs(columnDelta) >= abs(rowDelta) {
                candidate.axis = .horizontal
                candidate.span = ComponentPlacement.clamp(span: abs(columnDelta), for: spec)
                if columnDelta < 0 {
                    candidate.anchor = anchor.offset(columns: columnDelta)
                }
            } else {
                candidate.axis = .vertical
                candidate.span = ComponentPlacement.clamp(span: abs(rowDelta), for: spec)
                if rowDelta < 0 {
                    candidate.anchor = anchor.offset(rows: rowDelta)
                }
            }
        } else {
            candidate.axis = abs(columnDelta) >= abs(rowDelta) ? .horizontal : .vertical
            candidate.span = 1
        }
        return candidate
    }

}
