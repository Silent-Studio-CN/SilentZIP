import Foundation

// SilentZIP 命令行工具
// 用法：silentzip <命令> [参数]

func findEngine() -> String? {
    // 优先用 app 内置的
    let exe = CommandLine.arguments[0]
    let appDir = (exe as NSString).deletingLastPathComponent
    let bundled = (appDir as NSString).deletingLastPathComponent + "/Resources/7zz"
    if FileManager.default.isExecutableFile(atPath: bundled) { return bundled }

    for c in ["/opt/homebrew/bin/7zz", "/opt/homebrew/bin/7z",
              "/usr/local/bin/7zz", "/usr/local/bin/7z"] {
        if FileManager.default.isExecutableFile(atPath: c) { return c }
    }
    return nil
}

func run(_ tool: String, _ args: [String]) -> (String, Int32) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: tool)
    p.arguments = args
    let out = Pipe(), err = Pipe()
    p.standardOutput = out
    p.standardError = err
    try? p.run()
    p.waitUntilExit()
    let data = out.fileHandleForReading.readDataToEndOfFile()
    let e = err.fileHandleForReading.readDataToEndOfFile()
    let text = String(data: data, encoding: .utf8) ?? ""
    let et = String(data: e, encoding: .utf8) ?? ""
    return (text.isEmpty ? et : text, p.terminationStatus)
}

func usage() {
    print("""
    SilentZIP — macOS 归档工具

    用法：
      silentzip list    <归档>              列出内容
      silentzip extract <归档> [目录]       解压（默认当前目录）
      silentzip create  <归档> <文件...>    创建归档（格式看后缀）
      silentzip test    <归档>              校验完整性
      silentzip info    <归档>              归档信息
      silentzip version                     版本

    支持的归档格式见 README。
    """)
}

let args = CommandLine.arguments
guard args.count >= 2 else { usage(); exit(0) }

guard let tool = findEngine() else {
    FileHandle.standardError.write("找不到 7-Zip 引擎\n".data(using: .utf8)!)
    exit(1)
}

switch args[1].lowercased() {
case "list", "l":
    guard args.count >= 3 else { usage(); exit(1) }
    let (out, code) = run(tool, ["l", "-slt", "-ba", args[2]])
    print(out)
    exit(code)

case "extract", "x":
    guard args.count >= 3 else { usage(); exit(1) }
    let dest = args.count >= 4 ? args[3] : FileManager.default.currentDirectoryPath
    let (out, code) = run(tool, ["x", args[2], "-o" + dest, "-y"])
    print(out)
    exit(code)

case "create", "a":
    guard args.count >= 4 else { usage(); exit(1) }
    let target = args[2]
    let files = Array(args[3...])
    var a = ["a", target]
    a.append(contentsOf: files)
    let (out, code) = run(tool, a)
    print(out)
    exit(code)

case "test", "t":
    guard args.count >= 3 else { usage(); exit(1) }
    let (out, code) = run(tool, ["t", args[2]])
    print(out)
    exit(code)

case "info", "i":
    guard args.count >= 3 else { usage(); exit(1) }
    let (out, code) = run(tool, ["l", args[2]])
    print(out)
    exit(code)

case "version", "v", "--version":
    let (out, _) = run(tool, [])
    print(out)
    exit(0)

default:
    usage()
    exit(1)
}
