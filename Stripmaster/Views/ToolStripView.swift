import SwiftUI

/// The floating tool palette. Each tool has a name as well as an icon: the two
/// jumper types in particular are easy to confuse from iconography alone.
struct ToolStripView: View {
    @Binding var tool: EditorTool

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 3) {
                ForEach(EditorTool.stripTools, id: \.self) { candidate in
                    toolButton(candidate)
                }
                if let spec = tool.placementSpec {
                    Rectangle()
                        .fill(.quaternary)
                        .frame(width: 1, height: 22)
                        .padding(.horizontal, 3)
                    placementChip(spec)
                }
            }
            .padding(5)
        }
        .frame(maxWidth: 760)
        .fixedSize(horizontal: false, vertical: true)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.13), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.35), radius: 18, y: 7)
        .accessibilityIdentifier("tool.strip")
    }

    private func toolButton(_ candidate: EditorTool) -> some View {
        let active = tool == candidate
        return Button {
            withAnimation(.easeInOut(duration: 0.14)) {
                tool = candidate
            }
        } label: {
            HStack(spacing: 4.5) {
                icon(for: candidate)
                Text(candidate.displayName)
                    .font(.system(size: 10.5, weight: .bold, design: .rounded))
                    .lineLimit(1)
            }
            .foregroundStyle(active ? .primary : .secondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(active ? candidate.accent.opacity(0.22) : Color.clear)
            )
            .overlay(
                Capsule()
                    .strokeBorder(active ? candidate.accent.opacity(0.85) : Color.clear, lineWidth: 1.2)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(candidate.help)
        .accessibilityIdentifier(candidate.accessibilityIdentifier)
        .accessibilityLabel(candidate.displayName)
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    @ViewBuilder
    private func icon(for candidate: EditorTool) -> some View {
        if let kind = candidate.jumperKind {
            JumperToolIcon(kind: kind, size: 14)
                .foregroundStyle(candidate.accent)
        } else if let systemImage = candidate.systemImage {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .bold))
                .frame(width: 14, height: 14)
                .foregroundStyle(candidate.accent)
        }
    }

    private func placementChip(_ spec: ComponentSpec) -> some View {
        HStack(spacing: 5) {
            ComponentGlyphView(
                glyph: spec.glyph,
                categoryID: spec.categoryID,
                size: 15
            )
            Text("Place \(spec.shortName)")
                .font(.system(size: 10.5, weight: .black, design: .rounded))
            Button {
                withAnimation(.easeInOut(duration: 0.14)) {
                    tool = .select
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Stop placing components")
            .accessibilityIdentifier("tool.place.cancel")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Capsule().fill(BoardTheme.selection.opacity(0.18)))
        .overlay(Capsule().strokeBorder(BoardTheme.selection.opacity(0.7), lineWidth: 1))
        .accessibilityIdentifier("tool.place.active")
        .accessibilityLabel("Placing \(spec.plainFullName)")
    }
}
