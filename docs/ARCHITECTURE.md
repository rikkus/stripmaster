# Architecture

This note records the decisions that are easy to get wrong later. The code is
split so that everything except drawing and gestures can be tested without
SwiftUI.

## Layers

```
Stripmaster/Model        pure Swift, Foundation/CoreGraphics only
Stripmaster/Document     SwiftUI Document bridge, FileWrapper reader/writer
Stripmaster/Views        Canvas rendering and gestures
Stripmaster/App          App, DocumentGroup, commands, launch helpers
```

`Model/` is compiled directly into `Tests/run-tests.sh` along with `Tests/`.
Nothing there may import SwiftUI. `StripmasterDocumentState` is the UI-free
document model: board, history, view and timestamps. `StripmasterDocument` is a
thin `@Observable` bridge that exposes that state to SwiftUI and raises the
autosave signal.

## Board coordinates

One unit is the distance between adjacent hole centres. A board with `c` columns
and `r` rows has hole centres at `(margin + column, margin + row)`, where the
margin is 0.9 units. The board material extends 0.9 units beyond the outer hole
centres.

The templates are always wider than they are tall: `columns` is the long axis and
copper strips are horizontal rows. "Landscape" means viewing the board in its
natural orientation. No template is square.

`BoardViewState` stores:

- `orientation` — quarter turns: 0°, 90°, 180°, 270°
- `side` — `.top` or `.bottom`
- `zoom` — points per hole, `nil` until first fitted
- `panX` / `panY` — points from the viewport centre
- `updatedAt`

Zoom is absolute rather than a multiplier of the current window's fit. This is
what makes "reopen at the size it was last edited at" work even if the window
has changed size. `Fit` recomputes it for the current viewport.

`BoardViewTransform` maps board-space points to view-space points and back. It
applies, in order: mirror horizontally if viewing the bottom, rotate the quarter
turn, scale by zoom, then translate by the viewport centre plus pan. Hit testing
uses the inverse, so editing on the mirrored/rotated back works exactly like
editing on the front.

Fit uses 34 points of padding. On first appearance of a document whose
`view.zoom == nil`, `ensureInitialFit` runs. It never overwrites a stored view.
Rotation refits and clears the pan because the new aspect is usually a different
shape. Flip preserves zoom and pan.

## Editing and history

`BoardEdit` is the reversible command type:

- set/clear a cut
- set/clear a solder joint
- add/remove a jumper (removal carries the original array index)
- add/remove a component (removal carries the index)
- update a component (before/after values)

`Stripboard.apply` and `Stripboard.revert` are the only places that mutate the
board from history. Indices are carried so undoing a removal restores z-order;
otherwise undo would silently reorder overlapping parts.

`EditHistory` stores entries and a cursor counting applied entries. Undo moves the
cursor back and reverts; redo moves it forward and applies. Recording a new edit
after an undo discards the redo suffix. The history is encoded with the document.

Deliberate choices:

- A no-op edit is never recorded. The public state mutators check for an actual
  change before creating a command.
- View changes never enter the history. Pan, zoom, rotate, side and fit update
  `modifiedAt` and trigger autosave, but not undo.
- Choosing a template is a document-creation action, allowed only while the
  board is untouched (`board.isPristine && history.isEmpty`). It resets history
  rather than creating an undoable command.
- Multi-hole tool drags currently record one edit per changed hole. Undoing a
  drag therefore steps back one hole at a time. This is simple and transparent;
  a compound command would be the next improvement if it becomes annoying.

## Connectivity

`Connectivity` is a real graph built from the board on each change.

- Nodes are uncut holes, plus any hole touched by a jumper (a cut hole crossed by
  a bare wire is still a point on that wire).
- Copper edges join horizontally adjacent uncut holes. A cut removes the pad at
  that hole, so it breaks the strip on both sides and the cut hole itself is not
  a copper node.
- A bare jumper adds an edge for every adjacent pair along its route, regardless
  of cuts. It contacts every hole it passes over and can deliberately bridge a
  cut.
- An insulated jumper adds exactly one edge between its endpoints. Intermediate
  holes are not nodes of that edge. The sleeve is non-conductive and is drawn as
  a sleeve, not as a conductive line.
- Solder joints do not change the graph. A solder blob is a physical joint at a
  hole, not a conductor between two holes.
- Placed components do not change the graph. A resistor is not a short; its legs
  do not connect holes to each other. The overlay is about conductivity between
  holes, not circuit nets through parts.

A union-find partitions the nodes. Nets are sorted by their smallest hole so
colours are deterministic. `NetColourPalette` provides 16 curated high-contrast
colours, then generates further tones with a golden-angle hue walk. Nets are
drawn on both faces with translucent pads and links.

Cut holes not touched by any jumper have no net and no overlay tint.

### Jumper routing

`JumperDraft` maintains a path of adjacent holes. A pointer update adds a
right-angled elbow towards the target hole; the previous segment's axis is
preferred when it still points at the target. Moving back over an earlier hole
truncates the path to it, which is the drawing equivalent of retracing a wire.
The router never adds a point already on the path and never adds a diagonal step.
The path length is capped. `Jumper` validation also rejects diagonals and
non-adjacent jumps if a malformed document is loaded.

`isValid(dimensions:)` is used by both the editor and the loader. The loaded-board
sanitiser drops invalid jumpers and components and clamps spans.

## Persistence

The file is pretty-printed JSON with a `formatVersion` and the full document
state. `StripmasterFileCodec` is the only encoder/decoder. Future versions are
rejected; old/missing fields get defaults; `sanitized()` filters out-of-range
geometry and duplicate IDs. Tests cover round-tripping, version rejection,
missing fields, corrupt data and invalid contents.

The UTI is declared in `Info.plist` and mirrored in `StripmasterFile.swift`:
`cc.hemsley.stripmaster.board`, conforming to `public.json`, extension
`.stripmaster`.

## Autosave and the system undo manager

The app uses the new SwiftUI `Document` protocol. Its `FileWrapperDocumentReader`
and `FileWrapperDocumentWriter` read and write the document. SwiftUI's autosave
requires an undo registration to know there are unsaved changes; without one it
will not autosave.

`StripmasterDocument.noteChange()` schedules a 350 ms `AutosaveSignal`. When the
signal fires, the document registers a deliberately empty undo action. That
registration is only a dirty flag for SwiftUI. The app's own Undo/Redo commands
and toolbar actions call the persisted `EditHistory` instead, so the system undo
stack is not used for user-visible undo.

Implications:

- Do not replace the empty undo registration with a closure that mutates the
  board unless you also rework the history commands; the two undo systems would
  fight.
- The window's edited indicator may remain because the no-op actions stay in the
  system undo stack. The file is still autosaved; this is a cosmetic systems
  detail.
- The debounce is tested separately in `Tests/AutosaveTests.swift` with a
  controllable delay.

## Components

The catalogue is intentionally data, not UI. Each `ComponentSpec` has a category,
short/tiny/full names, leg count, polarisation, optional two-lead stretch range,
a layout (two-lead, inline, DIP) and a `ComponentGlyph` for the palette.

Placement uses `PlacedComponent`:

- two-lead: pins at the anchor and anchor + span along the selected axis
- inline: adjacent holes from the anchor
- DIP: two rows three holes apart, pins on adjacent columns

The renderer uses `ComponentLayoutGeometry` for the body and hit rect. Two-lead
spans are clamped to the catalogue. Components are stored with their own UUID so
the same catalogue part can be placed repeatedly.

The palette's icons are custom Canvas drawings, not SF Symbols: there is no
resistor or capacitor symbol in SF Symbols, and labels alone are too easy to
misread. Each group has a short/tiny name and every member shows its short name
and tiny name.

## UI and gestures

`BoardCanvasView` is one SwiftUI `Canvas`. The renderer draws in screen space for
the material/shadow, then applies the board transform and draws in hole units.
This keeps gestures and rendering using the same `BoardViewTransform`.

Gestures:

- one-finger/mouse drag runs the selected tool; paint tools stage their holes and
  commit on release, so a pinch can cancel a half-started edit cleanly
- select-drag on empty board pans; select-drag on a component moves it
- a dedicated Pan tool always pans
- pinch is `MagnifyGesture`; it zooms around the gesture's start anchor
- on macOS, a local `scrollWheel` monitor pans while the pointer is over the
  board (unless Command is held)
- a pinch cancels any in-progress tool drag; the drag's end is ignored

The top toolbar carries Fit/Rotate/Flip (and undo/redo on macOS). Tools live in
the floating bottom strip. On compact iOS the palette becomes a sheet and the
status area collapses around it.

## Testing strategy

`Tests/run-tests.sh` compiles all of `Model/` plus the tests with `swiftc` and runs
them. There is no XCTest host, no simulator and no Xcode project build involved.
It covers geometry, editing, history, connectivity, routing, catalogue data,
persistence, autosave and view transforms.

`StripmasterUITests` is limited to smoke tests of the SwiftUI shell: launch,
toolbar/palette presence, template selection, rotate/flip, a cut/undo and palette
arming. macOS UI automation permission is required to run them; the environment
used to develop this app could not grant it, so the tests were compiled with
`build-for-testing` rather than executed.
