import XCTest

final class ContinueSessionCrashTests: XCTestCase {
    func testContinueFromDashboardOpensSessionDetail() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestSeedInterruptedSession"]
        XCUIDevice.shared.orientation = .landscapeRight
        app.launch()

        let continueButton = app.descendants(matching: .any)["continue.session"]
        XCTAssertTrue(continueButton.waitForExistence(timeout: 6))
        continueButton.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["screen.数据采集"].waitForExistence(timeout: 4)
        )

        let sessionRow = app.descendants(matching: .any)["continue.session.row"]
        XCTAssertTrue(sessionRow.waitForExistence(timeout: 4))
        sessionRow.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["session.detail"].waitForExistence(timeout: 4)
        )
        XCTAssertTrue(
            app.staticTexts["需要重做"].waitForExistence(timeout: 4)
        )

        let currentTask = app.descendants(matching: .any)["continue.current-task"]
        XCTAssertTrue(currentTask.waitForExistence(timeout: 4))
        currentTask.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["task.runner"].waitForExistence(timeout: 4)
        )
        XCTAssertEqual(app.state, .runningForeground)
    }
}
