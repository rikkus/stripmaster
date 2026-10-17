import Foundation

// Shared fixtures. These are immutable, so they are safe at file scope under
// Swift 6 concurrency checking.

let fixtureDate = Date(timeIntervalSinceReferenceDate: 1_000_000)
let fixtureLater = fixtureDate.addingTimeInterval(60)

func hole(_ column: Int, _ row: Int) -> GridPoint {
    GridPoint(column: column, row: row)
}

func freshState(template: BoardTemplate = .sixteenByEight) -> StripmasterDocumentState {
    StripmasterDocumentState(template: template, now: fixtureDate)
}

func resistorSpec() -> ComponentSpec {
    ComponentCatalogue.spec(categoryID: "resistor", memberID: "standard")!
}

func capacitorSpec() -> ComponentSpec {
    ComponentCatalogue.spec(categoryID: "capacitor", memberID: "electrolytic")!
}

func jumperRoute(_ holes: GridPoint...) -> [GridPoint] {
    holes
}

func straightRoute(from start: GridPoint, to end: GridPoint) -> [GridPoint] {
    guard start.row == end.row || start.column == end.column else { return [] }
    var path: [GridPoint] = [start]
    var current = start
    while current != end {
        if current.column != end.column {
            current = current.offset(columns: current.column < end.column ? 1 : -1)
        } else {
            current = current.offset(rows: current.row < end.row ? 1 : -1)
        }
        path.append(current)
    }
    return path
}
