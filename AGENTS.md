# stripmaster

A SwiftUI document app for stripboard circuit design on macOS and iOS. One
multiplatform target, iOS 27 and macOS 27, written in Swift 6.

## Build and test

The Xcode project is generated from `project.yml` and is not committed.

```sh
xcodegen generate

xcodebuild -project Stripmaster.xcodeproj -scheme Stripmaster \
  -destination 'platform=macOS' build

xcodebuild -project Stripmaster.xcodeproj -scheme Stripmaster \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build

./Tests/run-tests.sh        # functional suite; plain swiftc, no test host
```

The UI smoke tests need macOS UI automation permission:

```sh
xcodebuild -project Stripmaster.xcodeproj -scheme Stripmaster \
  -destination 'platform=macOS' \
  -only-testing:StripmasterUITests test
```

`build-for-testing` is enough to verify that the UI test bundle compiles.

## Constraints

- Everything in `Stripmaster/Model/` must remain free of SwiftUI. It is compiled
  into the functional test executable with plain `swiftc`, without a test host.
- `Stripmaster/Document/StripmasterDocument.swift` is the only place where the
  SwiftUI `Document` machinery belongs. UI-free model logic must stay in
  `Stripmaster/Model/`.
- The generated `Stripmaster.xcodeproj` is ignored. After adding a source file,
  rerun `xcodegen generate` or the new file will not be in the target.
- Autosave relies on `UndoManager` registration in `StripmasterDocument`. That
  registration is intentionally a no-op: the menu and toolbar undo/redo are
  served by the persisted edit history. Do not remove it without replacing the
  mechanism; SwiftUI will then stop autosaving. See `docs/ARCHITECTURE.md`.
- All work is on `main`; no pull requests.
- The functional suite is the main gate. UI tests are deliberately smoke tests
  only.

## Where things are

- `Stripmaster/Model/StripmasterDocumentState.swift` — edits, undo/redo, view
  fitting. No UI.
- `Stripmaster/Model/Connectivity.swift` — conductivity graph, net partitioning,
  net colours.
- `Stripmaster/Model/Jumper.swift` — jumper route validation and the live
  right-angle drag router.
- `Stripmaster/Model/ComponentCatalogue.swift` — all palette data.
- `Stripmaster/Model/StripmasterFile.swift` — JSON file format and UTI.
- `Stripmaster/Views/BoardRenderer.swift` — board drawing in Canvas.
- `Stripmaster/Views/BoardCanvasView.swift` — gestures and transient previews.
- `Stripmaster/Views/PaletteView.swift` — components panel.
- `Stripmaster/App/StripmasterCommands.swift` — history-backed Undo/Redo and the
  Board menu.

The app's document type is `.stripmaster` / `cc.hemsley.stripmaster.board`.
