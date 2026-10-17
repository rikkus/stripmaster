import SwiftUI

/// Compact read-out of the board, its face, its nets and the zoom level.
struct BoardStatusOverlay: View {
    let document: StripmasterDocument
    let viewport: CGSize

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var isCompact: Bool { horizontalSizeClass == .compact }

    private var fitZoom: CGFloat {
        document.metrics.fitZoom(
            viewport: viewport,
            orientation: document.view.orientation,
            padding: BoardZoom.fitPadding
        )
    }

    private var zoomPercent: Int {
        guard viewport.width > 1, fitZoom > 0 else { return 100 }
        let effective = document.view.effectiveZoom(viewport: viewport, metrics: document.metrics)
        return Int((effective / fitZoom * 100).rounded())
    }

    private var nets: [ConnectivityNet] {
        document.connectivity.nets
    }

    var body: some View {
        HStack(spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: document.view.side == .top ? "rectangle.grid.2x2" : "square.grid.3x3.square")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(BoardTheme.categoryAccent(for: "power"))
                Text(document.board.template.shortName)
                    .font(.system(size: 10.5, weight: .black, design: .rounded))
                Text("·")
                    .foregroundStyle(.tertiary)
                Text(document.view.side == .top ? "components" : "copper")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .glassPill(padding: 7)

            HStack(spacing: 4) {
                ForEach(nets.prefix(isCompact ? 3 : 6)) { net in
                    Circle()
                        .fill(BoardTheme.netColour(forNet: net.colourIndex))
                        .frame(width: 7, height: 7)
                }
                if nets.count > (isCompact ? 3 : 6) {
                    Text("+\(nets.count - (isCompact ? 3 : 6))")
                        .font(.system(size: 8.5, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                Text("\(nets.count) \(nets.count == 1 ? "net" : "nets")")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 2)
            }
            .glassPill(padding: 7)
            .help("Each colour is a separate connected group of holes.")

            if !isCompact {
                Text("\(zoomPercent)%")
                    .font(.system(size: 9.5, weight: .black, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .glassPill(padding: 7)
                    .help("Zoom relative to fit-to-window")
            }
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("board.status")
        .accessibilityLabel(
            "\(document.board.template.accessibilityName), \(document.view.side.accessibilityDescription), \(nets.count) nets, \(zoomPercent) percent zoom"
        )
    }
}
