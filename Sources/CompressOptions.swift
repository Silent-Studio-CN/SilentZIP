import Foundation

/// 压缩参数。对应 7-Zip 的「添加到压缩包」对话框。
struct CompressOptions {
    // 输出
    var outputPath: String = ""
    var format: String = "7z"

    // 压缩
    var level: Int = 5                  // 0-9
    var method: String = "LZMA2"        // LZMA2 / LZMA / BZip2 / PPMd / Deflate / Copy
    var dictionarySize: String = "16m"  // 16m / 32m / 64m / 128m / 256m / 512m / 1g
    var wordSize: Int = 64              // 5-273
    var solidSize: String = "4g"        // off / 4m / 8m ... 4g
    var threads: Int = 0                // 0 = 自动
    var volumeSize: String = ""         // 分卷，空 = 不分卷

    // 更新
    var updateMode: UpdateMode = .addAndReplace
    var pathMode: PathMode = .relative

    // 开关
    var createSFX: Bool = false
    var compressShared: Bool = false
    var deleteSource: Bool = false

    // 加密
    var password: String = ""
    var encryptHeaders: Bool = false

    // 自定义
    var extraParams: String = ""

    var effectiveOutput: String {
        if !outputPath.isEmpty { return outputPath }
        return ""
    }

    /// 转成 7z 命令行开关
    func arguments() -> [String] {
        var a: [String] = []
        a.append("-t" + format)
        a.append("-mx=" + String(level))

        if format == "7z" {
            a.append("-m0=" + method)
            if method == "LZMA2" || method == "LZMA" {
                a.append("-m0d=" + dictionarySize)
            }
            if method == "PPMd" {
                a.append("-m0mem=" + dictionarySize)
            }
            a.append("-mfb=" + String(wordSize))
            a.append("-ms=" + solidSize)
        }

        if threads > 0 { a.append("-mmt=" + String(threads)) }
        if !volumeSize.isEmpty { a.append("-v" + volumeSize) }

        switch updateMode {
        case .addAndReplace: a.append("-up0")          // 默认，不额外加
        case .addAndUpdate:  a.append("-up1q1r2x1y2z1w2")   // 只加新的和更新的
        case .updateAndAdd:  a.append("-up0q1r0x1y0z0w0")
        case .sync:          a.append("-u-")
        case .addOnly:       a.append("-up0q0")
        }

        switch pathMode {
        case .relative: a.append("-spf")      // 相对路径
        case .absolute: a.append("-spf2")     // 完整路径
        case .full:     a.append("-spf-")
        }

        if createSFX { a.append("-sfx") }
        if compressShared { a.append("-seml") }
        if deleteSource { a.append("-sdel") }

        if !password.isEmpty {
            a.append("-p" + password)
            if encryptHeaders && format == "7z" { a.append("-mhe=on") }
        }

        let custom = extraParams.split(separator: " ").map(String.init).filter { !$0.isEmpty }
        a.append(contentsOf: custom)

        return a
    }

    /// 界面上显示的一行摘要
    var summary: String {
        var s = format.uppercased() + " · " + String(level)
            + " " + L10n.t("cd.levelTag", "级")
        if format == "7z" { s += " · " + method }
        if !password.isEmpty { s += " · " + L10n.t("cd.encTag", "加密") }
        if !volumeSize.isEmpty {
            s += " · " + L10n.t("cd.volTag", "分卷") + " " + volumeSize
        }
        return s
    }
}

enum UpdateMode: String, CaseIterable {
    case addAndReplace = "addAndReplace"
    case addAndUpdate  = "addAndUpdate"
    case updateAndAdd  = "updateAndAdd"
    case sync          = "sync"
    case addOnly       = "addOnly"

    var label: String {
        switch self {
        case .addAndReplace: return L10n.t("um.addAndReplace", "添加并替换文件")
        case .addAndUpdate:  return L10n.t("um.addAndUpdate", "添加并更新文件")
        case .updateAndAdd:  return L10n.t("um.updateAndAdd", "更新并添加文件")
        case .sync:          return L10n.t("um.sync", "同步压缩包内容")
        case .addOnly:       return L10n.t("um.addOnly", "仅添加新文件")
        }
    }
}

enum PathMode: String, CaseIterable {
    case relative = "relative"
    case absolute = "absolute"
    case full     = "full"

    var label: String {
        switch self {
        case .relative: return L10n.t("pm.relative", "相对路径")
        case .absolute: return L10n.t("pm.absolute", "绝对路径")
        case .full:     return L10n.t("pm.full", "完整路径")
        }
    }
}
