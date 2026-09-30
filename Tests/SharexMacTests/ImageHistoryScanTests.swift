import XCTest
@testable import SharexMac

final class ImageHistoryScanTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("2026-09"), withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: folder)
    }

    func testScanFindsImagesRecursivelyNewestFirst() throws {
        try createFile("old.png", date: Date(timeIntervalSince1970: 1_000))
        try createFile("2026-09/newest.JPG", date: Date(timeIntervalSince1970: 3_000))
        try createFile("middle.gif", date: Date(timeIntervalSince1970: 2_000))

        let names = ImageHistoryWindowController.scan(folder).map(\.url.lastPathComponent)
        XCTAssertEqual(names, ["newest.JPG", "middle.gif", "old.png"])
    }

    func testScanIgnoresNonImagesAndHiddenFiles() throws {
        try createFile("notes.txt", date: Date())
        try createFile(".hidden.png", date: Date())
        try createFile("shot.png", date: Date())

        XCTAssertEqual(ImageHistoryWindowController.scan(folder).map(\.url.lastPathComponent), ["shot.png"])
    }

    func testScanOfMissingFolderIsEmpty() {
        XCTAssertTrue(ImageHistoryWindowController.scan(folder.appendingPathComponent("missing")).isEmpty)
    }

    private func createFile(_ relativePath: String, date: Date) throws {
        let url = folder.appendingPathComponent(relativePath)
        try Data([0]).write(to: url)
        try FileManager.default.setAttributes([.creationDate: date, .modificationDate: date], ofItemAtPath: url.path)
    }
}
