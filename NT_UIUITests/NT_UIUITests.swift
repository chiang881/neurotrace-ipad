import XCTest

final class NT_UIUITests: XCTestCase {
    func testLaunchAndOpenAllSidebarSections() {
        let app = XCUIApplication()
        XCUIDevice.shared.orientation = .landscapeRight
        app.launch()

        XCTAssertTrue(
            app.descendants(matching: .any)["screen.羊皮纸"].waitForExistence(timeout: 5)
        )

        let sections = [
            ("sidebar.subjects", "screen.受试者"),
            ("sidebar.sessions", "screen.测试"),
            ("sidebar.settings", "screen.设置"),
            ("sidebar.dashboard", "screen.羊皮纸")
        ]
        for (section, screen) in sections {
            let button = app.descendants(matching: .any)[section].firstMatch
            XCTAssertTrue(button.waitForExistence(timeout: 3))
            button.tap()
            XCTAssertTrue(app.descendants(matching: .any)[screen].waitForExistence(timeout: 3))
        }
    }
}
