import Foundation

/// A reversible change to the board.
///
/// These are the entries stored in the document's edit history. View changes
/// (pan, zoom, rotation, flipping) are deliberately not represented here.
enum BoardEdit: Equatable, Codable, Sendable {
    case setCut(hole: GridPoint, isCut: Bool)
    case setSoldered(hole: GridPoint, isSoldered: Bool)
    case addJumper(Jumper)
    case removeJumper(Jumper, index: Int)
    case addComponent(PlacedComponent)
    case removeComponent(PlacedComponent, index: Int)
    case updateComponent(before: PlacedComponent, after: PlacedComponent)
}

extension Stripboard {
    /// Applies an edit. Returns false when the target state was already present.
    @discardableResult
    mutating func apply(_ edit: BoardEdit) -> Bool {
        switch edit {
        case .setCut(let hole, let isCut):
            return setCut(hole, isCut)
        case .setSoldered(let hole, let isSoldered):
            return setSoldered(hole, isSoldered)
        case .addJumper(let jumper):
            return addJumper(jumper)
        case .removeJumper(let jumper, _):
            return removeJumper(id: jumper.id) != nil
        case .addComponent(let component):
            return addComponent(component)
        case .removeComponent(let component, _):
            return removeComponent(id: component.id) != nil
        case .updateComponent(_, let after):
            return replaceComponent(after) != nil
        }
    }

    /// Reverses an edit while preserving component and jumper ordering.
    @discardableResult
    mutating func revert(_ edit: BoardEdit) -> Bool {
        switch edit {
        case .setCut(let hole, let isCut):
            return setCut(hole, !isCut)
        case .setSoldered(let hole, let isSoldered):
            return setSoldered(hole, !isSoldered)
        case .addJumper(let jumper):
            return removeJumper(id: jumper.id) != nil
        case .removeJumper(let jumper, let index):
            return insertJumper(jumper, at: index)
        case .addComponent(let component):
            return removeComponent(id: component.id) != nil
        case .removeComponent(let component, let index):
            return insertComponent(component, at: index)
        case .updateComponent(let before, _):
            return replaceComponent(before) != nil
        }
    }
}

extension BoardEdit {
    /// A short, human-readable label used by history, menus, and tests.
    var label: String {
        switch self {
        case .setCut(let hole, let isCut):
            return "\(isCut ? "Cut" : "Uncut") \(HoleNames.label(for: hole))"
        case .setSoldered(let hole, let isSoldered):
            return "\(isSoldered ? "Solder" : "Unsolder") \(HoleNames.label(for: hole))"
        case .addJumper(let jumper):
            return "Add \(jumper.kind.displayName) \(jumper.endpointDescription)"
        case .removeJumper(let jumper, _):
            return "Remove \(jumper.kind.displayName) \(jumper.endpointDescription)"
        case .addComponent(let component):
            return "Place \(component.displayName)"
        case .removeComponent(let component, _):
            return "Remove \(component.displayName)"
        case .updateComponent(let before, let after):
            if before.anchor != after.anchor {
                return "Move \(after.displayName)"
            }
            return "Adjust \(after.displayName)"
        }
    }

    var kindDescription: String {
        switch self {
        case .setCut: "cut"
        case .setSoldered: "solder"
        case .addJumper, .removeJumper: "jumper"
        case .addComponent, .removeComponent, .updateComponent: "component"
        }
    }
}
