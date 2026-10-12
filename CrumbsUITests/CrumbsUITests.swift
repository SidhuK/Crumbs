//
//  CrumbsUITests.swift
//  CrumbsUITests
//

import XCTest

final class CrumbsUITests: XCTestCase {
    private var storageFolder: URL!

    override func setUpWithError() throws {
        continueAfterFailure = false
        storageFolder = URL.temporaryDirectory.appending(path: "CrumbsUITests-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: storageFolder)
    }

    /// Launches against an empty folder and checks the panel comes up and saves a typed note.
    @MainActor
    func testComposerAddsNoteToMarkdownFile() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-storageFolder", storageFolder.path(percentEncoded: false),
            "-activeList", "UITest",
            "-uiTesting",
        ]
        app.launch()

        let composer = app.descendants(matching: .any)["composer"].firstMatch
        XCTAssertTrue(composer.waitForExistence(timeout: 5))
        composer.click()
        composer.typeText("Remember the schema version\r")

        let fileURL = storageFolder.appending(path: "UITest.md")
        let saved = expectation(for: NSPredicate { _, _ in
            (try? String(contentsOf: fileURL, encoding: .utf8))?.contains("- [ ] Remember the schema version") == true
        }, evaluatedWith: nil)
        wait(for: [saved], timeout: 5)
    }
}
