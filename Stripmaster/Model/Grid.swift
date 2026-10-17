import Foundation

/// A hole position on a stripboard.
///
/// Columns run along the copper strips (the long edge of every supported board).
/// Rows are the strips themselves. The origin is the top-left hole in landscape
/// orientation. Positions are always stored in board space; view transforms mirror
/// and rotate them for display.
struct GridPoint: Hashable, Codable, Sendable, Comparable, CustomStringConvertible {
    var column: Int
    var row: Int

    init(column: Int, row: Int) {
        self.column = column
        self.row = row
    }

    static func < (lhs: GridPoint, rhs: GridPoint) -> Bool {
        if lhs.row != rhs.row { return lhs.row < rhs.row }
        return lhs.column < rhs.column
    }

    var description: String { "\(HoleNames.label(for: self))" }

    func offset(columns: Int = 0, rows: Int = 0) -> GridPoint {
        GridPoint(column: column + columns, row: row + rows)
    }

    func offset(along axis: GridAxis, by amount: Int) -> GridPoint {
        switch axis {
        case .horizontal: GridPoint(column: column + amount, row: row)
        case .vertical: GridPoint(column: column, row: row + amount)
        }
    }

    func isOrthogonallyAdjacent(to other: GridPoint) -> Bool {
        abs(column - other.column) + abs(row - other.row) == 1
    }

    var neighbours: [GridPoint] {
        [
            GridPoint(column: column - 1, row: row),
            GridPoint(column: column + 1, row: row),
            GridPoint(column: column, row: row - 1),
            GridPoint(column: column, row: row + 1),
        ]
    }
}

/// The two axes used for pin rows and pin headers.
enum GridAxis: String, Codable, CaseIterable, Sendable {
    case horizontal
    case vertical

    var perpendicular: GridAxis {
        switch self {
        case .horizontal: .vertical
        case .vertical: .horizontal
        }
    }

    var displayName: String {
        switch self {
        case .horizontal: "horizontal"
        case .vertical: "vertical"
        }
    }
}

/// The rectangular extent of holes on a board.
struct BoardDimensions: Equatable, Codable, Sendable {
    var columns: Int
    var rows: Int

    init(columns: Int, rows: Int) {
        precondition(columns > 0 && rows > 0, "A board needs at least one hole")
        self.columns = columns
        self.rows = rows
    }

    init(template: BoardTemplate) {
        self.init(columns: template.columns, rows: template.rows)
    }

    func contains(_ hole: GridPoint) -> Bool {
        hole.column >= 0 && hole.column < columns && hole.row >= 0 && hole.row < rows
    }

    var allHoles: [GridPoint] {
        var result: [GridPoint] = []
        result.reserveCapacity(columns * rows)
        for row in 0..<rows {
            for column in 0..<columns {
                result.append(GridPoint(column: column, row: row))
            }
        }
        return result
    }

    func clamped(_ hole: GridPoint) -> GridPoint {
        GridPoint(
            column: min(max(hole.column, 0), columns - 1),
            row: min(max(hole.row, 0), rows - 1)
        )
    }
}

/// Human-readable hole names used in history labels and accessibility text.
enum HoleNames {
    /// A, B, … Z, AA, AB, …
    static func columnLabel(_ index: Int) -> String {
        guard index >= 0 else { return "?" }
        var value = index
        var characters: [Character] = []
        repeat {
            let remainder = value % 26
            characters.append(Character(UnicodeScalar(UInt8(65 + remainder))))
            value = value / 26 - 1
        } while value >= 0
        return String(characters.reversed())
    }

    /// Rows are one-based, as they are printed on stripboard packaging.
    static func rowLabel(_ index: Int) -> String {
        String(index + 1)
    }

    static func label(for hole: GridPoint) -> String {
        columnLabel(hole.column) + rowLabel(hole.row)
    }
}
