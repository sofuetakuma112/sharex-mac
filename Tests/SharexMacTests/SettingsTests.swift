import XCTest
@testable import SharexMac

final class SettingsTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var temporaryFolder: URL!

    override func setUpWithError() throws {
        suiteName = "SettingsTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        temporaryFolder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryFolder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: temporaryFolder)
    }

    func testAfterCaptureTasksAreEnabledByDefault() {
        let settings = Settings(defaults: defaults)
        for task in AfterCaptureTask.allCases {
            XCTAssertTrue(settings.isEnabled(task), task.rawValue)
        }
    }

    func testToggleFlipsTask() {
        let settings = Settings(defaults: defaults)
        settings.toggle(.playSound)
        XCTAssertFalse(settings.isEnabled(.playSound))
        settings.toggle(.playSound)
        XCTAssertTrue(settings.isEnabled(.playSound))
    }

    func testThumbnailSizeDefaultsTo160() {
        XCTAssertEqual(Settings(defaults: defaults).thumbnailSize, 160)
    }

    func testScreenshotsFolderDefaultsToPictures() {
        let expected = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Pictures/sharex-mac")
        XCTAssertEqual(Settings(defaults: defaults).screenshotsFolder.standardizedFileURL.path, expected.standardizedFileURL.path)
    }

    func testScreenshotsFolderCanBeOverriddenWithTildePath() {
        defaults.set("~/Desktop/Captures", forKey: Settings.screenshotsFolderKey)
        let expected = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop/Captures")
        XCTAssertEqual(Settings(defaults: defaults).screenshotsFolder.standardizedFileURL.path, expected.standardizedFileURL.path)
    }

    func testRecentFilesAreDeduplicatedNewestFirstAndLimited() throws {
        let settings = Settings(defaults: defaults)
        let files = try (0..<(Settings.recentFilesLimit + 2)).map { index -> URL in
            let url = temporaryFolder.appendingPathComponent("\(index).png")
            try Data().write(to: url)
            return url
        }
        files.forEach(settings.addRecentFile)
        settings.addRecentFile(files[5])

        let recent = settings.recentFiles
        XCTAssertEqual(recent.count, Settings.recentFilesLimit)
        XCTAssertEqual(recent.first?.lastPathComponent, "5.png")
        XCTAssertEqual(Set(recent.map(\.lastPathComponent)).count, recent.count)
    }

    func testRecentFilesSkipDeletedFiles() throws {
        let settings = Settings(defaults: defaults)
        let url = temporaryFolder.appendingPathComponent("deleted.png")
        try Data().write(to: url)
        settings.addRecentFile(url)
        try FileManager.default.removeItem(at: url)
        XCTAssertTrue(settings.recentFiles.isEmpty)
    }
}
