import CoreGraphics
import Foundation
import UniformTypeIdentifiers

@MainActor
func runPersistenceTests(_ t: TestLog) {
    var state = StripmasterDocumentState(template: .thirtyTwoBySixteen, now: fixtureDate)
    _ = state.setCut(hole(1, 1), true, at: fixtureDate)
    _ = state.setSoldered(hole(2, 2), true, at: fixtureDate)
    _ = state.addJumper(
        kind: .bare,
        route: [hole(0, 0), hole(1, 0), hole(2, 0)],
        id: UUID(uuidString: "66666666-6666-6666-6666-666666666666")!,
        at: fixtureDate
    )
    _ = state.addJumper(
        kind: .insulated,
        route: [hole(4, 4), hole(4, 5), hole(4, 6), hole(5, 6)],
        at: fixtureDate
    )
    let componentID = UUID(uuidString: "77777777-7777-7777-7777-777777777777")!
    _ = state.placeComponent(
        spec: capacitorSpec(),
        at: hole(5, 5),
        id: componentID,
        at: fixtureDate
    )
    state.view.orientation = .portrait
    state.view.side = .bottom
    state.view.zoom = 21.5
    state.view.panX = 13.25
    state.view.panY = -7.5
    state.view.updatedAt = fixtureLater
    // Leave one redoable entry so history cursor persistence is exercised while
    // the board still contains every feature.
    _ = state.setCut(hole(10, 10), true, at: fixtureLater)
    _ = state.undo(at: fixtureLater)

    let file = StripmasterFile(state: state)
    t.equal(file.formatVersion, StripmasterFile.currentFormatVersion)

    let data: Data
    do {
        data = try StripmasterFileCodec.encode(file)
    } catch {
        t.expect(false, "encoding should not throw: \(error)")
        return
    }
    let jsonText = String(data: data, encoding: .utf8) ?? ""
    t.expect(jsonText.contains("\"formatVersion\""))
    t.expect(jsonText.contains("\n"), "documents are pretty-printed")

    let decoded: StripmasterFile
    do {
        decoded = try StripmasterFileCodec.decode(data)
    } catch {
        t.expect(false, "decoding should not throw: \(error)")
        return
    }
    t.equal(decoded, file, "a full document round-trips exactly")
    t.equal(decoded.state.board.template, .thirtyTwoBySixteen)
    t.equal(decoded.state.board.cutHoles, Set([hole(1, 1)]))
    t.equal(decoded.state.board.solderedHoles, Set([hole(2, 2)]))
    t.equal(decoded.state.board.jumpers.count, 2)
    t.equal(decoded.state.board.jumpers[0].kind, .bare)
    t.equal(decoded.state.board.jumpers[1].kind, .insulated)
    t.equal(decoded.state.board.components.count, 1)
    t.equal(decoded.state.board.components.first?.id, componentID)
    t.equal(decoded.state.board.components.first?.reference, capacitorSpec().reference)
    t.equal(decoded.state.view.orientation, .portrait)
    t.equal(decoded.state.view.side, .bottom)
    t.close(decoded.state.view.zoom ?? 0, 21.5)
    t.close(decoded.state.view.panX, 13.25)
    t.close(decoded.state.view.panY, -7.5)
    t.equal(decoded.state.history.entries.count, 6)
    t.equal(decoded.state.history.cursor, 5)
    t.equal(decoded.state.canUndo, true)
    t.equal(decoded.state.canRedo, true)

    // The persisted history is live: undo and redo still work after reopening.
    var reopened = decoded.state
    t.expect(reopened.undo(at: fixtureLater))
    t.isNil(reopened.board.component(id: componentID), "the first undo removes the component")
    t.equal(reopened.board.jumpers.count, 2)
    t.expect(reopened.undo(at: fixtureLater))
    t.equal(reopened.board.jumpers.count, 1)
    t.expect(reopened.redo(at: fixtureLater))
    t.expect(reopened.redo(at: fixtureLater))
    t.equal(reopened.board.component(id: componentID)?.id, componentID)

    // Older documents with no version or no view decode defensively.
    if var root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
        root.removeValue(forKey: "formatVersion")
        if var stateDict = root["state"] as? [String: Any] {
            stateDict.removeValue(forKey: "view")
            root["state"] = stateDict
        }
        if let olderData = try? JSONSerialization.data(withJSONObject: root),
           let older = try? StripmasterFileCodec.decode(olderData) {
            t.equal(older.formatVersion, 1)
            t.equal(older.state.view.orientation, .landscape)
            t.equal(older.state.view.side, .top)
            t.isNil(older.state.view.zoom)
        } else {
            t.expect(false, "a missing version and view should decode with defaults")
        }

        // A future format version is refused rather than misinterpreted.
        root["formatVersion"] = StripmasterFile.currentFormatVersion + 1
        if let futureData = try? JSONSerialization.data(withJSONObject: root) {
            t.throwsError { _ = try StripmasterFileCodec.decode(futureData) }
        } else {
            t.expect(false)
        }
    } else {
        t.expect(false, "encoded document should be JSON")
    }

    // A damaged history cursor is clamped on load.
    var cursorState = StripmasterDocumentState(template: .sixteenByEight, now: fixtureDate)
    _ = cursorState.setCut(hole(0, 0), true)
    _ = cursorState.setCut(hole(1, 0), true)
    if let cursorData = try? StripmasterFileCodec.encode(state: cursorState),
       var root = try? JSONSerialization.jsonObject(with: cursorData) as? [String: Any],
       var stateDict = root["state"] as? [String: Any],
       var historyDict = stateDict["history"] as? [String: Any] {
        historyDict["cursor"] = 999
        stateDict["history"] = historyDict
        root["state"] = stateDict
        if let brokenData = try? JSONSerialization.data(withJSONObject: root),
           let repaired = try? StripmasterFileCodec.decode(brokenData) {
            t.equal(repaired.state.history.cursor, 2)
            t.equal(repaired.state.history.entries.count, 2)
        } else {
            t.expect(false, "cursor-clamped history should decode")
        }
    } else {
        t.expect(false, "history JSON shape should be inspectable")
    }

    // Invalid geometry and dangling references are filtered at the boundary.
    let fixedJumperID = UUID(uuidString: "88888888-8888-8888-8888-888888888888")!
    let fixedComponentID = UUID(uuidString: "99999999-9999-9999-9999-999999999999")!
    let validJumper = Jumper(
        id: fixedJumperID,
        kind: .bare,
        route: [hole(0, 0), hole(1, 0)]
    )
    let duplicateJumper = Jumper(
        id: fixedJumperID,
        kind: .bare,
        route: [hole(2, 0), hole(3, 0)]
    )
    let diagonalJumper = Jumper(kind: .bare, route: [hole(0, 1), hole(1, 2)])
    let validComponent = PlacedComponent(
        id: fixedComponentID,
        reference: resistorSpec().reference,
        anchor: hole(0, 2),
        axis: .horizontal,
        span: 4
    )
    let duplicateComponent = PlacedComponent(
        id: fixedComponentID,
        reference: resistorSpec().reference,
        anchor: hole(2, 3),
        axis: .horizontal,
        span: 4
    )
    let unknownComponent = PlacedComponent(
        reference: ComponentReference(categoryID: "bogus", memberID: "none"),
        anchor: hole(1, 1)
    )
    let outOfBoundsComponent = PlacedComponent(
        reference: resistorSpec().reference,
        anchor: hole(99, 99)
    )
    let clampedComponent = PlacedComponent(
        id: UUID(),
        reference: resistorSpec().reference,
        anchor: hole(0, 4),
        axis: .horizontal,
        span: 99
    )
    let dirtyBoard = Stripboard(
        template: .sixteenByEight,
        cutHoles: [hole(0, 0), hole(99, 5)],
        solderedHoles: [hole(1, 1), hole(-1, 9)],
        jumpers: [validJumper, duplicateJumper, diagonalJumper],
        components: [
            validComponent,
            duplicateComponent,
            unknownComponent,
            outOfBoundsComponent,
            clampedComponent,
        ]
    )
    let cleanBoard = dirtyBoard.sanitized()
    t.equal(cleanBoard.cutHoles, Set([hole(0, 0)]))
    t.equal(cleanBoard.solderedHoles, Set([hole(1, 1)]))
    t.equal(cleanBoard.jumpers.count, 1)
    t.equal(cleanBoard.jumpers[0].id, fixedJumperID)
    t.equal(cleanBoard.components.count, 2)
    t.equal(cleanBoard.components[0].id, fixedComponentID)
    t.equal(cleanBoard.components[1].span, 6)
    t.expect(cleanBoard.components[1].isValid(dimensions: cleanBoard.dimensions))

    let dirtyState = StripmasterDocumentState(
        board: dirtyBoard,
        view: BoardViewState(zoom: -3, panX: 5, panY: 6),
        createdAt: fixtureDate,
        modifiedAt: fixtureLater
    )
    if let dirtyData = try? StripmasterFileCodec.encode(state: dirtyState),
       let cleaned = try? StripmasterFileCodec.decode(dirtyData) {
        t.equal(cleaned.state.board.jumpers.count, 1)
        t.equal(cleaned.state.board.components.count, 2)
        t.expect(cleaned.state.view.zoom == nil)
        t.close(cleaned.state.view.panX, 5)
        t.close(cleaned.state.view.panY, 6)
    } else {
        t.expect(false, "document sanitisation should survive a round trip")
    }

    // Non-finite view values (which cannot even be encoded as JSON) are repaired
    // by the in-memory sanitiser.
    let nonFiniteState = StripmasterDocumentState(
        board: dirtyBoard,
        view: BoardViewState(zoom: -3, panX: .nan, panY: .infinity),
        createdAt: fixtureDate,
        modifiedAt: fixtureLater
    )
    let repairedView = nonFiniteState.sanitized().view
    t.expect(repairedView.zoom == nil)
    t.close(repairedView.panX, 0)
    t.close(repairedView.panY, 0)

    // Corrupt JSON is rejected.
    t.throwsError { _ = try StripmasterFileCodec.decode(Data("not a board".utf8)) }
    t.throwsError { _ = try StripmasterFileCodec.decode(Data()) }

    // The native document type is registered by identifier and conforms to JSON.
    t.equal(UTType.stripmasterBoard.identifier, "cc.hemsley.stripmaster.board")
    t.equal(StripmasterFileFormat.contentType, .stripmasterBoard)
    t.equal(StripmasterFileFormat.contentType.identifier, "cc.hemsley.stripmaster.board")
    t.equal(StripmasterFileFormat.fileExtension, "stripmaster")
    t.equal(StripmasterFileFormat.defaultFilename, "Untitled.stripmaster")
}
