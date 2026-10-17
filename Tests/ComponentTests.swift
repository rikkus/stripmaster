import CoreGraphics
import Foundation

@MainActor
func runComponentTests(_ t: TestLog) {
    var state = freshState()
    let metrics = state.metrics
    let resistor = resistorSpec()

    let firstID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    let placed = state.placeComponent(
        spec: resistor,
        at: hole(0, 0),
        id: firstID,
        at: fixtureDate
    )
    t.isNotNil(placed)
    t.equal(placed?.axis, .horizontal)
    t.equal(placed?.span, 5)
    t.equal(state.board.components.count, 1)
    t.equal(state.history.entries.count, 1)
    t.equal(state.history.entries.first?.label, "Place resistor")
    t.equal(state.board.pinHoles, Set([hole(0, 0), hole(5, 0)]))
    t.expect(state.board.solderedHoles.isEmpty, "placing does not solder pins automatically")

    let stored = state.board.components[0]
    t.equal(stored.pinHoles(dimensions: state.dimensions), [hole(0, 0), hole(5, 0)])
    t.equal(stored.pins(dimensions: state.dimensions).map(\.index), [0, 1])
    t.expect(stored.isValid(dimensions: state.dimensions))

    // Hitting the body or pins selects the part.
    let geometry = stored.layoutGeometry(metrics: metrics)!
    let bodyPoint = CGPoint(x: geometry.bodyRect.midX, y: geometry.bodyRect.midY)
    t.equal(state.board.component(hitTest: bodyPoint)?.id, firstID)
    t.isNil(state.board.component(hitTest: CGPoint(x: 999, y: 999)))

    // Near the right-hand edge the auto-placer turns the part upright.
    let edgePlaced = state.placeComponent(
        spec: resistor,
        at: hole(15, 0),
        id: UUID(),
        at: fixtureDate
    )
    t.isNotNil(edgePlaced)
    t.equal(edgePlaced?.axis, .vertical)
    t.expect(edgePlaced?.isValid(dimensions: state.dimensions) ?? false)

    // A clearly impossible centred placement is refused.
    let impossible = PlacedComponent(
        reference: resistor.reference,
        anchor: hole(15, 7),
        axis: .horizontal,
        span: 5
    )
    t.expect(!impossible.isValid(dimensions: state.dimensions))
    let refused = state.placeComponent(impossible, at: fixtureDate)
    t.isNil(refused)
    t.equal(state.board.components.count, 2, "a refused placement does not enter the document")

    // Undo and redo preserve components.
    let countBeforeUndo = state.board.components.count
    t.expect(state.undo(at: fixtureDate))
    t.equal(state.board.components.count, countBeforeUndo - 1)
    t.expect(state.redo(at: fixtureDate))
    t.equal(state.board.components.count, countBeforeUndo)

    // DIP packages occupy two rows three holes apart.
    var dipState = freshState()
    let dipSpec = ComponentCatalogue.spec(categoryID: "ic", memberID: "opamp8")!
    let dip = dipState.placeComponent(
        spec: dipSpec,
        at: hole(2, 1),
        axis: .horizontal,
        at: fixtureDate
    )
    t.isNotNil(dip)
    t.equal(dip?.span, 1)
    let dipHoles = dip?.pinHoles(dimensions: dipState.dimensions) ?? []
    t.equal(dipHoles.count, 8)
    t.equal(Array(dipHoles.prefix(4)), [hole(2, 1), hole(3, 1), hole(4, 1), hole(5, 1)])
    t.equal(Array(dipHoles.suffix(4)), [hole(2, 4), hole(3, 4), hole(4, 4), hole(5, 4)])
    t.expect(dip?.isValid(dimensions: dipState.dimensions) ?? false)
    t.isNotNil(dip?.layoutGeometry(metrics: dipState.metrics))

    // One-leg parts are representable.
    var pointState = freshState()
    let testPoint = ComponentCatalogue.spec(categoryID: "misc", memberID: "testpoint")!
    let point = pointState.placeComponent(spec: testPoint, at: hole(0, 0), at: fixtureDate)
    t.isNotNil(point)
    t.equal(point?.pinHoles(dimensions: pointState.dimensions).count, 1)

    // Stretch clamps to the catalogue, rotation and flip are edits.
    var editState = freshState()
    let componentID = UUID()
    _ = editState.placeComponent(
        spec: resistor,
        at: hole(0, 0),
        axis: .horizontal,
        span: 4,
        id: componentID,
        at: fixtureDate
    )
    t.expect(editState.stretchComponent(id: componentID, span: 99, at: fixtureDate))
    t.equal(editState.board.components[0].span, 6)
    t.expect(editState.rotateComponent(id: componentID, at: fixtureDate))
    t.equal(editState.board.components[0].axis, .vertical)
    t.expect(editState.flipComponent(id: componentID, at: fixtureDate))
    t.equal(editState.board.components[0].flipped, true)
    t.expect(editState.undo(at: fixtureDate))
    t.equal(editState.board.components[0].flipped, false)
    t.expect(editState.undo(at: fixtureDate))
    t.equal(editState.board.components[0].axis, .horizontal)
    t.expect(editState.undo(at: fixtureDate))
    t.equal(editState.board.components[0].span, 4)

    // Moving a component is one update edit and validates the destination.
    var moveState = freshState()
    let moveID = UUID()
    _ = moveState.placeComponent(spec: resistor, at: hole(0, 0), id: moveID, at: fixtureDate)
    t.expect(moveState.moveComponent(id: moveID, to: hole(0, 1), at: fixtureDate))
    t.equal(moveState.board.components[0].anchor, hole(0, 1))
    t.equal(moveState.history.entries.last?.label, "Move resistor")
    t.expect(!moveState.moveComponent(id: moveID, to: hole(15, 7), at: fixtureDate))
    t.expect(moveState.undo(at: fixtureDate))
    t.equal(moveState.board.components[0].anchor, hole(0, 0))

    // Removing then undoing restores z-order.
    var orderState = freshState()
    let specA = resistor
    let specB = capacitorSpec()
    let idA = UUID(), idB = UUID()
    _ = orderState.placeComponent(spec: specA, at: hole(0, 0), id: idA, at: fixtureDate)
    _ = orderState.placeComponent(spec: specB, at: hole(8, 0), id: idB, at: fixtureDate)
    t.equal(orderState.board.components.map(\.id), [idA, idB])
    t.expect(orderState.removeComponent(id: idA, at: fixtureDate))
    t.equal(orderState.board.components.map(\.id), [idB])
    t.expect(orderState.undo(at: fixtureDate))
    t.equal(orderState.board.components.map(\.id), [idA, idB], "undo restores z-order")

    // Unknown catalogue references are inert and cannot be inserted.
    let unknown = PlacedComponent(
        reference: ComponentReference(categoryID: "nope", memberID: "nothing"),
        anchor: hole(0, 0)
    )
    t.isNil(unknown.spec)
    t.equal(unknown.pinHoles(dimensions: state.dimensions), [])
    t.expect(!state.board.addComponent(unknown))

    // Geometry remains usable for inline parts.
    let transistor = ComponentCatalogue.spec(categoryID: "transistor", memberID: "npn")!
    var inlineState = freshState()
    let inline = inlineState.placeComponent(
        spec: transistor,
        at: hole(1, 1),
        axis: .horizontal,
        at: fixtureDate
    )
    t.equal(inline?.pinHoles(dimensions: inlineState.dimensions), [hole(1, 1), hole(2, 1), hole(3, 1)])
    t.isNotNil(inline?.layoutGeometry(metrics: inlineState.metrics))

    let flippedGeometry = inline?.layoutGeometry(metrics: inlineState.metrics)
    t.close(Double(flippedGeometry?.pinHoles.count ?? 0), 3)
}
