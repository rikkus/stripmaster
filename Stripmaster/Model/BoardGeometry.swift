import CoreGraphics
import Foundation

/// Physical and drawing dimensions of a stripboard, expressed in hole-pitch units.
///
/// One unit is the distance from the centre of one hole to the centre of the next.
/// Drawing code applies a zoom to turn these units into points.
struct BoardMetrics: Equatable, Sendable {
    var columns: Int
    var rows: Int

    /// Board material surrounding the outermost hole centres.
    var margin: CGFloat = 0.9

    var holeRadius: CGFloat = 0.13
    var padRadius: CGFloat = 0.30
    var pinRadius: CGFloat = 0.11
    var solderRadius: CGFloat = 0.24
    var cutRadius: CGFloat = 0.34
    var stripHalfWidth: CGFloat = 0.245

    init(columns: Int, rows: Int) {
        self.columns = columns
        self.rows = rows
    }

    init(template: BoardTemplate) {
        self.init(columns: template.columns, rows: template.rows)
    }

    init(dimensions: BoardDimensions) {
        self.init(columns: dimensions.columns, rows: dimensions.rows)
    }

    var dimensions: BoardDimensions { BoardDimensions(columns: columns, rows: rows) }

    var boardSize: CGSize {
        CGSize(
            width: CGFloat(columns - 1) + 2 * margin,
            height: CGFloat(rows - 1) + 2 * margin
        )
    }

    var boardCenter: CGPoint {
        CGPoint(x: boardSize.width / 2, y: boardSize.height / 2)
    }

    func holeCenter(_ hole: GridPoint) -> CGPoint {
        CGPoint(x: margin + CGFloat(hole.column), y: margin + CGFloat(hole.row))
    }

    func nearestHole(to point: CGPoint, tolerance: CGFloat = 0.48) -> GridPoint? {
        let candidate = GridPoint(
            column: Int((point.x - margin).rounded()),
            row: Int((point.y - margin).rounded())
        )
        guard dimensions.contains(candidate) else { return nil }
        let centre = holeCenter(candidate)
        let dx = centre.x - point.x
        let dy = centre.y - point.y
        guard (dx * dx + dy * dy).squareRoot() <= tolerance else { return nil }
        return candidate
    }

    /// The screen-space size of the board at `zoom`, after orientation.
    func displayedSize(for orientation: BoardOrientation, zoom: CGFloat) -> CGSize {
        let size = orientation.isQuarterTurn
            ? CGSize(width: boardSize.height, height: boardSize.width)
            : boardSize
        return CGSize(width: size.width * zoom, height: size.height * zoom)
    }

    /// A zoom that fits the board inside `viewport` with `padding` points on every side.
    func fitZoom(viewport: CGSize, orientation: BoardOrientation, padding: CGFloat) -> CGFloat {
        let displayed = orientation.isQuarterTurn
            ? CGSize(width: boardSize.height, height: boardSize.width)
            : boardSize
        let availableWidth = max(viewport.width - padding * 2, 16)
        let availableHeight = max(viewport.height - padding * 2, 16)
        let horizontal = availableWidth / displayed.width
        let vertical = availableHeight / displayed.height
        return BoardZoom.clamp(min(horizontal, vertical))
    }
}

/// Zoom limits shared by fitting and gestures.
enum BoardZoom {
    static let minimum: CGFloat = 0.4
    static let maximum: CGFloat = 400
    static let fitPadding: CGFloat = 34

    static func clamp(_ value: CGFloat) -> CGFloat {
        guard value.isFinite else { return 24 }
        return min(max(value, minimum), maximum)
    }
}

/// Maps board-space points into the board editor's local view space.
struct BoardViewTransform: Equatable, Sendable {
    var viewportSize: CGSize
    var metrics: BoardMetrics
    var orientation: BoardOrientation
    var side: BoardSide
    var zoom: CGFloat
    var pan: CGSize

    init(
        viewportSize: CGSize,
        metrics: BoardMetrics,
        orientation: BoardOrientation,
        side: BoardSide,
        zoom: CGFloat,
        pan: CGSize
    ) {
        self.viewportSize = viewportSize
        self.metrics = metrics
        self.orientation = orientation
        self.side = side
        self.zoom = BoardZoom.clamp(zoom)
        self.pan = pan
    }

    init(viewportSize: CGSize, metrics: BoardMetrics, view: BoardViewState, fallbackZoom: CGFloat) {
        self.init(
            viewportSize: viewportSize,
            metrics: metrics,
            orientation: view.orientation,
            side: view.side,
            zoom: view.zoom.map { CGFloat($0) } ?? fallbackZoom,
            pan: view.pan
        )
    }

    /// The centre of the board in view space. Pan moves this away from the viewport centre.
    var center: CGPoint {
        CGPoint(
            x: viewportSize.width / 2 + pan.width,
            y: viewportSize.height / 2 + pan.height
        )
    }

    var displayedSize: CGSize {
        metrics.displayedSize(for: orientation, zoom: zoom)
    }

    /// The board's on-screen rectangle, before corner rounding.
    var boardRect: CGRect {
        let size = displayedSize
        let origin = CGPoint(
            x: center.x - size.width / 2,
            y: center.y - size.height / 2
        )
        return CGRect(origin: origin, size: size)
    }

    func boardToView(_ point: CGPoint) -> CGPoint {
        var x = point.x - metrics.boardCenter.x
        var y = point.y - metrics.boardCenter.y
        if side == .bottom { x = -x }
        switch orientation {
        case .landscape:
            break
        case .portrait:
            (x, y) = (-y, x)
        case .landscapeUpsideDown:
            (x, y) = (-x, -y)
        case .portraitUpsideDown:
            (x, y) = (y, -x)
        }
        x *= zoom
        y *= zoom
        return CGPoint(x: center.x + x, y: center.y + y)
    }

    func viewToBoard(_ point: CGPoint) -> CGPoint {
        var x = (point.x - center.x) / zoom
        var y = (point.y - center.y) / zoom
        switch orientation {
        case .landscape:
            break
        case .portrait:
            (x, y) = (y, -x)
        case .landscapeUpsideDown:
            (x, y) = (-x, -y)
        case .portraitUpsideDown:
            (x, y) = (-y, x)
        }
        if side == .bottom { x = -x }
        return CGPoint(x: metrics.boardCenter.x + x, y: metrics.boardCenter.y + y)
    }

    func viewPoint(for hole: GridPoint) -> CGPoint {
        boardToView(metrics.holeCenter(hole))
    }

    func hole(at point: CGPoint, tolerance: CGFloat = 0.48) -> GridPoint? {
        guard boardRect.insetBy(dx: -zoom, dy: -zoom).contains(point) else { return nil }
        return metrics.nearestHole(to: viewToBoard(point), tolerance: tolerance)
    }

    /// A path for the board outline in board space.
    var boardPathInBoardSpace: CGPath {
        let rect = CGRect(origin: .zero, size: metrics.boardSize)
        return CGPath(
            roundedRect: rect,
            cornerWidth: 0.55,
            cornerHeight: 0.55,
            transform: nil
        )
    }
}

/// Applies the viewport transform to a GraphicsContext in view-layer code.
/// Kept here as an explanation of the transform order; the renderer uses the
/// same order when it calls GraphicsContext.
enum BoardViewTransformOrder {
    static let description = """
    translate(viewport centre + pan) · rotate(orientation) · scale(zoom) \
    · mirror(x, when viewing the back) · translate(-board centre)
    """
}
