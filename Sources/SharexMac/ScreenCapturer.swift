import AppKit
import ScreenCaptureKit

struct CapturedImage {
    let image: CGImage
    let scale: CGFloat
}

struct ScreenSnapshot {
    let screen: NSScreen
    let image: CGImage
}

struct WindowInfo {
    let id: CGWindowID
    let processID: pid_t
    let frame: CGRect
}

enum CaptureError: LocalizedError {
    case displayNotFound
    case windowNotFound

    var errorDescription: String? {
        switch self {
        case .displayNotFound: "キャプチャ対象のディスプレイが見つかりません。"
        case .windowNotFound: "キャプチャ対象のウィンドウが見つかりません。"
        }
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    var globalFrame: CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? frame.height
        return CGRect(x: frame.minX, y: primaryHeight - frame.maxY, width: frame.width, height: frame.height)
    }

    static var underMouse: NSScreen? {
        let location = NSEvent.mouseLocation
        return screens.first { NSMouseInRect(location, $0.frame, false) } ?? main
    }

    static func bestMatch(forGlobalRect rect: CGRect) -> NSScreen? {
        screens.max { lhs, rhs in
            lhs.globalFrame.intersection(rect).area < rhs.globalFrame.intersection(rect).area
        }
    }
}

private extension CGRect {
    var area: CGFloat { isNull ? 0 : width * height }
}

enum ScreenCapturer {
    static func snapshotAllScreens() async throws -> [ScreenSnapshot] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        var snapshots: [ScreenSnapshot] = []
        for screen in NSScreen.screens {
            guard let display = content.displays.first(where: { $0.displayID == screen.displayID }) else { continue }
            let image = try await capture(display: display, scale: screen.backingScaleFactor)
            snapshots.append(ScreenSnapshot(screen: screen, image: image))
        }
        guard !snapshots.isEmpty else { throw CaptureError.displayNotFound }
        return snapshots
    }

    static func captureScreenUnderMouse() async throws -> CapturedImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let screen = NSScreen.underMouse,
              let display = content.displays.first(where: { $0.displayID == screen.displayID }) else {
            throw CaptureError.displayNotFound
        }
        let image = try await capture(display: display, scale: screen.backingScaleFactor)
        return CapturedImage(image: image, scale: screen.backingScaleFactor)
    }

    static func captureFrontmostWindow() async throws -> CapturedImage {
        guard let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              let target = onScreenWindows().first(where: { $0.processID == frontmostPID }) else {
            throw CaptureError.windowNotFound
        }
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        guard let window = content.windows.first(where: { $0.windowID == target.id }) else {
            throw CaptureError.windowNotFound
        }
        let scale = NSScreen.bestMatch(forGlobalRect: window.frame)?.backingScaleFactor ?? 2
        let configuration = SCStreamConfiguration()
        configuration.width = Int(window.frame.width * scale)
        configuration.height = Int(window.frame.height * scale)
        configuration.showsCursor = false
        configuration.ignoreShadowsSingleWindow = true
        configuration.captureResolution = .best
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        return CapturedImage(image: image, scale: scale)
    }

    static func onScreenWindows() -> [WindowInfo] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }
        return list.compactMap { info in
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  let id = info[kCGWindowNumber as String] as? CGWindowID,
                  let processID = info[kCGWindowOwnerPID as String] as? pid_t,
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let bounds = info[kCGWindowBounds as String],
                  let frame = CGRect(dictionaryRepresentation: bounds as! CFDictionary),
                  frame.width > 20, frame.height > 20 else {
                return nil
            }
            return WindowInfo(id: id, processID: processID, frame: frame)
        }
    }

    private static func capture(display: SCDisplay, scale: CGFloat) async throws -> CGImage {
        let configuration = SCStreamConfiguration()
        configuration.width = Int(CGFloat(display.width) * scale)
        configuration.height = Int(CGFloat(display.height) * scale)
        configuration.showsCursor = false
        configuration.captureResolution = .best
        let filter = SCContentFilter(display: display, excludingWindows: [])
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
    }
}
