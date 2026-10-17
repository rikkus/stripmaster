import SwiftUI

@main
struct StripmasterApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(StripmasterAppDelegate.self) private var appDelegate
    #endif

    var body: some Scene {
        #if os(iOS)
        DocumentGroupLaunchScene("stripmaster") {
            NewDocumentButton("16 × 8", contentType: .stripmasterBoard, source: .sixteenByEight)
            NewDocumentButton("24 × 12", contentType: .stripmasterBoard, source: .twentyFourByTwelve)
            NewDocumentButton("32 × 16", contentType: .stripmasterBoard, source: .thirtyTwoBySixteen)
            NewDocumentButton("48 × 24", contentType: .stripmasterBoard, source: .fortyEightByTwentyFour)
        } background: {
            LaunchBackground()
        }
        #endif

        #if os(macOS)
        documentSceneWithRestoration
        #else
        documentScene
        #endif
    }

    private var documentScene: some Scene {
        DocumentGroup { document in
            EditorView(document: document)
        } makeDocument: { configuration, context in
            StripmasterDocument(configuration: configuration, context: context)
        }
        .commands {
            StripmasterCommands()
        }
    }

    #if os(macOS)
    private var documentSceneWithRestoration: some Scene {
        documentScene.restorationBehavior(
            ProcessInfo.processInfo.arguments.contains("--ui-testing") ? .disabled : .automatic
        )
    }
    #endif
}

#if os(iOS)
/// A quiet stripboard drawing behind the iOS launch screen's New buttons.
struct LaunchBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.055, green: 0.13, blue: 0.10),
                    Color(red: 0.03, green: 0.055, blue: 0.05),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Canvas { context, size in
                let rows = 18
                let columns = 12
                let inset: CGFloat = 30
                let usable = CGRect(origin: .zero, size: size).insetBy(dx: inset, dy: inset)
                for row in 0..<rows {
                    let y = usable.minY + usable.height * CGFloat(row) / CGFloat(max(rows - 1, 1))
                    var line = Path()
                    line.move(to: CGPoint(x: usable.minX, y: y))
                    line.addLine(to: CGPoint(x: usable.maxX, y: y))
                    context.stroke(
                        line,
                        with: .color(BoardTheme.copper.opacity(0.11)),
                        lineWidth: 1.2
                    )
                    for column in 0..<columns {
                        let x = usable.minX + usable.width * CGFloat(column) / CGFloat(max(columns - 1, 1))
                        context.fill(
                            Path(ellipseIn: CGRect(x: x - 1.3, y: y - 1.3, width: 2.6, height: 2.6)),
                            with: .color(.black.opacity(0.35))
                        )
                    }
                }
            }
            .opacity(0.7)
            RadialGradient(
                colors: [Color.white.opacity(0.06), .clear],
                center: .center,
                startRadius: 10,
                endRadius: 420
            )
        }
        .ignoresSafeArea()
    }
}
#endif
