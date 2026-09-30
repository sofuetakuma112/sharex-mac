import ImageIO
import XCTest
@testable import SharexMac

final class CaptureOutputTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var temporaryFolder: URL!

    override func setUp() {
        suiteName = "CaptureOutputTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        temporaryFolder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defaults.set(temporaryFolder.path, forKey: Settings.screenshotsFolderKey)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: temporaryFolder)
    }

    func testRandomNameIsTenAlphanumericCharacters() {
        for _ in 0..<100 {
            let name = CaptureOutput.randomName()
            XCTAssertEqual(name.count, 10)
            XCTAssertTrue(name.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }, name)
        }
    }

    func testSaveWritesPNGIntoScreenshotsFolderWithRetinaDPI() throws {
        let output = CaptureOutput(settings: Settings(defaults: defaults))
        let url = try output.save(CapturedImage(image: try makeImage(width: 40, height: 30), scale: 2))

        XCTAssertEqual(url.deletingLastPathComponent().standardizedFileURL.path, temporaryFolder.standardizedFileURL.path)
        XCTAssertEqual(url.pathExtension, "png")

        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        XCTAssertEqual(properties[kCGImagePropertyPixelWidth] as? Int, 40)
        XCTAssertEqual(properties[kCGImagePropertyPixelHeight] as? Int, 30)
        XCTAssertEqual((properties[kCGImagePropertyDPIWidth] as? Double) ?? 0, 144, accuracy: 0.5)
    }

    private func makeImage(width: Int, height: Int) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try XCTUnwrap(context.makeImage())
    }
}
