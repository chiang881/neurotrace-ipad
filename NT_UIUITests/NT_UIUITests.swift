import XCTest

final class NT_UIUITests: XCTestCase {
    func testLaunchAndOpenAllTabs() {
        let app = XCUIApplication()
        XCUIDevice.shared.orientation = .landscapeRight
        app.launch()

        XCTAssertTrue(
            app.descendants(matching: .any)["screen.羊皮纸"].waitForExistence(timeout: 5)
        )

        let tabs = [
            ("tab.collection", "screen.数据采集"),
            ("tab.records", "screen.测试记录"),
            ("tab.trends", "screen.数据趋势"),
            ("tab.dashboard", "screen.羊皮纸")
        ]
        for (tab, screen) in tabs {
            let button = app.descendants(matching: .any)[tab].firstMatch
            XCTAssertTrue(button.waitForExistence(timeout: 3))
            button.tap()
            XCTAssertTrue(app.descendants(matching: .any)[screen].waitForExistence(timeout: 3))
        }
    }
}
