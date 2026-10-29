import Foundation

/// SilentZIP 的归档后端。
/// v1 走 7z 命令行（p7zip），因为它的格式覆盖最全，
/// 而且 7z l -slt 的输出是稳定的 key=value，比解析自然语言可靠。
struct ArchiveEntry: Identifiable, Hashable {
    let id = UUID()
    let path: String        // 归档内完整路径
    let name: String        // 文件名
    let isDirectory: Bool
    let size: Int64
    let packedSize: Int64
    let modified: String
    let crc: String

    var parentPath: String {
        let p = (path as NSString).deletingLastPathComponent
        return p == "." ? "" : p
    }
}

enum ArchiveError: LocalizedError {
    case toolMissing
    case failed(String)
    var errorDescription: String? {
        switch self {
        case .toolMissing: return "找不到 7z 命令，请先安装：brew install p7zip"
        case .failed(let s): return s
        }
    }
}

/// 刻意不加 @MainActor —— 它只做子进程调用，必须在后台线程跑，
/// 否则解压大包会把界面卡死。
final class ArchiveBackend: @unchecked Sendable {
    static let shared = ArchiveBackend()

    /// 找出 7z / 7za / 7zz 可执行文件（构造时算一次，之后只读）
    let toolPath: String? = {
        let candidates = ["/opt/homebrew/bin/7z", "/usr/local/bin/7z",
                          "/opt/homebrew/bin/7zz", "/usr/local/bin/7zz",
                          "/opt/homebrew/bin/7za", "/usr/local/bin/7za"]
        for c in candidates where FileManager.default.isExecutableFile(atPath: c) { return c }
        return nil
    }()

    /// 跑命令，返回 (stdout, stderr, exitCode)
    @discardableResult
    func run(_ launch: String, _ args: [String], cwd: URL? = nil) throws -> (String, String, Int32) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: launch)
        p.arguments = args
        if let cwd { p.currentDirectoryURL = cwd }
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        // 关掉本地化，保证 key=value 是英文
        var env = ProcessInfo.processInfo.environment
        env["LC_ALL"] = "C"
        env["LANG"] = "C"
        p.environment = env
        try p.run()
        let o = out.fileHandleForReading.readDataToEndOfFile()
        let e = err.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (String(decoding: o, as: UTF8.self),
                String(decoding: e, as: UTF8.self),
                p.terminationStatus)
    }

    /// 列出归档内容
    func list(_ archive: URL) throws -> [ArchiveEntry] {
        guard let tool = toolPath else { throw ArchiveError.toolMissing }
        let (out, err, code) = try run(tool, ["l", "-slt", "-ba", archive.path])
        guard code == 0 else { throw ArchiveError.failed(err.isEmpty ? "无法读取归档" : err) }
        return Self.parse(out)
    }

    /// 解析 7z l -slt 输出
    static func parse(_ text: String) -> [ArchiveEntry] {
        var entries: [ArchiveEntry] = []
        var path = "", size: Int64 = 0, packed: Int64 = 0
        var modified = "", crc = "", dir = false, inEntry = false

        func flush() {
            guard inEntry, !path.isEmpty else { return }
            entries.append(ArchiveEntry(
                path: path,
                name: (path as NSString).lastPathComponent,
                isDirectory: dir,
                size: size, packedSize: packed,
                modified: modified, crc: crc))
        }

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            if line.hasPrefix("Path = ") {
                flush()
                inEntry = true
                path = String(line.dropFirst(7))
                size = 0; packed = 0; modified = ""; crc = ""; dir = false
            } else if line.hasPrefix("Size = ") {
                size = Int64(line.dropFirst(7)) ?? 0
            } else if line.hasPrefix("Packed Size = ") {
                packed = Int64(line.dropFirst(14)) ?? 0
            } else if line.hasPrefix("Modified = ") {
                modified = String(line.dropFirst(11))
            } else if line.hasPrefix("CRC = ") {
                crc = String(line.dropFirst(6))
            } else if line.hasPrefix("Attributes = ") {
                let a = line.dropFirst(13)
                if a.contains("D") { dir = true }
            } else if line.trimmingCharacters(in: .whitespaces).isEmpty {
                flush()
                inEntry = false
            }
        }
        flush()
        return entries
    }

    /// 解压到目录
    func extract(_ archive: URL, to dir: URL, subset: [String] = []) throws {
        guard let tool = toolPath else { throw ArchiveError.toolMissing }
        var args = ["x", archive.path, "-o" + dir.path, "-y"]
        if !subset.isEmpty { args.append(contentsOf: subset) }
        let (_, err, code) = try run(tool, args)
        guard code == 0 else { throw ArchiveError.failed(err) }
    }

    /// 创建归档
    func create(_ archive: URL, from items: [URL], format: String = "7z") throws {
        guard let tool = toolPath else { throw ArchiveError.toolMissing }
        var args = ["a", "-t" + format, archive.path]
        args.append(contentsOf: items.map { $0.path })
        let (_, err, code) = try run(tool, args)
        guard code == 0 else { throw ArchiveError.failed(err) }
    }

    /// 测试完整性
    func test(_ archive: URL) throws -> String {
        guard let tool = toolPath else { throw ArchiveError.toolMissing }
        let (out, err, code) = try run(tool, ["t", archive.path])
        if code != 0 { throw ArchiveError.failed(err.isEmpty ? out : err) }
        return "完整性检查通过"
    }
    // MARK: - 详细测试

    struct TestResult {
        let summary: String
        let detail: String
    }

    func testDetailed(_ archive: URL) throws -> TestResult {
        guard let tool = toolPath else { throw ArchiveError.toolMissing }
        let (out, err, code) = try run(tool, ["t", archive.path])
        let lines = out.split(separator: "\n").map(String.init)

        let filesLine = lines.first { $0.hasPrefix("Files:") } ?? ""
        let okCount = filesLine.components(separatedBy: " ").compactMap { Int($0) }.first ?? 0
        let badCount = lines.filter {
            $0.hasPrefix("Error") || $0.contains("CRC Failed") || $0.contains("ERROR")
        }.count
        let passed = code == 0 && badCount == 0

        let summary = passed
            ? "检查通过：\(okCount) 个文件校验无误"
            : "检查失败：\(badCount) 个错误（退出码 \(code)）"

        let detail = """
        \(passed ? "✅ 归档完整" : "❌ 归档存在问题")

        校验文件   \(okCount) 个
        错误       \(badCount) 个
        退出码     \(code)
        工具       \(tool)

        ── 输出末尾 ──
        \(lines.suffix(8).joined(separator: "\n"))

        \(err.isEmpty ? "" : "── 错误流 ──\n" + err)
        """
        return TestResult(summary: summary, detail: detail)
    }

    // MARK: - 归档内重命名/移动

    func rename(_ archive: URL, from: String, to: String) throws {
        guard let tool = toolPath else { throw ArchiveError.toolMissing }
        let (_, err, code) = try run(tool, ["rn", archive.path, from, to])
        guard code == 0 else { throw ArchiveError.failed(err.isEmpty ? "移动失败" : err) }
    }

    // MARK: - 归档内复制

    /// 7z 没有「归档内复制」命令，做法是：
    /// 解出该条目到临时目录 → 在临时目录里改到目标路径 → 用相对路径加回归档。
    func copyEntry(_ archive: URL, from: String, to: String) throws {
        guard let tool = toolPath else { throw ArchiveError.toolMissing }

        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("silentzip-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        try extract(archive, to: tmp, subset: [from])

        let src = tmp.appendingPathComponent(from)
        let dst = tmp.appendingPathComponent(to)
        guard FileManager.default.fileExists(atPath: src.path) else {
            throw ArchiveError.failed("解压出来的条目找不到：\(from)")
        }
        try FileManager.default.createDirectory(at: dst.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: src, to: dst)

        // 在临时目录里用相对路径加回去，保证归档内路径是 to 而不是绝对路径
        let (_, err, code) = try run(tool, ["a", archive.path, to], cwd: tmp)
        guard code == 0 else { throw ArchiveError.failed(err.isEmpty ? "复制失败" : err) }
    }

    // MARK: - 删除归档内条目

    func remove(_ archive: URL, items: [String]) throws {
        guard let tool = toolPath else { throw ArchiveError.toolMissing }
        guard !items.isEmpty else { return }
        var args = ["d", archive.path]
        args.append(contentsOf: items)
        let (_, err, code) = try run(tool, args)
        guard code == 0 else { throw ArchiveError.failed(err) }
    }

}