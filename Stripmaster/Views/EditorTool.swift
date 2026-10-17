import SwiftUI

/// The active editing tool. This is window state, not document state, and is
/// deliberately not persisted.
enum EditorTool: Hashable {
    case select
    case pan
    case cut
    case uncut
    case solder
    case unsolder
    case jumper(JumperKind)
    case place(ComponentReference)

    static let stripTools: [EditorTool] = [
        .select,
        .pan,
        .cut,
        .uncut,
        .solder,
        .unsolder,
        .jumper(.bare),
        .jumper(.insulated),
    ]

    var displayName: String {
        switch self {
        case .select: "Select"
        case .pan: "Pan"
        case .cut: "Cut"
        case .uncut: "Uncut"
        case .solder: "Solder"
        case .unsolder: "Unsolder"
        case .jumper(.bare): "Wire"
        case .jumper(.insulated): "Sleeved"
        case .place(let reference): ComponentCatalogue.spec(for: reference)?.shortName ?? "Place"
        }
    }

    var systemImage: String? {
        switch self {
        case .select: "cursorarrow"
        case .pan: "hand.draw"
        case .cut: "scissors"
        case .uncut: "arrow.uturn.backward"
        case .solder: "drop.fill"
        case .unsolder: "drop"
        case .jumper: nil
        case .place: "plus.square"
        }
    }

    var accent: Color {
        switch self {
        case .select, .place: BoardTheme.selection
        case .pan: Color(red: 0.62, green: 0.67, blue: 0.70)
        case .cut: BoardTheme.cut
        case .uncut: BoardTheme.valid
        case .solder: Color(red: 1.0, green: 0.82, blue: 0.38)
        case .unsolder: Color(red: 0.58, green: 0.66, blue: 0.72)
        case .jumper(.bare): BoardTheme.bareWire
        case .jumper(.insulated): Color(red: 1.0, green: 0.63, blue: 0.26)
        }
    }

    var help: String {
        switch self {
        case .select:
            return "Select a component. Drag empty space to pan."
        case .pan:
            return "Drag to pan the board."
        case .cut:
            return "Cut copper around holes to break a track. Drag across several holes."
        case .uncut:
            return "Restore copper around cut holes. Drag across several holes."
        case .solder:
            return "Solder pins or holes. Drag across several holes."
        case .unsolder:
            return "Remove solder from pins or holes. Drag across several holes."
        case .jumper(.bare):
            return "Draw a bare wire. It is conductive along its whole length."
        case .jumper(.insulated):
            return "Draw an insulated jumper. Only its two ends are conductive."
        case .place(let reference):
            if let spec = ComponentCatalogue.spec(for: reference) {
                return "Place \(spec.plainFullName). Click a hole, or drag to set its span."
            }
            return "Place a component."
        }
    }

    var accessibilityIdentifier: String {
        switch self {
        case .select: "tool.select"
        case .pan: "tool.pan"
        case .cut: "tool.cut"
        case .uncut: "tool.uncut"
        case .solder: "tool.solder"
        case .unsolder: "tool.unsolder"
        case .jumper(.bare): "tool.jumper.bare"
        case .jumper(.insulated): "tool.jumper.insulated"
        case .place(let reference): "tool.place.\(reference.id)"
        }
    }

    var isPaintTool: Bool {
        switch self {
        case .cut, .uncut, .solder, .unsolder: true
        default: false
        }
    }

    var paintValue: Bool? {
        switch self {
        case .cut, .solder: true
        case .uncut, .unsolder: false
        default: nil
        }
    }

    var jumperKind: JumperKind? {
        if case .jumper(let kind) = self { return kind }
        return nil
    }

    var placementSpec: ComponentSpec? {
        if case .place(let reference) = self {
            return ComponentCatalogue.spec(for: reference)
        }
        return nil
    }

    var isSelectionTool: Bool {
        if case .select = self { return true }
        return false
    }

    var isPanTool: Bool {
        if case .pan = self { return true }
        return false
    }
}

/// The tool strip needs a custom glyph for the two jumper types.
struct JumperToolIcon: View {
    let kind: JumperKind
    var size: CGFloat = 16

    var body: some View {
        Canvas { context, canvasSize in
            let rect = CGRect(origin: .zero, size: canvasSize).insetBy(dx: 2.5, dy: 2.5)
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY - 1))
            path.addLine(to: CGPoint(x: rect.midX - 1, y: rect.maxY - 1))
            path.addLine(to: CGPoint(x: rect.midX - 1, y: rect.minY + 1))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + 1))
            context.stroke(
                path,
                with: .foreground,
                style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round)
            )
            let start = CGPoint(x: rect.minX, y: rect.maxY - 1)
            let end = CGPoint(x: rect.maxX, y: rect.minY + 1)
            for point in [start, end] {
                context.fill(
                    Path(ellipseIn: CGRect(x: point.x - 2, y: point.y - 2, width: 4, height: 4)),
                    with: .foreground
                )
            }
            if kind == .insulated {
                let sleeve = Path {
                    $0.move(to: CGPoint(x: rect.minX + 5, y: rect.maxY - 1))
                    $0.addLine(to: CGPoint(x: rect.midX - 1, y: rect.maxY - 1))
                    $0.addLine(to: CGPoint(x: rect.midX - 1, y: rect.minY + 1))
                    $0.addLine(to: CGPoint(x: rect.maxX - 5, y: rect.minY + 1))
                }
                context.stroke(
                    sleeve,
                    with: .color(BoardTheme.categoryAccent(for: "relay")),
                    style: StrokeStyle(lineWidth: 3.4, lineCap: .round, lineJoin: .round)
                )
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
