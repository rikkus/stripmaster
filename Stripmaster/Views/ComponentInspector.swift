import SwiftUI

/// Selected-component controls. Deliberately compact so it can float over the
/// top-right corner of the board.
struct ComponentInspectorView: View {
    let document: StripmasterDocument
    let component: PlacedComponent
    var onClose: () -> Void
    var onDeleted: () -> Void

    private var spec: ComponentSpec? { component.spec }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                if let spec {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(BoardTheme.categoryAccent(for: spec.categoryID).opacity(0.16))
                        ComponentGlyphView(glyph: spec.glyph, categoryID: spec.categoryID, size: 24)
                    }
                    .frame(width: 32, height: 32)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(spec?.plainFullName ?? "Component")
                        .font(.system(size: 12, weight: .black, design: .rounded))
                        .lineLimit(2)
                    Text(detailLine)
                        .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 2)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .padding(4)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Deselect component")
                .accessibilityIdentifier("inspector.close")
            }

            HStack(spacing: 5) {
                controlButton("rotate.right", label: "Rotate component") {
                    _ = document.rotateComponent(id: component.id)
                }
                .accessibilityIdentifier("inspector.rotate")

                controlButton("flip.horizontal", label: "Flip component") {
                    _ = document.flipComponent(id: component.id)
                }
                .accessibilityIdentifier("inspector.flip")

                if let stretch = spec?.stretch {
                    HStack(spacing: 2) {
                        controlButton("minus", label: "Reduce pin span") {
                            _ = document.stretchComponent(id: component.id, span: component.span - 1)
                        }
                        .disabled(component.span <= stretch.min)
                        .accessibilityIdentifier("inspector.stretch.minus")
                        Text("\(component.span)")
                            .font(.system(size: 10, weight: .black, design: .monospaced))
                            .frame(minWidth: 15)
                        controlButton("plus", label: "Increase pin span") {
                            _ = document.stretchComponent(id: component.id, span: component.span + 1)
                        }
                        .disabled(component.span >= stretch.max)
                        .accessibilityIdentifier("inspector.stretch.plus")
                    }
                    .padding(.horizontal, 4)
                    .background(RoundedRectangle(cornerRadius: 7).fill(.quaternary.opacity(0.35)))
                }

                Spacer(minLength: 0)

                controlButton("trash", label: "Delete component", tint: BoardTheme.invalid) {
                    if document.removeComponent(id: component.id) {
                        onDeleted()
                    }
                }
                .accessibilityIdentifier("inspector.delete")
            }
        }
        .padding(10)
        .frame(maxWidth: 286, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(red: 0.075, green: 0.09, blue: 0.085).opacity(0.95))
        }
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.3), radius: 14, y: 6)
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("component.inspector")
    }

    private var detailLine: String {
        guard let spec else { return "" }
        var bits = [spec.tinyName, spec.legDescription]
        if spec.isPolarised { bits.append("polarised") }
        bits.append(component.axis.displayName)
        return bits.joined(separator: " · ")
    }

    private func controlButton(
        _ systemImage: String,
        label: String,
        tint: Color = .primary,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 22, height: 22)
                .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary.opacity(0.35)))
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }
}
