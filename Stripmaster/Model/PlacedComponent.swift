import CoreGraphics
import Foundation

/// A component placed on the board. The board stores hole positions; the
/// catalogue supplies the physical package details.
struct PlacedComponent: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var reference: ComponentReference
    var anchor: GridPoint
    /// The direction in which the pins run for two-lead and inline packages.
    var axis: GridAxis
    /// Pin-to-pin distance for two-lead parts. Ignored for inline/DIP layouts.
    var span: Int
    /// Reverses the displayed pin order / polarity marker without moving the holes.
    var flipped: Bool

    init(
        id: UUID = UUID(),
        reference: ComponentReference,
        anchor: GridPoint,
        axis: GridAxis = .horizontal,
        span: Int = 1,
        flipped: Bool = false
    ) {
        self.id = id
        self.reference = reference
        self.anchor = anchor
        self.axis = axis
        self.span = span
        self.flipped = flipped
    }

    var spec: ComponentSpec? {
        ComponentCatalogue.spec(for: reference)
    }

    var displayName: String {
        spec?.plainFullName ?? reference.memberID
    }
}

/// A pin of a placed component, addressed by its hole and ordinal.
struct PlacedPin: Equatable, Sendable {
    var index: Int
    var hole: GridPoint
}

extension PlacedComponent {
    /// All pin holes in physical order. For DIP packages the first row is
    /// returned first, followed by the opposite row.
    func pinHoles(dimensions: BoardDimensions) -> [GridPoint] {
        guard let spec else { return [] }
        switch spec.layout {
        case .twoLead:
            let effectiveSpan = spec.stretch?.clamp(span) ?? max(1, span)
            return [
                anchor,
                anchor.offset(along: axis, by: effectiveSpan),
            ]
        case .inline:
            return (0..<max(1, spec.legs)).map {
                anchor.offset(along: axis, by: $0)
            }
        case .dualInline:
            let perSide = max(1, spec.legs / 2)
            let opposite = axis.perpendicular
            let firstRow = (0..<perSide).map {
                anchor.offset(along: axis, by: $0)
            }
            let secondRow = (0..<perSide).map {
                anchor
                    .offset(along: axis, by: $0)
                    .offset(along: opposite, by: 3)
            }
            return firstRow + secondRow
        }
    }

    func pins(dimensions: BoardDimensions) -> [PlacedPin] {
        pinHoles(dimensions: dimensions).enumerated().map {
            PlacedPin(index: $0.offset, hole: $0.element)
        }
    }

    /// True when every pin is a real hole and the stored span is within the
    /// catalogue's allowed stretch.
    func isValid(dimensions: BoardDimensions) -> Bool {
        guard let spec else { return false }
        let holes = pinHoles(dimensions: dimensions)
        guard holes.count == spec.legs, holes.allSatisfy(dimensions.contains) else { return false }
        if spec.layout == .twoLead, let stretch = spec.stretch {
            return (stretch.min...stretch.max).contains(span)
        }
        return true
    }

    /// A normalised copy: span clamped to the catalogue stretch and all pins in bounds.
    func normalised(dimensions: BoardDimensions) -> PlacedComponent? {
        guard let spec else { return nil }
        var copy = self
        if let stretch = spec.stretch {
            copy.span = stretch.clamp(span)
        } else {
            copy.span = 1
        }
        return copy.isValid(dimensions: dimensions) ? copy : nil
    }

    /// Move the anchor, keeping the rest of the placement.
    func moved(to newAnchor: GridPoint, dimensions: BoardDimensions) -> PlacedComponent? {
        var copy = self
        copy.anchor = newAnchor
        return copy.normalised(dimensions: dimensions)
    }

    /// Rotate the pin row by 90° around the anchor.
    func rotated(dimensions: BoardDimensions) -> PlacedComponent? {
        var copy = self
        copy.axis = axis == .horizontal ? .vertical : .horizontal
        return copy.normalised(dimensions: dimensions)
    }

    /// Try to find a legal placement for a part clicked at `hole`, preferring
    /// horizontal, then vertical orientation.
    static func autoPlaced(
        spec: ComponentSpec,
        at hole: GridPoint,
        dimensions: BoardDimensions,
        id: UUID = UUID()
    ) -> PlacedComponent? {
        let candidateSpans = ComponentPlacement.suggestedSpans(for: spec)
        for axis in GridAxis.allCases {
            for span in candidateSpans {
                let candidate = PlacedComponent(
                    id: id,
                    reference: spec.reference,
                    anchor: hole,
                    axis: axis,
                    span: span,
                    flipped: false
                )
                if candidate.isValid(dimensions: dimensions) {
                    return candidate
                }
            }
        }
        return nil
    }

    /// Shape used for drawing and hit testing, in board hole-pitch units.
    func layoutGeometry(metrics: BoardMetrics) -> ComponentLayoutGeometry? {
        guard let spec else { return nil }
        return ComponentLayoutGeometry(component: self, spec: spec, metrics: metrics)
    }
}

enum ComponentPlacement {
    /// Default span for a click placement.
    static func defaultSpan(for spec: ComponentSpec) -> Int {
        spec.stretch?.defaultSpan ?? 1
    }

    /// Spans to try, shortest first around the default, ending at the limits.
    static func suggestedSpans(for spec: ComponentSpec) -> [Int] {
        guard let stretch = spec.stretch else { return [1] }
        let preferred = stretch.defaultSpan
        let clampedPreferred = stretch.clamp(preferred)
        let values = [clampedPreferred]
            + stride(from: clampedPreferred - 1, through: stretch.min, by: -1)
            + stride(from: clampedPreferred + 1, through: stretch.max, by: 1)
        var seen = Set<Int>()
        return values.filter { seen.insert($0).inserted }
    }

    static func clamp(span: Int, for spec: ComponentSpec) -> Int {
        spec.stretch?.clamp(span) ?? 1
    }
}

/// Geometry for a placed component's pins, body, and hit area.
///
/// All coordinates are in board units (one unit between adjacent holes), not
/// screen points. The view transform converts them.
struct ComponentLayoutGeometry: Equatable, Sendable {
    var pinHoles: [GridPoint]
    /// The body rectangle in board-space units.
    var bodyRect: CGRect
    /// An expanded rect suitable for selection and body drags.
    var hitRect: CGRect
    var packageWidth: CGFloat
    var packageLength: CGFloat

    init(component: PlacedComponent, spec: ComponentSpec, metrics: BoardMetrics) {
        let holes = component.pinHoles(dimensions: metrics.dimensions)
        pinHoles = holes
        let points = holes.map(metrics.holeCenter)

        guard let first = points.first else {
            bodyRect = .zero
            hitRect = .zero
            packageWidth = 0.5
            packageLength = 0.5
            return
        }

        let minX = points.map(\.x).min() ?? first.x
        let maxX = points.map(\.x).max() ?? first.x
        let minY = points.map(\.y).min() ?? first.y
        let maxY = points.map(\.y).max() ?? first.y
        var length = max(maxX - minX, maxY - minY)

        switch spec.layout {
        case .twoLead:
            length = max(length, 0.8)
            let width: CGFloat = 0.52
            packageWidth = width
            packageLength = length
            let midpoint = CGPoint(x: (minX + maxX) / 2, y: (minY + maxY) / 2)
            if component.axis == .horizontal {
                let bodyLength = max(length - 0.5, 0.3)
                bodyRect = CGRect(
                    x: midpoint.x - bodyLength / 2,
                    y: midpoint.y - width / 2,
                    width: bodyLength,
                    height: width
                )
            } else {
                let bodyLength = max(length - 0.5, 0.3)
                bodyRect = CGRect(
                    x: midpoint.x - width / 2,
                    y: midpoint.y - bodyLength / 2,
                    width: width,
                    height: bodyLength
                )
            }
        case .inline:
            let width: CGFloat = 0.78
            packageWidth = width
            packageLength = max(length, 0.9)
            if component.axis == .horizontal {
                bodyRect = CGRect(
                    x: minX - 0.12,
                    y: minY - width / 2 - 0.18,
                    width: length + 0.24,
                    height: width
                )
            } else {
                bodyRect = CGRect(
                    x: minX - width / 2 - 0.18,
                    y: minY - 0.12,
                    width: width,
                    height: length + 0.24
                )
            }
        case .dualInline:
            let width: CGFloat = 2.3
            packageWidth = width
            packageLength = max(length, 1.2)
            if component.axis == .horizontal {
                // Pins sit on two rows three holes apart. The epoxy body fills the
                // gap between them, with a little clearance for the leads.
                bodyRect = CGRect(
                    x: minX - 0.55,
                    y: minY + 0.35,
                    width: length + 1.1,
                    height: max(maxY - minY - 0.7, 0.8)
                )
            } else {
                bodyRect = CGRect(
                    x: minX + 0.35,
                    y: minY - 0.55,
                    width: max(maxX - minX - 0.7, 0.8),
                    height: length + 1.1
                )
            }
        }

        let pinBounds = CGRect(
            x: points.map(\.x).min() ?? minX,
            y: points.map(\.y).min() ?? minY,
            width: max((points.map(\.x).max() ?? maxX) - minX, 0.01),
            height: max((points.map(\.y).max() ?? maxY) - minY, 0.01)
        )
        hitRect = bodyRect.union(pinBounds).insetBy(dx: -0.28, dy: -0.28)
    }

    func contains(pinHolePoint point: CGPoint) -> Bool {
        hitRect.contains(point)
    }
}
