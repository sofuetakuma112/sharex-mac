import AppKit
import ImageIO
import UniformTypeIdentifiers
import UserNotifications

final class CaptureOutput {
    private let settings = Settings.shared
    private lazy var captureSound = NSSound(named: "CaptureSound")
    private lazy var completedSound = NSSound(named: "TaskCompletedSound")

    func playCaptureSound() {
        guard settings.isEnabled(.playSound) else { return }
        captureSound?.stop()
        captureSound?.play()
    }

    func handle(_ captured: CapturedImage) throws {
        var savedURL: URL?
        if settings.isEnabled(.saveToFile) {
            let url = try save(captured)
            settings.addRecentFile(url)
            savedURL = url
        }
        if settings.isEnabled(.copyToClipboard) {
            copyToClipboard(captured)
        }
        if settings.isEnabled(.playSound) {
            completedSound?.play()
        }
        if settings.isEnabled(.showNotification) {
            notify(captured, savedURL: savedURL)
        }
    }

    private func save(_ captured: CapturedImage) throws -> URL {
        let folder = settings.screenshotsFolder
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var url = folder.appendingPathComponent(Self.randomName()).appendingPathExtension("png")
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent(Self.randomName()).appendingPathExtension("png")
        }
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let dpi = 72 * captured.scale
        let properties: [CFString: Any] = [kCGImagePropertyDPIWidth: dpi, kCGImagePropertyDPIHeight: dpi]
        CGImageDestinationAddImage(destination, captured.image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
        return url
    }

    private func copyToClipboard(_ captured: CapturedImage) {
        let size = CGSize(width: CGFloat(captured.image.width) / captured.scale, height: CGFloat(captured.image.height) / captured.scale)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([NSImage(cgImage: captured.image, size: size)])
    }

    private func notify(_ captured: CapturedImage, savedURL: URL?) {
        let content = UNMutableNotificationContent()
        content.title = savedURL == nil ? "クリップボードにコピーしました" : "キャプチャを保存しました"
        let dimensions = "\(captured.image.width) × \(captured.image.height)"
        content.body = savedURL.map { "\($0.lastPathComponent)（\(dimensions)）" } ?? dimensions
        if let savedURL {
            content.userInfo = ["path": savedURL.path]
        }
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private static func randomName() -> String {
        let characters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789")
        return String((0..<10).map { _ in characters.randomElement()! })
    }
}
