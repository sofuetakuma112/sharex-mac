import Foundation

enum AfterCaptureTask: String, CaseIterable {
    case saveToFile
    case copyToClipboard
    case showNotification
    case playSound

    var title: String {
        switch self {
        case .saveToFile: "ファイルに保存"
        case .copyToClipboard: "クリップボードにコピー"
        case .showNotification: "通知を表示"
        case .playSound: "サウンドを再生"
        }
    }
}

final class Settings {
    static let shared = Settings()

    private let defaults = UserDefaults.standard
    private let recentFilesKey = "recentFiles"
    private let recentFilesLimit = 10
    private let thumbnailSizeKey = "imageHistoryThumbnailSize"

    private init() {
        var registered: [String: Any] = Dictionary(uniqueKeysWithValues: AfterCaptureTask.allCases.map { ($0.rawValue, true) })
        registered[thumbnailSizeKey] = 160.0
        defaults.register(defaults: registered)
    }

    var thumbnailSize: Double {
        get { defaults.double(forKey: thumbnailSizeKey) }
        set { defaults.set(newValue, forKey: thumbnailSizeKey) }
    }

    func isEnabled(_ task: AfterCaptureTask) -> Bool {
        defaults.bool(forKey: task.rawValue)
    }

    func toggle(_ task: AfterCaptureTask) {
        defaults.set(!isEnabled(task), forKey: task.rawValue)
    }

    var screenshotsFolder: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Pictures", isDirectory: true)
            .appendingPathComponent("ShareX", isDirectory: true)
    }

    var recentFiles: [URL] {
        (defaults.stringArray(forKey: recentFilesKey) ?? [])
            .map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    func addRecentFile(_ url: URL) {
        var paths = defaults.stringArray(forKey: recentFilesKey) ?? []
        paths.removeAll { $0 == url.path }
        paths.insert(url.path, at: 0)
        defaults.set(Array(paths.prefix(recentFilesLimit)), forKey: recentFilesKey)
    }
}
