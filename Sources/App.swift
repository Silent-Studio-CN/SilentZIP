import SwiftUI
import UniformTypeIdentifiers
import AppKit

// MARK: - 文件打开事件总线
// macOS 双击/「打开方式」传文件，走的是 NSApplicationDelegate 的 open 事件，
// 不是命令行参数 —— 这里把它转成 SwiftUI 可订阅的发布值。
@MainActor
final class OpenBus: ObservableObject {
    static let shared = OpenBus()
    @Published var pending: URL?
}

@MainActor
final class AboutBus: ObservableObject {
    static let shared = AboutBus()
    @Published var open = false
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        guard let first = filenames.first else {
            sender.reply(toOpenOrPrint: .failure)
            return
        }
        let url = URL(fileURLWithPath: first)
        try? "openFiles: \(first)\n".write(
            toFile: "/tmp/silentzip-open.log", atomically: true, encoding: .utf8)
        Task { @MainActor in
            OpenBus.shared.pending = url
            NSApp.activate(ignoringOtherApps: true)
        }
        sender.reply(toOpenOrPrint: .success)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        L10n.load()
        NSApp.activate(ignoringOtherApps: true)
        // 让系统重新扫描本 app 的 NSServices —— 否则右键菜单里看不到，
        // 用户还得手动去「系统设置 → 键盘 → 服务」勾选
        NSUpdateDynamicServices()

        // 首次启动静默接管压缩包。
        // 从 app 内部调 LS API 系统不弹确认窗口，所以用户装完拖进
        // Applications、第一次打开就全自动完成，不需要任何设置。
        if !UserDefaults.standard.bool(forKey: "didRegisterDefaults") {
            let n = ArchiveTypes.becomeDefault()
            if n > 0 {
                UserDefaults.standard.set(true, forKey: "didRegisterDefaults")
            }
        }
    }

    // MARK: - Finder 右键「快速操作」/「服务」

    /// 用 SilentZIP 打开 —— 对应 Info.plist 里 NSServices 的 NSMessage
    @objc func openArchive(_ pboard: NSPasteboard,
                           userData: String,
                           error: AutoreleasingUnsafeMutablePointer<NSString>) {
        let log = "openArchive fired, types=" + String(describing: pboard.types)
        try? log.write(toFile: "/tmp/silentzip-service.log",
                       atomically: true, encoding: .utf8)
        guard let urls = pboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
              let first = urls.first else { return }
        Task { @MainActor in
            OpenBus.shared.pending = first
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    /// 解压到此处 —— 直接在归档所在目录展开
    @objc func extractHere(_ pboard: NSPasteboard,
                           userData: String,
                           error: AutoreleasingUnsafeMutablePointer<NSString>) {
        guard let urls = pboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
              let first = urls.first else { return }

        let dest = first.deletingLastPathComponent()
        Task.detached(priority: .userInitiated) {
            do {
                try ArchiveBackend.shared.extract(first, to: dest)
                await MainActor.run {
                    NSApp.activate(ignoringOtherApps: true)
                    OpenBus.shared.pending = first
                }
            } catch {
                await MainActor.run {
                    let a = NSAlert()
                    a.messageText = L10n.t("error.extractFailed", "解压失败")
                    a.informativeText = error.localizedDescription
                    a.runModal()
                }
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// 退出时删掉临时解压目录
    func applicationWillTerminate(_ notification: Notification) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SilentZIP-Open", isDirectory: true)
        try? FileManager.default.removeItem(at: root)
    }
}

// MARK: - 支持的归档后缀
/// 7-Zip 26.01 能解析的全部扩展名（取自 7zz i 的 Formats 表）
let archiveExts: Set<String> = [
    // 原生压缩
    "7z", "zip", "z01", "rar", "r00", "tar", "ova",
    "gz", "gzip", "tgz", "tpz", "bz2", "bzip2", "tbz", "tbz2",
    "xz", "txz", "z", "taz", "lzma", "lzma86", "zst", "tzst",
    // 安装包 / 打包
    "iso", "cab", "arj", "lzh", "lha", "cpio", "ar", "a", "lib",
    "deb", "udeb", "rpm", "msi", "msp", "msm", "pkg", "xip", "xar",
    "wim", "swm", "esd", "ppkg", "dmg", "apk",
    // 旧版 Office（Compound 文档，7z 能解出内部流）
    "doc", "xls", "ppt", "msm",
    // 帮助文档
    "chm", "chi", "chq", "chw", "hxs", "hxi", "hxr", "hxq", "hxw", "lit",
    // 磁盘镜像
    "img", "ext", "ext2", "ext3", "ext4", "apfs", "fat",
    "hfs", "hfsx", "cramfs", "squashfs", "udf",
    "vhd", "vhdx", "vmdk", "vdi", "avhdx",
    // 可执行 / 目标文件
    "elf", "macho", "uefif", "scap", "obj", "ihex", "te",
    // 其它容器
    "swf", "flv", "b64", "001", "simg", "lpimg", "gpt", "mbr", "apm"
]

func isArchive(_ url: URL) -> Bool {
    archiveExts.contains(url.pathExtension.lowercased())
}

/// 7z 能「打开查看内部」的其它格式：
/// 可执行文件（PE 资源）、Java 包、Office 文档（本质是 zip）、安装包等。
/// 双击这些时先试着当归档解析，失败才交给系统默认程序。
let archiveLikeExts: Set<String> = [
    "jar", "war", "ear", "apk", "ipa", "xpi", "crx",
    "exe", "dll", "msi", "sys",
    "docx", "xlsx", "pptx", "odt", "ods", "odp",
    "epub", "dmg", "pkg", "deb", "rpm"
]

/// 一眼就知道解压不了的格式 —— 双击直接交给系统，不浪费一次解析
let nonArchiveExts: Set<String> = [
    // 图片
    "png", "jpg", "jpeg", "gif", "webp", "heic", "heif", "bmp", "tiff", "tif",
    "svg", "ico", "icns", "raw", "psd", "ai",
    // 音视频
    "mp4", "mov", "m4v", "avi", "mkv", "flv", "wmv", "webm",
    "mp3", "m4a", "aac", "wav", "aiff", "flac", "ogg",
    // 文档与文本
    "pdf", "txt", "md", "rtf", "html", "htm", "css", "js", "mjs",
    "json", "xml", "yaml", "yml", "toml", "ini", "conf", "log",
    "csv", "tsv",
    // 字体
    "ttf", "otf", "woff", "woff2",
    // 证书 / 密钥
    "pem", "crt", "cer", "key", "p12", "pfx",
    // 其它
    "sh", "command", "bat", "ps1", "py", "rb", "swift", "c", "h", "cpp", "rs", "go", "java"
]

func canTryAsArchive(_ url: URL) -> Bool {
    let e = url.pathExtension.lowercased()
    if nonArchiveExts.contains(e) { return false }
    return true
}

// MARK: - 图标缓存
// NSWorkspace.icon 每次调用都走一遍系统，列表几百行会卡；
// 这里用 NSCache 按路径缓存，惰性失效。
final class IconCache: @unchecked Sendable {
    static let shared = IconCache()
    private let cache = NSCache<NSString, NSImage>()

    func icon(for url: URL) -> NSImage {
        let key = url.path as NSString
        if let hit = cache.object(forKey: key) { return hit }
        let img = NSWorkspace.shared.icon(forFile: url.path)
        cache.setObject(img, forKey: key)
        return img
    }
}

// MARK: - 类型判定

/// 这些后缀在磁盘上是目录，但语义上是「一个整体」——压缩时应当整体打包
let bundleExts: Set<String> = ["app","framework","bundle","plugin","appex","prefpane","kext","xcodeproj","xcworkspace","playground","docset","qlgenerator","mdimporter"]

func looksLikeBundle(_ url: URL) -> Bool {
    bundleExts.contains(url.pathExtension.lowercased())
}

/// 常见类型的英文名。
/// UTType.localizedDescription 跟的是**系统**语言，不跟 app 内的语言开关 ——
/// 系统中文、界面英文时它会返回「PNG 图像」，所以英文界面下走这张表。
let englishTypeNames: [String: String] = [
    "png": "PNG image", "jpg": "JPEG image", "jpeg": "JPEG image",
    "gif": "GIF image", "webp": "WebP image", "heic": "HEIC image",
    "tiff": "TIFF image", "bmp": "BMP image", "svg": "SVG image",
    "pdf": "PDF document", "txt": "Text", "md": "Markdown", "rtf": "RTF",
    "html": "HTML", "htm": "HTML", "css": "CSS", "json": "JSON",
    "yaml": "YAML", "yml": "YAML", "xml": "XML", "csv": "CSV",
    "doc": "Word document", "docx": "Word document",
    "xls": "Excel spreadsheet", "xlsx": "Excel spreadsheet",
    "ppt": "PowerPoint presentation", "pptx": "PowerPoint presentation",
    "pages": "Pages document", "numbers": "Numbers spreadsheet",
    "key": "Keynote presentation",
    "mp3": "MP3 audio", "wav": "WAV audio", "aac": "AAC audio",
    "flac": "FLAC audio", "m4a": "M4A audio",
    "mp4": "MP4 video", "mov": "QuickTime movie", "mkv": "MKV video",
    "avi": "AVI video", "webm": "WebM video",
    "jar": "Java archive", "class": "Java class",
    "sh": "Shell script", "py": "Python script", "js": "JavaScript",
    "swift": "Swift source", "c": "C source", "cpp": "C++ source",
    "pem": "Certificate", "cer": "Certificate", "crt": "Certificate",
    "dmg": "Disk image", "iso": "Disk image", "pkg": "Installer",
    "dylib": "Library", "so": "Library", "a": "Static library",
    "sqlite": "SQLite database", "db": "Database",
    "epub": "EPUB book", "ttf": "Font", "otf": "Font"
]

/// 类型名。中文界面用系统本地化名，其他语言走英文表。
func typeName(_ url: URL) -> String {
    let ext = url.pathExtension.lowercased()
    if ext.isEmpty { return L10n.t("type.folder", "文件夹") }
    if ext == "app" { return L10n.t("type.app", "应用程序") }
    if ext == "framework" { return L10n.t("type.framework", "框架") }

    let isChinese = L10n.currentCode().hasPrefix("zh")

    if isChinese {
        if let t = UTType(filenameExtension: ext),
           let d = t.localizedDescription, !d.isEmpty {
            return d
        }
        return ext.uppercased() + L10n.t("type.fileSuffix", " 文件")
    }

    if let en = englishTypeNames[ext] { return en }
    if archiveExts.contains(ext) { return L10n.t("type.archive", "Archive") }
    return ext.uppercased() + " " + L10n.t("type.fileSuffixEn", "file")
}

// MARK: - 命令行工具
enum CLITool {
    /// 把 app 内的 sz 链到 /usr/local/bin，方便终端直接调用
    static func install() {
        guard let exe = Bundle.main.executableURL else { return }
        let sz = exe.deletingLastPathComponent().appendingPathComponent("sz")
        guard FileManager.default.isExecutableFile(atPath: sz.path) else {
            alert(L10n.t("cli.missingTitle", "命令行工具缺失"), L10n.t("app.cliMissingBody", "app 里没找到 sz，可能这次构建没编进去。"))
            return
        }

        let target = URL(fileURLWithPath: "/usr/local/bin/sz")
        let fm = FileManager.default

        // 已存在就先删（可能是旧链接）
        if fm.fileExists(atPath: target.path) {
            if (try? fm.destinationOfSymbolicLink(atPath: target.path)) == nil {
                alert(L10n.t("error.installFailed", "安装失败"), L10n.t("app.cliNotSymlink", "/usr/local/bin/sz 已存在且不是软链，请手动处理。"))
                return
            }
            try? fm.removeItem(at: target)
        }

        do {
            try fm.createSymbolicLink(at: target, withDestinationURL: sz)
            alert(L10n.t("cli.installedTitle", "已安装"), L10n.t("app.cliInstalledBody", "现在可以在终端里直接用："))
        } catch {
            CopyableAlert.show(
                title: L10n.t("error.installFailed", "安装失败"),
                message: L10n.t("cli.noPermission",
                                "没有权限写入 /usr/local/bin。\n\n可以在终端里手动执行下面这条命令："),
                command: "sudo ln -sf \"\(sz.path)\" /usr/local/bin/sz"
            )
        }
    }

    private static func alert(_ title: String, _ body: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = body
        a.runModal()
    }
}

// MARK: - 把自己注册成默认压缩工具
enum ArchiveTypes {
    static let utis: [String] = [
        "org.7-zip.7-zip-archive",
        "public.zip-archive",
        "com.rarlab.rar-archive",
        "public.tar-archive",
        "org.gnu.gnu-zip-archive",
        "org.gnu.gnu-zip-tar-archive",
        "public.bzip2-archive",
        "org.tukaani.xz-archive",
        "cn.silentstudio.archive.zst",
        "cn.silentstudio.archive.lzh",
        "com.microsoft.cab"
    ]

    static var bundleID: CFString { "cn.silentstudio.silentzip" as CFString }

    /// 让本 app 成为所有归档格式的默认打开方式。
    /// 需要用户主动触发 —— 系统会忽略无交互的静默设置。
    @discardableResult
    static func becomeDefault() -> Int {
        var changed = 0
        for u in utis {
            for role: LSRolesMask in [.viewer, .editor, .shell] {
                _ = LSSetDefaultRoleHandlerForContentType(u as CFString, role, bundleID)
            }
            let cur = LSCopyDefaultRoleHandlerForContentType(u as CFString, .viewer)?
                .takeRetainedValue() as String? ?? ""
            if cur == "cn.silentstudio.silentzip" { changed += 1 }
        }
        return changed
    }

    /// 当前有多少格式已经指向我们
    static func currentCount() -> Int {
        utis.filter {
            (LSCopyDefaultRoleHandlerForContentType($0 as CFString, .viewer)?
                .takeRetainedValue() as String?) == "cn.silentstudio.silentzip"
        }.count
    }
}

// MARK: - 受保护路径
// 这些目录照常显示（用户有权看），但禁止压缩、写入、删除 ——
// 在应用层提前拦住，比让 7z 写到一半报错体验好，也避免半截文件。
let protectedPaths: [String] = [
    "/System", "/usr", "/bin", "/sbin", "/private", "/dev", "/cores",
    "/etc", "/var", "/tmp", "/Volumes", "/Library/Apple", "/Library/Extensions",
    "/Applications"   // 安装好的 app 不该被压缩工具动
]

func isProtectedPath(_ url: URL) -> Bool {
    let p = url.standardizedFileURL.path
    // 精确等于或在其下
    return protectedPaths.contains { p == $0 || p.hasPrefix($0 + "/") }
}

// MARK: - 关于
// 布局参照 Silent Game：主体只放摘要，完整条款单独一页。
struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showFullTerms = false

    private var version: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0.0.0"
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 9) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 86, height: 86)
                    .padding(.bottom, 2)

                Text("SilentZIP")
                    .font(.system(size: 23, weight: .semibold))
                Text(L10n.t("about.version", "版本 ") + version).font(.callout).foregroundStyle(.secondary)
                Text(L10n.t("about.tagline", "macOS 归档管理器")).font(.callout).foregroundStyle(.secondary)
            }
            .padding(.top, 20)
            .padding(.bottom, 14)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("(C) SilentStudio / SilentCodeTeams™")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Text(L10n.t("about.privateLicense", "私有许可协议")).font(.headline)
                            Text("v1.0")
                                .font(.caption2)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.15))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }

                        Text(L10n.t("about.licenseAllow", "允许：免费使用（个人与商业）、分发未修改的副本。"))
                        Text(L10n.t("about.licenseDeny", "禁止：修改、反向工程、把源码或算法移植到其他项目、转售。"))
                        Text("")
                        Text("Proprietary License").font(.headline)
                        Text("Permitted: free use (personal and commercial), distribution of unmodified copies.")
                        Text("Prohibited: modification, reverse engineering, porting into other projects, resale.")
                        Text(L10n.t("about.licensePrecedence", "中英文如有歧义，以中文为准。"))
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                    .font(.callout)

                    Button {
                        showFullTerms = true
                    } label: {
                        Label(L10n.t("terms.viewFull", "查看完整条款"), systemImage: "doc.text")
                    }
                    .controlSize(.large)

                    Divider().padding(.vertical, 2)

                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.t("about.tech", "技术")).font(.headline)

                        techRow(L10n.t("about.ui", "界面"), "SwiftUI + AppKit")
                        techRow(L10n.t("about.engine", "归档引擎"), L10n.t("app.engineName", "7-Zip 26.05（自编译）"))
                        techRow(L10n.t("about.engineCopyright", "引擎版权"), "© 1999-2025 Igor Pavlov")
                        techRow(L10n.t("about.engineLicense", "引擎许可"), "GNU LGPL · unRAR restriction")

                        Text(L10n.t("about.engineNote", "7-Zip 以独立进程方式调用，不静态链接。其版权与许可归原作者，独立于本协议。"))
                            .font(.caption).foregroundStyle(.tertiary)
                            .padding(.top, 2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 26)
                .padding(.vertical, 16)
            }

            Divider()

            HStack {
                Spacer()
                Button(L10n.t("ui.ok", "好")) { dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(width: 500, height: 620)
        .onAppear {
            if CommandLine.arguments.contains("--terms") { showFullTerms = true }
        }
        .sheet(isPresented: $showFullTerms) {
            FullTermsView()
        }
    }

    private func techRow(_ label: String, _ value: String) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
            GridRow(alignment: .firstTextBaseline) {
                Text(label)
                    .foregroundStyle(.secondary)
                    .font(.callout)
                    .frame(width: 68, alignment: .leading)
                    .gridColumnAlignment(.leading)
                Text(value)
                    .font(.callout)
                    .textSelection(.enabled)
                    .gridColumnAlignment(.leading)
            }
        }
    }
}

// MARK: - 完整条款（单独一页，内部滚动）
struct FullTermsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var tab: Int = 0

    private let files = [
        (L10n.t("terms.tabApp", "SilentZIP 协议"), "LICENSE"),
        (L10n.t("terms.tab7zip", "7-Zip 许可"), "THIRD-PARTY-7zip"),
        ("LGPL 2.1", "COPYING.LGPL-2.1")
    ]

    /// 直接读 bundle 里的原始文件 —— 一字不改地展示
    private func text(for name: String) -> String {
        for ext in ["md", "txt"] {
            if let u = Bundle.main.url(forResource: name, withExtension: ext),
               let s = try? String(contentsOf: u, encoding: .utf8) {
                return s
            }
        }
        return L10n.t("terms.fileMissing", "许可文件缺失：") + name
    }

    private var lines: [(offset: Int, text: String)] {
        text(for: files[tab].1).components(separatedBy: "\n")
            .enumerated()
            .map { (offset: $0.offset, text: $0.element) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L10n.t("terms.title", "许可协议")).font(.headline)
                Spacer()
                Button(L10n.t("ui.close", "关闭")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 10)

            Picker("", selection: $tab) {
                ForEach(Array(files.enumerated()), id: \.offset) { idx, f in
                    Text(f.0).tag(idx)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)
            .padding(.bottom, 12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(lines, id: \.offset) { line in
                        lineView(line.text)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.vertical, 18)
            }

            Divider()

            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal")
                    .foregroundStyle(.secondary)
                Text(L10n.t("terms.thirdPartyNote", "第三方许可取自官方源，原样收录，未作修改"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 20).padding(.vertical, 8)
        }
        .frame(width: 720, height: 700)
    }

    /// LICENSE.md 走 markdown 渲染；第三方原文一律原样输出，
    /// 行首缩进也保持原样，不改写许可文本
    private var isMarkdown: Bool { files[tab].1 == "LICENSE" }

    @ViewBuilder
    private func lineView(_ raw: String) -> some View {
        if !isMarkdown {
            Text(raw.isEmpty ? " " : raw)
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            markdownLine(raw)
        }
    }

    @ViewBuilder
    private func markdownLine(_ raw: String) -> some View {
        let t = raw.trimmingCharacters(in: .whitespaces)

        if t.isEmpty {
            Spacer().frame(height: 6)
        } else if t.hasPrefix("### ") {
            Text(t.dropFirst(4))
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.top, 5)
        } else if t.hasPrefix("## ") {
            Text(t.dropFirst(3))
                .font(.system(size: 15, weight: .semibold))
                .padding(.top, 12).padding(.bottom, 2)
        } else if t.hasPrefix("# ") {
            Text(t.dropFirst(2))
                .font(.system(size: 19, weight: .semibold))
                .padding(.top, 14).padding(.bottom, 4)
        } else if t.hasPrefix("---") {
            Divider().padding(.vertical, 6)
        } else {
            Text(inline(t))
                .font(.system(size: 12.5))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func inline(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s)) ?? AttributedString(s)
    }
}

struct InfoRow: Identifiable {
    let id = UUID()
    let label: String
    let value: String
}

// MARK: - 文件系统条目
struct FSEntry: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let isDir: Bool
    let size: Int64
    let modified: Date?
    var isLink: Bool = false

    var name: String { url.lastPathComponent }

    /// 系统真实图标（和 Finder 一致）
    var icon: NSImage {
        IconCache.shared.icon(for: url)
    }
    var isBundle: Bool { looksLikeBundle(url) }
    var typeLabel: String {
        if isLink { return L10n.t("type.symlink", "符号链接") }
        if isBundle { return typeName(url) }
        return isDir ? L10n.t("type.folder", "文件夹") : typeName(url)
    }

    var sizeText: String {
        if isDir { return "—" }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    var dateText: String {
        guard let d = modified else { return "—" }
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        return f.string(from: d)
    }
}

// MARK: - 模型
@MainActor
final class ZipModel: ObservableObject {
    // 文件系统（左栏）
    @Published var fsPath: URL = FileManager.default.urls(for: .desktopDirectory,
                                                      in: .userDomainMask).first
                                  ?? URL(fileURLWithPath: NSHomeDirectory())
    @Published var fsItems: [FSEntry] = []
    @Published var fsSelected: Set<UUID> = []

    /// 路径条分段（/Users/apple → [/] [Users] [apple]）
    var pathChunks: [(label: String, path: URL)] {
        var out: [(String, URL)] = [("/", URL(fileURLWithPath: "/"))]
        var acc = ""
        for c in fsPath.pathComponents where c != "/" {
            acc += "/" + c
            out.append((friendlyName(c), URL(fileURLWithPath: acc)))
        }
        return out
    }

    /// 常见目录显示中文，其余原样
    private func friendlyName(_ s: String) -> String {
        switch s {
        case "Users": return L10n.t("path.users", "用户")
        case "Desktop": return L10n.t("path.desktop", "桌面")
        case "Downloads": return L10n.t("path.downloads", "下载")
        case "Documents": return L10n.t("path.documents", "文稿")
        case "Movies": return L10n.t("path.movies", "影片")
        case "Music": return L10n.t("path.music", "音乐")
        case "Pictures": return L10n.t("path.pictures", "图片")
        case "Library": return L10n.t("path.library", "资源库")
        case "Applications": return L10n.t("type.app", "应用程序")
        case "System": return L10n.t("path.system", "系统")
        case "Volumes": return L10n.t("path.volumes", "宗卷")
        default: return s
        }
    }

    func jump(to url: URL) { loadFS(url) }

    /// 左栏当前选中的文件/文件夹
    var fsSelectedItems: [URL] {
        fsItems.filter { fsSelected.contains($0.id) }.map { $0.url }
    }

    /// 当前选用的压缩预设
    @Published var preset: CompressPreset = PresetStore.all.first ?? CompressPreset(name: L10n.t("preset.standard", "标准 7z"))

    /// 用完整参数压缩
    func createArchive(from items: [URL], to target: URL, options: CompressOptions) {
        guard !items.isEmpty else { return }
        busy = true
        status = L10n.t("status.compressing", "压缩中…")

        let extra = options.arguments()
        Task.detached(priority: .userInitiated) {
            do {
                try ArchiveBackend.shared.create(target, from: items,
                                                  format: options.format, extra: extra)
                let list = try ArchiveBackend.shared.list(target)
                await MainActor.run {
                    self.archive = target
                    self.entries = list
                    self.currentPath = ""
                    self.selection = []
                    self.status = L10n.f("status.created", "已创建 %@（%d 个条目）",
                                         target.lastPathComponent, list.count)
                    self.busy = false
                    self.loadFS(self.fsPath)
                }
            } catch {
                await MainActor.run {
                    self.status = L10n.f("error.compressFailed", "压缩失败：%@",
                                         error.localizedDescription)
                    self.busy = false
                }
            }
        }
    }

    /// 把选中的文件/文件夹压缩成新归档
    func createArchive(from items: [URL], to target: URL) {
        guard !items.isEmpty else { status = L10n.t("hint.selectToCompress", "先在左边选中要压缩的内容"); return }
        busy = true
        status = L10n.f("status.compressingCount", "压缩中…（%d 项）", items.count)

        let fmt: String = {
            let e = target.pathExtension.lowercased()
            return e.isEmpty ? "7z" : e
        }()
        // 进后台前先把参数抓出来，preset 是主线程属性
        let extra = preset.arguments

        Task.detached(priority: .userInitiated) {
            do {
                try ArchiveBackend.shared.create(target, from: items, format: fmt,
                                                  extra: extra)
                let list = try ArchiveBackend.shared.list(target)
                await MainActor.run {
                    self.archive = target
                    self.entries = list
                    self.currentPath = ""
                    self.selection = []
                    self.status = L10n.f("status.created", "已创建 %@（%d 个条目）", target.lastPathComponent, list.count)
                    self.busy = false
                    self.loadFS(self.fsPath)
                }
            } catch {
                await MainActor.run {
                    self.status = L10n.f("error.compressFailed", "压缩失败：%@", error.localizedDescription)
                    self.busy = false
                }
            }
        }
    }

    /// 当前目录是否允许修改（压缩/写入/删除）
    var canModify: Bool { !isProtectedPath(fsPath) }

    /// 当前目录为什么不能改
    var lockedReason: String? {
        canModify ? nil : L10n.t("lock.protected", "系统目录受保护，不能写入或压缩")
    }

    // 归档（右栏）
    @Published var archive: URL?
    @Published var entries: [ArchiveEntry] = []
    @Published var currentPath: String = ""
    @Published var selection: Set<UUID> = []
    @Published var status: String = ""

    /// 初始 status 是在 L10n 加载前求值的，界面起来后补一次
    func refreshStatusIfIdle() {
        if archive == nil && status.isEmpty {
            status = L10n.t("status.noArchive", "选择一个归档文件，或拖进来")
        }
    }
    @Published var busy = false
    @Published var infoText: String = ""
    @Published var infoRows: [InfoRow] = []

    var directories: [String] {
        var set = Set<String>()
        for e in entries {
            var p = e.parentPath
            while !p.isEmpty {
                set.insert(p)
                p = (p as NSString).deletingLastPathComponent
                if p == "." || p == "/" { break }
            }
        }
        return set.sorted()
    }

    var visible: [ArchiveEntry] {
        entries.filter { $0.parentPath == currentPath }
            .sorted { a, b in
                if a.isDirectory != b.isDirectory { return a.isDirectory }
                return a.name.localizedStandardCompare(b.name) == .orderedAscending
            }
    }

    // MARK: 文件系统
    func loadFS(_ url: URL) {
        fsPath = url
        UserDefaults.standard.set(url.path, forKey: "lastVisitedPath")
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .fileSizeKey,
                                          .contentModificationDateKey, .isSymbolicLinkKey]
        var list: [URL] = []
        do {
            // 不能用 .skipsHiddenFiles —— macOS 给 /bin /usr /var 这些
            // 打了隐藏标记，用了会一起过滤掉。只去掉 . 开头的真隐藏文件。
            list = try FileManager.default.contentsOfDirectory(
                at: url, includingPropertiesForKeys: Array(keys),
                options: [])
            .filter { !$0.lastPathComponent.hasPrefix(".") }
        } catch {
            status = L10n.f("error.cannotRead", "无法读取 %@：%@", url.lastPathComponent, error.localizedDescription)
        }
        fsItems = list.map { u in
            let v = try? u.resourceValues(forKeys: keys)
            return FSEntry(url: u,
                           isDir: v?.isDirectory ?? false,
                           size: Int64(v?.fileSize ?? 0),
                           modified: v?.contentModificationDate,
                           isLink: v?.isSymbolicLink ?? false)
        }
        .sorted { a, b in
            if a.isDir != b.isDir { return a.isDir }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }

    /// 把目录（.app 包）当归档列出来 —— 7z 无法 l 目录，
    /// 所以直接遍历文件系统，构造和归档一样的条目结构。
    nonisolated static func listDirectoryAsArchive(_ root: URL) -> [ArchiveEntry] {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey]
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd HH:mm:ss"

        guard let en = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: Array(keys)) else { return [] }

        var out: [ArchiveEntry] = []
        for case let u as URL in en {
            let v = try? u.resourceValues(forKeys: keys)
            var rel = u.path
            if rel.hasPrefix(root.path + "/") {
                rel = String(rel.dropFirst(root.path.count + 1))
            }
            guard !rel.isEmpty else { continue }
            out.append(ArchiveEntry(
                path: rel,
                name: u.lastPathComponent,
                isDirectory: v?.isDirectory ?? false,
                size: Int64(v?.fileSize ?? 0),
                packedSize: 0,
                modified: fmt.string(from: v?.contentModificationDate ?? Date()),
                crc: ""))
        }
        return out
    }

    func enter(_ e: FSEntry) {
        // 符号链接不追进去，避免循环
        if e.isLink { status = L10n.f("status.isSymlink", "%@ 是符号链接", e.name); return }

        // 普通文件夹 → 左边导航（这才是「文件资源管理器」）
        // .app / .framework 这类包磁盘上是目录，但语义是「一个整体」，
        // 双击应该在右边展开看内部，而不是钻进去
        if e.isDir && !e.isBundle { loadFS(e.url); return }

        // 明显不是归档的（图片/音视频/文本…）直接交回系统
        guard canTryAsArchive(e.url) else {
            NSWorkspace.shared.open(e.url)
            status = L10n.f("status.openedWithSystem", "已用系统程序打开 %@", e.name)
            return
        }

        open(e.url)
    }

    func goUp() {
        let p = fsPath.deletingLastPathComponent()
        if p.path != fsPath.path { loadFS(p) }
    }

    // MARK: 归档
    func open(_ url: URL, fallbackToSystem: Bool = false) {
        busy = true; status = L10n.t("status.reading", "读取中…"); archive = url; entries = []; currentPath = ""
        let path = url.path
        Task.detached(priority: .userInitiated) {
            do {
                var isDir: ObjCBool = false
                FileManager.default.fileExists(atPath: path, isDirectory: &isDir)

                // 目录（.app 这类包）：遍历文件系统，当成归档展示
                // 文件：交给 7z 解析（zip/7z/jar/exe/docx…）
                let list: [ArchiveEntry] = isDir.boolValue
                    ? ZipModel.listDirectoryAsArchive(URL(fileURLWithPath: path))
                    : try ArchiveBackend.shared.list(URL(fileURLWithPath: path))
                await MainActor.run {
                    self.entries = list
                    self.status = L10n.f("status.entryCount", "%d 个条目", list.count)
                    self.busy = false
                }
            } catch {
                await MainActor.run {
                    self.busy = false
                    if fallbackToSystem {
                        // 解析不了 —— 说明不是归档，交回系统
                        self.archive = nil
                        self.entries = []
                        NSWorkspace.shared.open(URL(fileURLWithPath: path))
                        self.status = L10n.f("status.openedDefault", "已用系统默认程序打开 %@", url.lastPathComponent)
                    } else {
                        self.archive = nil
                        self.entries = []
                        self.status = L10n.t("error.cannotOpen", "打不开：") + error.localizedDescription
                    }
                }
            }
        }
    }

    // MARK: 归档内部操作

    /// 右栏双击：
    /// - 目录 → 进入
    /// - 归档类文件（jar/docx/zip…）→ 临时解压后作为嵌套归档展开
    /// - 其它文件 → 临时解压并用系统程序打开
    func enterEntry(_ e: ArchiveEntry) {
        if e.isDirectory { currentPath = e.path; return }
        guard let a = archive else { return }

        busy = true
        status = L10n.f("status.expanding", "展开 %@…", e.name)
        Task.detached(priority: .userInitiated) {
            do {
                let f = try ArchiveBackend.shared.extractEntry(a, path: e.path)
                let list = try ArchiveBackend.shared.list(f)
                await MainActor.run {
                    self.busy = false
                    self.status = L10n.f("status.nested", "嵌套：%@（%d 个条目）", e.name, list.count)
                    self.archive = f
                    self.entries = list
                    self.currentPath = ""
                    self.selection = []
                }
            } catch {
                await MainActor.run {
                    self.busy = false
                    self.openEntry(e)
                }
            }
        }
    }

    /// 临时解压到临时目录，交给系统默认程序打开。
    /// 临时目录在 app 退出时整体删除。
    func openEntry(_ e: ArchiveEntry) {
        guard let a = archive else { return }
        status = L10n.f("status.opening", "正在打开 %@…", e.name)
        Task.detached(priority: .userInitiated) {
            do {
                let f = try ArchiveBackend.shared.extractEntry(a, path: e.path)
                await MainActor.run {
                    NSWorkspace.shared.open(f)
                    self.status = L10n.f("status.opened", "已打开 %@", e.name)
                }
            } catch {
                await MainActor.run {
                    self.status = L10n.t("error.openFailed", "打开失败：") + error.localizedDescription
                }
            }
        }
    }

    /// 解压整个归档
    func extractAll(to dir: URL) {
        guard let a = archive else { return }
        busy = true; status = L10n.t("status.extracting", "解压中…")
        Task.detached(priority: .userInitiated) {
            do {
                try ArchiveBackend.shared.extract(URL(fileURLWithPath: a.path), to: dir)
                await MainActor.run {
                    self.status = L10n.f("status.extractedTo", "已解压到 %@", dir.lastPathComponent)
                    self.busy = false
                    self.loadFS(self.fsPath)
                }
            } catch {
                await MainActor.run { self.status = error.localizedDescription; self.busy = false }
            }
        }
    }

    /// 解压选中的条目。没选就什么都不做 —— 由界面负责提示。
    func extract(to dir: URL) {
        guard let a = archive else { return }
        let sub = entries.filter { selection.contains($0.id) }.map { $0.path }
        guard !sub.isEmpty else { return }
        busy = true; status = L10n.t("status.extracting", "解压中…")
        Task.detached(priority: .userInitiated) {
            do {
                try ArchiveBackend.shared.extract(URL(fileURLWithPath: a.path), to: dir, subset: sub)
                await MainActor.run {
                    self.status = L10n.f("status.extractedTo", "已解压到 %@", dir.lastPathComponent)
                    self.busy = false
                    self.loadFS(self.fsPath)
                }
            } catch {
                await MainActor.run { self.status = error.localizedDescription; self.busy = false }
            }
        }
    }

    func test() {
        guard let a = archive else { return }
        busy = true; status = L10n.t("status.testing", "检查中…")
        Task.detached(priority: .userInitiated) {
            do {
                let r = try ArchiveBackend.shared.testDetailed(URL(fileURLWithPath: a.path))
                await MainActor.run {
                    self.status = r.summary
                    self.infoText = r.detail
                    self.busy = false
                }
            } catch {
                await MainActor.run { self.status = L10n.f("error.testFailed", "检查失败：%@", error.localizedDescription); self.busy = false }
            }
        }
    }

    /// 往当前打开的归档里添加磁盘上的文件
    func addToArchive(_ urls: [URL]) {
        guard let a = archive, !urls.isEmpty else { return }
        busy = true
        status = L10n.t("status.adding", "添加中…")
        Task.detached(priority: .userInitiated) {
            do {
                try ArchiveBackend.shared.add(URL(fileURLWithPath: a.path), files: urls)
                let list = try ArchiveBackend.shared.list(URL(fileURLWithPath: a.path))
                await MainActor.run {
                    self.entries = list
                    self.status = L10n.f("status.addedCount", "已添加 %d 项", urls.count)
                    self.busy = false
                }
            } catch {
                await MainActor.run {
                    self.status = L10n.t("error.addFailed", "添加失败：") + error.localizedDescription
                    self.busy = false
                }
            }
        }
    }

    /// 导出单个条目到临时目录，给拖拽用
    func exportEntryForDrag(_ e: ArchiveEntry, completion: @escaping (URL?) -> Void) {
        guard let a = archive else { completion(nil); return }
        Task.detached(priority: .userInitiated) {
            let url = try? ArchiveBackend.shared.extractEntry(
                URL(fileURLWithPath: a.path), path: e.path)
            await MainActor.run { completion(url) }
        }
    }

    /// 归档内复制 / 移动
    func moveOrCopy(from: String, to: String, copy: Bool) {
        guard let a = archive else { return }
        busy = true
        status = copy ? L10n.t("status.copying", "复制中…") : L10n.t("status.moving", "移动中…")
        Task.detached(priority: .userInitiated) {
            do {
                if copy {
                    try ArchiveBackend.shared.copyEntry(URL(fileURLWithPath: a.path), from: from, to: to)
                } else {
                    try ArchiveBackend.shared.rename(URL(fileURLWithPath: a.path), from: from, to: to)
                }
                let list = try ArchiveBackend.shared.list(URL(fileURLWithPath: a.path))
                await MainActor.run {
                    self.entries = list
                    self.selection = []
                    self.status = (copy ? L10n.t("app.copiedTo", "已复制到 ") : L10n.t("app.movedTo", "已移动到 ")) + to
                    self.busy = false
                }
            } catch {
                await MainActor.run {
                    self.status = L10n.t("error.generic", "失败：") + error.localizedDescription
                    self.busy = false
                }
            }
        }
    }

    /// 移到废纸篓（可撤销）
    func trash(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.recycle(urls) { _, error in
            Task { @MainActor in
                if let error {
                    self.status = L10n.t("error.deleteFailed", "删除失败：") + error.localizedDescription
                } else {
                    self.status = L10n.f("status.trashed", "已移到废纸篓（%d 项）", urls.count)
                    self.loadFS(self.fsPath)
                }
            }
        }
    }

    func showInfo() {
        guard let a = archive else { return }
        let size = (try? FileManager.default.attributesOfItem(atPath: a.path)[.size] as? Int64) ?? 0
        let dirs = entries.filter { $0.isDirectory }.count
        let files = entries.count - dirs
        let raw = entries.filter { !$0.isDirectory }.reduce(Int64(0)) { $0 + $1.size }
        let packed = entries.filter { !$0.isDirectory }.reduce(Int64(0)) { $0 + $1.packedSize }
        let ratio = raw > 0 ? Double(packed) / Double(raw) * 100 : 0
        infoRows = [
            InfoRow(label: L10n.t("info.file", "文件"), value: a.lastPathComponent),
            InfoRow(label: L10n.t("info.archiveSize", "归档大小"), value: ByteCountFormatter.string(fromByteCount: size, countStyle: .file)),
            InfoRow(label: L10n.t("info.entries", "条目"), value: L10n.f("app.itemsCount", "%d 个（%@ 目录 / %@ 文件）", entries.count, String(dirs), String(files))),
            InfoRow(label: L10n.t("info.rawSize", "原始大小"), value: ByteCountFormatter.string(fromByteCount: raw, countStyle: .file)),
            InfoRow(label: L10n.t("col.packed", "压缩后"), value: ByteCountFormatter.string(fromByteCount: packed, countStyle: .file)),
            InfoRow(label: L10n.t("info.ratio", "压缩率"), value: String(format: "%.1f%%", ratio))
        ]
        status = L10n.t("info.title", "归档信息")
    }

    func removeSelected() {
        guard let a = archive else { return }
        let sub = entries.filter { selection.contains($0.id) }.map { $0.path }
        if sub.isEmpty { status = L10n.t("hint.selectToDelete", "先选中要删除的条目"); return }
        busy = true; status = L10n.t("status.deleting", "删除中…")
        Task.detached(priority: .userInitiated) {
            do {
                try ArchiveBackend.shared.remove(URL(fileURLWithPath: a.path), items: sub)
                let list = try ArchiveBackend.shared.list(URL(fileURLWithPath: a.path))
                await MainActor.run {
                    self.entries = list
                    self.selection = []
                    self.status = L10n.f("status.deletedCount", "已删除 %d 项", sub.count)
                    self.busy = false
                }
            } catch {
                await MainActor.run { self.status = error.localizedDescription; self.busy = false }
            }
        }
    }
}

// MARK: - 视图
struct ContentView: View {
    @StateObject private var model = ZipModel()
    @State private var showOpen = false

    @State private var showInfoSheet = false
    @State private var showAbout = false
    /// 换语言后 +1，用来强制重建界面
    @State private var appLanguageRevision = 0
    /// 参数对话框要一直持有，否则窗口刚显示就被释放
    @State private var activeDialog: AnyObject?
    // 0 表示用户还没拖过 —— 此时左栏固定占一半，分隔线居中
    @AppStorage("leftPaneWidth") private var leftWidth: Double = 0
    @AppStorage("lastVisitedPath") private var lastVisitedPath: String = ""
    @State private var dragStartWidth: Double? = nil

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            GeometryReader { geo in
                HStack(spacing: 0) {
                    fsPane
                        .frame(width: paneWidth(total: geo.size.width))
                    splitHandle
                    archivePane
                        .frame(maxWidth: .infinity)
                }
            }
            Divider()
            statusBar
        }
        .frame(minWidth: 1000, idealWidth: 1180, minHeight: 600)
        .onAppear {
            model.refreshStatusIfIdle()

            // 把界面的动作挂给菜单栏
            AppActions.shared.openArchive = { showOpen = true }
            AppActions.shared.extractAll = { askExtractAll() }
            AppActions.shared.compressSelected = { askAndCreateArchive() }
            AppActions.shared.refresh = { model.loadFS(model.fsPath) }
            AppActions.shared.goUp = { model.goUp() }
            AppActions.shared.goHome = {
                model.loadFS(URL(fileURLWithPath: NSHomeDirectory()))
            }
            AppActions.shared.goDesktop = {
                if let d = FileManager.default.urls(for: .desktopDirectory,
                                                    in: .userDomainMask).first {
                    model.loadFS(d)
                }
            }
            AppActions.shared.testArchive = { model.test() }
            AppActions.shared.showInfo = {
                model.showInfo()
                showInfoSheet = true
            }
            AppActions.shared.runBenchmark = { Benchmark.run() }
            AppActions.shared.languageChanged = {
                // 语言文件换了，重建界面
                appLanguageRevision += 1
            }

            // 恢复上次访问的目录
            let saved = UserDefaults.standard.string(forKey: "lastVisitedPath") ?? ""
            let target = saved.isEmpty ? model.fsPath : URL(fileURLWithPath: saved)
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: target.path, isDirectory: &isDir), isDir.boolValue {
                model.loadFS(target)
            } else {
                model.loadFS(model.fsPath)
            }

            // 记住窗口位置尺寸
            if let w = NSApp.windows.first {
                w.setFrameAutosaveName("SilentZIPMainWindow")
            }
            // 三条路都试：open 事件 / 命令行参数 / 拖拽
            if let u = OpenBus.shared.pending {
                model.open(u)
            } else if let a = CommandLine.arguments.dropFirst().first(where: { !$0.hasPrefix("-") }) {
                model.open(URL(fileURLWithPath: a))
            }
            if CommandLine.arguments.contains("--selftest2") {
                let z = URL(fileURLWithPath: "/tmp/silentzip-selftest.zip")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { model.open(z) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    model.moveOrCopy(from: "Sources", to: "SourcesMoved", copy: false)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 4.5) {
                    model.moveOrCopy(from: "SourcesMoved", to: "SourcesCopy", copy: true)
                }
            }
            if CommandLine.arguments.contains("--selftest") {
                // 自测：把 Sources 目录压成 zip，然后打开它
                let src = URL(fileURLWithPath: "/Users/apple/Desktop/SilentZIP/Sources")
                let target = URL(fileURLWithPath: "/tmp/silentzip-selftest.zip")
                try? FileManager.default.removeItem(at: target)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    model.createArchive(from: [src], to: target)
                }
            }
            if CommandLine.arguments.contains("--about")
                || CommandLine.arguments.contains("--terms") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    showAbout = true
                }
            }

            if CommandLine.arguments.contains("--compress-dialog") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    let dlg = CompressDialog()
                    dlg.show(suggested: NSHomeDirectory() + "/Desktop/test.7z") { _ in }
                    activeDialog = dlg
                }
            }
            if CommandLine.arguments.contains("--set-default") {
                let n = ArchiveTypes.becomeDefault()
                let msg = "becomeDefault: " + String(n) + "/" + String(ArchiveTypes.utis.count)
                try? msg.write(toFile: "/tmp/silentzip-default.log",
                               atomically: true, encoding: .utf8)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { NSApp.terminate(nil) }
            }
            // 调试用：--info 启动后自动弹信息窗
            if CommandLine.arguments.contains("--info") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    model.showInfo()
                    showInfoSheet = true
                }
            }
            try? "appear, pending=\(String(describing: OpenBus.shared.pending))\n".write(
                toFile: "/tmp/silentzip-appear.log", atomically: true, encoding: .utf8)
        }
        .onReceive(OpenBus.shared.$pending) { url in
            if let url { model.open(url) }
        }
        .onOpenURL { url in
            model.open(url)
        }
        .fileImporter(isPresented: $showOpen, allowedContentTypes: [.data], allowsMultipleSelection: false) { r in
            if case .success(let u) = r, let f = u.first { model.open(f) }
        }
        .sheet(isPresented: $showAbout) {
            AboutView()
        }
        .onReceive(AboutBus.shared.$open) { v in
            if v { showAbout = true; AboutBus.shared.open = false }
        }
        .sheet(isPresented: $showInfoSheet) {
            VStack(alignment: .leading, spacing: 16) {
                Text(L10n.t("info.title", "归档信息")).font(.headline)

                // 两列：标签列固定靠左，值列也靠左，各自对齐
                Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 10) {
                    ForEach(model.infoRows) { row in
                        GridRow(alignment: .firstTextBaseline) {
                            Text(row.label)
                                .foregroundStyle(.secondary)
                                .gridColumnAlignment(.leading)
                            Text(row.value)
                                .textSelection(.enabled)
                                .gridColumnAlignment(.leading)
                        }
                    }
                }

                if !model.infoText.isEmpty {
                    Divider()
                    ScrollView {
                        Text(model.infoText)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 180)
                }

                HStack {
                    Spacer()
                    Button(L10n.t("ui.close", "关闭")) { showInfoSheet = false }
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(24)
            .frame(minWidth: 460)
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { p in
            guard let f = p.first else { return false }
            _ = f.loadObject(ofClass: URL.self) { u, _ in
                if let u { Task { @MainActor in model.open(u) } }
            }
            return true
        }
    }

    private var toolbar: some View {
        HStack(spacing: 4) {
            tb("folder", L10n.t("open", "打开归档")) { showOpen = true }
            tb("plus.square",
               model.canModify ? L10n.t("addFiles", "把选中的文件/文件夹压缩成归档")
                               : L10n.t("protected", L10n.t("lock.protectedCompress", "系统目录受保护，不能在此压缩")),
               disabled: !model.canModify) { askAndCreateArchive() }
            tb("arrow.down.doc",
               model.canModify ? L10n.t("extract", "解压选中的文件")
                               : L10n.t("protected", L10n.t("lock.protectedExtract", "系统目录受保护，不能解压到此处"))) { askExtract() }
                .disabled(model.archive == nil || !model.canModify)
            tb("checkmark.shield", L10n.t("test", L10n.t("ctx.test", "测试完整性")), disabled: model.archive == nil) { model.test() }
            Divider().frame(height: 18)
            tb("doc.on.doc", L10n.t("copy", "复制选中条目到归档内新路径"),
               disabled: model.archive == nil) { askMoveCopy(copy: true) }
            tb("arrow.right.doc.on.clipboard", L10n.t("move", "移动/重命名选中条目"),
               disabled: model.archive == nil) { askMoveCopy(copy: false) }
            tb("plus.rectangle.on.folder",
               L10n.t("addToArchive", "往当前归档里添加文件"),
               disabled: model.archive == nil) { askAddToArchive() }
            tb("trash",
               model.canModify ? L10n.t("delete", "删除选中")
                               : L10n.t("protectedDelete", "系统目录受保护，不能删除"),
               disabled: model.archive == nil || !model.canModify) { model.removeSelected() }
            tb("info.circle", L10n.t("info", L10n.t("ctx.info", "显示归档信息")), disabled: model.archive == nil) {
                model.showInfo(); showInfoSheet = true
            }
            Spacer(minLength: 24)

            // 右侧：常用位置导航
            HStack(spacing: 2) {
                quickPlace(L10n.t("path.desktop", "桌面"), "desktopcomputer", .desktopDirectory)
                quickPlace(L10n.t("path.downloads", "下载"), "arrow.down.circle", .downloadsDirectory)
                quickPlace(L10n.t("path.documents", "文稿"), "doc.text", .documentDirectory)
                quickPlace(L10n.t("place.home", "主目录"), "house", nil)
                quickPlace(L10n.t("place.root", "根目录"), "externaldrive", nil, forced: "/")
            }

            if model.busy {
                ProgressView().controlSize(.small).padding(.leading, 6)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func tb(_ symbol: String, _ tip: String, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 15))
                .frame(width: 30, height: 24)
        }
        .buttonStyle(.borderless)
        .disabled(disabled)
        .opacity(disabled ? 0.32 : 1.0)
        .help(tip)
    }

    private var fsPane: some View {
        VStack(spacing: 0) {
            // 路径条：每一段都能点，直接跳回去
            HStack(spacing: 4) {
                Button { model.goUp() } label: {
                    Image(systemName: "chevron.up.circle.fill").font(.system(size: 15))
                }
                .buttonStyle(.borderless).help(L10n.t("place.up", "上一级"))

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 2) {
                        ForEach(Array(model.pathChunks.enumerated()), id: \.offset) { idx, chunk in
                            if idx > 0 {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 8)).foregroundStyle(.tertiary)
                            }
                            Button(chunk.label) { model.jump(to: chunk.path) }
                                .buttonStyle(.borderless)
                                .font(.caption)
                                .foregroundStyle(idx == model.pathChunks.count - 1 ? .primary : .secondary)
                        }
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 8).padding(.vertical, 6)

            Divider()

            // 和右栏一样的表格：单击就进入，不用双击
            Table(model.fsItems, selection: $model.fsSelected) {
                TableColumn(L10n.t("col.name", "名称")) { e in
                    HStack(spacing: 6) {
                        Image(nsImage: e.icon)
                            .resizable()
                            .frame(width: 18, height: 18)
                        Text(e.name).lineLimit(1)
                        Spacer(minLength: 0)   // 撑满整列，空白处也能双击
                    }
                    // 单击只选中（Table 原生），双击才进目录
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { model.enter(e) }
                    .contextMenu {
                        // 「打开」= 交给系统默认程序（和 Finder 一致）
                        Button(L10n.t("ctx.open", "打开")) {
                            NSWorkspace.shared.open(e.url)
                        }
                        // 能解析成归档的，额外给一个入口
                        if canTryAsArchive(e.url) {
                            Button(L10n.t("ctx.openAsArchive", "作为归档查看")) {
                                model.open(e.url, fallbackToSystem: false)
                            }
                        }
                        Divider()
                        Button(L10n.t("ctx.compress7z", "压缩为 7z…")) { askCreate(items: [e.url], ext: "7z") }
                        Button(L10n.t("ctx.compressZip", "压缩为 zip…")) { askCreate(items: [e.url], ext: "zip") }
                        Divider()
                        Button(L10n.t("ctx.revealInFinder", "在 Finder 中显示")) {
                            NSWorkspace.shared.activateFileViewerSelecting([e.url])
                        }
                        Button(L10n.t("ctx.moveToTrash", "移到废纸篓")) { model.trash([e.url]) }
                            .disabled(!model.canModify)
                    }
                    .help(e.url.path)
                }
                TableColumn(L10n.t("col.type", "类型")) { e in
                    Text(e.typeLabel).foregroundStyle(.secondary).font(.caption)
                }.width(90)
                TableColumn(L10n.t("col.size", "大小")) { e in
                    Text(e.sizeText).foregroundStyle(.secondary)
                        .monospacedDigit().font(.caption)
                }.width(75)
                TableColumn(L10n.t("col.modified", "修改")) { e in
                    Text(e.dateText).foregroundStyle(.secondary).font(.caption)
                }.width(100)
            }
            .tableStyle(.inset)
        }
    }

    private var archivePane: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                if !model.currentPath.isEmpty {
                    Button { model.currentPath = (model.currentPath as NSString).deletingLastPathComponent == "." ? "" : (model.currentPath as NSString).deletingLastPathComponent } label: {
                        Image(systemName: "arrow.up.backward")
                    }.buttonStyle(.borderless).help(L10n.t("place.upTooltip", "返回上级目录"))
                }
                Text(model.archive?.lastPathComponent ?? L10n.t("status.noArchiveTitle", "未打开归档")).font(.caption).bold()
                if !model.currentPath.isEmpty {
                    Text("/" + model.currentPath).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            Divider()
            Table(model.visible, selection: $model.selection) {
                TableColumn(L10n.t("col.name", "名称")) { e in
                    HStack(spacing: 6) {
                        Image(systemName: e.isDirectory ? "folder" : "doc")
                            .foregroundStyle(e.isDirectory ? Color.accentColor : .secondary)
                        Text(e.name)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { model.enterEntry(e) }
                    // 拖到 Finder 就是导出：先临时解出来，再交给系统
                    .onDrag {
                        let provider = NSItemProvider()
                        let name = (e.path as NSString).lastPathComponent
                        provider.suggestedName = name
                        provider.registerFileRepresentation(
                            forTypeIdentifier: UTType.data.identifier,
                            fileOptions: [],
                            visibility: .all
                        ) { completion in
                            Task { @MainActor in
                                model.exportEntryForDrag(e) { url in
                                    completion(url, false, nil)
                                }
                            }
                            return nil
                        }
                        return provider
                    }
                    .contextMenu {
                        Button(L10n.t("ctx.open", "打开")) { model.openEntry(e) }
                        Button(L10n.t("ctx.expandNested", "展开嵌套归档")) { model.enterEntry(e) }
                        Divider()
                        Button(L10n.t("ctx.extractSelected", "解压选中项")) { askExtract() }
                        Button(L10n.t("ctx.extractAll", "全部解压…")) { askExtractAll() }
                        Divider()
                        Button(L10n.t("ctx.copyTo", "复制到…")) { askMoveCopy(copy: true) }
                        Button(L10n.t("ctx.moveTo", "移动到…")) { askMoveCopy(copy: false) }
                        Divider()
                        Button(L10n.t("ctx.test", "测试完整性")) { model.test() }
                        Button(L10n.t("ctx.info", "显示归档信息")) { model.showInfo(); showInfoSheet = true }
                        if let a = model.archive {
                            Button(L10n.t("ctx.revealArchive", "在 Finder 中显示归档")) {
                                NSWorkspace.shared.activateFileViewerSelecting([a])
                            }
                        }
                    }
                }
                TableColumn(L10n.t("col.size", "大小")) { e in
                    Text(e.isDirectory ? "—" : ByteCountFormatter.string(fromByteCount: e.size, countStyle: .file))
                        .foregroundStyle(.secondary).monospacedDigit()
                }.width(90)
                TableColumn(L10n.t("col.packed", "压缩后")) { e in
                    Text(e.isDirectory ? "—" : ByteCountFormatter.string(fromByteCount: e.packedSize, countStyle: .file))
                        .foregroundStyle(.secondary).monospacedDigit()
                }.width(90)
                TableColumn(L10n.t("col.modifiedFull", "修改时间")) { e in
                    Text(e.modified).foregroundStyle(.secondary).font(.caption)
                }.width(150)
                TableColumn("CRC") { e in
                    Text(e.crc).foregroundStyle(.tertiary).font(.caption).monospaced()
                }.width(90)
            }
        }
    }

    /// 常用位置按钮
    @ViewBuilder
    private func quickPlace(_ title: String, _ symbol: String,
                            _ dir: FileManager.SearchPathDirectory?,
                            forced: String? = nil) -> some View {
        Button {
            let target: URL
            if let forced {
                target = URL(fileURLWithPath: forced)
            } else if let dir {
                target = FileManager.default.urls(for: dir, in: .userDomainMask).first
                    ?? URL(fileURLWithPath: NSHomeDirectory())
            } else {
                target = URL(fileURLWithPath: NSHomeDirectory())
            }
            model.loadFS(target)
        } label: {
            Label(title, systemImage: symbol)
                .font(.caption)
                .padding(.horizontal, 7).padding(.vertical, 3)
        }
        .buttonStyle(.borderless)
        .help(title)
    }

    /// 归档内复制/移动：弹个输入框要新路径
    private func askMoveCopy(copy: Bool) {
        guard model.archive != nil else { return }
        let sel = model.entries.filter { model.selection.contains($0.id) }
        guard let first = sel.first else {
            model.status = L10n.t("hint.selectEntryFirst", "先在右边选中一个条目")
            return
        }

        let alert = NSAlert()
        alert.messageText = copy ? L10n.t("dialog.copyToTitle", "复制到（归档内路径）") : L10n.t("dialog.moveToTitle", "移动到（归档内路径）")
        alert.informativeText = L10n.t("dialog.pathHint", "例如 dir/newname.txt —— 只改归档内部结构，不动磁盘")
        alert.addButton(withTitle: L10n.t("ui.confirm", "确定"))
        alert.addButton(withTitle: L10n.t("ui.cancel", "取消"))

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 380, height: 24))
        field.stringValue = first.path
        alert.accessoryView = field

        if alert.runModal() == .alertFirstButtonReturn {
            let newPath = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !newPath.isEmpty, newPath != first.path else { return }
            model.moveOrCopy(from: first.path, to: newPath, copy: copy)
        }
    }

    /// 压缩按钮：先弹完整的参数对话框，确认后再压
    private func askAndCreateArchive() {
        let items = model.fsSelectedItems
        guard !items.isEmpty else {
            let a = NSAlert()
            a.messageText = L10n.t("hint.selectToCompressFirst", "先选中要压缩的文件或文件夹")
            a.addButton(withTitle: L10n.t("ui.gotIt", "知道了"))
            a.runModal()
            return
        }

        let base = items.first?.deletingPathExtension().lastPathComponent ?? L10n.t("app.defaultName", "归档")
        let suggested = model.fsPath.appendingPathComponent(base + ".7z").path

        let dlg = CompressDialog()
        dlg.show(suggested: suggested) { opts in
            let target = URL(fileURLWithPath: opts.outputPath)
            model.createArchive(from: items, to: target, options: opts)
        }
        // 保持引用，窗口关掉前不能释放
        activeDialog = dlg
    }

    /// 解压按钮：有选中就解压选中，没选中就提示，不替用户做决定
    private func askExtract() {
        guard model.archive != nil else { return }

        let picked = model.entries.filter { model.selection.contains($0.id) }
        guard !picked.isEmpty else {
            let a = NSAlert()
            a.messageText = L10n.t("dialog.selectToExtract", "先选一下要解压的文件")
            a.informativeText = L10n.t("dialog.selectToExtractBody", "在右边列表里点选条目，再点解压。\n如果想全部解压，右键菜单里有「全部解压」。")
            a.addButton(withTitle: L10n.t("ui.gotIt", "知道了"))
            a.runModal()
            return
        }

        let panel = NSOpenPanel()
        panel.title = L10n.t("dialog.extractWhere", "解压到哪里")
        panel.prompt = L10n.t("ui.extract", "解压")
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.directoryURL = model.fsPath
        panel.begin { resp in
            guard resp == .OK, let dir = panel.url else { return }
            Task { @MainActor in model.extract(to: dir) }
        }
    }

    /// 全部解压：先把整个包解出来
    private func askExtractAll() {
        guard model.archive != nil else { return }
        let panel = NSOpenPanel()
        panel.title = L10n.t("dialog.extractAllWhere", "全部解压到哪里")
        panel.prompt = L10n.t("ui.extract", "解压")
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.directoryURL = model.fsPath
        panel.begin { resp in
            guard resp == .OK, let dir = panel.url else { return }
            Task { @MainActor in model.extractAll(to: dir) }
        }
    }

    /// 选文件，加进当前归档
    private func askAddToArchive() {
        guard model.archive != nil else { return }
        let panel = NSOpenPanel()
        panel.title = L10n.t("dialog.addToArchive", "添加到归档")
        panel.prompt = L10n.t("ui.add", "添加")
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.begin { resp in
            guard resp == .OK, !panel.urls.isEmpty else { return }
            let urls = panel.urls
            Task { @MainActor in model.addToArchive(urls) }
        }
    }

    /// 弹保存面板，选格式和位置
    private func askCreate(items: [URL], ext: String) {
        guard !items.isEmpty else {
            model.status = L10n.t("hint.selectToCompressFirst", "先选中要压缩的文件或文件夹")
            return
        }

        let panel = NSSavePanel()
        panel.title = L10n.t("dialog.createArchive", "创建归档")
        panel.prompt = L10n.t("ui.compress", "压缩")
        let base = items.first?.deletingPathExtension().lastPathComponent ?? L10n.t("ui.archive", "归档")
        panel.nameFieldStringValue = base + "." + ext
        panel.directoryURL = model.fsPath
        panel.canCreateDirectories = true

        var types: [UTType] = []
        for ext in ["7z", "zip", "tar", "gz", "xz", "bz2"] {
            if let t = UTType(filenameExtension: ext) { types.append(t) }
        }
        panel.allowedContentTypes = types

        // 预设下拉：压缩前能直接改用什么参数
        let picker = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 260, height: 26))
        let presets = PresetStore.all
        picker.addItems(withTitles: presets.map { $0.name + "  (" + $0.summary + ")" })
        if let idx = presets.firstIndex(where: { $0.name == model.preset.name }) {
            picker.selectItem(at: idx)
        }
        let label = NSTextField(labelWithString: L10n.t("app.presetLabel", "压缩预设"))
        label.font = .systemFont(ofSize: 11)
        let box = NSStackView(views: [label, picker])
        box.orientation = .horizontal
        box.spacing = 8
        box.frame = NSRect(x: 0, y: 0, width: 360, height: 32)
        panel.accessoryView = box

        panel.begin { resp in
            if let i = presets.firstIndex(where: { $0.name == presets[picker.indexOfSelectedItem].name }) {
                model.preset = presets[i]
            }
            guard resp == .OK, let target = panel.url else { return }
            Task { @MainActor in
                model.createArchive(from: items, to: target)
            }
        }
    }

    /// 左栏宽度：没拖过就居中，拖过就用存下来的值
    private func paneWidth(total: CGFloat) -> CGFloat {
        if leftWidth <= 0 {
            return max(280, (total - 1) / 2)
        }
        return max(260, min(total - 320, leftWidth))
    }

    /// 可拖动的分栏手柄，宽度写进 UserDefaults
    private var splitHandle: some View {
        ZStack {
            Rectangle()
                .fill(Color(nsColor: .separatorColor))
                .frame(width: 1)
            Rectangle()
                .fill(Color.clear)
                .frame(width: 9)
                .contentShape(Rectangle())
                .onHover { inside in
                    if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                }
                .gesture(
                    DragGesture(minimumDistance: 1)
                        .onChanged { g in
                            if dragStartWidth == nil { dragStartWidth = leftWidth }
                            let base = dragStartWidth ?? leftWidth
                            leftWidth = max(260, base + g.translation.width)
                        }
                        .onEnded { _ in dragStartWidth = nil }
                )
        }
        .frame(width: 1)
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            Text(model.fsPath.path).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            Text(L10n.f("status.itemCount", "%d 项", model.fsItems.count)).font(.caption2).foregroundStyle(.tertiary)
            Divider().frame(height: 12)
            Text(model.status).font(.caption).lineLimit(1).truncationMode(.middle)
            Spacer()
            if let reason = model.lockedReason {
                Label(reason, systemImage: "lock.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
    }
}

@main
struct SilentZIPApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        // 用 Window 而不是 WindowGroup：整个应用只允许一个窗口
        Window("SilentZIP", id: "main") {
            ContentView()
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .appInfo) {
                Button(L10n.t("menu.about", "关于 SilentZIP")) {
                    AboutBus.shared.open = true
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
            CommandGroup(after: .appInfo) {
                Divider()
                Button(L10n.t("menu.setDefault", "设为默认压缩工具")) {
                    ArchiveTypes.becomeDefault()
                }
                Button(L10n.t("menu.installCLI", "安装命令行工具…")) {
                    CLITool.install()
                }
                Divider()
                Menu(L10n.t("menu.language", "语言")) {
                    ForEach(L10n.available, id: \.code) { lang in
                        Button {
                            UserDefaults.standard.set(lang.code, forKey: "uiLanguage")
                            L10n.load(lang.code)
                            AppActions.shared.languageChanged?()
                        } label: {
                            if L10n.currentCode() == lang.code {
                                Text("✓ " + lang.name)
                            } else {
                                Text("   " + lang.name)
                            }
                        }
                    }
                }
                Divider()
                Button(L10n.t("menu.benchmark", "基准测试…")) {
                    AppActions.shared.runBenchmark?()
                }
            }
            // 文件
            CommandGroup(after: .newItem) {
                Divider()
                Button(L10n.t("menu.openArchive", "打开归档…")) {
                    AppActions.shared.openArchive?()
                }
                .keyboardShortcut("o", modifiers: .command)
                Button(L10n.t("menu.extractAll", "全部解压…")) {
                    AppActions.shared.extractAll?()
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                Button(L10n.t("menu.compressSelected", "压缩选中项…")) {
                    AppActions.shared.compressSelected?()
                }
                .keyboardShortcut("n", modifiers: .command)
            }

            // 查看
            CommandMenu(L10n.t("menu.go", "转到")) {
                Button(L10n.t("menu.refresh", "刷新")) {
                    AppActions.shared.refresh?()
                }
                .keyboardShortcut("r", modifiers: .command)
                Button(L10n.t("menu.up", "向上一级")) {
                    AppActions.shared.goUp?()
                }
                .keyboardShortcut(.upArrow, modifiers: .command)
                Divider()
                Button(L10n.t("menu.openHome", "回到主目录")) {
                    AppActions.shared.goHome?()
                }
                Button(L10n.t("menu.openDesktop", "回到桌面")) {
                    AppActions.shared.goDesktop?()
                }
            }

            // 工具
            CommandMenu(L10n.t("menu.tools", "工具")) {
                Button(L10n.t("menu.testIntegrity", "测试完整性")) {
                    AppActions.shared.testArchive?()
                }
                .keyboardShortcut("t", modifiers: .command)
                Button(L10n.t("menu.archiveInfo", "归档信息")) {
                    AppActions.shared.showInfo?()
                }
                .keyboardShortcut("i", modifiers: .command)
                Divider()
                Button(L10n.t("menu.setDefault", "设为默认压缩工具")) {
                    ArchiveTypes.becomeDefault()
                }
                Button(L10n.t("menu.installCLI", "安装命令行工具…")) {
                    CLITool.install()
                }
            }
        }
    }
}
