import CoreGraphics
import Foundation

@MainActor
func runHistoryTests(_ t: TestLog) {
    var state = freshState()
    t.equal(state.history.entries.count, 0)
    t.equal(state.canUndo, false)
    t.equal(state.canRedo, false)
    t.isNil(state.undoLabel)
    t.isNil(state.redoLabel)
    t.expect(state.isUntouched)
    t.equal(state.modifiedAt, fixtureDate)
    t.equal(state.createdAt, fixtureDate)

    // A cut is one edit and one history entry.
    t.equal(state.setCut(hole(2, 2), true, at: fixtureLater), true)
    t.equal(state.history.entries.count, 1)
    t.equal(state.history.cursor, 1)
    t.equal(state.undoLabel, "Cut C3")
    t.equal(state.board.isCut(hole(2, 2)), true)
    t.equal(state.modifiedAt, fixtureLater)
    t.equal(state.history.entries[0].date, fixtureLater)
    t.expect(!state.isUntouched)
    t.equal(state.setCut(hole(2, 2), true, at: fixtureLater), false, "a no-op is not recorded")
    t.equal(state.history.entries.count, 1)

    // View changes never enter the edit history.
    t.expect(state.ensureInitialFit(viewport: CGSize(width: 700, height: 500), at: fixtureLater))
    t.equal(state.history.entries.count, 1)
    let storedZoom = state.view.zoom
    t.isNotNil(storedZoom)
    t.expect(state.rotateView(viewport: CGSize(width: 700, height: 500), at: fixtureLater))
    t.equal(state.view.orientation, .portrait)
    t.equal(state.history.entries.count, 1)
    t.expect(state.flipView(at: fixtureLater))
    t.equal(state.view.side, .bottom)
    t.equal(state.history.entries.count, 1)
    t.expect(state.panView(by: CGSize(width: 12, height: 4), at: fixtureLater))
    t.equal(state.history.entries.count, 1)
    t.expect(state.zoomView(by: 1.2, viewport: CGSize(width: 700, height: 500), fallbackZoom: 20, at: fixtureLater))
    t.equal(state.history.entries.count, 1)
    t.equal(state.history.undoLabel, "Cut C3", "view changes do not become undo targets")

    // Undo and redo use the history, not the system undo manager.
    t.expect(state.undo(at: fixtureLater))
    t.equal(state.board.isCut(hole(2, 2)), false)
    t.equal(state.canUndo, false)
    t.equal(state.canRedo, true)
    t.equal(state.redoLabel, "Cut C3")
    t.equal(state.history.cursor, 0)
    t.expect(state.redo(at: fixtureLater))
    t.equal(state.board.isCut(hole(2, 2)), true)
    t.equal(state.canRedo, false)
    t.expect(state.undo(at: fixtureLater))
    t.equal(state.board.isCut(hole(2, 2)), false)
    t.expect(!state.undo(at: fixtureLater), "undo at the beginning is a no-op")
    t.expect(state.redo(at: fixtureLater))
    t.equal(state.board.isCut(hole(2, 2)), true)
    t.expect(!state.redo(at: fixtureLater), "redo at the end is a no-op")

    // A new edit after undo discards redoable work.
    var branching = freshState()
    _ = branching.setCut(hole(0, 0), true, at: fixtureDate)
    _ = branching.setCut(hole(1, 0), true, at: fixtureDate)
    _ = branching.undo(at: fixtureDate)
    t.equal(branching.history.redoCount, 1)
    _ = branching.setSoldered(hole(3, 3), true, at: fixtureDate)
    t.equal(branching.history.entries.count, 2)
    t.equal(branching.history.redoCount, 0)
    t.equal(branching.board.isCut(hole(1, 0)), false, "the discarded redo was not re-applied")
    t.equal(branching.board.isCut(hole(0, 0)), true)
    t.equal(branching.board.isSoldered(hole(3, 3)), true)

    // Jumpers and components round-trip through undo/redo.
    var editing = freshState()
    let jumperID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
    let jumper = editing.addJumper(
        kind: .insulated,
        route: [hole(0, 0), hole(1, 0), hole(1, 1), hole(1, 2)],
        id: jumperID,
        at: fixtureDate
    )
    t.isNotNil(jumper)
    t.equal(editing.history.entries.last?.label, "Add insulated jumper A1 → B3")
    t.expect(editing.undo(at: fixtureDate))
    t.equal(editing.board.jumpers.count, 0)
    t.expect(editing.redo(at: fixtureDate))
    t.equal(editing.board.jumpers.count, 1)
    t.equal(editing.board.jumpers[0].id, jumperID)
    t.expect(editing.removeJumper(id: jumperID, at: fixtureDate))
    t.equal(editing.history.entries.last?.label, "Remove insulated jumper A1 → B3")
    t.expect(editing.undo(at: fixtureDate))
    t.equal(editing.board.jumpers.count, 1)

    let componentID = UUID(uuidString: "55555555-5555-5555-5555-555555555555")!
    _ = editing.placeComponent(
        spec: resistorSpec(),
        at: hole(3, 3),
        id: componentID,
        at: fixtureDate
    )
    t.equal(editing.history.entries.last?.label, "Place resistor")
    t.expect(editing.undo(at: fixtureDate))
    t.equal(editing.board.component(id: componentID), nil)
    t.expect(editing.redo(at: fixtureDate))
    t.isNotNil(editing.board.component(id: componentID))
    t.expect(editing.removeComponent(id: componentID, at: fixtureDate))
    t.equal(editing.history.entries.last?.label, "Remove resistor")
    t.expect(editing.undo(at: fixtureDate))
    t.isNotNil(editing.board.component(id: componentID))

    // Invalid and missing targets are not recorded.
    let count = editing.history.entries.count
    t.equal(editing.setCut(hole(99, 99), true, at: fixtureDate), false)
    t.isNil(editing.addJumper(kind: .bare, route: [hole(0, 0), hole(2, 2)], at: fixtureDate))
    t.equal(editing.removeJumper(id: UUID(), at: fixtureDate), false)
    t.equal(editing.removeComponent(id: UUID(), at: fixtureDate), false)
    let invalidUpdate = PlacedComponent(
        reference: resistorSpec().reference,
        anchor: hole(15, 7),
        axis: .horizontal,
        span: 5
    )
    t.equal(editing.updateComponent(invalidUpdate, at: fixtureDate), false)
    t.equal(editing.history.entries.count, count)

    // Walk all the way back and forward.
    var allEdits = freshState()
    _ = allEdits.setCut(hole(0, 0), true, at: fixtureDate)
    _ = allEdits.setSoldered(hole(1, 1), true, at: fixtureDate)
    _ = allEdits.addJumper(kind: .bare, route: [hole(0, 0), hole(0, 1), hole(0, 2)], at: fixtureDate)
    _ = allEdits.placeComponent(spec: resistorSpec(), at: hole(2, 2), at: fixtureDate)
    let finalBoard = allEdits.board
    let finalCount = allEdits.history.entries.count
    t.equal(finalCount, 4)
    var undos = 0
    while allEdits.undo(at: fixtureDate) { undos += 1 }
    t.equal(undos, finalCount)
    t.equal(allEdits.board, Stripboard(template: .sixteenByEight))
    t.equal(allEdits.history.cursor, 0)
    var redos = 0
    while allEdits.redo(at: fixtureDate) { redos += 1 }
    t.equal(redos, finalCount)
    t.equal(allEdits.board, finalBoard)

    // Labels for all edit kinds.
    t.equal(BoardEdit.setCut(hole: hole(0, 0), isCut: true).label, "Cut A1")
    t.equal(BoardEdit.setCut(hole: hole(0, 0), isCut: false).label, "Uncut A1")
    t.equal(BoardEdit.setSoldered(hole: hole(1, 2), isSoldered: true).label, "Solder B3")
    t.equal(BoardEdit.setSoldered(hole: hole(1, 2), isSoldered: false).label, "Unsolder B3")
    let labelJumper = Jumper(kind: .bare, route: [hole(0, 0), hole(1, 0)])
    t.equal(BoardEdit.addJumper(labelJumper).label, "Add bare wire A1 → B1")
    t.equal(BoardEdit.removeJumper(labelJumper, index: 0).label, "Remove bare wire A1 → B1")
    t.equal(BoardEdit.addJumper(labelJumper).kindDescription, "jumper")

    // Template choice is an untouched-document action, not an edit entry.
    var templateState = freshState()
    t.expect(templateState.isUntouched)
    t.expect(templateState.selectTemplate(.twentyFourByTwelve, at: fixtureLater))
    t.equal(templateState.board.template, .twentyFourByTwelve)
    t.equal(templateState.history.entries.count, 0)
    t.isNil(templateState.view.zoom)
    t.expect(templateState.isUntouched)
    _ = templateState.setCut(hole(0, 0), true)
    t.equal(templateState.selectTemplate(.sixteenByEight, at: fixtureLater), false)

    // Undoing every edit does not make an edited document "untouched" again;
    // the history is intentionally still non-empty.
    var undoneState = freshState()
    _ = undoneState.setCut(hole(0, 0), true)
    _ = undoneState.undo()
    t.equal(undoneState.board, Stripboard(template: .sixteenByEight))
    t.expect(!undoneState.isUntouched)
    t.equal(undoneState.selectTemplate(.fortyEightByTwentyFour), false)

    // History encoding round-trips including the cursor.
    var roundTripHistory = EditHistory()
    roundTripHistory.record(.setCut(hole: hole(0, 0), isCut: true), date: fixtureDate)
    roundTripHistory.record(.setSoldered(hole: hole(1, 1), isSoldered: true), date: fixtureLater)
    _ = roundTripHistory.undo()
    let data = try? JSONEncoder().encode(roundTripHistory)
    let decodedHistory = data.flatMap { try? JSONDecoder().decode(EditHistory.self, from: $0) }
    t.isNotNil(decodedHistory)
    t.equal(decodedHistory?.canUndo, true)
    t.equal(decodedHistory?.canRedo, true)
    t.equal(decodedHistory?.entries.count, 2)
    t.equal(decodedHistory?.cursor, 1)
    t.equal(decodedHistory?.undoLabel, "Cut A1")
    t.equal(decodedHistory?.redoLabel, "Solder B2")

    // Cursor clamping and duplicate protection when repairing history.
    let repaired = EditHistory(entries: roundTripHistory.entries, cursor: -50).sanitized()
    t.equal(repaired.cursor, 0)
    t.equal(repaired.entries.count, 2)
}
