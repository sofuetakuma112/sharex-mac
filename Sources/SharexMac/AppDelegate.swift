import AppKit
import ServiceManagement
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, UNUserNotificationCenterDelegate {
    private enum CaptureMode {
        case region
        case activeWindow
        case fullscreen
    }

    private var statusItem: NSStatusItem!
    private let hotkeyManager = HotkeyManager()
    private let output = CaptureOutput()
    private let settings = Settings.shared
    private var regionSelector: RegionSelector?
    private var imageHistory: ImageHistoryWindowController?
    private var isCapturing = false

    private let recentMenu = NSMenu()
    private let afterCaptureMenu = NSMenu()
    private var launchAtLoginItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        setUpStatusItem()
        registerHotkeys()
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        if !CGPreflightScreenCaptureAccess() {
            CGRequestScreenCaptureAccess()
        }
    }

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "sharex-mac")
        image?.isTemplate = true
        statusItem.button?.image = image

        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(menuItem("範囲キャプチャ", hotkey: .region, action: #selector(captureRegion)))
        menu.addItem(menuItem("ウィンドウキャプチャ", hotkey: .activeWindow, action: #selector(captureActiveWindow)))
        menu.addItem(menuItem("全画面キャプチャ", hotkey: .fullscreen, action: #selector(captureFullscreen)))
        menu.addItem(.separator())

        menu.addItem(NSMenuItem(title: "画像履歴…", action: #selector(showImageHistory), keyEquivalent: ""))
        let recentItem = NSMenuItem(title: "最近のキャプチャ", action: nil, keyEquivalent: "")
        recentMenu.delegate = self
        recentItem.submenu = recentMenu
        menu.addItem(recentItem)
        menu.addItem(NSMenuItem(title: "スクリーンショットフォルダを開く", action: #selector(openScreenshotsFolder), keyEquivalent: ""))
        menu.addItem(.separator())

        let afterCaptureItem = NSMenuItem(title: "キャプチャ後の処理", action: nil, keyEquivalent: "")
        afterCaptureMenu.delegate = self
        afterCaptureItem.submenu = afterCaptureMenu
        menu.addItem(afterCaptureItem)
        launchAtLoginItem = NSMenuItem(title: "ログイン時に起動", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        menu.addItem(launchAtLoginItem)
        menu.addItem(NSMenuItem(title: "画面収録の権限設定を開く…", action: #selector(openScreenRecordingSettings), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "sharex-mac を終了", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        menu.items.forEach { if $0.action != #selector(NSApplication.terminate(_:)) { $0.target = self } }
        statusItem.menu = menu
    }

    private func menuItem(_ title: String, hotkey: Hotkey, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: hotkey.keyEquivalent)
        item.keyEquivalentModifierMask = hotkey.modifiers
        return item
    }

    private func registerHotkeys() {
        let registrations: [(Hotkey, CaptureMode)] = [(.region, .region), (.activeWindow, .activeWindow), (.fullscreen, .fullscreen)]
        let failed = registrations.filter { hotkey, mode in
            !hotkeyManager.register(hotkey) { [weak self] in self?.startCapture(mode, delay: 0) }
        }
        if !failed.isEmpty {
            showError("一部のホットキーを登録できませんでした。他のアプリが同じショートカットを使用している可能性があります。")
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu === recentMenu {
            rebuildRecentMenu()
        } else if menu === afterCaptureMenu {
            rebuildAfterCaptureMenu()
        } else {
            launchAtLoginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        }
    }

    private func rebuildRecentMenu() {
        recentMenu.removeAllItems()
        let files = settings.recentFiles
        if files.isEmpty {
            let empty = NSMenuItem(title: "なし", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            recentMenu.addItem(empty)
            return
        }
        for url in files {
            let item = NSMenuItem(title: url.lastPathComponent, action: #selector(openRecentFile(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = url
            if let thumbnail = NSImage(contentsOf: url) {
                thumbnail.size = CGSize(width: 32, height: 32 * thumbnail.size.height / max(thumbnail.size.width, 1))
                item.image = thumbnail
            }
            recentMenu.addItem(item)
        }
        recentMenu.addItem(.separator())
        let showAll = NSMenuItem(title: "すべて表示…", action: #selector(showImageHistory), keyEquivalent: "")
        showAll.target = self
        recentMenu.addItem(showAll)
    }

    private func rebuildAfterCaptureMenu() {
        afterCaptureMenu.removeAllItems()
        for task in AfterCaptureTask.allCases {
            let item = NSMenuItem(title: task.title, action: #selector(toggleAfterCaptureTask(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = task.rawValue
            item.state = settings.isEnabled(task) ? .on : .off
            afterCaptureMenu.addItem(item)
        }
    }

    @objc private func captureRegion() { startCapture(.region, delay: 0.25) }
    @objc private func captureActiveWindow() { startCapture(.activeWindow, delay: 0.25) }
    @objc private func captureFullscreen() { startCapture(.fullscreen, delay: 0.25) }

    private func startCapture(_ mode: CaptureMode, delay: TimeInterval) {
        guard !isCapturing else { return }
        isCapturing = true
        Task { @MainActor in
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            do {
                switch mode {
                case .region:
                    try await performRegionCapture()
                case .activeWindow:
                    try complete(with: await ScreenCapturer.captureFrontmostWindow())
                case .fullscreen:
                    try complete(with: await ScreenCapturer.captureScreenUnderMouse())
                }
            } catch {
                isCapturing = false
                handleCaptureError(error)
            }
        }
    }

    @MainActor
    private func performRegionCapture() async throws {
        let windows = ScreenCapturer.onScreenWindows()
        let snapshots = try await ScreenCapturer.snapshotAllScreens()
        let selector = RegionSelector()
        regionSelector = selector
        selector.begin(snapshots: snapshots, windows: windows) { [weak self] result in
            guard let self else { return }
            regionSelector = nil
            guard let result else {
                isCapturing = false
                return
            }
            do {
                try complete(with: result)
            } catch {
                isCapturing = false
                handleCaptureError(error)
            }
        }
    }

    private func complete(with captured: CapturedImage) throws {
        defer { isCapturing = false }
        output.playCaptureSound()
        try output.handle(captured)
        imageHistory?.reloadIfVisible()
    }

    @objc private func showImageHistory() {
        let controller = imageHistory ?? ImageHistoryWindowController()
        imageHistory = controller
        controller.present()
    }

    private func handleCaptureError(_ error: Error) {
        if !CGPreflightScreenCaptureAccess() {
            let alert = NSAlert()
            alert.messageText = "画面収録の権限が必要です"
            alert.informativeText = "システム設定 > プライバシーとセキュリティ > 画面収録とシステムオーディオ録音 で sharex-mac を許可してから、sharex-mac を再起動してください。"
            alert.addButton(withTitle: "システム設定を開く")
            alert.addButton(withTitle: "キャンセル")
            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertFirstButtonReturn {
                openScreenRecordingSettings()
            }
            return
        }
        showError(error.localizedDescription)
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "sharex-mac"
        alert.informativeText = message
        alert.alertStyle = .warning
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    @objc private func openRecentFile(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func openScreenshotsFolder() {
        let folder = settings.screenshotsFolder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(folder)
    }

    @objc private func toggleAfterCaptureTask(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String, let task = AfterCaptureTask(rawValue: rawValue) else { return }
        settings.toggle(task)
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            showError("ログイン時の起動設定を変更できませんでした: \(error.localizedDescription)")
        }
    }

    @objc private func openScreenRecordingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if let path = response.notification.request.content.userInfo["path"] as? String {
            let url = URL(fileURLWithPath: path)
            DispatchQueue.main.async { NSWorkspace.shared.open(url) }
        }
        completionHandler()
    }
}
