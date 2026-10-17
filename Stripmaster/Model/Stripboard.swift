import CoreGraphics
import Foundation

/// The editable stripboard itself: holes, copper cuts, solder joints, jumpers,
/// and placed components.
///
/// The board does not know about undo, history, or the view. Those live in
/// `StripmasterDocumentState` so the model can be exercised without SwiftUI.
struct Stripboard: Equatable, Codable, Sendable {
    var template: BoardTemplate
    private(set) var cutHoles: Set<GridPoint>
    private(set) var solderedHoles: Set<GridPoint>
    private(set) var jumpers: [Jumper]
    private(set) var components: [PlacedComponent]

    init(template: BoardTemplate = .default) {
        self.template = template
        self.cutHoles = []
        self.solderedHoles = []
        self.jumpers = []
        self.components = []
    }

    /// Memberwise-style initialiser, primarily for loading and testing. The
    /// contents are not validated here; call `sanitized()` to filter invalid
    /// entries. Editing APIs keep the invariant themselves.
    init(
        template: BoardTemplate,
        cutHoles: Set<GridPoint> = [],
        solderedHoles: Set<GridPoint> = [],
        jumpers: [Jumper] = [],
        components: [PlacedComponent] = []
    ) {
        self.template = template
        self.cutHoles = cutHoles
        self.solderedHoles = solderedHoles
        self.jumpers = jumpers
        self.components = components
    }

    var dimensions: BoardDimensions { BoardDimensions(template: template) }
    var metrics: BoardMetrics { BoardMetrics(template: template) }
    var columns: Int { template.columns }
    var rows: Int { template.rows }
    var holeCount: Int { template.holeCount }

    var isPristine: Bool {
        cutHoles.isEmpty && solderedHoles.isEmpty && jumpers.isEmpty && components.isEmpty
    }

    func isCut(_ hole: GridPoint) -> Bool { cutHoles.contains(hole) }
    func isSoldered(_ hole: GridPoint) -> Bool { solderedHoles.contains(hole) }

    // MARK: - Holes

    @discardableResult
    mutating func setCut(_ hole: GridPoint, _ isCut: Bool) -> Bool {
        guard dimensions.contains(hole) else { return false }
        if isCut {
            return cutHoles.insert(hole).inserted
        }
        return cutHoles.remove(hole) != nil
    }

    @discardableResult
    mutating func setSoldered(_ hole: GridPoint, _ isSoldered: Bool) -> Bool {
        guard dimensions.contains(hole) else { return false }
        if isSoldered {
            return solderedHoles.insert(hole).inserted
        }
        return solderedHoles.remove(hole) != nil
    }

    // MARK: - Jumpers

    func jumper(id: UUID) -> Jumper? {
        jumpers.first { $0.id == id }
    }

    @discardableResult
    mutating func addJumper(_ jumper: Jumper) -> Bool {
        guard jumper.isValid(dimensions: dimensions) else { return false }
        guard jumpers.contains(where: { $0.id == jumper.id }) == false else { return false }
        jumpers.append(jumper)
        return true
    }

    @discardableResult
    mutating func removeJumper(id: UUID) -> (jumper: Jumper, index: Int)? {
        guard let index = jumpers.firstIndex(where: { $0.id == id }) else { return nil }
        let removed = jumpers.remove(at: index)
        return (removed, index)
    }

    @discardableResult
    mutating func insertJumper(_ jumper: Jumper, at index: Int) -> Bool {
        guard jumper.isValid(dimensions: dimensions) else { return false }
        guard jumpers.contains(where: { $0.id == jumper.id }) == false else { return false }
        let clamped = min(max(index, 0), jumpers.count)
        jumpers.insert(jumper, at: clamped)
        return true
    }

    // MARK: - Components

    func component(id: UUID) -> PlacedComponent? {
        components.first { $0.id == id }
    }

    func componentIndex(id: UUID) -> Int? {
        components.firstIndex { $0.id == id }
    }

    /// Components are added on top of older components, as in a parts bag.
    @discardableResult
    mutating func addComponent(_ component: PlacedComponent) -> Bool {
        guard components.contains(where: { $0.id == component.id }) == false else { return false }
        guard let normalised = component.normalised(dimensions: dimensions) else { return false }
        components.append(normalised)
        return true
    }

    @discardableResult
    mutating func removeComponent(id: UUID) -> (component: PlacedComponent, index: Int)? {
        guard let index = components.firstIndex(where: { $0.id == id }) else { return nil }
        let removed = components.remove(at: index)
        return (removed, index)
    }

    @discardableResult
    mutating func insertComponent(_ component: PlacedComponent, at index: Int) -> Bool {
        guard components.contains(where: { $0.id == component.id }) == false else { return false }
        guard let normalised = component.normalised(dimensions: dimensions) else { return false }
        let clamped = min(max(index, 0), components.count)
        components.insert(normalised, at: clamped)
        return true
    }

    /// Replaces a component with an updated placement, preserving its z-order.
    @discardableResult
    mutating func replaceComponent(_ updated: PlacedComponent) -> PlacedComponent? {
        guard let index = components.firstIndex(where: { $0.id == updated.id }) else { return nil }
        guard let normalised = updated.normalised(dimensions: dimensions) else { return nil }
        let old = components[index]
        guard old != normalised else { return nil }
        components[index] = normalised
        return old
    }

    // MARK: - Derived information

    /// Every hole that has a component pin in it, with duplicates removed.
    var pinHoles: Set<GridPoint> {
        var result = Set<GridPoint>()
        for component in components {
            for hole in component.pinHoles(dimensions: dimensions) {
                result.insert(hole)
            }
        }
        return result
    }

    /// The topmost component whose body or pins contain a board-space point.
    func component(hitTest point: CGPoint, metrics: BoardMetrics? = nil) -> PlacedComponent? {
        let metrics = metrics ?? self.metrics
        for component in components.reversed() {
            if let geometry = component.layoutGeometry(metrics: metrics),
               geometry.hitRect.contains(point) {
                return component
            }
        }
        return nil
    }

    /// Copper runs per row. A cut hole removes the copper around that hole and
    /// splits its strip. Returned as inclusive column ranges of uncut holes.
    func copperRuns() -> [CopperRun] {
        var runs: [CopperRun] = []
        for row in 0..<rows {
            var start: Int?
            for column in 0..<columns {
                let hole = GridPoint(column: column, row: row)
                if cutHoles.contains(hole) {
                    if let runStart = start {
                        runs.append(CopperRun(row: row, startColumn: runStart, endColumn: column - 1))
                        start = nil
                    }
                } else if start == nil {
                    start = column
                }
            }
            if let runStart = start {
                runs.append(CopperRun(row: row, startColumn: runStart, endColumn: columns - 1))
            }
        }
        return runs
    }

    struct CopperRun: Equatable, Codable, Sendable {
        var row: Int
        var startColumn: Int
        var endColumn: Int
    }

    // MARK: - Loading

    /// Filters anything that cannot be represented on the current template.
    /// This keeps a hand-edited or future-version file from crashing the editor.
    func sanitized() -> Stripboard {
        var copy = self
        copy.cutHoles = Set(cutHoles.filter(dimensions.contains))
        copy.solderedHoles = Set(solderedHoles.filter(dimensions.contains))

        var seenJumperIDs = Set<UUID>()
        copy.jumpers = jumpers.filter { jumper in
            jumper.isValid(dimensions: dimensions) && seenJumperIDs.insert(jumper.id).inserted
        }

        var seenComponentIDs = Set<UUID>()
        copy.components = components.compactMap { component in
            guard seenComponentIDs.insert(component.id).inserted else { return nil }
            return component.normalised(dimensions: dimensions)
        }
        return copy
    }
}
