import Foundation

/// 一个在跑的 7z 任务：能看进度、能暂停、能取消、能降到后台。
///
/// 7z 的进度是往 stdout 刷的（-bsp1），用 \r 覆盖同一行：
///     4% 20 + big/f9.bin        9% 20 + big/f9.bin ...
/// 这里按 \r 切开，取最后一个百分比。
final class ProgressTask {

    let process = Process()
    private let pipe = Pipe()
    private let errPipe = Pipe()
    private var buffer = ""

    private(set) var percent: Int = 0
    private(set) var currentFile: String = ""
    private(set) var isPaused = false
    private(set) var isCancelled = false

    /// 进度回调：(百分比, 当前文件)
    var onProgress: ((Int, String) -> Void)?
    /// 结束回调：(是否成功, 输出末尾)
    var onFinish: ((Bool, String) -> Void)?

    private var allOutput = ""

    init(tool: String, args: [String], cwd: URL?) {
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = args
        if let cwd { process.currentDirectoryURL = cwd }

        var env = ProcessInfo.processInfo.environment
        env["LC_ALL"] = "C"
        env["LANG"] = "C"
        process.environment = env

        // stdout 和 stderr 必须分开接 —— 共用一个 Pipe 的话
        // 增量读取会丢数据（7z 的进度全在 stdout）
        process.standardOutput = pipe
        process.standardError = errPipe

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            self?.consume(text)
        }
        errPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            self?.allOutput += text
        }
    }

    func start() throws {
        try process.run()
        // 让它跟着进程死
        DispatchQueue.global(qos: .utility).async { [weak self] in
            self?.process.waitUntilExit()
            guard let self else { return }
            let ok = self.process.terminationStatus == 0 && !self.isCancelled
            self.pipe.fileHandleForReading.readabilityHandler = nil
            self.errPipe.fileHandleForReading.readabilityHandler = nil
            let tail = self.allOutput
            DispatchQueue.main.async { self.onFinish?(ok, tail) }
        }
    }

    // MARK: - 控制

    /// 暂停：给进程发 SIGSTOP，它会冻在那儿，不占 CPU
    func pause() {
        guard !isPaused, process.isRunning else { return }
        isPaused = true
        kill(process.processIdentifier, SIGSTOP)
    }

    func resume() {
        guard isPaused, process.isRunning else { return }
        isPaused = false
        kill(process.processIdentifier, SIGCONT)
    }

    /// 取消：先温和终止，一秒后还没死就硬杀
    func cancel() {
        guard process.isRunning else { return }
        isCancelled = true
        if isPaused { kill(process.processIdentifier, SIGCONT); isPaused = false }
        process.terminate()
        let pid = process.processIdentifier
        DispatchQueue.global().asyncAfter(deadline: .now() + 1.5) {
            if self.process.isRunning { kill(pid, SIGKILL) }
        }
    }

    /// 后台模式：让系统把它当后台任务，前台不会卡
    /// - Parameter on: true = 降级到后台，false = 恢复正常
    func setBackground(_ on: Bool) {
        guard process.isRunning else { return }
        let t = Process()
        t.executableURL = URL(fileURLWithPath: "/usr/bin/taskpolicy")
        t.arguments = [on ? "-b" : "-B", "-p", String(process.processIdentifier)]
        try? t.run()
    }

    // MARK: - 输出解析

    private func consume(_ text: String) {
        allOutput += text

        // 7z 覆盖进度行用的是**退格符**（\x08），不是 \r：
        //   "  0%\x08\x08\x08\x08    \x08\x08\x08\x08  2% 20 + big/f9.bin"
        // 把退格和回车都当成行分隔，才能一条条切出百分比
        let normalized = text
            .replacingOccurrences(of: "\u{08}", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        buffer += normalized
        var parts = buffer.components(separatedBy: "\n")
        // 最后一段不完整，留到下次
        buffer = parts.removeLast()

        for line in parts {
            guard let pct = Self.percent(in: line) else { continue }
            let file = Self.fileName(in: line)
            if pct != percent || file != currentFile {
                percent = pct
                currentFile = file
                let p = pct, f = file
                DispatchQueue.main.async { self.onProgress?(p, f) }
            }
        }
    }

    /// "  4% 20 + big/f9.bin" -> 4
    private static func percent(in line: String) -> Int? {
        guard let r = line.range(of: #"(\d{1,3})%"#, options: .regularExpression) else { return nil }
        return Int(line[r].dropLast())
    }

    /// 取 "+ 文件名" 后面那段
    private static func fileName(in line: String) -> String {
        guard let plus = line.range(of: " + ") else {
            if let slash = line.range(of: " - ") {
                return String(line[slash.upperBound...]).trimmingCharacters(in: .whitespaces)
            }
            return ""
        }
        return String(line[plus.upperBound...]).trimmingCharacters(in: .whitespaces)
    }
}
