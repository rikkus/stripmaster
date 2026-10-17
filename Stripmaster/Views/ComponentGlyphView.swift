import SwiftUI

/// Bold, hand-drawn symbols for every part in the palette.
///
/// SF Symbols has no resistor, capacitor or transistor, and text abbreviations
/// alone are too easy to misread. These are drawn in a 24 × 24 design space so
/// they stay crisp at any palette size.
struct ComponentGlyphView: View {
    let glyph: ComponentGlyph
    let categoryID: String
    var size: CGFloat = 30

    var body: some View {
        Canvas { context, canvasSize in
            var ctx = context
            let scale = min(canvasSize.width, canvasSize.height) / 24
            ctx.scaleBy(x: scale, y: scale)
            GlyphArtwork(
                ink: .primary,
                accent: BoardTheme.categoryAccent(for: categoryID)
            ).draw(glyph, in: &ctx)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

private struct GlyphArtwork {
    let ink: Color
    let accent: Color

    private let style = StrokeStyle(lineWidth: 2.15, lineCap: .round, lineJoin: .round)

    func draw(_ glyph: ComponentGlyph, in ctx: inout GraphicsContext) {
        switch glyph {
        case .resistor:
            resistor(in: &ctx, style: .standard)
        case .powerResistor:
            resistor(in: &ctx, style: .power)
        case .photoresistor:
            resistor(in: &ctx, style: .photo)
        case .thermistor:
            resistor(in: &ctx, style: .thermistor)
        case .trimmer:
            resistor(in: &ctx, style: .trimmer)
        case .potentiometer:
            resistor(in: &ctx, style: .potentiometer)
        case .capacitor:
            capacitor(in: &ctx, style: .standard)
        case .electrolytic:
            capacitor(in: &ctx, style: .electrolytic)
        case .tantalum:
            capacitor(in: &ctx, style: .tantalum)
        case .trimmerCapacitor:
            capacitor(in: &ctx, style: .trimmer)
        case .diode:
            diode(in: &ctx, style: .standard)
        case .schottky:
            diode(in: &ctx, style: .schottky)
        case .zener:
            diode(in: &ctx, style: .zener)
        case .led:
            diode(in: &ctx, style: .led)
        case .photodiode:
            diode(in: &ctx, style: .photodiode)
        case .bridge:
            bridge(in: &ctx)
        case .transistorNPN:
            transistor(in: &ctx, style: .npn)
        case .transistorPNP:
            transistor(in: &ctx, style: .pnp)
        case .mosfetN:
            transistor(in: &ctx, style: .nmos)
        case .mosfetP:
            transistor(in: &ctx, style: .pmos)
        case .darlington:
            transistor(in: &ctx, style: .darlington)
        case .jfet:
            transistor(in: &ctx, style: .jfet)
        case .ujt:
            transistor(in: &ctx, style: .ujt)
        case .ic:
            chip(in: &ctx, hasOpto: false)
        case .opto:
            chip(in: &ctx, hasOpto: true)
        case .inductor:
            inductor(in: &ctx, ferrite: false)
        case .ferriteBead:
            inductor(in: &ctx, ferrite: true)
        case .transformer:
            transformer(in: &ctx)
        case .crystal:
            crystal(in: &ctx, resonator: false)
        case .resonator:
            crystal(in: &ctx, resonator: true)
        case .oscillator:
            oscillator(in: &ctx)
        case .tactileSwitch:
            switchGlyph(in: &ctx, style: .tactile)
        case .pushbutton:
            switchGlyph(in: &ctx, style: .push)
        case .toggleSwitch:
            switchGlyph(in: &ctx, style: .toggle)
        case .slideSwitch:
            switchGlyph(in: &ctx, style: .slide)
        case .dipSwitch:
            switchGlyph(in: &ctx, style: .dip)
        case .reedSwitch:
            switchGlyph(in: &ctx, style: .reed)
        case .header:
            connector(in: &ctx, style: .header)
        case .terminal:
            connector(in: &ctx, style: .terminal)
        case .jack:
            connector(in: &ctx, style: .jack)
        case .barrel:
            connector(in: &ctx, style: .barrel)
        case .socket:
            chip(in: &ctx, hasOpto: false, isSocket: true)
        case .relay:
            relay(in: &ctx)
        case .buzzer:
            buzzer(in: &ctx, speaker: false)
        case .speaker:
            buzzer(in: &ctx, speaker: true)
        case .motor:
            motor(in: &ctx)
        case .hall:
            sensor(in: &ctx, style: .hall)
        case .thermometer:
            sensor(in: &ctx, style: .temperature)
        case .tilt:
            sensor(in: &ctx, style: .tilt)
        case .pir:
            sensor(in: &ctx, style: .pir)
        case .sonar:
            sensor(in: &ctx, style: .sonar)
        case .battery:
            power(in: &ctx, style: .battery)
        case .regulator:
            power(in: &ctx, style: .regulator)
        case .fuse:
            power(in: &ctx, style: .fuse)
        case .testPoint:
            power(in: &ctx, style: .testPoint)
        case .sparkGap:
            power(in: &ctx, style: .sparkGap)
        case .link:
            power(in: &ctx, style: .link)
        }
    }

    // MARK: - Drawing helpers

    private func stroke(
        _ ctx: inout GraphicsContext,
        _ path: Path,
        color: Color? = nil,
        width: CGFloat? = nil,
        dash: [CGFloat] = []
    ) {
        var strokeStyle = style
        if let width { strokeStyle.lineWidth = width }
        strokeStyle.dash = dash
        ctx.stroke(path, with: .color(color ?? ink), style: strokeStyle)
    }

    private func fill(_ ctx: inout GraphicsContext, _ path: Path, color: Color) {
        ctx.fill(path, with: .color(color))
    }

    private func line(_ a: CGPoint, _ b: CGPoint) -> Path {
        Path {
            $0.move(to: a)
            $0.addLine(to: b)
        }
    }

    private func dot(_ center: CGPoint, _ radius: CGFloat, color: Color) -> Path {
        Path(ellipseIn: CGRect(
            x: center.x - radius,
            y: center.y - radius,
            width: radius * 2,
            height: radius * 2
        ))
    }

    private func arrowHead(
        _ tip: CGPoint,
        from direction: CGVector,
        size: CGFloat = 3.2
    ) -> Path {
        let length = max(hypot(direction.dx, direction.dy), 0.001)
        let ux = direction.dx / length
        let uy = direction.dy / length
        let px = -uy
        let py = ux
        return Path {
            $0.move(to: CGPoint(x: tip.x - ux * size + px * size * 0.65, y: tip.y - uy * size + py * size * 0.65))
            $0.addLine(to: tip)
            $0.addLine(to: CGPoint(x: tip.x - ux * size - px * size * 0.65, y: tip.y - uy * size - py * size * 0.65))
        }
    }

    private func arcArrow(
        _ ctx: inout GraphicsContext,
        center: CGPoint,
        radius: CGFloat,
        from start: Double,
        to end: Double,
        color: Color
    ) {
        var path = Path()
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(start),
            endAngle: .degrees(end),
            clockwise: false
        )
        stroke(&ctx, path, color: color, width: 1.9)
        let tip = CGPoint(
            x: center.x + cos(end * .pi / 180) * radius,
            y: center.y + sin(end * .pi / 180) * radius
        )
        let direction = CGVector(
            dx: -sin(end * .pi / 180),
            dy: cos(end * .pi / 180)
        )
        fill(&ctx, arrowHead(tip, from: direction, size: 2.6), color: color)
    }

    // MARK: - Passive components

    private enum ResistorStyle { case standard, power, photo, thermistor, trimmer, potentiometer }

    private func resistor(in ctx: inout GraphicsContext, style: ResistorStyle) {
        stroke(&ctx, line(CGPoint(x: 2.5, y: 12), CGPoint(x: 7, y: 12)))
        stroke(&ctx, line(CGPoint(x: 17, y: 12), CGPoint(x: 21.5, y: 12)))

        switch style {
        case .standard, .photo, .thermistor:
            var zigzag = Path()
            zigzag.move(to: CGPoint(x: 7, y: 12))
            zigzag.addLine(to: CGPoint(x: 8.4, y: 7.3))
            zigzag.addLine(to: CGPoint(x: 10.8, y: 16.7))
            zigzag.addLine(to: CGPoint(x: 13.2, y: 7.3))
            zigzag.addLine(to: CGPoint(x: 15.6, y: 16.7))
            zigzag.addLine(to: CGPoint(x: 17, y: 12))
            stroke(&ctx, zigzag)
            if style == .photo {
                stroke(&ctx, line(CGPoint(x: 5.2, y: 3.4), CGPoint(x: 8.0, y: 6.2)), color: accent)
                fill(&ctx, arrowHead(CGPoint(x: 8.2, y: 6.4), from: CGVector(dx: 1, dy: 1), size: 2.4), color: accent)
                stroke(&ctx, line(CGPoint(x: 10.5, y: 2.6), CGPoint(x: 11.2, y: 5.8)), color: accent)
                fill(&ctx, arrowHead(CGPoint(x: 11.2, y: 6.0), from: CGVector(dx: 0.2, dy: 1), size: 2.4), color: accent)
            }
            if style == .thermistor {
                stroke(&ctx, line(CGPoint(x: 18.5, y: 5), CGPoint(x: 21.5, y: 19)), color: accent)
            }
        case .power:
            let body = Path(roundedRect: CGRect(x: 6.7, y: 7.8, width: 10.6, height: 8.4), cornerRadius: 1.2)
            stroke(&ctx, body)
            stroke(&ctx, line(CGPoint(x: 8.2, y: 12), CGPoint(x: 15.8, y: 12)), color: accent, width: 2.7)
        case .trimmer:
            let body = Path(roundedRect: CGRect(x: 6.7, y: 8.4, width: 10.6, height: 7.2), cornerRadius: 1)
            stroke(&ctx, body)
            stroke(&ctx, line(CGPoint(x: 12, y: 3.4), CGPoint(x: 12, y: 7.8)), color: accent)
            fill(&ctx, arrowHead(CGPoint(x: 12, y: 8.2), from: CGVector(dx: 0, dy: 1), size: 2.6), color: accent)
            stroke(&ctx, line(CGPoint(x: 8, y: 5), CGPoint(x: 16, y: 5)), color: accent, width: 1.6)
        case .potentiometer:
            let body = Path(roundedRect: CGRect(x: 6.7, y: 8.4, width: 10.6, height: 7.2), cornerRadius: 1)
            stroke(&ctx, body)
            stroke(&ctx, dot(CGPoint(x: 12, y: 12), 2.9, color: accent))
            fill(&ctx, dot(CGPoint(x: 12, y: 12), 1.1, color: accent), color: accent)
            stroke(&ctx, line(CGPoint(x: 12, y: 4), CGPoint(x: 12, y: 8.2)), color: accent)
        }
    }

    private enum CapacitorStyle { case standard, electrolytic, tantalum, trimmer }

    private func capacitor(in ctx: inout GraphicsContext, style: CapacitorStyle) {
        stroke(&ctx, line(CGPoint(x: 2.5, y: 12), CGPoint(x: 9, y: 12)))
        stroke(&ctx, line(CGPoint(x: 15, y: 12), CGPoint(x: 21.5, y: 12)))

        switch style {
        case .standard:
            stroke(&ctx, line(CGPoint(x: 9, y: 5.5), CGPoint(x: 9, y: 18.5)), width: 2.6)
            stroke(&ctx, line(CGPoint(x: 15, y: 5.5), CGPoint(x: 15, y: 18.5)), width: 2.6)
        case .electrolytic:
            stroke(&ctx, line(CGPoint(x: 9.4, y: 5.5), CGPoint(x: 9.4, y: 18.5)), width: 2.6)
            var curve = Path()
            curve.move(to: CGPoint(x: 15.2, y: 5.5))
            curve.addQuadCurve(to: CGPoint(x: 15.2, y: 18.5), control: CGPoint(x: 11.2, y: 12))
            stroke(&ctx, curve, width: 2.6)
            stroke(&ctx, line(CGPoint(x: 4.5, y: 4.8), CGPoint(x: 7.6, y: 4.8)), color: accent)
            stroke(&ctx, line(CGPoint(x: 6.05, y: 3.25), CGPoint(x: 6.05, y: 6.35)), color: accent)
        case .tantalum:
            stroke(&ctx, line(CGPoint(x: 9, y: 5.5), CGPoint(x: 9, y: 18.5)), width: 2.6)
            let plate = Path(roundedRect: CGRect(x: 13.4, y: 5.5, width: 2.4, height: 13), cornerRadius: 0.8)
            fill(&ctx, plate, color: accent)
            stroke(&ctx, line(CGPoint(x: 17, y: 5.8), CGPoint(x: 17, y: 18.2)), color: accent, width: 1.3)
            stroke(&ctx, line(CGPoint(x: 4.5, y: 4.8), CGPoint(x: 7.6, y: 4.8)), color: accent)
            stroke(&ctx, line(CGPoint(x: 6.05, y: 3.25), CGPoint(x: 6.05, y: 6.35)), color: accent)
        case .trimmer:
            stroke(&ctx, line(CGPoint(x: 9, y: 6.2), CGPoint(x: 9, y: 17.8)), width: 2.6)
            stroke(&ctx, line(CGPoint(x: 15, y: 6.2), CGPoint(x: 15, y: 17.8)), width: 2.6)
            stroke(&ctx, line(CGPoint(x: 7.2, y: 18.5), CGPoint(x: 16.8, y: 3.5)), color: accent)
            fill(&ctx, arrowHead(CGPoint(x: 17.0, y: 3.2), from: CGVector(dx: 1, dy: -1.5), size: 2.6), color: accent)
        }
    }

    private enum DiodeStyle { case standard, schottky, zener, led, photodiode }

    private func diode(in ctx: inout GraphicsContext, style: DiodeStyle) {
        stroke(&ctx, line(CGPoint(x: 2.5, y: 12), CGPoint(x: 8.5, y: 12)))
        stroke(&ctx, line(CGPoint(x: 16, y: 12), CGPoint(x: 21.5, y: 12)))

        let triangle = Path {
            $0.move(to: CGPoint(x: 8.5, y: 5.8))
            $0.addLine(to: CGPoint(x: 8.5, y: 18.2))
            $0.addLine(to: CGPoint(x: 16, y: 12))
            $0.closeSubpath()
        }
        fill(&ctx, triangle, color: accent)

        switch style {
        case .standard:
            stroke(&ctx, line(CGPoint(x: 16, y: 5.8), CGPoint(x: 16, y: 18.2)), width: 2.4)
        case .schottky:
            var bar = Path()
            bar.move(to: CGPoint(x: 13.8, y: 5.4))
            bar.addLine(to: CGPoint(x: 16, y: 5.4))
            bar.addLine(to: CGPoint(x: 16, y: 18.6))
            bar.addLine(to: CGPoint(x: 18.2, y: 18.6))
            stroke(&ctx, bar, width: 2.2)
        case .zener:
            var bar = Path()
            bar.move(to: CGPoint(x: 13.8, y: 7))
            bar.addLine(to: CGPoint(x: 16, y: 5.4))
            bar.addLine(to: CGPoint(x: 16, y: 18.6))
            bar.addLine(to: CGPoint(x: 18.2, y: 17))
            stroke(&ctx, bar, width: 2.2)
        case .led:
            stroke(&ctx, line(CGPoint(x: 16, y: 5.8), CGPoint(x: 16, y: 18.2)), width: 2.4)
            stroke(&ctx, line(CGPoint(x: 17.4, y: 7.5), CGPoint(x: 21.2, y: 3.7)), color: ink, width: 1.8)
            fill(&ctx, arrowHead(CGPoint(x: 21.5, y: 3.4), from: CGVector(dx: 1, dy: -1), size: 2.3), color: ink)
            stroke(&ctx, line(CGPoint(x: 19.6, y: 9.7), CGPoint(x: 23.2, y: 6.1)), color: ink, width: 1.8)
            fill(&ctx, arrowHead(CGPoint(x: 23.4, y: 5.9), from: CGVector(dx: 1, dy: -1), size: 2.3), color: ink)
        case .photodiode:
            stroke(&ctx, line(CGPoint(x: 16, y: 5.8), CGPoint(x: 16, y: 18.2)), width: 2.4)
            stroke(&ctx, line(CGPoint(x: 4.0, y: 3.8), CGPoint(x: 7.4, y: 6.4)), color: ink, width: 1.8)
            fill(&ctx, arrowHead(CGPoint(x: 7.8, y: 6.7), from: CGVector(dx: 1, dy: 0.7), size: 2.3), color: ink)
            stroke(&ctx, line(CGPoint(x: 8.2, y: 2.6), CGPoint(x: 10.4, y: 5.4)), color: ink, width: 1.8)
            fill(&ctx, arrowHead(CGPoint(x: 10.7, y: 5.8), from: CGVector(dx: 0.6, dy: 1), size: 2.3), color: ink)
        }
    }

    private func bridge(in ctx: inout GraphicsContext) {
        let rect = Path(roundedRect: CGRect(x: 5, y: 5, width: 14, height: 14), cornerRadius: 1.8)
        stroke(&ctx, rect)
        stroke(&ctx, line(CGPoint(x: 12, y: 2), CGPoint(x: 12, y: 5)))
        stroke(&ctx, line(CGPoint(x: 12, y: 19), CGPoint(x: 12, y: 22)))
        stroke(&ctx, line(CGPoint(x: 2, y: 12), CGPoint(x: 5, y: 12)))
        stroke(&ctx, line(CGPoint(x: 19, y: 12), CGPoint(x: 22, y: 12)))
        var mid = Path()
        mid.move(to: CGPoint(x: 8.2, y: 8.2))
        mid.addLine(to: CGPoint(x: 15.8, y: 15.8))
        mid.move(to: CGPoint(x: 15.8, y: 8.2))
        mid.addLine(to: CGPoint(x: 8.2, y: 15.8))
        stroke(&ctx, mid, color: accent, width: 1.9)
    }

    private enum TransistorStyle { case npn, pnp, nmos, pmos, darlington, jfet, ujt }

    private func transistor(in ctx: inout GraphicsContext, style: TransistorStyle) {
        switch style {
        case .npn, .pnp, .darlington:
            stroke(&ctx, dot(CGPoint(x: 12, y: 12), 8, color: ink))
            stroke(&ctx, line(CGPoint(x: 7.5, y: 6.6), CGPoint(x: 7.5, y: 17.4)), color: ink, width: 2.4)
            stroke(&ctx, line(CGPoint(x: 7.5, y: 9.6), CGPoint(x: 16.5, y: 4.6)))
            stroke(&ctx, line(CGPoint(x: 7.5, y: 14.4), CGPoint(x: 16.5, y: 19.4)))
            let direction: CGVector = style == .pnp
                ? CGVector(dx: -1, dy: 1)
                : CGVector(dx: 1, dy: -1)
            let emitterTip = style == .pnp
                ? CGPoint(x: 10.4, y: 12.3)
                : CGPoint(x: 13.4, y: 16.7)
            fill(&ctx, arrowHead(emitterTip, from: direction, size: 2.7), color: accent)
            if style == .darlington {
                stroke(&ctx, line(CGPoint(x: 13.5, y: 10.6), CGPoint(x: 18.5, y: 7.4)), color: accent, width: 1.7)
            }
        case .nmos, .pmos:
            stroke(&ctx, dot(CGPoint(x: 12, y: 12), 8, color: ink))
            stroke(&ctx, line(CGPoint(x: 7, y: 6), CGPoint(x: 7, y: 18)), color: ink, width: 2)
            stroke(&ctx, line(CGPoint(x: 9.6, y: 6), CGPoint(x: 9.6, y: 18)), color: ink, width: 2.6)
            stroke(&ctx, line(CGPoint(x: 9.6, y: 8.5), CGPoint(x: 17, y: 8.5)))
            stroke(&ctx, line(CGPoint(x: 9.6, y: 12), CGPoint(x: 17, y: 12)))
            stroke(&ctx, line(CGPoint(x: 9.6, y: 15.5), CGPoint(x: 17, y: 15.5)))
            let direction: CGVector = style == .pmos ? CGVector(dx: -1, dy: 0) : CGVector(dx: 1, dy: 0)
            fill(&ctx, arrowHead(CGPoint(x: 12.8, y: 12), from: direction, size: 2.5), color: accent)
        case .jfet:
            stroke(&ctx, dot(CGPoint(x: 12, y: 12), 8, color: ink))
            stroke(&ctx, line(CGPoint(x: 9.5, y: 5.5), CGPoint(x: 9.5, y: 18.5)), color: ink, width: 2.4)
            stroke(&ctx, line(CGPoint(x: 9.5, y: 9.5), CGPoint(x: 17, y: 5.5)))
            stroke(&ctx, line(CGPoint(x: 9.5, y: 14.5), CGPoint(x: 17, y: 18.5)))
            fill(&ctx, arrowHead(CGPoint(x: 12.6, y: 12), from: CGVector(dx: -1, dy: 0), size: 2.5), color: accent)
        case .ujt:
            stroke(&ctx, dot(CGPoint(x: 12, y: 12), 8, color: ink))
            stroke(&ctx, line(CGPoint(x: 7.5, y: 7), CGPoint(x: 16.5, y: 17)), color: ink)
            stroke(&ctx, line(CGPoint(x: 16.5, y: 17), CGPoint(x: 19, y: 18.6)), color: ink)
            stroke(&ctx, line(CGPoint(x: 9.5, y: 15.8), CGPoint(x: 12.8, y: 8.6)), color: accent)
            fill(&ctx, arrowHead(CGPoint(x: 13.1, y: 7.9), from: CGVector(dx: 1, dy: -1.5), size: 2.5), color: accent)
        }
    }

    private func chip(in ctx: inout GraphicsContext, hasOpto: Bool, isSocket: Bool = false) {
        let body = Path(roundedRect: CGRect(x: 5.5, y: 6, width: 13, height: 12), cornerRadius: 1.6)
        if isSocket {
            stroke(&ctx, body)
        } else {
            fill(&ctx, body, color: ink)
        }
        for x in [8, 11.3, 14.6, 17.9] {
            stroke(&ctx, line(CGPoint(x: x, y: 3), CGPoint(x: x, y: 6)), width: 1.7)
            stroke(&ctx, line(CGPoint(x: x, y: 18), CGPoint(x: x, y: 21)), width: 1.7)
        }
        if isSocket {
            for x in [8, 11.3, 14.6, 17.9] {
                stroke(&ctx, dot(CGPoint(x: x, y: 8.2), 0.8, color: ink), width: 1.2)
                stroke(&ctx, dot(CGPoint(x: x, y: 15.8), 0.8, color: ink), width: 1.2)
            }
        } else {
            fill(&ctx, dot(CGPoint(x: 8.2, y: 8.7), 1.0, color: isSocket ? ink : .primary), color: isSocket ? ink : .white)
            if hasOpto {
                stroke(&ctx, line(CGPoint(x: 12, y: 9.6), CGPoint(x: 16.5, y: 9.6)), color: accent, width: 1.6)
                stroke(&ctx, line(CGPoint(x: 12, y: 14.4), CGPoint(x: 16.5, y: 14.4)), color: accent, width: 1.6)
                stroke(&ctx, dot(CGPoint(x: 10.4, y: 12), 1.4, color: accent), color: accent, width: 1.2)
            } else {
                stroke(&ctx, line(CGPoint(x: 8.2, y: 12), CGPoint(x: 15.8, y: 12)), color: .white.opacity(0.7), width: 1.2)
            }
        }
    }

    private func inductor(in ctx: inout GraphicsContext, ferrite: Bool) {
        stroke(&ctx, line(CGPoint(x: 2.5, y: 12), CGPoint(x: 6, y: 12)))
        stroke(&ctx, line(CGPoint(x: 18, y: 12), CGPoint(x: 21.5, y: 12)))
        var coil = Path()
        coil.move(to: CGPoint(x: 6, y: 12))
        coil.addQuadCurve(to: CGPoint(x: 9.4, y: 12), control: CGPoint(x: 7.7, y: 5.8))
        coil.addQuadCurve(to: CGPoint(x: 12.8, y: 12), control: CGPoint(x: 11.1, y: 5.8))
        coil.addQuadCurve(to: CGPoint(x: 16.2, y: 12), control: CGPoint(x: 14.5, y: 5.8))
        coil.addQuadCurve(to: CGPoint(x: 18, y: 12), control: CGPoint(x: 17.1, y: 7.6))
        stroke(&ctx, coil)
        if ferrite {
            let bead = Path(roundedRect: CGRect(x: 8.2, y: 4.5, width: 7.6, height: 4.2), cornerRadius: 1.2)
            fill(&ctx, bead, color: accent)
        }
    }

    private func transformer(in ctx: inout GraphicsContext) {
        var left = Path()
        left.move(to: CGPoint(x: 7, y: 7))
        left.addQuadCurve(to: CGPoint(x: 7, y: 11), control: CGPoint(x: 2.8, y: 9))
        left.addQuadCurve(to: CGPoint(x: 7, y: 15), control: CGPoint(x: 2.8, y: 13))
        left.addQuadCurve(to: CGPoint(x: 7, y: 19), control: CGPoint(x: 2.8, y: 17))
        stroke(&ctx, left)
        var right = Path()
        right.move(to: CGPoint(x: 17, y: 7))
        right.addQuadCurve(to: CGPoint(x: 17, y: 11), control: CGPoint(x: 21.2, y: 9))
        right.addQuadCurve(to: CGPoint(x: 17, y: 15), control: CGPoint(x: 21.2, y: 13))
        right.addQuadCurve(to: CGPoint(x: 17, y: 19), control: CGPoint(x: 21.2, y: 17))
        stroke(&ctx, right)
        stroke(&ctx, line(CGPoint(x: 11, y: 5), CGPoint(x: 11, y: 19)), width: 1.4)
        stroke(&ctx, line(CGPoint(x: 13, y: 5), CGPoint(x: 13, y: 19)), width: 1.4)
        fill(&ctx, dot(CGPoint(x: 11, y: 6), 1.0, color: accent), color: accent)
        fill(&ctx, dot(CGPoint(x: 13, y: 18), 1.0, color: accent), color: accent)
    }

    private func crystal(in ctx: inout GraphicsContext, resonator: Bool) {
        stroke(&ctx, line(CGPoint(x: 2.5, y: 12), CGPoint(x: 7, y: 12)))
        stroke(&ctx, line(CGPoint(x: 17, y: 12), CGPoint(x: 21.5, y: 12)))
        if resonator {
            stroke(&ctx, line(CGPoint(x: 7, y: 12), CGPoint(x: 8.2, y: 12)))
            stroke(&ctx, line(CGPoint(x: 15.8, y: 12), CGPoint(x: 17, y: 12)))
            stroke(&ctx, line(CGPoint(x: 9.2, y: 6), CGPoint(x: 9.2, y: 18)), width: 2.4)
            stroke(&ctx, line(CGPoint(x: 14.8, y: 6), CGPoint(x: 14.8, y: 18)), width: 2.4)
            let center = Path(roundedRect: CGRect(x: 10.3, y: 7.2, width: 3.4, height: 9.6), cornerRadius: 0.8)
            fill(&ctx, center, color: accent)
        } else {
            stroke(&ctx, line(CGPoint(x: 8.4, y: 5.5), CGPoint(x: 8.4, y: 18.5)), width: 2.4)
            stroke(&ctx, line(CGPoint(x: 15.6, y: 5.5), CGPoint(x: 15.6, y: 18.5)), width: 2.4)
            let center = Path(roundedRect: CGRect(x: 10.2, y: 7, width: 3.6, height: 10), cornerRadius: 0.8)
            stroke(&ctx, center)
            stroke(&ctx, line(CGPoint(x: 9.8, y: 12), CGPoint(x: 10.2, y: 12)), color: accent)
            stroke(&ctx, line(CGPoint(x: 13.8, y: 12), CGPoint(x: 14.2, y: 12)), color: accent)
        }
    }

    private func oscillator(in ctx: inout GraphicsContext) {
        let body = Path(roundedRect: CGRect(x: 5, y: 7, width: 14, height: 10), cornerRadius: 1.3)
        stroke(&ctx, body)
        var wave = Path()
        wave.move(to: CGPoint(x: 7.5, y: 12))
        wave.addCurve(
            to: CGPoint(x: 12, y: 12),
            control1: CGPoint(x: 8.6, y: 7.6),
            control2: CGPoint(x: 10.9, y: 7.6)
        )
        wave.addCurve(
            to: CGPoint(x: 16.5, y: 12),
            control1: CGPoint(x: 13.1, y: 16.4),
            control2: CGPoint(x: 15.4, y: 16.4)
        )
        stroke(&ctx, wave, color: accent, width: 2.1)
        stroke(&ctx, line(CGPoint(x: 2, y: 12), CGPoint(x: 5, y: 12)), width: 1.8)
        stroke(&ctx, line(CGPoint(x: 19, y: 12), CGPoint(x: 22, y: 12)), width: 1.8)
    }

    // MARK: - Switches and connectors

    private enum SwitchStyle { case tactile, push, toggle, slide, dip, reed }

    private func switchGlyph(in ctx: inout GraphicsContext, style: SwitchStyle) {
        switch style {
        case .tactile, .push:
            stroke(&ctx, line(CGPoint(x: 4, y: 20), CGPoint(x: 20, y: 20)), width: 1.8)
            for x in [6.5, 9.5, 14.5, 17.5] {
                stroke(&ctx, line(CGPoint(x: x, y: 20), CGPoint(x: x, y: 16)), width: 1.7)
            }
            let button = Path(roundedRect: CGRect(x: 8, y: 7, width: 8, height: 5.5), cornerRadius: 2.3)
            fill(&ctx, button, color: accent)
            stroke(&ctx, line(CGPoint(x: 8, y: 15), CGPoint(x: 16, y: 15)), width: 2.5)
            stroke(&ctx, line(CGPoint(x: 12, y: 5.2), CGPoint(x: 12, y: 7)), width: 1.8)
        case .toggle:
            stroke(&ctx, line(CGPoint(x: 3, y: 17), CGPoint(x: 21, y: 17)), width: 1.6)
            fill(&ctx, dot(CGPoint(x: 7, y: 17), 1.7, color: ink), color: ink)
            fill(&ctx, dot(CGPoint(x: 17, y: 17), 1.7, color: ink), color: ink)
            stroke(&ctx, line(CGPoint(x: 7, y: 17), CGPoint(x: 18, y: 7)), color: accent, width: 2.5)
            fill(&ctx, dot(CGPoint(x: 18, y: 7), 2.0, color: accent), color: accent)
        case .slide:
            let track = Path(roundedRect: CGRect(x: 4, y: 10, width: 16, height: 4), cornerRadius: 2)
            stroke(&ctx, track)
            fill(&ctx, Path(roundedRect: CGRect(x: 12, y: 7.5, width: 5, height: 9), cornerRadius: 1.5), color: accent)
            stroke(&ctx, line(CGPoint(x: 4, y: 18), CGPoint(x: 20, y: 18)), width: 1.6)
        case .dip:
            let body = Path(roundedRect: CGRect(x: 3, y: 7, width: 18, height: 10), cornerRadius: 1.2)
            stroke(&ctx, body)
            for index in 0..<4 {
                let x = 5.0 + Double(index) * 4.2
                stroke(&ctx, line(CGPoint(x: x, y: 7), CGPoint(x: x, y: 3.5)), width: 1.5)
                stroke(&ctx, line(CGPoint(x: x, y: 17), CGPoint(x: x, y: 20.5)), width: 1.5)
                stroke(&ctx, line(CGPoint(x: x - 0.9, y: 13), CGPoint(x: x + 0.9, y: 11)), color: accent, width: 2)
            }
        case .reed:
            let capsule = Path(roundedRect: CGRect(x: 3, y: 8, width: 18, height: 8), cornerRadius: 4)
            stroke(&ctx, capsule)
            stroke(&ctx, line(CGPoint(x: 6.5, y: 12), CGPoint(x: 11, y: 12)), width: 2)
            stroke(&ctx, line(CGPoint(x: 13, y: 12), CGPoint(x: 17.5, y: 12)), width: 2)
            stroke(&ctx, line(CGPoint(x: 11, y: 12), CGPoint(x: 12.2, y: 10.5)), color: accent, width: 1.5)
            stroke(&ctx, line(CGPoint(x: 13, y: 12), CGPoint(x: 11.8, y: 13.5)), color: accent, width: 1.5)
        }
    }

    private enum ConnectorStyle { case header, terminal, jack, barrel }

    private func connector(in ctx: inout GraphicsContext, style: ConnectorStyle) {
        switch style {
        case .header:
            let base = Path(roundedRect: CGRect(x: 4, y: 7, width: 16, height: 6), cornerRadius: 1.2)
            fill(&ctx, base, color: ink)
            for x in [CGFloat(7), 12, 17] {
                stroke(&ctx, line(CGPoint(x: x, y: 13), CGPoint(x: x, y: 19)), width: 2)
                fill(&ctx, dot(CGPoint(x: x, y: 8.8), 1.15, color: accent), color: accent)
            }
        case .terminal:
            let base = Path(roundedRect: CGRect(x: 3, y: 6, width: 18, height: 12), cornerRadius: 2)
            stroke(&ctx, base)
            for x in [8.5, 15.5] {
                stroke(&ctx, dot(CGPoint(x: x, y: 12), 2.3, color: ink))
                stroke(&ctx, line(CGPoint(x: x - 1.2, y: 12), CGPoint(x: x + 1.2, y: 12)), width: 1.2)
                stroke(&ctx, line(CGPoint(x: x, y: 10.8), CGPoint(x: x, y: 13.2)), width: 1.2)
                stroke(&ctx, line(CGPoint(x: x, y: 18), CGPoint(x: x, y: 22)), width: 1.5)
            }
        case .jack:
            stroke(&ctx, line(CGPoint(x: 2, y: 15), CGPoint(x: 5, y: 15)), width: 1.8)
            let outer = Path(roundedRect: CGRect(x: 5, y: 4, width: 14, height: 16), cornerRadius: 3.5)
            stroke(&ctx, outer)
            stroke(&ctx, dot(CGPoint(x: 12, y: 12), 4.2, color: ink))
            fill(&ctx, dot(CGPoint(x: 12, y: 12), 1.4, color: accent), color: accent)
        case .barrel:
            stroke(&ctx, dot(CGPoint(x: 10, y: 12), 7, color: ink))
            fill(&ctx, dot(CGPoint(x: 10, y: 12), 2.2, color: ink), color: ink)
            stroke(&ctx, line(CGPoint(x: 17, y: 8), CGPoint(x: 22, y: 8)), width: 2)
            stroke(&ctx, line(CGPoint(x: 17, y: 16), CGPoint(x: 22, y: 16)), width: 2)
            stroke(&ctx, line(CGPoint(x: 22, y: 8), CGPoint(x: 22, y: 16)), width: 2)
        }
    }

    private func relay(in ctx: inout GraphicsContext) {
        let coil = Path(roundedRect: CGRect(x: 3, y: 12, width: 8, height: 7), cornerRadius: 1.2)
        stroke(&ctx, coil)
        stroke(&ctx, line(CGPoint(x: 4.5, y: 16), CGPoint(x: 4.5, y: 18.2)), color: accent, width: 1.4)
        stroke(&ctx, line(CGPoint(x: 7, y: 16), CGPoint(x: 7, y: 18.2)), color: accent, width: 1.4)
        stroke(&ctx, line(CGPoint(x: 9.5, y: 16), CGPoint(x: 9.5, y: 18.2)), color: accent, width: 1.4)
        stroke(&ctx, line(CGPoint(x: 2, y: 15), CGPoint(x: 3, y: 15)), width: 2)
        stroke(&ctx, line(CGPoint(x: 11, y: 15), CGPoint(x: 12, y: 15)), width: 2)
        fill(&ctx, dot(CGPoint(x: 15, y: 14), 1.7, color: ink), color: ink)
        fill(&ctx, dot(CGPoint(x: 21, y: 14), 1.7, color: ink), color: ink)
        stroke(&ctx, line(CGPoint(x: 15, y: 14), CGPoint(x: 21, y: 7)), color: accent, width: 2.2)
        stroke(&ctx, line(CGPoint(x: 15, y: 14), CGPoint(x: 21, y: 20)), width: 1.3)
    }

    private func buzzer(in ctx: inout GraphicsContext, speaker: Bool) {
        if speaker {
            var cone = Path()
            cone.move(to: CGPoint(x: 4, y: 9))
            cone.addLine(to: CGPoint(x: 9, y: 9))
            cone.addLine(to: CGPoint(x: 14, y: 4))
            cone.addLine(to: CGPoint(x: 14, y: 20))
            cone.addLine(to: CGPoint(x: 9, y: 15))
            cone.addLine(to: CGPoint(x: 4, y: 15))
            cone.closeSubpath()
            stroke(&ctx, cone)
            arcArrow(&ctx, center: CGPoint(x: 16, y: 12), radius: 4, from: -55, to: 55, color: accent)
            arcArrow(&ctx, center: CGPoint(x: 16, y: 12), radius: 7, from: -50, to: 50, color: accent)
        } else {
            var dome = Path()
            dome.move(to: CGPoint(x: 4, y: 18))
            dome.addLine(to: CGPoint(x: 4, y: 14))
            dome.addArc(center: CGPoint(x: 12, y: 14), radius: 8, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
            dome.addLine(to: CGPoint(x: 20, y: 18))
            dome.closeSubpath()
            stroke(&ctx, dome)
            fill(&ctx, dot(CGPoint(x: 12, y: 14), 2.2, color: accent), color: accent)
            stroke(&ctx, line(CGPoint(x: 2, y: 21), CGPoint(x: 22, y: 21)), width: 1.8)
        }
    }

    private func motor(in ctx: inout GraphicsContext) {
        stroke(&ctx, dot(CGPoint(x: 12, y: 12), 8, color: ink))
        var m = Path()
        m.move(to: CGPoint(x: 7.5, y: 16))
        m.addLine(to: CGPoint(x: 7.5, y: 8))
        m.addLine(to: CGPoint(x: 12, y: 13))
        m.addLine(to: CGPoint(x: 16.5, y: 8))
        m.addLine(to: CGPoint(x: 16.5, y: 16))
        stroke(&ctx, m, color: accent, width: 2.3)
    }

    // MARK: - Sensors and power

    private enum SensorStyle { case hall, temperature, tilt, pir, sonar }

    private func sensor(in ctx: inout GraphicsContext, style: SensorStyle) {
        switch style {
        case .hall:
            let body = Path(roundedRect: CGRect(x: 5, y: 7, width: 8, height: 12), cornerRadius: 1.4)
            stroke(&ctx, body)
            stroke(&ctx, line(CGPoint(x: 13, y: 10), CGPoint(x: 19, y: 7.5)), width: 1.7)
            stroke(&ctx, line(CGPoint(x: 13, y: 14), CGPoint(x: 19, y: 14)), width: 1.7)
            stroke(&ctx, line(CGPoint(x: 13, y: 18), CGPoint(x: 19, y: 20.5)), width: 1.7)
            stroke(&ctx, line(CGPoint(x: 6, y: 21), CGPoint(x: 12, y: 21)), width: 1.6)
            fill(&ctx, dot(CGPoint(x: 9, y: 11), 1.2, color: accent), color: accent)
        case .temperature:
            stroke(&ctx, dot(CGPoint(x: 12, y: 18.5), 3.4, color: ink))
            stroke(&ctx, line(CGPoint(x: 12, y: 5), CGPoint(x: 12, y: 15.4)), width: 2.4)
            stroke(&ctx, line(CGPoint(x: 12, y: 7), CGPoint(x: 12, y: 12)), color: accent, width: 1.3)
            stroke(&ctx, line(CGPoint(x: 15, y: 8), CGPoint(x: 18, y: 8)), width: 1.3)
            stroke(&ctx, line(CGPoint(x: 15, y: 11), CGPoint(x: 18, y: 11)), width: 1.3)
        case .tilt:
            let tube = Path(roundedRect: CGRect(x: 3, y: 8, width: 18, height: 8), cornerRadius: 4)
            stroke(&ctx, tube)
            fill(&ctx, dot(CGPoint(x: 8, y: 12), 2.1, color: accent), color: accent)
            stroke(&ctx, line(CGPoint(x: 14, y: 12), CGPoint(x: 18, y: 12)), width: 1.8)
        case .pir:
            var dome = Path()
            dome.move(to: CGPoint(x: 4, y: 18))
            dome.addArc(center: CGPoint(x: 12, y: 18), radius: 8, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
            dome.closeSubpath()
            stroke(&ctx, dome)
            arcArrow(&ctx, center: CGPoint(x: 12, y: 18), radius: 4.3, from: -70, to: -30, color: accent)
            stroke(&ctx, line(CGPoint(x: 4, y: 21), CGPoint(x: 20, y: 21)), width: 1.8)
        case .sonar:
            fill(&ctx, dot(CGPoint(x: 7, y: 17), 1.8, color: accent), color: accent)
            arcArrow(&ctx, center: CGPoint(x: 7, y: 17), radius: 5, from: -80, to: 0, color: ink)
            arcArrow(&ctx, center: CGPoint(x: 7, y: 17), radius: 9, from: -80, to: 0, color: ink)
            stroke(&ctx, line(CGPoint(x: 7, y: 21), CGPoint(x: 7, y: 23)), width: 1.4)
        }
    }

    private enum PowerStyle { case battery, regulator, fuse, testPoint, sparkGap, link }

    private func power(in ctx: inout GraphicsContext, style: PowerStyle) {
        switch style {
        case .battery:
            stroke(&ctx, line(CGPoint(x: 2, y: 12), CGPoint(x: 7, y: 12)), width: 1.8)
            stroke(&ctx, line(CGPoint(x: 17, y: 12), CGPoint(x: 22, y: 12)), width: 1.8)
            stroke(&ctx, line(CGPoint(x: 8, y: 6), CGPoint(x: 8, y: 18)), width: 2.6)
            stroke(&ctx, line(CGPoint(x: 12, y: 8), CGPoint(x: 12, y: 16)), width: 2)
            stroke(&ctx, line(CGPoint(x: 16, y: 6), CGPoint(x: 16, y: 18)), width: 2.6)
            stroke(&ctx, line(CGPoint(x: 14, y: 8), CGPoint(x: 14, y: 16)), width: 2)
            stroke(&ctx, line(CGPoint(x: 19, y: 8), CGPoint(x: 21, y: 8)), color: accent)
            stroke(&ctx, line(CGPoint(x: 20, y: 7), CGPoint(x: 20, y: 9)), color: accent)
        case .regulator:
            let body = Path(roundedRect: CGRect(x: 5, y: 6, width: 14, height: 9), cornerRadius: 1)
            fill(&ctx, body, color: ink)
            stroke(&ctx, line(CGPoint(x: 7, y: 15), CGPoint(x: 7, y: 20)), width: 2)
            stroke(&ctx, line(CGPoint(x: 12, y: 15), CGPoint(x: 12, y: 20)), width: 2)
            stroke(&ctx, line(CGPoint(x: 17, y: 15), CGPoint(x: 17, y: 20)), width: 2)
            stroke(&ctx, line(CGPoint(x: 8, y: 9), CGPoint(x: 16, y: 9)), color: accent, width: 1.4)
            stroke(&ctx, line(CGPoint(x: 8, y: 12), CGPoint(x: 16, y: 12)), color: accent, width: 1.4)
        case .fuse:
            let body = Path(roundedRect: CGRect(x: 5, y: 8, width: 14, height: 8), cornerRadius: 3)
            stroke(&ctx, body)
            stroke(&ctx, line(CGPoint(x: 2, y: 12), CGPoint(x: 5, y: 12)), width: 1.8)
            stroke(&ctx, line(CGPoint(x: 19, y: 12), CGPoint(x: 22, y: 12)), width: 1.8)
            var filament = Path()
            filament.move(to: CGPoint(x: 7, y: 12))
            filament.addCurve(
                to: CGPoint(x: 17, y: 12),
                control1: CGPoint(x: 9, y: 8),
                control2: CGPoint(x: 15, y: 16)
            )
            stroke(&ctx, filament, color: accent, width: 1.8)
        case .testPoint:
            stroke(&ctx, line(CGPoint(x: 4, y: 20), CGPoint(x: 15, y: 9)), width: 2)
            stroke(&ctx, dot(CGPoint(x: 16, y: 8), 3.3, color: ink), width: 2.1)
            fill(&ctx, dot(CGPoint(x: 18.2, y: 5.8), 1.0, color: accent), color: accent)
        case .sparkGap:
            stroke(&ctx, line(CGPoint(x: 2, y: 18), CGPoint(x: 8, y: 18)), width: 2)
            stroke(&ctx, line(CGPoint(x: 8, y: 18), CGPoint(x: 10, y: 14)), width: 2)
            stroke(&ctx, line(CGPoint(x: 22, y: 18), CGPoint(x: 16, y: 18)), width: 2)
            stroke(&ctx, line(CGPoint(x: 16, y: 18), CGPoint(x: 14, y: 14)), width: 2)
            var spark = Path()
            spark.move(to: CGPoint(x: 12, y: 6))
            spark.addLine(to: CGPoint(x: 10.3, y: 10))
            spark.addLine(to: CGPoint(x: 13, y: 9.4))
            spark.addLine(to: CGPoint(x: 11.3, y: 13.5))
            stroke(&ctx, spark, color: accent, width: 1.8)
        case .link:
            fill(&ctx, Path(roundedRect: CGRect(x: 7, y: 10.3, width: 10, height: 3.4), cornerRadius: 1.7), color: accent)
            fill(&ctx, dot(CGPoint(x: 6, y: 12), 2.4, color: ink), color: ink)
            fill(&ctx, dot(CGPoint(x: 18, y: 12), 2.4, color: ink), color: ink)
            stroke(&ctx, line(CGPoint(x: 2, y: 12), CGPoint(x: 4, y: 12)), width: 1.8)
            stroke(&ctx, line(CGPoint(x: 20, y: 12), CGPoint(x: 22, y: 12)), width: 1.8)
        }
    }
}
