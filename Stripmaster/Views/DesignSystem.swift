import SwiftUI

/// Visual language shared by the workspace, palette and canvas.
enum BoardTheme {
    // Workbench behind the board.
    static let workspaceTop = Color(red: 0.115, green: 0.135, blue: 0.125)
    static let workspaceBottom = Color(red: 0.055, green: 0.065, blue: 0.06)

    // Board materials.
    static let topBoard = Color(red: 0.76, green: 0.68, blue: 0.51)
    static let topBoardHighlight = Color(red: 0.83, green: 0.75, blue: 0.59)
    static let topBoardEdge = Color(red: 0.41, green: 0.35, blue: 0.24)
    static let bottomBoard = Color(red: 0.10, green: 0.31, blue: 0.22)
    static let bottomBoardHighlight = Color(red: 0.14, green: 0.38, blue: 0.27)
    static let bottomBoardEdge = Color(red: 0.04, green: 0.15, blue: 0.10)

    static let copper = Color(red: 0.83, green: 0.51, blue: 0.23)
    static let copperHighlight = Color(red: 0.96, green: 0.70, blue: 0.40)
    static let copperShadow = Color(red: 0.44, green: 0.25, blue: 0.10)

    static let hole = Color(red: 0.075, green: 0.08, blue: 0.075)
    static let holeRim = Color(red: 0.30, green: 0.27, blue: 0.20)
    static let drillHighlight = Color.white.opacity(0.12)

    static let solder = Color(red: 0.86, green: 0.88, blue: 0.90)
    static let solderHighlight = Color.white.opacity(0.9)
    static let bareWire = Color(red: 0.83, green: 0.86, blue: 0.88)
    static let bareWireShadow = Color(red: 0.23, green: 0.26, blue: 0.27)

    static let cut = Color(red: 1.0, green: 0.36, blue: 0.33)
    static let selection = Color(red: 0.35, green: 0.78, blue: 1.0)
    static let valid = Color(red: 0.38, green: 0.88, blue: 0.55)
    static let invalid = Color(red: 1.0, green: 0.36, blue: 0.33)

    static let sleeveColours: [Color] = [
        Color(red: 0.88, green: 0.19, blue: 0.22),
        Color(red: 0.15, green: 0.40, blue: 0.88),
        Color(red: 0.94, green: 0.68, blue: 0.08),
        Color(red: 0.20, green: 0.65, blue: 0.36),
        Color(red: 0.58, green: 0.30, blue: 0.80),
        Color(red: 0.94, green: 0.45, blue: 0.15),
    ]

    static func sleeveColour(index: Int) -> Color {
        sleeveColours[((index % sleeveColours.count) + sleeveColours.count) % sleeveColours.count]
    }

    static func netColour(_ colour: NetColour) -> Color {
        Color(red: colour.red, green: colour.green, blue: colour.blue)
    }

    static func netColour(forNet index: Int) -> Color {
        netColour(NetColourPalette.colour(forNet: index))
    }

    // Category tones are used for both the palette tiles and the parts themselves.
    static func categoryAccent(for categoryID: String) -> Color {
        switch categoryID {
        case "resistor": Color(red: 0.86, green: 0.53, blue: 0.20)
        case "capacitor": Color(red: 0.20, green: 0.55, blue: 0.88)
        case "diode": Color(red: 0.94, green: 0.34, blue: 0.30)
        case "transistor": Color(red: 0.47, green: 0.42, blue: 0.88)
        case "ic": Color(red: 0.31, green: 0.35, blue: 0.40)
        case "inductor": Color(red: 0.72, green: 0.48, blue: 0.24)
        case "crystal": Color(red: 0.19, green: 0.66, blue: 0.63)
        case "switch": Color(red: 0.90, green: 0.30, blue: 0.38)
        case "connector": Color(red: 0.20, green: 0.50, blue: 0.74)
        case "relay": Color(red: 0.55, green: 0.58, blue: 0.64)
        case "sensor": Color(red: 0.30, green: 0.68, blue: 0.39)
        case "power": Color(red: 0.91, green: 0.55, blue: 0.15)
        default: Color(red: 0.48, green: 0.54, blue: 0.58)
        }
    }

    static func componentBody(for categoryID: String) -> Color {
        switch categoryID {
        case "resistor": Color(red: 0.86, green: 0.73, blue: 0.50)
        case "capacitor": Color(red: 0.16, green: 0.30, blue: 0.44)
        case "diode": Color(red: 0.12, green: 0.13, blue: 0.14)
        case "transistor": Color(red: 0.10, green: 0.11, blue: 0.13)
        case "ic": Color(red: 0.09, green: 0.10, blue: 0.11)
        case "inductor": Color(red: 0.38, green: 0.24, blue: 0.15)
        case "crystal": Color(red: 0.62, green: 0.65, blue: 0.68)
        case "switch": Color(red: 0.28, green: 0.29, blue: 0.31)
        case "connector": Color(red: 0.15, green: 0.34, blue: 0.54)
        case "relay": Color(red: 0.24, green: 0.27, blue: 0.31)
        case "sensor": Color(red: 0.16, green: 0.31, blue: 0.22)
        case "power": Color(red: 0.33, green: 0.20, blue: 0.15)
        default: Color(red: 0.22, green: 0.24, blue: 0.25)
        }
    }

    static func contrastInk(for categoryID: String) -> Color {
        // Component bodies in this palette are all dark except the resistor.
        categoryID == "resistor"
            ? Color(red: 0.15, green: 0.12, blue: 0.08)
            : .white
    }
}

/// Small surfaces used by the palette and overlays.
struct GlassPill: ViewModifier {
    var padding: CGFloat = 8

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, padding)
            .padding(.vertical, padding * 0.55)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5))
    }
}

extension View {
    func glassPill(padding: CGFloat = 8) -> some View {
        modifier(GlassPill(padding: padding))
    }
}

struct SectionLabel: View {
    let title: String
    var systemImage: String?

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .bold))
            }
            Text(title.uppercased())
                .font(.system(size: 11, weight: .black, design: .rounded))
                .tracking(0.8)
        }
        .foregroundStyle(.secondary)
    }
}
