import SwiftUI

/// What is currently being gestured on the canvas, shown as a translucent
/// preview until the gesture is committed.
enum BoardPreview: Equatable {
    case none
    case paint(tool: EditorTool, holes: Set<GridPoint>)
    case jumper(kind: JumperKind, route: [GridPoint])
    case component(PlacedComponent, valid: Bool)
}

/// Draws the complete board: material, copper, connectivity overlay, holes,
/// components, jumpers, solder, cuts, and interaction previews.
struct BoardRenderer {
    let board: Stripboard
    let connectivity: Connectivity
    let view: BoardViewState
    let viewport: CGSize
    let selectedComponentID: UUID?
    let hiddenComponentID: UUID?
    let hoveredHole: GridPoint?
    let tool: EditorTool
    let preview: BoardPreview
    let fallbackZoom: CGFloat

    private var metrics: BoardMetrics { board.metrics }

    private func hole(_ column: Int, _ row: Int) -> GridPoint {
        GridPoint(column: column, row: row)
    }

    private var transform: BoardViewTransform {
        BoardViewTransform(
            viewportSize: viewport,
            metrics: metrics,
            view: view,
            fallbackZoom: fallbackZoom
        )
    }

    func draw(in context: inout GraphicsContext) {
        guard viewport.width > 1, viewport.height > 1 else { return }
        drawWorkspace(in: &context)

        let transform = transform
        let zoom = transform.zoom
        let boardRect = transform.boardRect
        let cornerRadius = min(22, max(7, min(boardRect.width, boardRect.height) * 0.035))
        let boardPath = Path(roundedRect: boardRect, cornerRadius: cornerRadius)

        var shadowContext = context
        shadowContext.addFilter(
            .shadow(
                color: Color.black.opacity(0.55),
                radius: max(10, min(28, zoom * 0.7)),
                x: 0,
                y: max(6, min(18, zoom * 0.35))
            )
        )
        shadowContext.fill(boardPath, with: .color(.black))

        context.fill(boardPath, with: boardSurface)
        context.stroke(
            boardPath,
            with: .color(view.side == .top ? BoardTheme.topBoardEdge : BoardTheme.bottomBoardEdge),
            lineWidth: 1.2
        )
        context.stroke(
            Path(
                roundedRect: boardRect.insetBy(dx: 1.2, dy: 1.2),
                cornerRadius: max(0, cornerRadius - 1.2)
            ),
            with: .color(.white.opacity(0.10)),
            lineWidth: 0.6
        )

        context.clip(to: boardPath)
        context.translateBy(x: transform.center.x, y: transform.center.y)
        context.rotate(by: .degrees(view.orientation.degrees))
        context.scaleBy(x: zoom, y: zoom)
        if view.side == .bottom {
            context.scaleBy(x: -1, y: 1)
        }
        context.translateBy(x: -metrics.boardSize.width / 2, y: -metrics.boardSize.height / 2)

        if view.side == .bottom {
            drawCopper(in: &context)
            drawConnectivityOverlay(in: &context)
            drawHoles(in: &context)
            drawPinsFromBack(in: &context)
            drawSolder(in: &context)
            drawCuts(in: &context)
        } else {
            drawConnectivityOverlay(in: &context)
            drawHoles(in: &context)
            drawComponents(in: &context)
            drawJumpers(in: &context)
            drawSolder(in: &context)
            drawCuts(in: &context)
            drawSelection(in: &context)
        }

        drawBackOfBoardTouchUps(in: &context)
        drawPreview(in: &context)
        drawHover(in: &context)
    }

    // MARK: - Materials

    private var boardSurface: GraphicsContext.Shading {
        let top = view.side == .top ? BoardTheme.topBoardHighlight : BoardTheme.bottomBoardHighlight
        let bottom = view.side == .top ? BoardTheme.topBoard : BoardTheme.bottomBoard
        return .linearGradient(
            Gradient(colors: [top, bottom]),
            startPoint: CGPoint(x: transform.boardRect.minX, y: transform.boardRect.minY),
            endPoint: CGPoint(x: transform.boardRect.maxX, y: transform.boardRect.maxY)
        )
    }

    private func drawWorkspace(in ctx: inout GraphicsContext) {
        let rect = CGRect(origin: .zero, size: viewport)
        ctx.fill(
            Path(rect),
            with: .linearGradient(
                Gradient(colors: [BoardTheme.workspaceTop, BoardTheme.workspaceBottom]),
                startPoint: CGPoint(x: 0, y: 0),
                endPoint: CGPoint(x: 0, y: viewport.height)
            )
        )

        var grid = Path()
        let spacing: CGFloat = 28
        var x: CGFloat = 0
        while x <= viewport.width {
            grid.move(to: CGPoint(x: x, y: 0))
            grid.addLine(to: CGPoint(x: x, y: viewport.height))
            x += spacing
        }
        var y: CGFloat = 0
        while y <= viewport.height {
            grid.move(to: CGPoint(x: 0, y: y))
            grid.addLine(to: CGPoint(x: viewport.width, y: y))
            y += spacing
        }
        ctx.stroke(grid, with: .color(.white.opacity(0.022)), lineWidth: 0.5)
    }

    /// Corner screws and a fine rim give the back of the board a little depth.
    private func drawBackOfBoardTouchUps(in ctx: inout GraphicsContext) {
        guard view.side == .bottom else { return }
        for point in [
            CGPoint(x: metrics.margin * 0.46, y: metrics.margin * 0.46),
            CGPoint(x: metrics.boardSize.width - metrics.margin * 0.46, y: metrics.margin * 0.46),
            CGPoint(x: metrics.margin * 0.46, y: metrics.boardSize.height - metrics.margin * 0.46),
            CGPoint(x: metrics.boardSize.width - metrics.margin * 0.46, y: metrics.boardSize.height - metrics.margin * 0.46),
        ] {
            ctx.fill(
                Path(ellipseIn: CGRect(x: point.x - 0.14, y: point.y - 0.14, width: 0.28, height: 0.28)),
                with: .color(BoardTheme.copper.opacity(0.85))
            )
            ctx.stroke(
                Path(ellipseIn: CGRect(x: point.x - 0.14, y: point.y - 0.14, width: 0.28, height: 0.28)),
                with: .color(BoardTheme.copperShadow.opacity(0.7)),
                lineWidth: 0.02
            )
            ctx.stroke(
                Path {
                    $0.move(to: CGPoint(x: point.x - 0.08, y: point.y))
                    $0.addLine(to: CGPoint(x: point.x + 0.08, y: point.y))
                },
                with: .color(.white.opacity(0.30)),
                lineWidth: 0.018
            )
        }
    }

    // MARK: - Copper

    private func drawCopper(in ctx: inout GraphicsContext) {
        let runs = board.copperRuns()
        let extensionLength: CGFloat = 0.70
        for run in runs {
            let y = metrics.holeCenter(hole(0, run.row)).y
            let startX = metrics.holeCenter(hole(run.startColumn, run.row)).x - extensionLength
            let endX = metrics.holeCenter(hole(run.endColumn, run.row)).x + extensionLength
            let strip = Path(
                roundedRect: CGRect(
                    x: startX,
                    y: y - metrics.stripHalfWidth,
                    width: max(0.1, endX - startX),
                    height: metrics.stripHalfWidth * 2
                ),
                cornerRadius: 0.08
            )
            ctx.fill(
                strip,
                with: .linearGradient(
                    Gradient(colors: [
                        BoardTheme.copperShadow,
                        BoardTheme.copper,
                        BoardTheme.copperHighlight,
                    ]),
                    startPoint: CGPoint(x: 0, y: y - metrics.stripHalfWidth),
                    endPoint: CGPoint(x: 0, y: y + metrics.stripHalfWidth)
                )
            )
            var highlight = Path()
            highlight.move(to: CGPoint(x: startX + 0.08, y: y - 0.10))
            highlight.addLine(to: CGPoint(x: endX - 0.08, y: y - 0.10))
            ctx.stroke(highlight, with: .color(.white.opacity(0.16)), lineWidth: 0.045)
            var shadow = Path()
            shadow.move(to: CGPoint(x: startX + 0.08, y: y + 0.14))
            shadow.addLine(to: CGPoint(x: endX - 0.08, y: y + 0.14))
            ctx.stroke(shadow, with: .color(BoardTheme.copperShadow.opacity(0.45)), lineWidth: 0.03)
        }
    }

    // MARK: - Connectivity overlay

    private func drawConnectivityOverlay(in ctx: inout GraphicsContext) {
        for net in connectivity.nets {
            let colour = BoardTheme.netColour(forNet: net.colourIndex)

            var edgesPath = Path()
            var seenPairs = Set<HolePair>()
            for edge in net.edges where edge.kind != .insulatedJumper {
                let pair = HolePair(edge.a, edge.b)
                guard seenPairs.insert(pair).inserted else { continue }
                let a = metrics.holeCenter(edge.a)
                let b = metrics.holeCenter(edge.b)
                edgesPath.move(to: a)
                edgesPath.addLine(to: b)
            }
            if !edgesPath.isEmpty {
                ctx.stroke(
                    edgesPath,
                    with: .color(colour.opacity(0.22)),
                    style: StrokeStyle(lineWidth: 0.46, lineCap: .round)
                )
            }

            var pads = Path()
            for hole in net.holes {
                let centre = metrics.holeCenter(hole)
                pads.addEllipse(in: CGRect(
                    x: centre.x - metrics.padRadius,
                    y: centre.y - metrics.padRadius,
                    width: metrics.padRadius * 2,
                    height: metrics.padRadius * 2
                ))
            }
            ctx.fill(pads, with: .color(colour.opacity(0.18)))
            ctx.stroke(pads, with: .color(colour.opacity(0.55)), lineWidth: 0.035)
        }
    }

    private struct HolePair: Hashable {
        let a: GridPoint
        let b: GridPoint

        init(_ first: GridPoint, _ second: GridPoint) {
            if first <= second {
                a = first
                b = second
            } else {
                a = second
                b = first
            }
        }
    }

    // MARK: - Holes, pins and solder

    private func drawHoles(in ctx: inout GraphicsContext) {
        var rims = Path()
        var centres = Path()
        for row in 0..<metrics.rows {
            for column in 0..<metrics.columns {
                let centre = metrics.holeCenter(hole(column, row))
                rims.addEllipse(in: CGRect(
                    x: centre.x - metrics.holeRadius - 0.035,
                    y: centre.y - metrics.holeRadius - 0.035,
                    width: (metrics.holeRadius + 0.035) * 2,
                    height: (metrics.holeRadius + 0.035) * 2
                ))
                centres.addEllipse(in: CGRect(
                    x: centre.x - metrics.holeRadius,
                    y: centre.y - metrics.holeRadius,
                    width: metrics.holeRadius * 2,
                    height: metrics.holeRadius * 2
                ))
            }
        }
        ctx.fill(rims, with: .color(view.side == .top ? BoardTheme.holeRim : BoardTheme.copperShadow))
        ctx.fill(centres, with: .color(BoardTheme.hole))
        var glints = Path()
        for row in 0..<metrics.rows {
            for column in 0..<metrics.columns {
                let centre = metrics.holeCenter(hole(column, row))
                glints.addEllipse(in: CGRect(
                    x: centre.x - metrics.holeRadius * 0.45,
                    y: centre.y - metrics.holeRadius * 0.75,
                    width: metrics.holeRadius * 0.5,
                    height: metrics.holeRadius * 0.35
                ))
            }
        }
        ctx.fill(glints, with: .color(BoardTheme.drillHighlight))
    }

    private func drawPinsFromBack(in ctx: inout GraphicsContext) {
        let solderHoles = solderHoles
        for pinHole in board.pinHoles {
            let centre = metrics.holeCenter(pinHole)
            if !solderHoles.contains(pinHole) {
                ctx.fill(
                    Path(ellipseIn: CGRect(
                        x: centre.x - 0.12,
                        y: centre.y - 0.12,
                        width: 0.24,
                        height: 0.24
                    )),
                    with: .color(BoardTheme.solder)
                )
                ctx.fill(
                    Path(ellipseIn: CGRect(
                        x: centre.x - 0.06,
                        y: centre.y - 0.07,
                        width: 0.10,
                        height: 0.10
                    )),
                    with: .color(.white.opacity(0.65))
                )
            }
        }
    }

    private var solderHoles: Set<GridPoint> {
        var result = board.solderedHoles
        for jumper in board.jumpers {
            if let start = jumper.route.first { result.insert(start) }
            if let end = jumper.route.last { result.insert(end) }
        }
        return result
    }

    private func drawSolder(in ctx: inout GraphicsContext) {
        for hole in solderHoles {
            let centre = metrics.holeCenter(hole)
            let radius = metrics.solderRadius
            let blob = Path(ellipseIn: CGRect(
                x: centre.x - radius,
                y: centre.y - radius,
                width: radius * 2,
                height: radius * 2
            ))
            ctx.fill(blob, with: .color(BoardTheme.solder))
            ctx.stroke(blob, with: .color(.black.opacity(0.35)), lineWidth: 0.035)
            let glint = Path(ellipseIn: CGRect(
                x: centre.x - radius * 0.45,
                y: centre.y - radius * 0.55,
                width: radius * 0.75,
                height: radius * 0.55
            ))
            ctx.fill(glint, with: .color(.white.opacity(0.75)))
        }
    }

    private func drawCuts(in ctx: inout GraphicsContext) {
        for hole in board.cutHoles {
            let centre = metrics.holeCenter(hole)
            let radius: CGFloat = metrics.cutRadius + 0.04
            let ring = Path(ellipseIn: CGRect(
                x: centre.x - radius,
                y: centre.y - radius,
                width: radius * 2,
                height: radius * 2
            ))
            ctx.stroke(
                ring,
                with: .color(BoardTheme.cut.opacity(0.9)),
                style: StrokeStyle(lineWidth: 0.06, lineCap: .round, dash: [0.14, 0.10])
            )
            var slash = Path()
            slash.move(to: CGPoint(x: centre.x - 0.20, y: centre.y + 0.20))
            slash.addLine(to: CGPoint(x: centre.x + 0.20, y: centre.y - 0.20))
            ctx.stroke(slash, with: .color(BoardTheme.cut), style: StrokeStyle(lineWidth: 0.075, lineCap: .round))
            for offset in [-1.0, 1.0] {
                var tick = Path()
                tick.move(to: CGPoint(x: centre.x - 0.25, y: centre.y + 0.10 * offset))
                tick.addLine(to: CGPoint(x: centre.x - 0.15, y: centre.y + 0.10 * offset))
                ctx.stroke(tick, with: .color(BoardTheme.cut.opacity(0.8)), lineWidth: 0.04)
            }
        }
    }

    // MARK: - Components

    private func drawComponents(in ctx: inout GraphicsContext) {
        for component in board.components where component.id != hiddenComponentID {
            drawComponent(component, in: &ctx)
        }
    }

    private func drawComponent(_ component: PlacedComponent, in ctx: inout GraphicsContext) {
        guard let spec = component.spec,
              let geometry = component.layoutGeometry(metrics: metrics)
        else { return }

        let bodyColor = BoardTheme.componentBody(for: spec.categoryID)
        let accent = BoardTheme.categoryAccent(for: spec.categoryID)
        let ink = BoardTheme.contrastInk(for: spec.categoryID)

        for pinHole in geometry.pinHoles {
            let pin = metrics.holeCenter(pinHole)
            let target = nearestPoint(on: geometry.bodyRect, to: pin)
            let lead = Path {
                $0.move(to: pin)
                $0.addLine(to: target)
            }
            ctx.stroke(lead, with: .color(.black.opacity(0.45)), style: StrokeStyle(lineWidth: 0.095, lineCap: .round))
            ctx.stroke(lead, with: .color(BoardTheme.solder), style: StrokeStyle(lineWidth: 0.055, lineCap: .round))
        }

        let body = Path(roundedRect: geometry.bodyRect, cornerRadius: bodyCornerRadius(for: geometry.bodyRect, layout: spec.layout))
        if spec.layout == .dualInline {
            ctx.fill(body, with: .color(bodyColor))
            ctx.stroke(body, with: .color(.black.opacity(0.8)), lineWidth: 0.035)
            // Notch and pin-one dot.
            let notchRadius: CGFloat = 0.16
            let notchX = component.flipped ? geometry.bodyRect.maxX - 0.3 : geometry.bodyRect.minX + 0.3
            let notch = Path(ellipseIn: CGRect(
                x: notchX - notchRadius,
                y: geometry.bodyRect.minY - notchRadius * 0.2,
                width: notchRadius * 2,
                height: notchRadius * 1.2
            ))
            ctx.fill(notch, with: .color(.white.opacity(0.26)))
            let dotX = component.flipped ? geometry.bodyRect.maxX - 0.28 : geometry.bodyRect.minX + 0.28
            let dot = Path(ellipseIn: CGRect(
                x: dotX - 0.055,
                y: geometry.bodyRect.minY + 0.23,
                width: 0.11,
                height: 0.11
            ))
            ctx.fill(dot, with: .color(accent))
        } else if spec.layout == .inline {
            ctx.fill(body, with: .color(bodyColor))
            ctx.stroke(body, with: .color(.black.opacity(0.75)), lineWidth: 0.03)
            let accentRect: CGRect
            if component.axis == .horizontal {
                accentRect = CGRect(
                    x: geometry.bodyRect.minX + 0.08,
                    y: geometry.bodyRect.minY + 0.08,
                    width: 0.09,
                    height: max(0.1, geometry.bodyRect.height - 0.16)
                )
            } else {
                accentRect = CGRect(
                    x: geometry.bodyRect.minX + 0.08,
                    y: geometry.bodyRect.minY + 0.08,
                    width: max(0.1, geometry.bodyRect.width - 0.16),
                    height: 0.09
                )
            }
            ctx.fill(Path(roundedRect: accentRect, cornerRadius: 0.04), with: .color(accent.opacity(0.9)))
        } else {
            ctx.fill(body, with: .color(bodyColor))
            ctx.stroke(body, with: .color(.black.opacity(0.65)), lineWidth: 0.03)
            var bands = Path()
            if component.axis == .horizontal {
                let bandWidth = max(0.07, geometry.bodyRect.width * 0.045)
                for fraction in [0.22, 0.34, 0.46] {
                    bands.addRect(CGRect(
                        x: geometry.bodyRect.minX + geometry.bodyRect.width * fraction,
                        y: geometry.bodyRect.minY,
                        width: bandWidth,
                        height: geometry.bodyRect.height
                    ))
                }
            } else {
                let bandWidth = max(0.07, geometry.bodyRect.height * 0.045)
                for fraction in [0.22, 0.34, 0.46] {
                    bands.addRect(CGRect(
                        x: geometry.bodyRect.minX,
                        y: geometry.bodyRect.minY + geometry.bodyRect.height * fraction,
                        width: geometry.bodyRect.width,
                        height: bandWidth
                    ))
                }
            }
            ctx.fill(bands, with: .color(accent.opacity(0.6)))

            if spec.isPolarised {
                let marker: CGRect
                if component.axis == .horizontal {
                    marker = CGRect(
                        x: component.flipped ? geometry.bodyRect.minX + 0.06 : geometry.bodyRect.maxX - 0.16,
                        y: geometry.bodyRect.minY + 0.04,
                        width: 0.10,
                        height: max(0.1, geometry.bodyRect.height - 0.08)
                    )
                } else {
                    marker = CGRect(
                        x: geometry.bodyRect.minX + 0.04,
                        y: component.flipped ? geometry.bodyRect.minY + 0.06 : geometry.bodyRect.maxY - 0.16,
                        width: max(0.1, geometry.bodyRect.width - 0.08),
                        height: 0.10
                    )
                }
                ctx.fill(Path(roundedRect: marker, cornerRadius: 0.03), with: .color(.white.opacity(0.72)))
            }
        }

        // A short label helps identify small parts once there is room for it.
        if geometry.bodyRect.width >= 0.75,
           geometry.bodyRect.height * transform.zoom >= 11,
           geometry.bodyRect.width * transform.zoom >= 15 {
            let fontUnits = min(
                geometry.bodyRect.height * 0.52,
                geometry.bodyRect.width * 0.9,
                0.66
            )
            let label = Text(spec.tinyName)
                .font(.system(size: fontUnits, weight: .black, design: .rounded))
                .foregroundColor(ink)
            ctx.draw(
                label,
                at: CGPoint(x: geometry.bodyRect.midX, y: geometry.bodyRect.midY),
                anchor: .center
            )
        }
    }

    private func bodyCornerRadius(for rect: CGRect, layout: ComponentLayout) -> CGFloat {
        switch layout {
        case .twoLead:
            min(rect.height / 2.0, rect.width / 2.0)
        case .inline:
            min(0.18, rect.height / 4)
        case .dualInline:
            0.18
        }
    }

    private func nearestPoint(on rect: CGRect, to point: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(point.x, rect.minX), rect.maxX),
            y: min(max(point.y, rect.minY), rect.maxY)
        )
    }

    private func drawSelection(in ctx: inout GraphicsContext) {
        guard let selectedComponentID,
              selectedComponentID != hiddenComponentID,
              let component = board.component(id: selectedComponentID),
              let geometry = component.layoutGeometry(metrics: metrics)
        else { return }

        let selectionRect = geometry.hitRect.insetBy(dx: 0.02, dy: 0.02)
        let path = Path(roundedRect: selectionRect, cornerRadius: 0.16)
        ctx.stroke(
            path,
            with: .color(BoardTheme.selection.opacity(0.95)),
            style: StrokeStyle(lineWidth: 0.055, lineCap: .round, dash: [0.14, 0.09])
        )
        for pin in geometry.pinHoles {
            let centre = metrics.holeCenter(pin)
            ctx.stroke(
                Path(ellipseIn: CGRect(x: centre.x - 0.27, y: centre.y - 0.27, width: 0.54, height: 0.54)),
                with: .color(BoardTheme.selection.opacity(0.8)),
                lineWidth: 0.04
            )
        }
    }

    // MARK: - Jumpers

    private func drawJumpers(in ctx: inout GraphicsContext) {
        for (index, jumper) in board.jumpers.enumerated() {
            drawJumper(jumper, sleeveIndex: index, opacity: 1, in: &ctx)
        }
    }

    private func drawJumper(
        _ jumper: Jumper,
        sleeveIndex: Int,
        opacity: Double,
        in ctx: inout GraphicsContext
    ) {
        let points = jumper.route.map(metrics.holeCenter)
        guard points.count >= 2 else { return }
        let route = polyline(points)

        if jumper.kind == .bare {
            ctx.stroke(
                route,
                with: .color(.black.opacity(0.42 * opacity)),
                style: StrokeStyle(lineWidth: 0.20, lineCap: .round, lineJoin: .round)
            )
            ctx.stroke(
                route,
                with: .color(BoardTheme.bareWire.opacity(opacity)),
                style: StrokeStyle(lineWidth: 0.13, lineCap: .round, lineJoin: .round)
            )
            ctx.stroke(
                route,
                with: .color(.white.opacity(0.55 * opacity)),
                style: StrokeStyle(lineWidth: 0.035, lineCap: .round, lineJoin: .round)
            )
        } else {
            let sleeveColor = BoardTheme.sleeveColour(index: sleeveIndex)
            ctx.stroke(
                route,
                with: .color(.black.opacity(0.40 * opacity)),
                style: StrokeStyle(lineWidth: 0.27, lineCap: .round, lineJoin: .round)
            )
            ctx.stroke(
                route,
                with: .color(BoardTheme.bareWire.opacity(opacity)),
                style: StrokeStyle(lineWidth: 0.17, lineCap: .round, lineJoin: .round)
            )
            let trimmed = trimPolyline(points, inset: 0.30)
            if trimmed.count >= 2 {
                let sleevePath = polyline(trimmed)
                ctx.stroke(
                    sleevePath,
                    with: .color(sleeveColor.opacity(0.95 * opacity)),
                    style: StrokeStyle(lineWidth: 0.225, lineCap: .round, lineJoin: .round)
                )
                ctx.stroke(
                    sleevePath,
                    with: .color(.white.opacity(0.28 * opacity)),
                    style: StrokeStyle(lineWidth: 0.045, lineCap: .round, lineJoin: .round)
                )
            }
        }

        // The ends of either kind of jumper are soldered to their holes.
        for endpoint in [jumper.route.first, jumper.route.last].compactMap({ $0 }) {
            let centre = metrics.holeCenter(endpoint)
            let blob = Path(ellipseIn: CGRect(
                x: centre.x - 0.21,
                y: centre.y - 0.21,
                width: 0.42,
                height: 0.42
            ))
            ctx.fill(blob, with: .color(BoardTheme.solder.opacity(0.95 * opacity)))
            ctx.fill(
                Path(ellipseIn: CGRect(
                    x: centre.x - 0.10,
                    y: centre.y - 0.12,
                    width: 0.17,
                    height: 0.12
                )),
                with: .color(.white.opacity(0.6 * opacity))
            )
        }
    }

    private func polyline(_ points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        return path
    }

    private func trimPolyline(_ points: [CGPoint], inset: CGFloat) -> [CGPoint] {
        guard points.count >= 2, inset > 0 else { return points }
        var result = points

        var remaining = inset
        var startIndex = 0
        var startPoint = points[0]
        while startIndex < points.count - 1 {
            let next = points[startIndex + 1]
            let length = hypot(next.x - startPoint.x, next.y - startPoint.y)
            if length >= remaining {
                let ratio = remaining / max(length, 0.0001)
                startPoint = CGPoint(
                    x: startPoint.x + (next.x - startPoint.x) * ratio,
                    y: startPoint.y + (next.y - startPoint.y) * ratio
                )
                break
            }
            remaining -= length
            startIndex += 1
            startPoint = next
        }

        var endIndex = points.count - 1
        var endPoint = points[points.count - 1]
        remaining = inset
        while endIndex > 0 {
            let previous = points[endIndex - 1]
            let length = hypot(endPoint.x - previous.x, endPoint.y - previous.y)
            if length >= remaining {
                let ratio = remaining / max(length, 0.0001)
                endPoint = CGPoint(
                    x: endPoint.x + (previous.x - endPoint.x) * ratio,
                    y: endPoint.y + (previous.y - endPoint.y) * ratio
                )
                break
            }
            remaining -= length
            endIndex -= 1
            endPoint = previous
        }

        if startIndex > endIndex { return [] }
        result = [startPoint]
        if startIndex + 1 < endIndex {
            result.append(contentsOf: points[(startIndex + 1)..<endIndex])
        }
        if endPoint != startPoint {
            result.append(endPoint)
        }
        return result
    }

    // MARK: - Preview and hover

    private func drawPreview(in ctx: inout GraphicsContext) {
        switch preview {
        case .none:
            break
        case .paint(let tool, let holes):
            for hole in holes {
                drawHoleMarker(hole, tool: tool, in: &ctx, strong: true)
            }
        case .jumper(let kind, let route):
            let jumper = Jumper(kind: kind, route: route)
            drawJumper(jumper, sleeveIndex: board.jumpers.count, opacity: 0.62, in: &ctx)
            if let last = route.last {
                let centre = metrics.holeCenter(last)
                ctx.stroke(
                    Path(ellipseIn: CGRect(x: centre.x - 0.36, y: centre.y - 0.36, width: 0.72, height: 0.72)),
                    with: .color(tool.accent.opacity(0.9)),
                    lineWidth: 0.045
                )
            }
        case .component(let component, let valid):
            drawGhost(component, valid: valid, in: &ctx)
        }
    }

    private func drawGhost(_ component: PlacedComponent, valid: Bool, in ctx: inout GraphicsContext) {
        guard let spec = component.spec,
              let geometry = component.layoutGeometry(metrics: metrics)
        else { return }

        let tint = valid ? BoardTheme.selection : BoardTheme.invalid
        let body = Path(
            roundedRect: geometry.bodyRect,
            cornerRadius: bodyCornerRadius(for: geometry.bodyRect, layout: spec.layout)
        )
        ctx.fill(body, with: .color(tint.opacity(valid ? 0.24 : 0.18)))
        ctx.stroke(
            body,
            with: .color(tint.opacity(0.95)),
            style: StrokeStyle(lineWidth: 0.05, lineCap: .round, dash: [0.12, 0.08])
        )
        for pinHole in geometry.pinHoles {
            let centre = metrics.holeCenter(pinHole)
            ctx.fill(
                Path(ellipseIn: CGRect(x: centre.x - 0.18, y: centre.y - 0.18, width: 0.36, height: 0.36)),
                with: .color(tint.opacity(0.85))
            )
        }
        if geometry.bodyRect.width * transform.zoom > 30 {
            let label = Text(spec.shortName)
                .font(.system(size: min(0.55, geometry.bodyRect.height * 0.5), weight: .bold, design: .rounded))
                .foregroundColor(tint)
            ctx.draw(
                label,
                at: CGPoint(x: geometry.bodyRect.midX, y: geometry.bodyRect.midY),
                anchor: .center
            )
        }
    }

    private func drawHover(in ctx: inout GraphicsContext) {
        guard let hoveredHole else { return }
        drawHoleMarker(hoveredHole, tool: tool, in: &ctx, strong: false)
    }

    private func drawHoleMarker(
        _ hole: GridPoint,
        tool: EditorTool,
        in ctx: inout GraphicsContext,
        strong: Bool
    ) {
        let centre = metrics.holeCenter(hole)
        let radius = metrics.padRadius + 0.08
        let ring = Path(ellipseIn: CGRect(
            x: centre.x - radius,
            y: centre.y - radius,
            width: radius * 2,
            height: radius * 2
        ))
        let colour = tool.accent
        ctx.stroke(
            ring,
            with: .color(colour.opacity(strong ? 0.95 : 0.7)),
            style: StrokeStyle(
                lineWidth: strong ? 0.05 : 0.035,
                lineCap: .round,
                dash: strong ? [] : [0.10, 0.07]
            )
        )
        if strong {
            ctx.fill(
                Path(ellipseIn: CGRect(x: centre.x - 0.10, y: centre.y - 0.10, width: 0.20, height: 0.20)),
                with: .color(colour.opacity(0.9))
            )
        }
        if case .cut = tool {
            var slash = Path()
            slash.move(to: CGPoint(x: centre.x - 0.18, y: centre.y + 0.18))
            slash.addLine(to: CGPoint(x: centre.x + 0.18, y: centre.y - 0.18))
            ctx.stroke(slash, with: .color(colour), lineWidth: 0.04)
        }
        if case .uncut = tool {
            var plus = Path()
            plus.move(to: CGPoint(x: centre.x - 0.12, y: centre.y))
            plus.addLine(to: CGPoint(x: centre.x + 0.12, y: centre.y))
            plus.move(to: CGPoint(x: centre.x, y: centre.y - 0.12))
            plus.addLine(to: CGPoint(x: centre.x, y: centre.y + 0.12))
            ctx.stroke(plus, with: .color(colour), lineWidth: 0.04)
        }
    }
}
