import Foundation

@MainActor
func runJumperDraftTests(_ t: TestLog) {
    let dimensions = BoardDimensions(columns: 16, rows: 8)

    t.isNil(JumperDraft(kind: .bare, start: hole(-1, 0), dimensions: dimensions))
    t.isNil(JumperDraft(kind: .bare, start: hole(16, 0), dimensions: dimensions))

    var straight = JumperDraft(kind: .bare, start: hole(0, 0), dimensions: dimensions)!
    t.equal(straight.path, [hole(0, 0)])
    t.expect(straight.isEmpty)
    t.isNil(straight.makeJumper())
    t.expect(straight.move(to: hole(3, 0)))
    t.equal(straight.path, [hole(0, 0), hole(1, 0), hole(2, 0), hole(3, 0)])
    t.expect(straight.canCommit)
    let straightJumper = straight.makeJumper()
    t.isNotNil(straightJumper)
    t.equal(straightJumper?.kind, .bare)
    t.equal(straightJumper?.isValid(dimensions: dimensions), true)
    t.equal(straightJumper?.endpointDescription, "A1 → D1")

    // A diagonal pointer jump becomes a right-angled elbow, never a diagonal.
    var elbow = JumperDraft(kind: .bare, start: hole(0, 0), dimensions: dimensions)!
    t.expect(elbow.move(to: hole(3, 2)))
    t.equal(elbow.path.last, hole(3, 2))
    t.equal(elbow.path.count, 6)
    for index in 1..<elbow.path.count {
        let a = elbow.path[index - 1]
        let b = elbow.path[index]
        t.expect(a.isOrthogonallyAdjacent(to: b), "segment \(index) must be orthogonal")
        t.expect(!(abs(a.column - b.column) == 1 && abs(a.row - b.row) == 1), "no diagonals")
    }
    let elbowJumper = elbow.makeJumper()
    t.isNotNil(elbowJumper)
    t.equal(elbowJumper?.isValid(dimensions: dimensions), true)
    t.equal(elbowJumper?.endpointDescription, "A1 → D3")

    // Arbitrary multi-turn shapes.
    var shaped = JumperDraft(kind: .insulated, start: hole(0, 0), dimensions: dimensions)!
    _ = shaped.move(to: hole(2, 1))
    _ = shaped.move(to: hole(2, 4))
    _ = shaped.move(to: hole(4, 4))
    t.equal(shaped.path, [
        hole(0, 0), hole(1, 0), hole(2, 0), hole(2, 1),
        hole(2, 2), hole(2, 3), hole(2, 4), hole(3, 4), hole(4, 4),
    ])
    t.equal(shaped.kind, .insulated)
    for index in 1..<shaped.path.count {
        t.expect(shaped.path[index - 1].isOrthogonallyAdjacent(to: shaped.path[index]))
    }
    t.equal(Set(shaped.path).count, shaped.path.count, "routes do not repeat holes")
    t.isNotNil(shaped.makeJumper())

    t.equal(shaped.jumper?.kind, .insulated)

    // Retracing back to an earlier hole truncates the path.
    let beforeBacktrackCount = shaped.path.count
    t.expect(shaped.move(to: hole(2, 2)))
    t.equal(shaped.path, [hole(0, 0), hole(1, 0), hole(2, 0), hole(2, 1), hole(2, 2)])
    t.expect(shaped.path.count < beforeBacktrackCount)

    // Same-hole moves are no-ops.
    t.expect(!shaped.move(to: shaped.end))
    let unchanged = shaped.path
    t.expect(!shaped.move(to: hole(99, 0)))
    t.equal(shaped.path, unchanged)

    // The length cap leaves a valid prefix.
    var capped = JumperDraft(kind: .bare, start: hole(0, 0), dimensions: dimensions, maximumHoles: 5)!
    _ = capped.move(to: hole(5, 0))
    t.expect(capped.path.count <= 5)
    for index in 1..<capped.path.count {
        t.expect(capped.path[index - 1].isOrthogonallyAdjacent(to: capped.path[index]))
    }

    // Jumper validation catches every malformed shape.
    t.equal(
        Jumper(kind: .bare, route: [hole(0, 0)]).validationError(dimensions: dimensions),
        .tooShort
    )
    t.equal(
        Jumper(kind: .bare, route: [hole(0, 0), hole(0, 1)]).validationError(dimensions: dimensions),
        nil
    )
    t.equal(
        Jumper(kind: .bare, route: [hole(0, 0), hole(1, 1)]).validationError(dimensions: dimensions),
        .diagonalSegment(1)
    )
    t.equal(
        Jumper(kind: .bare, route: [hole(0, 0), hole(3, 0)]).validationError(dimensions: dimensions),
        .nonAdjacentSegment(1)
    )
    t.equal(
        Jumper(kind: .bare, route: [hole(0, 0), hole(-1, 0)]).validationError(dimensions: dimensions),
        .outOfBounds(hole(-1, 0))
    )
    t.equal(
        Jumper(kind: .bare, route: [hole(0, 0), hole(0, 1), hole(0, 0)]).validationError(dimensions: dimensions),
        .repeatedPoint(hole(0, 0))
    )

    let bare = Jumper(kind: .bare, route: [hole(0, 0), hole(1, 0), hole(1, 1)])
    let insulated = Jumper(kind: .insulated, route: [hole(0, 0), hole(1, 0), hole(1, 1)])
    t.equal(bare.conductiveHoles, [hole(0, 0), hole(1, 0), hole(1, 1)])
    t.equal(insulated.conductiveHoles, [hole(0, 0), hole(1, 1)])
    t.equal(bare.segmentCount, 2)
    t.expect(bare.kind.isConductiveAlongLength)
    t.expect(!insulated.kind.isConductiveAlongLength)

    // Very long routes are rejected with a specific error.
    let tooLong = Jumper(
        kind: .bare,
        route: Array(repeating: hole(0, 0), count: JumperValidation.maximumHoles + 1)
    )
    t.equal(tooLong.validationError(dimensions: dimensions), .tooLong)
}
