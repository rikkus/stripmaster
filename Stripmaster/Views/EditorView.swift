import SwiftUI

/// The document editor window: palette on the left (regular width), board in
/// the middle, with a floating tool strip and selected-part inspector.
struct EditorView: View {
    let document: StripmasterDocument

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.undoManager) private var undoManager
    @Environment(\.scenePhase) private var scenePhase

    @State private var tool: EditorTool = .select
    @State private var selectedComponentID: UUID?
    @State private var boardViewport = CGSize.zero
    @State private var showPaletteSheet = false
    @State private var templateCardDismissed = false

    private var isCompact: Bool { horizontalSizeClass == .compact }

    private var selectedComponent: PlacedComponent? {
        guard let selectedComponentID else { return nil }
        return document.board.component(id: selectedComponentID)
    }

    private var showsTemplateCard: Bool {
        document.offersInitialTemplateChoice && document.isUntouched && !templateCardDismissed
    }

    var body: some View {
        HStack(spacing: 0) {
            if !isCompact {
                PaletteView(
                    document: document,
                    tool: $tool,
                    onComponentPicked: nil,
                    onTemplatePicked: nil
                )
                .frame(width: 310)
                .background(.regularMaterial)
                Divider().overlay(Color.black.opacity(0.35))
            }
            boardArea
        }
        .background(BoardTheme.workspaceBottom)
        .toolbar { toolbarContent }
        .sheet(isPresented: $showPaletteSheet) { paletteSheet }
        .onAppear {
            document.attach(undoManager: undoManager)
        }
        .onDisappear {
            document.flushAutosave()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                document.flushAutosave()
            }
        }
        .onChange(of: undoManager.map { ObjectIdentifier($0) }) { _, _ in
            document.attach(undoManager: undoManager)
        }
        .onChange(of: document.board.components.map(\.id)) { _, ids in
            if let selectedComponentID, !ids.contains(selectedComponentID) {
                self.selectedComponentID = nil
            }
        }
        .onChange(of: tool) { _, newTool in
            if !newTool.isSelectionTool, newTool.placementSpec == nil {
                selectedComponentID = nil
            }
            // Jumpers and parts live on the component side. Selecting their
            // tools while inspecting the copper side brings the board back to
            // the side the edit belongs on.
            if (newTool.jumperKind != nil || newTool.placementSpec != nil),
               document.view.side == .bottom {
                _ = document.flipView()
            }
        }
        .focusedSceneValue(\.stripmasterDocument, document)
        .focusedSceneValue(\.stripmasterViewport, boardViewport)
        #if os(macOS)
        .frame(minWidth: 940, minHeight: 580)
        #endif
        .accessibilityIdentifier("editor")
    }

    // MARK: - Workspace

    private var boardArea: some View {
        GeometryReader { proxy in
            BoardCanvasView(
                document: document,
                tool: $tool,
                selectedComponentID: $selectedComponentID,
                viewport: proxy.size
            )
            .overlay(alignment: .topLeading) {
                BoardStatusOverlay(document: document, viewport: proxy.size)
                    .padding(14)
            }
            .overlay(alignment: .topTrailing) {
                if let selectedComponent {
                    ComponentInspectorView(
                        document: document,
                        component: selectedComponent,
                        onClose: { selectedComponentID = nil },
                        onDeleted: { selectedComponentID = nil }
                    )
                    .padding(.top, isCompact ? 56 : 14)
                    .padding(.trailing, 14)
                    .padding(.leading, 14)
                }
            }
            .overlay(alignment: .center) {
                if showsTemplateCard {
                    TemplateChooserCard(document: document) {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            templateCardDismissed = true
                        }
                    }
                    .padding(18)
                    .transition(.scale(scale: 0.96).combined(with: .opacity))
                }
            }
            .overlay(alignment: .bottom) {
                bottomControls
            }
            .onAppear {
                updateBoardViewport(proxy.size)
            }
            .onChange(of: proxy.size) { _, newSize in
                updateBoardViewport(newSize)
            }
            .onChange(of: document.view.zoom == nil) { _, needsFit in
                if needsFit {
                    fitIfNeeded(proxy.size)
                }
            }
            .onChange(of: document.board.template) { _, _ in
                fitIfNeeded(proxy.size)
            }
        }
        .background(BoardTheme.workspaceBottom)
    }

    private var bottomControls: some View {
        VStack(spacing: 8) {
            if isCompact {
                HStack {
                    Button {
                        showPaletteSheet = true
                    } label: {
                        Label("Parts", systemImage: "square.grid.2x2")
                            .font(.system(size: 11, weight: .black, design: .rounded))
                    }
                    .buttonStyle(.plain)
                    .glassPill(padding: 8)
                    .accessibilityIdentifier("palette.open")
                    Spacer()
                }
                .padding(.horizontal, 14)
            }

            Text(tool.help)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5))
                .allowsHitTesting(false)
                .accessibilityIdentifier("tool.hint")

            ToolStripView(tool: $tool)
        }
        .frame(maxWidth: 780)
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        #if os(macOS)
        ToolbarItemGroup(placement: .primaryAction) {
            undoButton
            redoButton
            fitButton
            rotateButton
            flipButton
        }
        #else
        ToolbarItem(placement: .topBarLeading) {
            Menu {
                Button {
                    _ = document.undo()
                } label: {
                    Label(document.undoLabel.map { "Undo \($0)" } ?? "Undo", systemImage: "arrow.uturn.backward")
                }
                .disabled(!document.canUndo)

                Button {
                    _ = document.redo()
                } label: {
                    Label(document.redoLabel.map { "Redo \($0)" } ?? "Redo", systemImage: "arrow.uturn.forward")
                }
                .disabled(!document.canRedo)

                Divider()

                Button {
                    showPaletteSheet = true
                } label: {
                    Label("Components", systemImage: "square.grid.2x2")
                }

                Button {
                    fitToWindow()
                } label: {
                    Label("Fit to Window", systemImage: "arrow.up.left.and.arrow.down.right")
                }

                Divider()

                Button {
                    _ = document.rotateView(viewport: boardViewport)
                } label: {
                    Label("Rotate 90°", systemImage: "rotate.right")
                }

                Button {
                    _ = document.flipView()
                } label: {
                    Label(
                        document.view.side == .top ? "Show copper side" : "Show component side",
                        systemImage: "flip.horizontal"
                    )
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .accessibilityIdentifier("toolbar.menu")
            .accessibilityLabel("More actions")
        }

        ToolbarItemGroup(placement: .topBarTrailing) {
            fitButton
            rotateButton
            flipButton
        }
        #endif
    }

    private var undoButton: some View {
        Button {
            _ = document.undo()
        } label: {
            Image(systemName: "arrow.uturn.backward")
        }
        .disabled(!document.canUndo)
        .help(document.undoLabel.map { "Undo \($0)" } ?? "Undo")
        .accessibilityLabel(document.undoLabel.map { "Undo \($0)" } ?? "Undo")
        .accessibilityIdentifier("toolbar.undo")
    }

    private var redoButton: some View {
        Button {
            _ = document.redo()
        } label: {
            Image(systemName: "arrow.uturn.forward")
        }
        .disabled(!document.canRedo)
        .help(document.redoLabel.map { "Redo \($0)" } ?? "Redo")
        .accessibilityLabel(document.redoLabel.map { "Redo \($0)" } ?? "Redo")
        .accessibilityIdentifier("toolbar.redo")
    }

    private var fitButton: some View {
        Button {
            fitToWindow()
        } label: {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
        }
        .disabled(boardViewport.width < 2)
        .help("Fit board to window")
        .accessibilityLabel("Fit to window")
        .accessibilityIdentifier("toolbar.fit")
    }

    private var rotateButton: some View {
        Button {
            _ = document.rotateView(viewport: boardViewport.width > 1 ? boardViewport : nil)
        } label: {
            Image(systemName: "rotate.right")
        }
        .help("Rotate board 90°")
        .accessibilityLabel("Rotate 90 degrees")
        .accessibilityIdentifier("toolbar.rotate")
    }

    private var flipButton: some View {
        Button {
            _ = document.flipView()
        } label: {
            Image(systemName: "flip.horizontal")
        }
        .help(document.view.side == .top ? "Flip board to the copper side" : "Flip board to the component side")
        .accessibilityLabel(document.view.side == .top ? "Show copper side" : "Show component side")
        .accessibilityIdentifier("toolbar.flip")
    }

    // MARK: - Sheets

    private var paletteSheet: some View {
        NavigationStack {
            PaletteView(
                document: document,
                tool: $tool,
                onComponentPicked: {
                    showPaletteSheet = false
                },
                onTemplatePicked: nil
            )
            .navigationTitle("Components")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        showPaletteSheet = false
                    }
                    .accessibilityIdentifier("palette.done")
                }
            }
        }
        #if os(iOS)
        .presentationDetents([.medium, .large])
        #endif
    }

    // MARK: - View fitting

    private func updateBoardViewport(_ size: CGSize) {
        guard size.width > 1, size.height > 1 else { return }
        boardViewport = size
        fitIfNeeded(size)
    }

    private func fitIfNeeded(_ size: CGSize) {
        guard document.view.zoom == nil else { return }
        _ = document.ensureInitialFit(viewport: size)
    }

    private func fitToWindow() {
        guard boardViewport.width > 1, boardViewport.height > 1 else { return }
        _ = document.fitView(viewport: boardViewport)
    }
}
