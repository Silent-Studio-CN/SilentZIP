import Foundation

/// 语言文件加载器。
///
/// 格式是最朴素的 INI：key = value，分号开头是注释。
/// 之所以用这个，是因为改起来不需要懂任何编程 —— 打开文件，
/// 改等号右边，保存，重启 app 就生效。
enum L10n {
    private static var table: [String: String] = [:]
    private static var currentLanguage: String = "zh-Hans"

    /// 已加载的键数量，给「语言」设置页显示用
    static var keyCount: Int { table.count }

    static var language: String { currentLanguage }

    /// 启动时调一次
    static func load(_ lang: String = preferred()) {
        currentLanguage = lang
        table = [:]

        // 优先找用户放到 Application Support 的自定义语言文件
        let custom = userLanguageDir.appendingPathComponent(lang + ".ini")
        if FileManager.default.fileExists(atPath: custom.path),
           let text = try? String(contentsOf: custom, encoding: .utf8) {
            parse(text)
            return
        }

        // 其次用 app 内置的
        if let url = Bundle.main.url(forResource: lang, withExtension: "ini",
                                     subdirectory: "app"),
           let text = try? String(contentsOf: url, encoding: .utf8) {
            parse(text)
        }
    }

    /// 系统语言偏好 → 我们的语言代码
    static func preferred() -> String {
        let saved = UserDefaults.standard.string(forKey: "uiLanguage") ?? ""
        if !saved.isEmpty { return saved }

        let sys = Locale.preferredLanguages.first ?? "zh-Hans"
        if sys.hasPrefix("zh-Hant") || sys.hasPrefix("zh-TW") || sys.hasPrefix("zh-HK") {
            return "zh-Hant"
        }
        if sys.hasPrefix("zh") { return "zh-Hans" }
        return "en"
    }

    /// 用户自定义语言文件放哪
    static var userLanguageDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory())
        let dir = base.appendingPathComponent("SilentZIP/Languages", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func parse(_ text: String) {
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix(";") || line.hasPrefix("#") { continue }
            if line.hasPrefix("[") { continue }   // 段名只做分组，键本身要唯一

            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = String(line[line.startIndex..<eq]).trimmingCharacters(in: .whitespaces)
            let val = String(line[line.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
            if !key.isEmpty { table[key] = val }
        }
    }

    /// 取一个键。找不到就用 fallback，保证界面上永远不会出现裸 key
    static func t(_ key: String, _ fallback: String) -> String {
        if let v = table[key], !v.isEmpty { return v }
        return fallback
    }
}
