import Foundation

@MainActor
func runConnectivityTests(_ t: TestLog) {
    let dimensions = BoardDimensions(columns: 16, rows: 8)

    let fresh = Stripboard(template: .sixteenByEight)
    let freshGraph = Connectivity(board: fresh)
    t.equal(freshGraph.netCount, 8, "each strip starts independent")
    t.equal(freshGraph.nodeCount, 128)
    t.equal(freshGraph.edgeCount, 120)
    t.equal(freshGraph.nets.map(\.size), Array(repeating: 16, count: 8))
    for row in 0..<8 {
        t.expect(freshGraph.isConnected(hole(0, row), hole(15, row)), "row \(row) is one net")
    }
    t.expect(!freshGraph.isConnected(hole(0, 0), hole(0, 1)))
    t.equal(freshGraph.net(containing: hole(0, 0))?.index, 0)
    t.equal(freshGraph.net(containing: hole(15, 7))?.index, 7)
    t.equal(freshGraph.nets[0].edges.count, 15)
    t.expect(freshGraph.nets[0].edges.allSatisfy { $0.kind == .copper })
    t.equal(freshGraph.neighbours(of: hole(0, 0)), Set([hole(1, 0)]))
    t.equal(freshGraph.neighbours(of: hole(5, 0)), Set([hole(4, 0), hole(6, 0)]))

    // A cut splits the strip and removes the cut pad from the graph.
    var cutBoard = fresh
    t.expect(cutBoard.setCut(hole(2, 2), true))
    let cutGraph = Connectivity(board: cutBoard)
    t.equal(cutGraph.netCount, 9)
    t.equal(cutGraph.nodeCount, 127)
    t.equal(cutGraph.edgeCount, 118)
    t.expect(cutGraph.isConnected(hole(0, 2), hole(1, 2)))
    t.expect(cutGraph.isConnected(hole(3, 2), hole(15, 2)))
    t.expect(!cutGraph.isConnected(hole(1, 2), hole(3, 2)))
    t.expect(!cutGraph.isConnected(hole(2, 2), hole(1, 2)))
    t.isNil(cutGraph.net(containing: hole(2, 2)))
    let leftNet = cutGraph.net(containing: hole(0, 2))
    let rightNet = cutGraph.net(containing: hole(3, 2))
    t.equal(leftNet?.size, 2)
    t.equal(rightNet?.size, 13)
    t.notEqual(leftNet?.index, rightNet?.index)

    // Cutting a hole beside another cut still leaves the remaining strips valid.
    var manyCuts = fresh
    for column in [0, 2, 4] {
        _ = manyCuts.setCut(hole(column, 0), true)
    }
    let manyCutsGraph = Connectivity(board: manyCuts)
    t.equal(manyCutsGraph.netCount, 10)
    t.equal(manyCutsGraph.nodeCount, 125)
    t.expect(manyCutsGraph.isConnected(hole(5, 0), hole(15, 0)), "a run after cuts is still conductive")

    // Solder marks do not add inter-hole conductivity.
    var soldered = fresh
    for column in 0..<16 {
        _ = soldered.setSoldered(hole(column, 0), true)
    }
    let solderedGraph = Connectivity(board: soldered)
    t.equal(solderedGraph.netCount, freshGraph.netCount)
    t.equal(solderedGraph.edgeCount, freshGraph.edgeCount)
    t.equal(solderedGraph.nets, freshGraph.nets)

    // A bare jumper is conductive all along its route; it touches every hole it
    // passes over and bridges cuts.
    var bareAcrossCut = fresh
    _ = bareAcrossCut.setCut(hole(2, 2), true)
    let bareJumper = Jumper(
        id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
        kind: .bare,
        route: [hole(0, 2), hole(1, 2), hole(2, 2), hole(3, 2), hole(4, 2)]
    )
    t.expect(bareAcrossCut.addJumper(bareJumper))
    let bareAcrossCutGraph = Connectivity(board: bareAcrossCut)
    t.equal(bareAcrossCutGraph.netCount, 8, "the bare wire rejoins the split strip")
    t.equal(bareAcrossCutGraph.nodeCount, 128, "the cut hole is part of the wire's net")
    t.expect(bareAcrossCutGraph.isConnected(hole(1, 2), hole(3, 2)))
    t.expect(bareAcrossCutGraph.isConnected(hole(2, 2), hole(1, 2)))
    t.equal(bareAcrossCutGraph.net(containing: hole(2, 2))?.size, 16)
    t.expect(bareAcrossCutGraph.edges.contains(ConductionEdge(a: hole(1, 2), b: hole(2, 2), kind: .bareJumper)))

    // A bare vertical jumper joins every strip it crosses.
    var bareVertical = fresh
    let verticalBare = Jumper(kind: .bare, route: straightRoute(from: hole(0, 0), to: hole(0, 3)))
    t.expect(bareVertical.addJumper(verticalBare))
    let verticalBareGraph = Connectivity(board: bareVertical)
    t.equal(verticalBareGraph.netCount, 5, "rows 0–3 are now one net, rows 4–7 stay separate")
    t.expect(verticalBareGraph.isConnected(hole(0, 0), hole(0, 3)))
    t.expect(verticalBareGraph.isConnected(hole(0, 1), hole(7, 2)))
    t.expect(!verticalBareGraph.isConnected(hole(0, 3), hole(0, 4)))

    // The insulated jumper is only conductive at its endpoints. Intermediate
    // strips must remain separate and the middle holes of the route untouched.
    var insulated = fresh
    let insulatedJumper = Jumper(
        id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
        kind: .insulated,
        route: straightRoute(from: hole(0, 0), to: hole(0, 3))
    )
    t.expect(insulated.addJumper(insulatedJumper))
    let insulatedGraph = Connectivity(board: insulated)
    t.equal(insulatedGraph.netCount, 7, "only the two endpoint strips join")
    t.expect(insulatedGraph.isConnected(hole(0, 0), hole(0, 3)))
    t.expect(!insulatedGraph.isConnected(hole(0, 0), hole(0, 1)))
    t.expect(!insulatedGraph.isConnected(hole(0, 0), hole(0, 2)))
    t.expect(insulatedGraph.isConnected(hole(0, 1), hole(15, 1)), "row 1 is untouched")
    t.expect(
        insulatedGraph.edges.contains(
            ConductionEdge(a: hole(0, 0), b: hole(0, 3), kind: .insulatedJumper)
        )
    )
    t.expect(
        !insulatedGraph.edges.contains(
            ConductionEdge(a: hole(0, 0), b: hole(0, 1), kind: .insulatedJumper)
        )
    )

    // Two bare jumpers can deliberately short otherwise separate nets.
    var doubleJumper = fresh
    _ = doubleJumper.addJumper(Jumper(kind: .bare, route: [hole(0, 0), hole(0, 1)]))
    _ = doubleJumper.addJumper(
        Jumper(kind: .bare, route: [hole(0, 1), hole(0, 2), hole(0, 3)])
    )
    let doubleGraph = Connectivity(board: doubleJumper)
    t.expect(doubleGraph.isConnected(hole(0, 1), hole(0, 3)))
    t.expect(!doubleGraph.isConnected(hole(0, 3), hole(0, 4)))
    t.equal(doubleGraph.netCount, 5)

    // Placing components does not create conductivity between holes; they are
    // parts, not shorts.
    var componentState = freshState()
    _ = componentState.placeComponent(
        spec: resistorSpec(),
        at: hole(1, 1),
        axis: .vertical,
        span: 4,
        at: fixtureDate
    )
    t.equal(componentState.connectivity.netCount, 8)
    t.equal(componentState.connectivity.edgeCount, freshGraph.edgeCount)

    // Invalid routes in a loaded board are ignored rather than corrupting the graph.
    let invalidBoard = Stripboard(
        template: .sixteenByEight,
        jumpers: [Jumper(kind: .bare, route: [hole(0, 0), hole(2, 2)])]
    )
    let invalidGraph = Connectivity(board: invalidBoard)
    t.equal(invalidGraph.netCount, 8)
    t.equal(invalidGraph.edgeCount, 120)

    // Net membership partitions the node set.
    let totalNetHoles = bareAcrossCutGraph.nets.reduce(0) { $0 + $1.size }
    t.equal(totalNetHoles, bareAcrossCutGraph.nodeCount)
    t.equal(bareAcrossCutGraph.summary, "8 nets")

    // Colours are deterministic and distinct for many nets.
    let colours = (0..<32).map { NetColourPalette.colour(forNet: $0) }
    t.equal(Set(colours.map(\.hex)).count, 32, "the first 32 nets have distinct colours")
    t.equal(NetColourPalette.colour(forNet: 3), NetColourPalette.colour(forNet: 3))
    t.equal(NetColourPalette.curated.count, 16)
    t.equal(Set(NetColourPalette.curated.map(\.hex)).count, 16)
    let netColours = NetColourPalette.colours(for: freshGraph.nets)
    t.equal(netColours.count, 8)
    t.expect(Set(netColours.map(\.hex)).count == 8)

    // Edges are undirected.
    let e1 = ConductionEdge(a: hole(0, 0), b: hole(1, 0), kind: .copper)
    let e2 = ConductionEdge(a: hole(1, 0), b: hole(0, 0), kind: .copper)
    t.equal(e1, e2)
    t.equal(e1.other(than: hole(0, 0)), hole(1, 0))
    t.isNil(e1.other(than: hole(5, 5)))

    t.equal(freshGraph.isConnected(hole(999, 999), hole(0, 0)), false)
    t.equal(Connectivity(dimensions: dimensions, cutHoles: [], jumpers: []).netCount, dimensions.rows)
}
