import Foundation

enum AppInfo {
    static let name = "sharex-mac"
}

func localized(_ key: String) -> String {
    NSLocalizedString(key, bundle: .main, comment: "")
}

func localized(_ key: String, _ arguments: CVarArg...) -> String {
    String(format: localized(key), arguments: arguments)
}
