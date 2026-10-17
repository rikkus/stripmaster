import SwiftUI

/// First-run size chooser for a brand-new document. It floats over the board
/// rather than blocking the editor, and disappears once the board is edited.
struct TemplateChooserCard: View {
    let document: StripmasterDocument
    var onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Choose a board")
                        .font(.system(size: 16, weight: .black, design: .rounded))
                    Text("Pick a stripboard size, or keep 24 × 12. You can change this until you start editing.")
                        .font(.system(size: 10.5, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                        .padding(5)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss board size chooser")
                .accessibilityIdentifier("templateCard.dismiss")
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 7), GridItem(.flexible(), spacing: 7)], spacing: 7) {
                ForEach(BoardTemplate.ordered) { template in
                    templateButton(template)
                }
            }

            HStack {
                Text("\(document.board.template.columns) columns × \(document.board.template.rows) strips")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("Keep current board", action: onDismiss)
                    .font(.system(size: 10.5, weight: .bold, design: .rounded))
                    .buttonStyle(.plain)
                    .foregroundStyle(BoardTheme.selection)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(BoardTheme.selection.opacity(0.14)))
                    .accessibilityIdentifier("templateCard.keep")
            }
        }
        .padding(13)
        .frame(maxWidth: 380)
        .background {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(Color(red: 0.075, green: 0.09, blue: 0.085).opacity(0.96))
        }
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.45), radius: 26, y: 12)
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("templateCard")
    }

    private func templateButton(_ template: BoardTemplate) -> some View {
        let current = document.board.template == template
        return Button {
            if document.board.template != template {
                _ = document.selectTemplate(template)
            }
            onDismiss()
        } label: {
            HStack(spacing: 8) {
                TemplateMiniBoard(template: template, highlighted: current)
                    .frame(width: 43, height: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(template.shortName)
                        .font(.system(size: 12.5, weight: .black, design: .rounded))
                    Text("\(template.rows) strips")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if current {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(BoardTheme.selection)
                }
            }
            .padding(7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(current ? BoardTheme.selection.opacity(0.14) : Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        current ? BoardTheme.selection.opacity(0.7) : Color.primary.opacity(0.08),
                        lineWidth: current ? 1.2 : 0.5
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("templateCard.\(template.rawValue)")
        .accessibilityLabel("\(template.shortName) board, \(template.rows) copper strips")
    }
}

/// Tiny stripboard diagram used in the size chooser.
struct TemplateMiniBoard: View {
    let template: BoardTemplate
    var highlighted: Bool = false

    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: 1.5, dy: 1.5)
            let board = Path(roundedRect: rect, cornerRadius: 3)
            context.fill(
                board,
                with: .color(BoardTheme.bottomBoard.opacity(highlighted ? 0.95 : 0.55))
            )
            context.stroke(
                board,
                with: .color(highlighted ? BoardTheme.selection.opacity(0.9) : Color.white.opacity(0.18)),
                lineWidth: highlighted ? 1.2 : 0.7
            )
            let rows = min(template.rows, 12)
            for row in 0..<rows {
                let fraction = rows == 1 ? 0.5 : CGFloat(row) / CGFloat(rows - 1)
                let y = rect.minY + 4 + fraction * (rect.height - 8)
                var line = Path()
                line.move(to: CGPoint(x: rect.minX + 4, y: y))
                line.addLine(to: CGPoint(x: rect.maxX - 4, y: y))
                context.stroke(
                    line,
                    with: .color(BoardTheme.copper.opacity(highlighted ? 0.9 : 0.45)),
                    lineWidth: 1
                )
                let columns = min(template.columns, 18)
                for column in 0..<columns {
                    let xFraction = columns == 1 ? 0.5 : CGFloat(column) / CGFloat(columns - 1)
                    let x = rect.minX + 4 + xFraction * (rect.width - 8)
                    context.fill(
                        Path(ellipseIn: CGRect(x: x - 0.65, y: y - 0.65, width: 1.3, height: 1.3)),
                        with: .color(.black.opacity(0.55))
                    )
                }
            }
        }
        .accessibilityHidden(true)
    }
}
