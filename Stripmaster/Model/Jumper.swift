import Foundation

/// The two jumper constructions the editor supports.
enum JumperKind: String, Codable, CaseIterable, Sendable {
    /// A bare tinned wire: conductive along its whole length, so it contacts
    /// every hole it passes over.
    case bare
    /// An insulated jumper: only the two ends are conductive. The sleeve passes
    /// over all the holes in between without touching their copper.
    case insulated

    var displayName: String {
        switch self {
        case .bare: "bare wire"
        case .insulated: "insulated jumper"
        }
    }

    var shortName: String {
        switch self {
        case .bare: "wire"
        case .insulated: "insulated"
        }
    }

    var isConductiveAlongLength: Bool { self == .bare }
}

/// A jumper drawn between holes. The route is an orthogonal polyline through
/// hole centres: every consecutive pair is one hole apart, horizontally or
/// vertically. No diagonal segments are representable.
struct Jumper: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var kind: JumperKind
    var route: [GridPoint]

    init(id: UUID = UUID(), kind: JumperKind, route: [GridPoint]) {
        self.id = id
        self.kind = kind
        self.route = route
    }

    var start: GridPoint? { route.first }
    var end: GridPoint? { route.last }
    var segmentCount: Int { max(0, route.count - 1) }

    var endpointDescription: String {
        guard let start, let end else { return "no route" }
        return "\(HoleNames.label(for: start)) → \(HoleNames.label(for: end))"
    }

    func validationError(dimensions: BoardDimensions) -> JumperValidationError? {
        guard route.count >= 2 else { return .tooShort }
        guard route.count <= JumperValidation.maximumHoles else { return .tooLong }
        for (index, hole) in route.enumerated() {
            guard dimensions.contains(hole) else { return .outOfBounds(hole) }
            if index > 0 {
                let previous = route[index - 1]
                if previous == hole { return .repeatedPoint(hole) }
                if !hole.isOrthogonallyAdjacent(to: previous) {
                    if abs(hole.column - previous.column) == 1 && abs(hole.row - previous.row) == 1 {
                        return .diagonalSegment(index)
                    }
                    return .nonAdjacentSegment(index)
                }
            }
        }
        var seen = Set<GridPoint>()
        for hole in route {
            guard seen.insert(hole).inserted else { return .repeatedPoint(hole) }
        }
        return nil
    }

    func isValid(dimensions: BoardDimensions) -> Bool {
        validationError(dimensions: dimensions) == nil
    }

    /// The conductive holes: a bare wire contacts its whole route, while an
    /// insulated jumper only contacts its two endpoints.
    var conductiveHoles: [GridPoint] {
        switch kind {
        case .bare: route
        case .insulated: [route.first, route.last].compactMap { $0 }
        }
    }
}

enum JumperValidationError: Error, Equatable, Sendable {
    case tooShort
    case tooLong
    case outOfBounds(GridPoint)
    case diagonalSegment(Int)
    case nonAdjacentSegment(Int)
    case repeatedPoint(GridPoint)

    var description: String {
        switch self {
        case .tooShort: "A jumper needs at least two holes."
        case .tooLong: "That jumper is too long."
        case .outOfBounds(let hole): "\(HoleNames.label(for: hole)) is not on the board."
        case .diagonalSegment: "Jumpers cannot move diagonally."
        case .nonAdjacentSegment: "Jumpers must move from hole to adjacent hole."
        case .repeatedPoint(let hole): "The jumper crosses itself at \(HoleNames.label(for: hole))."
        }
    }
}

enum JumperValidation {
    static let maximumHoles = 4_096
}

/// The live, orthogonal path built while the user drags a jumper.
///
/// The path is always valid: consecutive points are adjacent, there are no
/// repeated holes, and drags back over an earlier point truncate the route
/// (the same way one might retrace a wire while drawing it).
struct JumperDraft: Equatable, Sendable {
    let kind: JumperKind
    let dimensions: BoardDimensions
    private(set) var path: [GridPoint]
    private let maximumHoles: Int

    init?(
        kind: JumperKind,
        start: GridPoint,
        dimensions: BoardDimensions,
        maximumHoles: Int = JumperValidation.maximumHoles
    ) {
        guard dimensions.contains(start) else { return nil }
        self.kind = kind
        self.dimensions = dimensions
        self.path = [start]
        self.maximumHoles = max(2, maximumHoles)
    }

    var start: GridPoint { path[0] }
    var end: GridPoint { path[path.count - 1] }
    var canCommit: Bool { path.count >= 2 }
    var isEmpty: Bool { path.count < 2 }

    var jumper: Jumper? {
        makeJumper()
    }

    func makeJumper(id: UUID = UUID()) -> Jumper? {
        guard path.count >= 2 else { return nil }
        let jumper = Jumper(id: id, kind: kind, route: path)
        guard jumper.isValid(dimensions: dimensions) else { return nil }
        return jumper
    }

    /// Extends the draft to follow the pointer. Returns true when the path changed.
    @discardableResult
    mutating func move(to target: GridPoint) -> Bool {
        guard dimensions.contains(target) else { return false }
        guard let last = path.last else { return false }
        if target == last { return false }

        // Retracing back to an existing hole cuts the path back to that hole.
        if let existing = path.firstIndex(of: target) {
            path.removeSubrange((existing + 1)...)
            return true
        }

        let startCount = path.count
        let dx = target.column - last.column
        let dy = target.row - last.row

        if dx == 0 {
            appendVertical(dy: dy, target: target)
        } else if dy == 0 {
            appendHorizontal(dx: dx, target: target)
        } else {
            // A pointer jump across both axes gets a right-angled elbow. The
            // previous segment's direction is preferred when it still heads
            // towards the target, which keeps hand-drawn routes calm.
            let horizontalFirst: Bool
            if let preference = inferredDirection, preference.axis == .horizontal,
               dx != 0, (dx > 0) == preference.positive {
                horizontalFirst = true
            } else if let preference = inferredDirection, preference.axis == .vertical,
                      dy != 0, (dy > 0) == preference.positive {
                horizontalFirst = false
            } else {
                horizontalFirst = abs(dx) >= abs(dy)
            }

            if horizontalFirst {
                appendHorizontal(dx: dx, target: target)
                if let current = path.last, current != target {
                    appendVertical(dy: target.row - current.row, target: target)
                }
            } else {
                appendVertical(dy: dy, target: target)
                if let current = path.last, current != target {
                    appendHorizontal(dx: target.column - current.column, target: target)
                }
            }
        }

        return path.count != startCount
    }

    private var inferredDirection: (axis: GridAxis, positive: Bool)? {
        guard path.count >= 2 else { return nil }
        let a = path[path.count - 2]
        let b = path[path.count - 1]
        if a.row == b.row, a.column != b.column {
            return (.horizontal, b.column > a.column)
        }
        if a.column == b.column, a.row != b.row {
            return (.vertical, b.row > a.row)
        }
        return nil
    }

    private mutating func appendHorizontal(dx: Int, target: GridPoint) {
        guard dx != 0 else { return }
        let step = dx > 0 ? 1 : -1
        var remaining = abs(dx)
        while remaining > 0, let current = path.last, current != target {
            let next = current.offset(columns: step)
            guard append(next) else { return }
            remaining -= 1
        }
    }

    private mutating func appendVertical(dy: Int, target: GridPoint) {
        guard dy != 0 else { return }
        let step = dy > 0 ? 1 : -1
        var remaining = abs(dy)
        while remaining > 0, let current = path.last, current != target {
            let next = current.offset(rows: step)
            guard append(next) else { return }
            remaining -= 1
        }
    }

    /// Adds one hole. If it is already on the path, truncates back to it. Returns
    /// false only when the length cap is hit.
    private mutating func append(_ hole: GridPoint) -> Bool {
        guard dimensions.contains(hole) else { return false }
        guard let current = path.last, hole.isOrthogonallyAdjacent(to: current) else { return false }
        if let existing = path.firstIndex(of: hole) {
            if existing < path.count - 1 {
                path.removeSubrange((existing + 1)...)
            }
            return true
        }
        guard path.count < maximumHoles else { return false }
        path.append(hole)
        return true
    }
}
