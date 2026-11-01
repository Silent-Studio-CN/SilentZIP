import AppKit

// MARK: - AppleScript 命令
//
// 这几个类由 Info.plist 里的 NSAppleScriptEnabled 和 SDEF 文件挂上。
// 脚本里写：
//   tell application "SilentZIP"
//       extract POSIX file "/path/a.7z"
//       compress {POSIX file "/path/x"} to POSIX file "/path/x.7z"
//       list POSIX file "/path/a.7z"
//   end tell

private func enginePath() -> String? {
    if let u = Bundle.main.url(forResource: "7zz", withExtension: nil),
       FileManager.default.isExecutableFile(atPath: u.path) {
        return u.path
    }
    for c in ["/opt/homebrew/bin/7zz", "/opt/homebrew/bin/7z",
              "/usr/local/bin/7zz", "/usr/local/bin/7z"] {
        if FileManager.default.isExecutableFile(atPath: c) { return c }
    }
    return nil
}

@discardableResult
private func run7z(_ args: [String], cwd: URL? = nil) -> (String, Int32) {
    guard let tool = enginePath() else { return ("找不到 7-Zip 引擎", 1) }
    let p = Process()
    p.executableURL = URL(fileURLWithPath: tool)
    p.arguments = args
    if let cwd { p.currentDirectoryURL = cwd }
    let out = Pipe()
    p.standardOutput = out
    p.standardError = out
    do { try p.run() } catch { return (error.localizedDescription, 1) }
    p.waitUntilExit()
    let data = out.fileHandleForReading.readDataToEndOfFile()
    return (String(data: data, encoding: .utf8) ?? "", p.terminationStatus)
}

/// extract POSIX file "..." [to POSIX file "..."]
@objc(ExtractScriptCommand)
final class ExtractScriptCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        guard let fileURL = directParameter as? URL else {
            scriptErrorNumber = 1
            scriptErrorString = "需要一个压缩包路径"
            return nil
        }
        let dest: URL = (evaluatedArguments?["toDir"] as? URL)
            ?? fileURL.deletingLastPathComponent()

        let (out, code) = run7z(["x", fileURL.path, "-o" + dest.path, "-y"])
        if code != 0 {
            scriptErrorNumber = 2
            scriptErrorString = out.isEmpty ? "解压失败" : out
            return nil
        }
        return dest.path
    }
}

/// compress {POSIX file "..."} to POSIX file "..."
@objc(CompressScriptCommand)
final class CompressScriptCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        var items: [URL] = []
        if let list = directParameter as? [Any] {
            items = list.compactMap { $0 as? URL }
        } else if let one = directParameter as? URL {
            items = [one]
        }
        guard !items.isEmpty else {
            scriptErrorNumber = 1
            scriptErrorString = "需要至少一个文件或文件夹"
            return nil
        }
        guard let target = evaluatedArguments?["toArchive"] as? URL else {
            scriptErrorNumber = 1
            scriptErrorString = "缺少 to 参数（输出路径）"
            return nil
        }

        let fmt = target.pathExtension.isEmpty ? "7z" : target.pathExtension.lowercased()
        var args = ["a", "-t" + fmt, target.path]
        args.append(contentsOf: items.map { $0.path })
        let (out, code) = run7z(args)
        if code != 0 {
            scriptErrorNumber = 2
            scriptErrorString = out.isEmpty ? "压缩失败" : out
            return nil
        }
        return target.path
    }
}

/// list POSIX file "..."
@objc(ListScriptCommand)
final class ListScriptCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        guard let fileURL = directParameter as? URL else {
            scriptErrorNumber = 1
            scriptErrorString = "需要一个压缩包路径"
            return nil
        }
        let (out, code) = run7z(["l", "-slt", "-ba", fileURL.path])
        if code != 0 {
            scriptErrorNumber = 2
            scriptErrorString = out.isEmpty ? "读取失败" : out
            return nil
        }
        var paths: [String] = []
        for line in out.components(separatedBy: .newlines) where line.hasPrefix("Path = ") {
            paths.append(String(line.dropFirst(7)))
        }
        return paths
    }
}
