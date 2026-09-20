//
//  DriveOpsUITests.swift
//  DriveOpsUITests
//
//  Created by Abdul Baari Davids on 2026/03/25.
//

import XCTest

final class DriveOpsUITests: XCTestCase {
    @MainActor
    func testTrackLandscapeAndFieldSelection() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-hasSeenWelcome", "YES"]
        app.launch()
        app.tabBars.buttons["Track"].tap()
        app.buttons["Enter Track"].tap()
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        XCTAssertTrue(app.buttons["START"].waitForExistence(timeout: 5))
        // The full-screen cover's tab bar can briefly remain queryable in the
        // accessibility tree while its dismissal animation finishes, even
        // after the new screen's own content already exists — wait it out
        // instead of asserting the instant START appears.
        let tabBarGone = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: tabBarGone, object: app.tabBars.firstMatch)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: 15), .completed)
        app.buttons["START"].tap()
        XCTAssertTrue(app.buttons["LAP"].waitForExistence(timeout: 5))
        app.buttons["LAP"].tap()
        XCTAssertTrue(app.staticTexts["LAP 2"].exists)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Track landscape"
        attachment.lifetime = .keepAlways
        add(attachment)
        app.descendants(matching: .any)["track-field-0"].firstMatch.press(forDuration: 1)
        XCTAssertTrue(app.navigationBars["Change field"].waitForExistence(timeout: 5))
        app.buttons.containing(.staticText, identifier: "Engine RPM").firstMatch.tap()
        XCTAssertTrue(app.buttons["Exit"].waitForExistence(timeout: 5))
        app.buttons["Exit"].tap()
        app.tabBars.buttons["Settings"].tap()
        app.segmentedControls.buttons["Logs"].tap()
        XCTAssertTrue(app.navigationBars["Logs"].exists)
    }

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testExample() throws {
        // UI tests must launch the application that they test.
        let app = XCUIApplication()
        app.launch()

        // Use XCTAssert and related functions to verify your tests produce the correct results.
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
