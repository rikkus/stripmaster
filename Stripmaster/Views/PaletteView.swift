import SwiftUI

/// The component panel: board-size templates followed by every part in the
/// catalogue, grouped and searchable.
struct PaletteView: View {
    let document: StripmasterDocument
    @Binding var tool: EditorTool
    var onComponentPicked: (() -> Void)?
    var onTemplatePicked: (() -> Void)?

    @State private var query = ""

    private var filteredCategories: [ComponentCategory] {
        ComponentCatalogue.filteredCategories(matching: query)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                paletteHeader
                boardSection
                searchField
                if filteredCategories.isEmpty {
                    emptySearch
                } else {
                    ForEach(filteredCategories) { category in
                        categorySection(category)
                    }
                }
                colourKey
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 24)
        }
        .background {
            ZStack {
                Rectangle().fill(.regularMaterial)
                LinearGradient(
                    colors: [Color.white.opacity(0.035), Color.black.opacity(0.04)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("component.palette")
    }

    private var paletteHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text("Components")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                Spacer()
                Text("\(ComponentCatalogue.allMembers.count) parts")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(.quaternary.opacity(0.6)))
            }
            Text("\(ComponentCatalogue.categories.count) groups · tap a part, then place it on the board")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }

    private var boardSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(title: "Board template", systemImage: "rectangle.grid.2x2")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                ForEach(BoardTemplate.ordered) { template in
                    templateButton(template)
                }
            }
            if !document.isUntouched {
                HStack(alignment: .top, spacing: 5) {
                    Image(systemName: "lock.fill").font(.system(size: 9, weight: .bold))
                    Text("Board size is fixed once a board has edits. Start a new document to change it.")
                        .font(.system(size: 9.5, weight: .medium, design: .rounded))
                }
                .foregroundStyle(.tertiary)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.quaternary.opacity(0.25)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.quaternary.opacity(0.5)))
    }

    private func templateButton(_ template: BoardTemplate) -> some View {
        let isCurrent = document.board.template == template
        let enabled = document.isUntouched || isCurrent
        return Button {
            if document.board.template != template {
                _ = document.selectTemplate(template)
            }
            onTemplatePicked?()
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(template.shortName)
                        .font(.system(size: 13, weight: .black, design: .rounded))
                        .foregroundStyle(isCurrent ? BoardTheme.selection : .primary)
                    if isCurrent {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(BoardTheme.selection)
                    }
                    Spacer(minLength: 0)
                }
                Text("\(template.rows) strips")
                    .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isCurrent ? BoardTheme.selection.opacity(0.14) : Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        isCurrent ? BoardTheme.selection.opacity(0.65) : Color.primary.opacity(0.08),
                        lineWidth: isCurrent ? 1.2 : 0.6
                    )
            )
            .opacity(enabled ? 1 : 0.48)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help("\(template.columns) × \(template.rows) holes (\(template.rows) copper strips)")
        .accessibilityIdentifier("template.\(template.rawValue)")
        .accessibilityLabel("\(template.shortName) board, \(template.rows) strips")
    }

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
            TextField("Find a part", text: $query)
                #if os(macOS)
                .textFieldStyle(.plain)
                #endif
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .accessibilityIdentifier("palette.search")
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear part search")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.quaternary.opacity(0.35)))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(.quaternary.opacity(0.6)))
    }

    private var emptySearch: some View {
        VStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.tertiary)
            Text("No matching parts")
                .font(.system(size: 12, weight: .bold, design: .rounded))
            Text("Try a short name, a tiny name such as LED, or a group such as capacitor.")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private func categorySection(_ category: ComponentCategory) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if let first = category.members.first {
                    ZStack {
                        Circle()
                            .fill(BoardTheme.categoryAccent(for: category.id).opacity(0.18))
                        ComponentGlyphView(
                            glyph: first.glyph,
                            categoryID: category.id,
                            size: 18
                        )
                    }
                    .frame(width: 28, height: 28)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(category.fullName)
                        .font(.system(size: 13.5, weight: .black, design: .rounded))
                    Text("\(category.shortName) · \(category.tinyName)")
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(category.members.count)")
                    .font(.system(size: 9.5, weight: .bold, design: .rounded))
                    .foregroundStyle(.tertiary)
            }

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)],
                spacing: 6
            ) {
                ForEach(category.members) { member in
                    paletteTile(member, category: category)
                }
            }
        }
    }

    private func paletteTile(_ spec: ComponentSpec, category: ComponentCategory) -> some View {
        let isActive = tool == .place(spec.reference)
        let accent = BoardTheme.categoryAccent(for: category.id)
        return Button {
            withAnimation(.easeInOut(duration: 0.14)) {
                tool = .place(spec.reference)
            }
            onComponentPicked?()
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(accent.opacity(isActive ? 0.28 : 0.13))
                        ComponentGlyphView(glyph: spec.glyph, categoryID: category.id, size: 24)
                    }
                    .frame(width: 30, height: 30)
                    Spacer(minLength: 0)
                    Text(spec.tinyName)
                        .font(.system(size: 8.5, weight: .black, design: .monospaced))
                        .foregroundStyle(accent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                Text(spec.shortName)
                    .font(.system(size: 11.5, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .minimumScaleFactor(0.8)
                HStack(spacing: 3) {
                    Text("\(spec.legs)L")
                    if spec.isPolarised {
                        Text("•")
                        Text("polar")
                    }
                }
                .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            }
            .padding(7)
            .frame(maxWidth: .infinity, minHeight: 80, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isActive ? accent.opacity(0.13) : Color.primary.opacity(0.035))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(
                        isActive ? accent.opacity(0.9) : Color.primary.opacity(0.08),
                        lineWidth: isActive ? 1.6 : 0.6
                    )
            )
            .overlay(alignment: .top) {
                if isActive {
                    Capsule()
                        .fill(accent)
                        .frame(width: 24, height: 2)
                        .padding(.top, 3)
                }
            }
        }
        .buttonStyle(.plain)
        .help("\(spec.plainFullName) — \(spec.legDescription)\(spec.isPolarised ? ", polarised" : "")")
        .accessibilityIdentifier("palette.\(category.id).\(spec.memberID)")
        .accessibilityLabel("\(spec.plainFullName), \(spec.shortName), \(spec.legDescription)")
    }

    private var colourKey: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(title: "Connectivity", systemImage: "circle.grid.cross")
            HStack(spacing: 4) {
                ForEach(0..<10, id: \.self) { index in
                    Circle()
                        .fill(BoardTheme.netColour(forNet: index))
                        .frame(width: 11, height: 11)
                }
                Text("each net has its own colour")
                    .font(.system(size: 9.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 3)
            }
        }
        .padding(.top, 4)
    }
}
