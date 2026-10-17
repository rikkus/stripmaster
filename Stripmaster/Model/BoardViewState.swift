import CoreGraphics
import Foundation

/// Quarter-turn orientations of the board in the editor.
///
/// The natural orientation is landscape: strips run left to right. 180° and 270°
/// are included so repeated 90° rotations are lossless.
enum BoardOrientation: Int, Codable, CaseIterable, Sendable, CustomStringConvertible {
    case landscape = 0
    case portrait = 90
    case landscapeUpsideDown = 180
    case portraitUpsideDown = 270

    var degrees: CGFloat { CGFloat(rawValue) }

    var isQuarterTurn: Bool {
        self == .portrait || self == .portraitUpsideDown
    }

    var rotatedClockwise: BoardOrientation {
        switch self {
        case .landscape: .portrait
        case .portrait: .landscapeUpsideDown
        case .landscapeUpsideDown: .portraitUpsideDown
        case .portraitUpsideDown: .landscape
        }
    }

    var rotatedAnticlockwise: BoardOrientation {
        rotatedClockwise.rotatedClockwise.rotatedClockwise
    }

    var displayName: String {
        switch self {
        case .landscape: "Landscape"
        case .portrait: "Portrait"
        case .landscapeUpsideDown: "Landscape, upside down"
        case .portraitUpsideDown: "Portrait, upside down"
        }
    }

    var description: String { "\(rawValue)° \(displayName.lowercased())" }
}

/// Which face of the board is being looked at.
enum BoardSide: String, Codable, CaseIterable, Sendable {
    case top
    case bottom

    var flipped: BoardSide {
        switch self {
        case .top: .bottom
        case .bottom: .top
        }
    }

    var displayName: String {
        switch self {
        case .top: "Top"
        case .bottom: "Bottom"
        }
    }

    var description: String {
        switch self {
        case .top: "Top · components"
        case .bottom: "Bottom · copper tracks"
        }
    }

    var accessibilityDescription: String {
        switch self {
        case .top: "component side"
        case .bottom: "copper track side"
        }
    }
}

/// Everything about how the board is viewed, as opposed to how it is built.
///
/// It is stored in the document alongside the edit history, so reopening a board
/// restores the orientation, side, zoom and pan last used. View changes never
/// appear in the edit history.
struct BoardViewState: Codable, Equatable, Sendable {
    var orientation: BoardOrientation
    var side: BoardSide
    /// Points per hole. `nil` until the board has been fitted for the first time.
    var zoom: Double?
    var panX: Double
    var panY: Double
    var updatedAt: Date?

    init(
        orientation: BoardOrientation = .landscape,
        side: BoardSide = .top,
        zoom: Double? = nil,
        panX: Double = 0,
        panY: Double = 0,
        updatedAt: Date? = nil
    ) {
        self.orientation = orientation
        self.side = side
        self.zoom = zoom
        self.panX = panX
        self.panY = panY
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case orientation
        case side
        case zoom
        case panX
        case panY
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        orientation = try container.decodeIfPresent(BoardOrientation.self, forKey: .orientation) ?? .landscape
        side = try container.decodeIfPresent(BoardSide.self, forKey: .side) ?? .top
        zoom = try container.decodeIfPresent(Double.self, forKey: .zoom)
        panX = try container.decodeIfPresent(Double.self, forKey: .panX) ?? 0
        panY = try container.decodeIfPresent(Double.self, forKey: .panY) ?? 0
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
        self = sanitized()
    }

    var pan: CGSize {
        CGSize(width: panX, height: panY)
    }

    var zoomValue: CGFloat? {
        zoom.map { CGFloat($0) }
    }

    var needsInitialFit: Bool { zoom == nil }

    /// The user has looked at this board before, so its view should be restored.
    var hasSavedView: Bool { zoom != nil }

    func effectiveZoom(viewport: CGSize, metrics: BoardMetrics, padding: CGFloat = BoardZoom.fitPadding) -> CGFloat {
        if let zoomValue { return BoardZoom.clamp(zoomValue) }
        return metrics.fitZoom(viewport: viewport, orientation: orientation, padding: padding)
    }

    /// Repairs values that could arrive from an old or hand-edited document.
    func sanitized() -> BoardViewState {
        var copy = self
        if let zoom = copy.zoom {
            if zoom.isFinite, zoom > 0 {
                copy.zoom = Double(BoardZoom.clamp(CGFloat(zoom)))
            } else {
                copy.zoom = nil
            }
        }
        if !copy.panX.isFinite { copy.panX = 0 }
        if !copy.panY.isFinite { copy.panY = 0 }
        return copy
    }

    var summary: String {
        "\(orientation.displayName) · \(side.displayName)"
    }

    // MARK: - View mutations

    /// First-open behaviour: fit the board if no size has ever been stored.
    @discardableResult
    mutating func ensureInitialFit(
        viewport: CGSize,
        metrics: BoardMetrics,
        padding: CGFloat = BoardZoom.fitPadding,
        at date: Date = .now
    ) -> Bool {
        guard needsInitialFit, viewport.width > 1, viewport.height > 1 else { return false }
        fit(to: viewport, metrics: metrics, padding: padding, at: date)
        return true
    }

    mutating func fit(
        to viewport: CGSize,
        metrics: BoardMetrics,
        padding: CGFloat = BoardZoom.fitPadding,
        at date: Date = .now
    ) {
        guard viewport.width > 1, viewport.height > 1 else { return }
        zoom = Double(metrics.fitZoom(viewport: viewport, orientation: orientation, padding: padding))
        panX = 0
        panY = 0
        updatedAt = date
    }

    /// Rotate a quarter turn. When a viewport is supplied the board is refitted so
    /// the whole board remains visible after the rotation.
    mutating func rotateClockwise(
        viewport: CGSize?,
        metrics: BoardMetrics,
        padding: CGFloat = BoardZoom.fitPadding,
        at date: Date = .now
    ) {
        orientation = orientation.rotatedClockwise
        panX = 0
        panY = 0
        if let viewport, viewport.width > 1, viewport.height > 1 {
            zoom = Double(metrics.fitZoom(viewport: viewport, orientation: orientation, padding: padding))
        }
        updatedAt = date
    }

    mutating func flipSide(at date: Date = .now) {
        side = side.flipped
        updatedAt = date
    }

    mutating func pan(by delta: CGSize, at date: Date = .now) {
        guard delta.width.isFinite, delta.height.isFinite else { return }
        panX += Double(delta.width)
        panY += Double(delta.height)
        updatedAt = date
    }

    mutating func setPan(_ pan: CGSize, at date: Date = .now) {
        guard pan.width.isFinite, pan.height.isFinite else { return }
        panX = Double(pan.width)
        panY = Double(pan.height)
        updatedAt = date
    }

    /// Zooms around a point in view space, keeping the board content under that
    /// point stationary. Used by pinch and scroll-wheel zoom.
    @discardableResult
    mutating func zoom(
        to targetZoom: CGFloat,
        around anchor: CGPoint,
        viewport: CGSize,
        fallbackZoom: CGFloat,
        at date: Date = .now
    ) -> Bool {
        let oldZoom = zoomValue ?? fallbackZoom
        guard oldZoom > 0, targetZoom.isFinite else { return false }
        let newZoom = BoardZoom.clamp(targetZoom)
        let ratio = newZoom / oldZoom
        guard ratio.isFinite, ratio > 0 else { return false }

        let viewportCentre = CGPoint(x: viewport.width / 2, y: viewport.height / 2)
        let anchorOffset = CGPoint(x: anchor.x - viewportCentre.x, y: anchor.y - viewportCentre.y)
        let currentOffset = CGPoint(
            x: anchor.x - (viewportCentre.x + CGFloat(panX)),
            y: anchor.y - (viewportCentre.y + CGFloat(panY))
        )
        let newPan = CGPoint(
            x: anchorOffset.x - currentOffset.x * ratio,
            y: anchorOffset.y - currentOffset.y * ratio
        )

        let changed = newZoom != oldZoom || newPan.x != CGFloat(panX) || newPan.y != CGFloat(panY)
        guard changed else { return false }

        zoom = Double(newZoom)
        panX = Double(newPan.x)
        panY = Double(newPan.y)
        updatedAt = date
        return true
    }
}
