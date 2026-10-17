import XCTest

/// A handful of smoke tests for the SwiftUI shell. The model and editing
/// behaviour is covered exhaustively by the functional suite in Tests/.
@MainActor
final class StripmasterUITests: XCTestCase {
    private var app: XCUIApplication!

    private func launch() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing",
            "--new-document",
        ]
        app.launch()
        XCTAssertTrue(
            element("board.canvas").waitForExistence(timeout: 20),
            "The board editor should appear after launching a new document."
        )
    }

    func testEditorShowsBoardPaletteToolsAndViewButtons() {
        launch()
        XCTAssertTrue(element("board.canvas").exists)
        XCTAssertTrue(element("component.palette").exists, "The components panel should be visible.")

        XCTAssertTrue(element("toolbar.fit").exists)
        XCTAssertTrue(element("toolbar.rotate").exists)
        XCTAssertTrue(element("toolbar.flip").exists)

        XCTAssertTrue(element("tool.select").exists)
        XCTAssertTrue(element("tool.cut").exists)
        XCTAssertTrue(element("tool.solder").exists)
        XCTAssertTrue(element("tool.jumper.bare").exists)
        XCTAssertTrue(element("tool.jumper.insulated").exists)

        XCTAssertTrue(element("palette.resistor.standard").exists)
        XCTAssertTrue(element("template.24x12").exists)
    }

    func testRotateAndFlipUpdateTheBoardFace() {
        launch()
        dismissTemplateCardIfNeeded()
        let board = element("board.canvas")
        let before = (board.value as? String) ?? ""
        XCTAssertTrue(before.contains("Landscape"), "New boards start in landscape: \(before)")

        element("toolbar.rotate").click()
        XCTAssertTrue(
            waitUntil(timeout: 5) {
                let value = (board.value as? String) ?? ""
                return value.contains("Portrait")
            },
            "Rotate should turn the board a quarter turn."
        )

        element("toolbar.flip").click()
        XCTAssertTrue(
            waitUntil(timeout: 5) {
                let value = (board.value as? String) ?? ""
                return value.contains("copper track side")
            },
            "Flip should show the copper side."
        )

        element("toolbar.fit").click()
        XCTAssertTrue(board.exists)
    }

    func testTemplateChooserChangesTheBoardSize() {
        launch()
        let card = element("templateCard")
        guard card.waitForExistence(timeout: 5) else {
            XCTFail("A new document should offer the board size chooser.")
            return
        }
        element("templateCard.16x8").click()
        XCTAssertTrue(
            waitUntil(timeout: 8) {
                let value = (element("board.canvas").value as? String) ?? ""
                return value.contains("16 by 8")
            },
            "Choosing 16 × 8 should change the board."
        )
    }

    func testCutToolMakesAnUndoableEdit() {
        launch()
        dismissTemplateCardIfNeeded()
        XCTAssertFalse(element("toolbar.undo").isEnabled, "A fresh board has nothing to undo.")
        element("tool.cut").click()
        clickBoardHole(column: 10, row: 5)

        XCTAssertTrue(
            waitUntil(timeout: 6) { element("toolbar.undo").isEnabled },
            "Cutting a hole should create a history entry."
        )

        element("toolbar.undo").click()
        XCTAssertTrue(
            waitUntil(timeout: 6) { !element("toolbar.undo").isEnabled },
            "Undo should remove the cut and leave a fresh history."
        )
    }

    func testPaletteSelectionRevealsPlacementTool() {
        launch()
        dismissTemplateCardIfNeeded()
        let resistorTile = element("palette.resistor.standard")
        XCTAssertTrue(resistorTile.waitForExistence(timeout: 5))
        resistorTile.click()
        XCTAssertTrue(
            element("tool.place.active").waitForExistence(timeout: 5),
            "Choosing a palette part should arm the placement tool."
        )
        XCTAssertTrue(element("tool.hint").exists)
    }

    // MARK: - Helpers

    private var window: XCUIElement { app.windows.firstMatch }

    /// Prefer the frontmost document window so a restored document does not
    /// satisfy queries intended for the new test document.
    private func element(_ identifier: String) -> XCUIElement {
        let inWindow = window.descendants(matching: .any).matching(identifier: identifier).firstMatch
        if inWindow.exists {
            return inWindow
        }
        return app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func dismissTemplateCardIfNeeded() {
        let dismiss = element("templateCard.dismiss")
        if dismiss.waitForExistence(timeout: 2) {
            dismiss.click()
        }
    }

    private func waitUntil(
        timeout: TimeInterval,
        _ condition: () -> Bool
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return condition()
    }

    /// Converts a hole in the default 24 × 12 fitted landscape board to a click.
    private func clickBoardHole(column: Int, row: Int) {
        let board = element("board.canvas")
        let frame = board.frame
        let columns = 24
        let rows = 12
        let metricsWidth = CGFloat(columns - 1) + 1.8
        let metricsHeight = CGFloat(rows - 1) + 1.8
        let padding: CGFloat = 34
        let zoom = min(
            (frame.width - padding * 2) / metricsWidth,
            (frame.height - padding * 2) / metricsHeight
        )
        let centreColumn = CGFloat(columns - 1) / 2
        let centreRow = CGFloat(rows - 1) / 2
        let offset = CGVector(
            dx: frame.width / 2 + (CGFloat(column) - centreColumn) * zoom,
            dy: frame.height / 2 + (CGFloat(row) - centreRow) * zoom
        )
        board.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
            .withOffset(offset)
            .click()
    }
}
