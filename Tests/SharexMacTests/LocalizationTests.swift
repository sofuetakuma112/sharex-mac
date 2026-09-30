import XCTest

final class LocalizationTests: XCTestCase {
    private let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    func testEveryLocalizedKeyHasJapaneseTranslation() throws {
        let stringsURL = root.appendingPathComponent("Resources/ja.lproj/Localizable.strings")
        let translations = try XCTUnwrap(NSDictionary(contentsOf: stringsURL) as? [String: String])

        let sourcesURL = root.appendingPathComponent("Sources/SharexMac")
        let sourceFiles = try FileManager.default.contentsOfDirectory(at: sourcesURL, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        let pattern = try NSRegularExpression(pattern: #"localized\("((?:[^"\\]|\\.)*)""#)

        var keys: Set<String> = []
        for file in sourceFiles {
            let source = try String(contentsOf: file, encoding: .utf8)
            for match in pattern.matches(in: source, range: NSRange(source.startIndex..., in: source)) {
                if let range = Range(match.range(at: 1), in: source) {
                    keys.insert(String(source[range]))
                }
            }
        }

        XCTAssertFalse(keys.isEmpty)
        let missing = keys.subtracting(translations.keys).sorted()
        XCTAssertTrue(missing.isEmpty, "Missing ja translations: \(missing)")
        let unused = Set(translations.keys).subtracting(keys).sorted()
        XCTAssertTrue(unused.isEmpty, "Unused ja translations: \(unused)")
    }
}
