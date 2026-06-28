//
//  VvoxUITestsLaunchTests.swift
//  VvoxUITests
//
//  Created by marcop on 2026-06-27.
//

import XCTest

final class VvoxUITestsLaunchTests: XCTestCase {

    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        // Keep `false` so the launch test runs once in the current system
        // appearance instead of flipping between Light and Dark variants
        // every run — which was inadvertently overriding the user's
        // system-wide Auto appearance setting.
        false
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunch() throws {
        let app = XCUIApplication()
        app.launch()

        // Insert steps here to perform after app launch but before taking a screenshot,
        // such as logging into a test account or navigating somewhere in the app
        // XCUIAutomation Documentation
        // https://developer.apple.com/documentation/xcuiautomation

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
