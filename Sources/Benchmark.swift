import AppKit

/// 7-Zip 自带基准测试（7z b），测本机的压缩/解压吞吐。
/// 结果按官方给的 MIPS 单位显示，方便跟别人对比。
enum Benchmark {

    static func run() {
        let alert = NSAlert()
        alert.messageText = L10n.t("bench.title", "基准测试")
        alert.informativeText = L10n.t("bench.hint",
            "会跑一遍压缩和解压，大概十几秒。结果单位 MIPS，越大越快。")
        alert.addButton(withTitle: L10n.t("bench.start", "开始"))
        alert.addButton(withTitle: L10n.t("ui.cancel", "取消"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        DispatchQueue.global(qos: .userInitiated).async {
            let text = execute()
            DispatchQueue.main.async { show(text) }
        }
    }

    private static func execute() -> String {
        guard let tool = Bundle.main.url(forResource: "7zz", withExtension: nil),
              FileManager.default.isExecutableFile(atPath: tool.path) else {
            return "找不到 7-Zip 引擎"
        }

        let p = Process()
        p.executableURL = tool
        p.arguments = ["b"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do { try p.run() } catch { return error.localizedDescription }

        // 超时保护：基准测试正常十秒内结束
        let deadline = Date().addingTimeInterval(120)
        while p.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.2)
        }
        if p.isRunning { p.terminate() }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    private static func show(_ raw: String) {
        // 只留关键行，去掉进度刷屏
        let keep = raw.components(separatedBy: .newlines).filter { line in
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.isEmpty { return false }
            if t.hasPrefix("7-Zip") { return true }
            if t.contains("MIPS") || t.contains("Tot:") { return true }
            if t.hasPrefix("Compressing") || t.hasPrefix("Decompressing") { return true }
            if t.contains("Threads") { return true }
            return false
        }
        let body = keep.isEmpty ? raw : keep.joined(separator: "\n")

        let alert = NSAlert()
        alert.messageText = L10n.t("bench.result", "基准测试结果")
        alert.addButton(withTitle: L10n.t("ui.ok", "好"))
        alert.addButton(withTitle: L10n.t("ui.copyCommand", "复制结果"))

        let tv = NSTextView(frame: NSRect(x: 0, y: 0, width: 460, height: 220))
        tv.string = body
        tv.isEditable = false
        tv.isSelectable = true
        tv.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        tv.textContainerInset = NSSize(width: 8, height: 8)
        tv.isVerticallyResizable = true
        tv.textContainer?.widthTracksTextView = true

        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 460, height: 220))
        scroll.documentView = tv
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        alert.accessoryView = scroll

        if alert.runModal() == .alertSecondButtonReturn {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(body, forType: .string)
        }
    }
}
