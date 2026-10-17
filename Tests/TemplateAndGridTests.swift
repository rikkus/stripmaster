import Foundation

@MainActor
func runTemplateTests(_ t: TestLog) {
    t.equal(BoardTemplate.allCases.count, 4)
    t.equal(
        BoardTemplate.ordered.map(\.rawValue),
        ["16x8", "24x12", "32x16", "48x24"]
    )
    t.equal(BoardTemplate.default, .twentyFourByTwelve)

    let expected: [(BoardTemplate, Int, Int)] = [
        (.sixteenByEight, 16, 8),
        (.twentyFourByTwelve, 24, 12),
        (.thirtyTwoBySixteen, 32, 16),
        (.fortyEightByTwentyFour, 48, 24),
    ]
    for (template, columns, rows) in expected {
        t.equal(template.columns, columns, "\(template.rawValue) columns")
        t.equal(template.rows, rows, "\(template.rawValue) rows")
        t.equal(template.holeCount, columns * rows)
        t.expect(template.columns > template.rows, "the longer dimension must be the strip direction")
        t.equal(template.shortName, "\(columns) × \(rows)")
        t.equal(template.displayName, "\(columns) × \(rows) holes")
        t.equal(template.dimensions, BoardDimensions(columns: columns, rows: rows))
    }
}

@MainActor
func runGridTests(_ t: TestLog) {
    t.equal(HoleNames.columnLabel(0), "A")
    t.equal(HoleNames.columnLabel(1), "B")
    t.equal(HoleNames.columnLabel(25), "Z")
    t.equal(HoleNames.columnLabel(26), "AA")
    t.equal(HoleNames.columnLabel(27), "AB")
    t.equal(HoleNames.columnLabel(51), "AZ")
    t.equal(HoleNames.columnLabel(52), "BA")
    t.equal(HoleNames.columnLabel(701), "ZZ")
    t.equal(HoleNames.rowLabel(0), "1")
    t.equal(HoleNames.label(for: hole(2, 3)), "C4")

    let point = hole(3, 4)
    t.expect(point.isOrthogonallyAdjacent(to: hole(4, 4)))
    t.expect(point.isOrthogonallyAdjacent(to: hole(3, 5)))
    t.expect(!point.isOrthogonallyAdjacent(to: hole(4, 5)))
    t.expect(!point.isOrthogonallyAdjacent(to: point))
    t.equal(point.neighbours.count, 4)
    t.equal(point.offset(along: .horizontal, by: 2), hole(5, 4))
    t.equal(point.offset(along: .vertical, by: -2), hole(3, 2))

    let dimensions = BoardDimensions(columns: 16, rows: 8)
    t.expect(dimensions.contains(hole(0, 0)))
    t.expect(dimensions.contains(hole(15, 7)))
    t.expect(!dimensions.contains(hole(16, 7)))
    t.expect(!dimensions.contains(hole(-1, 0)))
    t.equal(dimensions.allHoles.count, 128)
    t.equal(dimensions.clamped(hole(-5, 99)), hole(0, 7))
    t.equal(dimensions.clamped(hole(20, 3)), hole(15, 3))

    t.equal(GridAxis.horizontal.perpendicular, .vertical)
    t.equal(GridAxis.vertical.perpendicular, .horizontal)
}
