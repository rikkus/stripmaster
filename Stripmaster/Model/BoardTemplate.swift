import Foundation

/// The four stripboard sizes the app ships with.
///
/// The first dimension is the number of holes along a copper strip. It is always
/// the longer dimension for these templates, so a strip runs across the board's
/// long edge. Boards are shown in landscape orientation by default.
enum BoardTemplate: String, CaseIterable, Codable, Identifiable, Sendable {
    case sixteenByEight = "16x8"
    case twentyFourByTwelve = "24x12"
    case thirtyTwoBySixteen = "32x16"
    case fortyEightByTwentyFour = "48x24"

    static let `default` = BoardTemplate.twentyFourByTwelve

    var id: String { rawValue }

    /// Holes along each copper strip (the long edge).
    var columns: Int {
        switch self {
        case .sixteenByEight: 16
        case .twentyFourByTwelve: 24
        case .thirtyTwoBySixteen: 32
        case .fortyEightByTwentyFour: 48
        }
    }

    /// Number of copper strips.
    var rows: Int {
        switch self {
        case .sixteenByEight: 8
        case .twentyFourByTwelve: 12
        case .thirtyTwoBySixteen: 16
        case .fortyEightByTwentyFour: 24
        }
    }

    var holeCount: Int { columns * rows }

    var dimensions: BoardDimensions { BoardDimensions(template: self) }

    /// e.g. "24 × 12"
    var shortName: String { "\(columns) × \(rows)" }

    /// e.g. "24 × 12 holes"
    var displayName: String { "\(shortName) holes" }

    /// A compact accessibility and menu label.
    var accessibilityName: String { "\(columns) by \(rows) hole board" }

    /// Small dimensions are listed first, which is the order they appear in menus.
    static var ordered: [BoardTemplate] {
        allCases.sorted { lhs, rhs in
            if lhs.holeCount != rhs.holeCount { return lhs.holeCount < rhs.holeCount }
            return lhs.rawValue < rhs.rawValue
        }
    }
}
