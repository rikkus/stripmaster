import CoreGraphics
import Foundation

@MainActor
func runViewStateTests(_ t: TestLog) {
    let metrics16 = BoardMetrics(template: .sixteenByEight)
    let viewport = CGSize(width: 800, height: 500)

    var fresh = BoardViewState()
    t.equal(fresh.orientation, .landscape, "default orientation is landscape")
    t.equal(fresh.side, .top, "default side is the component side")
    t.isNil(fresh.zoom)
    t.expect(fresh.needsInitialFit)
    t.expect(!fresh.hasSavedView)

    t.expect(fresh.ensureInitialFit(viewport: viewport, metrics: metrics16, at: fixtureDate))
    t.isNotNil(fresh.zoom)
    t.close(fresh.panX, 0)
    t.close(fresh.panY, 0)
    t.equal(fresh.updatedAt, fixtureDate)
    t.expect(!fresh.needsInitialFit)
    t.expect(!fresh.ensureInitialFit(viewport: viewport, metrics: metrics16, at: fixtureLater))

    if let zoom = fresh.zoomValue {
        let displayed = metrics16.displayedSize(for: fresh.orientation, zoom: zoom)
        t.expect(displayed.width <= viewport.width - BoardZoom.fitPadding * 2 + 0.001)
        t.expect(displayed.height <= viewport.height - BoardZoom.fitPadding * 2 + 0.001)
        let maxWidthFill = displayed.width / (viewport.width - BoardZoom.fitPadding * 2)
        let maxHeightFill = displayed.height / (viewport.height - BoardZoom.fitPadding * 2)
        t.close(max(maxWidthFill, maxHeightFill), 1, accuracy: 0.001, "fit uses the limiting dimension")
    }

    var portrait = BoardViewState(orientation: .portrait)
    t.expect(portrait.ensureInitialFit(viewport: viewport, metrics: metrics16))
    t.equal(portrait.orientation, .portrait)
    if let zoom = portrait.zoomValue {
        let displayed = metrics16.displayedSize(for: .portrait, zoom: zoom)
        t.expect(displayed.height <= viewport.height - BoardZoom.fitPadding * 2 + 0.001)
        t.expect(displayed.width <= viewport.width - BoardZoom.fitPadding * 2 + 0.001)
    }

    // A previously stored view is restored rather than overwritten.
    var stored = BoardViewState(zoom: 17, panX: 22, panY: -9)
    t.expect(!stored.ensureInitialFit(viewport: viewport, metrics: metrics16))
    t.close(stored.zoom ?? 0, 17)
    t.close(stored.panX, 22)
    t.close(stored.panY, -9)

    // Missing fields in older documents get sensible defaults.
    let decoded = try? JSONDecoder().decode(
        BoardViewState.self,
        from: Data(#"{"orientation":90}"#.utf8)
    )
    t.isNotNil(decoded)
    t.equal(decoded?.orientation, .portrait)
    t.equal(decoded?.side, .top)
    t.isNil(decoded?.zoom)
    t.close(decoded?.panX ?? -1, 0)

    var invalidZoom = BoardViewState(zoom: -4, panX: .nan, panY: .infinity)
    invalidZoom = invalidZoom.sanitized()
    t.isNil(invalidZoom.zoom)
    t.close(invalidZoom.panX, 0)
    t.close(invalidZoom.panY, 0)

    // Zoom keeps the content under the pinch anchor stationary.
    var anchorView = BoardViewState(zoom: 10, panX: 0, panY: 0)
    let anchor = CGPoint(x: 560, y: 230)
    let beforeTransform = BoardViewTransform(
        viewportSize: viewport,
        metrics: metrics16,
        view: anchorView,
        fallbackZoom: 10
    )
    let boardPointBefore = beforeTransform.viewToBoard(anchor)
    t.expect(
        anchorView.zoom(
            to: 20,
            around: anchor,
            viewport: viewport,
            fallbackZoom: 10,
            at: fixtureDate
        )
    )
    let afterTransform = BoardViewTransform(
        viewportSize: viewport,
        metrics: metrics16,
        view: anchorView,
        fallbackZoom: 20
    )
    let boardPointAfter = afterTransform.viewToBoard(anchor)
    t.close(boardPointAfter.x, boardPointBefore.x, accuracy: 1e-7)
    t.close(boardPointAfter.y, boardPointBefore.y, accuracy: 1e-7)
    t.close(anchorView.zoom ?? 0, 20)
    t.notEqual(anchorView.panX, 0)

    // Zoom limits are applied.
    var limited = BoardViewState(zoom: 10)
    _ = limited.zoom(to: 10_000, around: CGPoint(x: 400, y: 250), viewport: viewport, fallbackZoom: 10)
    t.close(limited.zoom ?? 0, Double(BoardZoom.maximum))
    _ = limited.zoom(to: 0.0001, around: CGPoint(x: 400, y: 250), viewport: viewport, fallbackZoom: 10)
    t.close(limited.zoom ?? 0, Double(BoardZoom.minimum))

    // Panning and flipping are view-only state changes.
    var panned = BoardViewState(zoom: 10)
    panned.pan(by: CGSize(width: 30, height: -12), at: fixtureLater)
    t.close(panned.panX, 30)
    t.close(panned.panY, -12)
    t.equal(panned.updatedAt, fixtureLater)
    panned.flipSide(at: fixtureLater)
    t.equal(panned.side, .bottom)
    panned.flipSide()
    t.equal(panned.side, .top)

    // Rotate in 90° steps, refitting to the new aspect and clearing pan.
    var rotating = BoardViewState()
    _ = rotating.ensureInitialFit(viewport: viewport, metrics: metrics16)
    let landscapeZoom = rotating.zoomValue ?? 0
    rotating.pan(by: CGSize(width: 10, height: 10))
    rotating.rotateClockwise(viewport: viewport, metrics: metrics16, at: fixtureLater)
    t.equal(rotating.orientation, .portrait)
    t.close(rotating.panX, 0)
    t.close(rotating.panY, 0)
    t.equal(rotating.updatedAt, fixtureLater)
    t.notEqual(rotating.zoomValue ?? 0, landscapeZoom)
    rotating.rotateClockwise(viewport: viewport, metrics: metrics16)
    t.equal(rotating.orientation, .landscapeUpsideDown)
    rotating.rotateClockwise(viewport: viewport, metrics: metrics16)
    t.equal(rotating.orientation, .portraitUpsideDown)
    rotating.rotateClockwise(viewport: viewport, metrics: metrics16)
    t.equal(rotating.orientation, .landscape, "four quarter turns return to landscape")

    var preserving = BoardViewState(zoom: 13.5)
    preserving.rotateClockwise(viewport: nil, metrics: metrics16)
    t.equal(preserving.orientation, .portrait)
    t.close(preserving.zoom ?? 0, 13.5)

    t.equal(BoardOrientation.portrait.rotatedClockwise, .landscapeUpsideDown)
    t.equal(BoardOrientation.landscape.rotatedAnticlockwise, .portraitUpsideDown)

    // Transform round-trips for every orientation and face.
    for orientation in BoardOrientation.allCases {
        for side in BoardSide.allCases {
            let view = BoardViewState(
                orientation: orientation,
                side: side,
                zoom: 18,
                panX: 37,
                panY: -21
            )
            let transform = BoardViewTransform(
                viewportSize: viewport,
                metrics: metrics16,
                view: view,
                fallbackZoom: 18
            )
            let localPoints = [
                CGPoint.zero,
                metrics16.boardCenter,
                CGPoint(x: metrics16.boardSize.width, y: metrics16.boardSize.height),
                metrics16.holeCenter(hole(0, 0)),
                metrics16.holeCenter(hole(15, 7)),
            ]
            for localPoint in localPoints {
                let roundTrip = transform.viewToBoard(transform.boardToView(localPoint))
                t.close(roundTrip.x, localPoint.x, accuracy: 1e-8, "\(orientation) \(side)")
                t.close(roundTrip.y, localPoint.y, accuracy: 1e-8, "\(orientation) \(side)")
            }
            for sample in [hole(0, 0), hole(3, 4), hole(15, 7)] {
                t.equal(
                    transform.hole(at: transform.viewPoint(for: sample)),
                    sample,
                    "hit testing follows \(orientation) \(side)"
                )
            }
            let rect = transform.boardRect
            t.close(rect.midX, transform.center.x, accuracy: 1e-8)
            t.close(rect.midY, transform.center.y, accuracy: 1e-8)
            if orientation.isQuarterTurn {
                t.close(rect.width, metrics16.boardSize.height * 18, accuracy: 1e-8)
                t.close(rect.height, metrics16.boardSize.width * 18, accuracy: 1e-8)
            } else {
                t.close(rect.width, metrics16.boardSize.width * 18, accuracy: 1e-8)
                t.close(rect.height, metrics16.boardSize.height * 18, accuracy: 1e-8)
            }
        }
    }

    // Back-side hit testing is mirrored, so a right-edge hole appears on the left.
    let topTransform = BoardViewTransform(
        viewportSize: viewport,
        metrics: metrics16,
        orientation: .landscape,
        side: .top,
        zoom: 20,
        pan: .zero
    )
    let bottomTransform = BoardViewTransform(
        viewportSize: viewport,
        metrics: metrics16,
        orientation: .landscape,
        side: .bottom,
        zoom: 20,
        pan: .zero
    )
    let rightHole = hole(15, 4)
    let topX = topTransform.viewPoint(for: rightHole).x
    let bottomX = bottomTransform.viewPoint(for: rightHole).x
    t.close(topX + bottomX, viewport.width, accuracy: 1e-8, "back view mirrors horizontally")
    t.equal(bottomTransform.hole(at: bottomTransform.viewPoint(for: rightHole)), rightHole)

    t.isNil(topTransform.hole(at: CGPoint(x: -5_000, y: -5_000)))

    // Bigger boards fit at a smaller zoom.
    var smallView = BoardViewState()
    var bigView = BoardViewState()
    _ = smallView.ensureInitialFit(viewport: viewport, metrics: BoardMetrics(template: .sixteenByEight))
    _ = bigView.ensureInitialFit(viewport: viewport, metrics: BoardMetrics(template: .fortyEightByTwentyFour))
    t.expect((bigView.zoomValue ?? 0) < (smallView.zoomValue ?? 0))
}
