import Cocoa
import FinderSync

/// Finder 右键菜单扩展。
/// 目的：让右键里出现「SilentZIP ▸」这样的二级菜单，
/// 悬停展开「打开 / 解压到此处 / 压缩为 7z / 添加标签」等。
/// NSServices 只能挂到「快速操作」，做不出二级菜单，所以必须走 FinderSync。
final class FinderSync: FIFinderSync {

    override init() {
        super.init()
        // 监听所有卷，右键任何位置都能用
        FIFinderSyncController.default().directoryURLs = [URL(fileURLWithPath: "/")]
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu {
        let menu = NSMenu(title: "")

        let root = NSMenuItem(title: "SilentZIP", action: nil, keyEquivalent: "")
        let sub = NSMenu(title: "SilentZIP")

        sub.addItem(withTitle: "用 SilentZIP 打开",
                    action: #selector(openArchive(_:)), keyEquivalent: "")
        sub.addItem(withTitle: "解压到此处",
                    action: #selector(extractHere(_:)), keyEquivalent: "")
        sub.addItem(.separator())
        sub.addItem(withTitle: "压缩为 7z…",
                    action: #selector(compress7z(_:)), keyEquivalent: "")
        sub.addItem(withTitle: "压缩为 zip…",
                    action: #selector(compressZip(_:)), keyEquivalent: "")

        for item in sub.items where item.action != nil {
            item.target = self
        }

        root.submenu = sub
        menu.addItem(root)
        return menu
    }

    // MARK: - 动作

    private var selectedURLs: [URL] {
        let items = FIFinderSyncController.default().selectedItemURLs() ?? []
        if !items.isEmpty { return items }
        if let t = FIFinderSyncController.default().targetedURL() { return [t] }
        return []
    }

    @objc private func openArchive(_ sender: AnyObject?) {
        guard let u = selectedURLs.first else { return }
        NSWorkspace.shared.openApplication(
            at: appURL, configuration: NSWorkspace.OpenConfiguration()) { app, _ in
            NSWorkspace.shared.open([u], withApplicationAt: self.appURL,
                                    configuration: NSWorkspace.OpenConfiguration()) { _, _ in }
        }
    }

    @objc private func extractHere(_ sender: AnyObject?) {
        guard let u = selectedURLs.first else { return }
        run("x", [u.path, "-o" + u.deletingLastPathComponent().path, "-y"])
    }

    @objc private func compress7z(_ sender: AnyObject?) {
        guard let first = selectedURLs.first else { return }
        let target = first.deletingLastPathComponent()
            .appendingPathComponent(first.deletingPathExtension().lastPathComponent + ".7z")
        var args = ["a", target.path]
        args.append(contentsOf: selectedURLs.map { $0.path })
        run("a", Array(args.dropFirst()), archive: target.path)
    }

    @objc private func compressZip(_ sender: AnyObject?) {
        guard let first = selectedURLs.first else { return }
        let target = first.deletingLastPathComponent()
            .appendingPathComponent(first.deletingPathExtension().lastPathComponent + ".zip")
        run("a", Array(["-tzip", target.path] + selectedURLs.map { $0.path }))
    }

    // MARK: - 工具

    private var appURL: URL {
        // appex 在 SilentZIP.app/Contents/PlugIns/ 下，往上四层就是 .app
        var u = Bundle.main.bundleURL
        for _ in 0..<4 { u = u.deletingLastPathComponent() }
        return u.pathExtension == "app" ? u : URL(fileURLWithPath: "/Applications/SilentZIP.app")
    }

    private func run(_ sub: String, _ args: [String], archive: String? = nil) {
        guard let tool = Self.find7z() else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = (archive == nil ? [sub] : [sub]) + args
        try? p.run()
    }

    static func find7z() -> String? {
        for c in ["/opt/homebrew/bin/7z", "/usr/local/bin/7z", "/opt/homebrew/bin/7zz"] {
            if FileManager.default.isExecutableFile(atPath: c) { return c }
        }
        return nil
    }
}
