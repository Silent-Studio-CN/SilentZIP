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
        NSApp.activate(ignoringOtherApps: true)
        // 让系统重新扫描本 app 的 NSServices —— 否则右键菜单里看不到，
        // 用户还得手动去「系统设置 → 键盘 → 服务」勾选
        NSUpdateDynamicServices()
    }

    // MARK: - Finder 右键「快速操作」/「服务」

    /// 用 SilentZIP 打开 —— 对应 Info.plist 里 NSServices 的 NSMessage
    @objc func openArchive(_ pboard: NSPasteboard,
                           userData: String,
                           error: AutoreleasingUnsafeMutablePointer<NSString>) {
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
                    a.messageText = "解压失败"
                    a.informativeText = error.localizedDescription
                    a.runModal()
                }
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

// MARK: - 支持的归档后缀
let archiveExts: Set<String> = ["7z","zip","rar","tar","gz","tgz","bz2","tbz","xz","txz","zst","iso","cab","lzh","arj","cpio","lzma"]

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

func canTryAsArchive(_ url: URL) -> Bool {
    let e = url.pathExtension.lowercased()
    return isArchive(url) || archiveLikeExts.contains(e)
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

/// 系统本地化的类型名（中文环境下自动是「应用程序」「压缩包」等）
func typeName(_ url: URL) -> String {
    let ext = url.pathExtension.lowercased()
    if ext.isEmpty { return "文件夹" }
    if ext == "app" { return "应用程序" }
    if ext == "framework" { return "框架" }
    if let t = UTType(filenameExtension: ext),
       let d = t.localizedDescription, !d.isEmpty {
        return d
    }
    return ext.uppercased() + " 文件"
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
                Text("版本 " + version).font(.callout).foregroundStyle(.secondary)
                Text("macOS 归档管理器").font(.callout).foregroundStyle(.secondary)
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
                            Text("私有许可协议").font(.headline)
                            Text("v1.0")
                                .font(.caption2)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.15))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }

                        Text("允许：免费使用（个人与商业）、分发未修改的副本。")
                        Text("禁止：修改、反向工程、把源码或算法移植到其他项目、转售。")
                        Text("")
                        Text("Proprietary License").font(.headline)
                        Text("Permitted: free use (personal and commercial), distribution of unmodified copies.")
                        Text("Prohibited: modification, reverse engineering, porting into other projects, resale.")
                        Text("中英文如有歧义，以中文为准。")
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                    .font(.callout)

                    Button {
                        showFullTerms = true
                    } label: {
                        Label("查看完整条款", systemImage: "doc.text")
                    }
                    .controlSize(.large)

                    Divider().padding(.vertical, 2)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("技术").font(.headline)

                        techRow("界面", "SwiftUI + AppKit")
                        techRow("归档引擎", "7-Zip（p7zip 17.05）")
                        techRow("引擎版权", "© 1999-2025 Igor Pavlov")
                        techRow("引擎许可", "GNU LGPL · unRAR restriction")

                        Text("7-Zip 以独立进程方式调用，不静态链接。其版权与许可归原作者，独立于本协议。")
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
                Button("好") { dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(width: 500, height: 620)
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

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("完整条款").font(.headline)
                Spacer()
                Button("关闭") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 20).padding(.vertical, 14)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("SilentZIP 私有许可协议 v1.0")
                        .font(.headline)

                    group("一、授权", """
                    SilentStudio 授予你一项非独占、不可转让的许可，你可以：
                    · 在本机安装并使用本软件，用于个人或商业用途，无需付费；
                    · 分发本软件的完整未修改副本，但须附带本协议全文。
                    """)

                    group("二、限制", """
                    你不得：
                    · 修改、翻译、反编译、反汇编或对本软件进行反向工程；
                    · 将本软件的源码、算法或界面设计移植、借鉴到其他项目；
                    · 将本软件或其修改版用于销售、租赁、捆绑销售；
                    · 移除或篡改本软件中的版权声明与许可标识；
                    · 将其用于训练机器学习模型。
                    """)

                    group("三、第三方组件", """
                    本软件以独立进程方式调用 7-Zip（7z）完成压缩与解压。
                    7-Zip 版权归 Igor Pavlov 所有，依 GNU LGPL 及其附带的
                    unRAR license restriction 发布，条款独立于本协议。
                    """)

                    group("四、免责", """
                    本软件按现状提供，不附带任何明示或默示担保。因使用本软件
                    造成的数据丢失、归档损坏或其他损失，SilentStudio 不承担责任。
                    使用前请自行备份重要数据。
                    """)

                    group("五、终止", """
                    违反本协议任一条款，授权立即自动终止，你应停止使用并删除
                    本软件。本协议适用中华人民共和国法律。
                    """)

                    Divider().padding(.vertical, 6)

                    Text("Proprietary License v1.0").font(.headline)

                    group("1. Grant", """
                    SilentStudio grants you a non-exclusive, non-transferable license
                    to install and use this software on your own machines for personal
                    or commercial purposes at no charge, and to distribute complete
                    unmodified copies provided this license is included.
                    """)

                    group("2. Restrictions", """
                    You may not modify, translate, decompile, disassemble, or reverse
                    engineer the software; port, adapt, or transplant its source code,
                    algorithms, or interface design into any other project; sell, rent,
                    or bundle it; remove or alter any copyright or license notice; or
                    use it to train machine-learning models.
                    """)

                    group("3. Third-Party Components", """
                    7-Zip is Copyright (C) 1999-2025 Igor Pavlov and is distributed
                    under the GNU LGPL together with the unRAR license restriction.
                    It is invoked as a separate process and is not statically linked.
                    """)

                    group("4. Disclaimer", """
                    THE SOFTWARE IS PROVIDED AS IS, WITHOUT WARRANTY OF ANY KIND.
                    SilentStudio is not liable for data loss, archive corruption, or
                    any other damage arising from its use.
                    """)

                    group("5. Termination", """
                    Any breach terminates this license immediately; you must stop
                    using the software and delete all copies. This license is governed
                    by the laws of the People's Republic of China.
                    """)

                    Text("中英文如有歧义，以中文为准。")
                        .font(.caption).foregroundStyle(.tertiary)
                        .padding(.top, 6)
                }
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(22)
            }
        }
        .frame(width: 620, height: 640)
    }

    private func group(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.callout).bold().padding(.top, 4)
            Text(body).foregroundStyle(.secondary).textSelection(.enabled)
        }
    }
}

// MARK: - 信息行
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
        if isLink { return "符号链接" }
        if isBundle { return typeName(url) }
        return isDir ? "文件夹" : typeName(url)
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
        case "Users": return "用户"
        case "Desktop": return "桌面"
        case "Downloads": return "下载"
        case "Documents": return "文稿"
        case "Movies": return "影片"
        case "Music": return "音乐"
        case "Pictures": return "图片"
        case "Library": return "资源库"
        case "Applications": return "应用程序"
        case "System": return "系统"
        case "Volumes": return "宗卷"
        default: return s
        }
    }

    func jump(to url: URL) { loadFS(url) }

    /// 左栏当前选中的文件/文件夹
    var fsSelectedItems: [URL] {
        fsItems.filter { fsSelected.contains($0.id) }.map { $0.url }
    }

    /// 把选中的文件/文件夹压缩成新归档
    func createArchive(from items: [URL], to target: URL) {
        guard !items.isEmpty else { status = "先在左边选中要压缩的内容"; return }
        busy = true
        status = "压缩中…（\(items.count) 项）"

        let fmt: String = {
            let e = target.pathExtension.lowercased()
            return e.isEmpty ? "7z" : e
        }()

        Task.detached(priority: .userInitiated) {
            do {
                try ArchiveBackend.shared.create(target, from: items, format: fmt)
                let list = try ArchiveBackend.shared.list(target)
                await MainActor.run {
                    self.archive = target
                    self.entries = list
                    self.currentPath = ""
                    self.selection = []
                    self.status = "已创建 \(target.lastPathComponent)（\(list.count) 个条目）"
                    self.busy = false
                    self.loadFS(self.fsPath)
                }
            } catch {
                await MainActor.run {
                    self.status = "压缩失败：\(error.localizedDescription)"
                    self.busy = false
                }
            }
        }
    }

    /// 当前目录是否允许修改（压缩/写入/删除）
    var canModify: Bool { !isProtectedPath(fsPath) }

    /// 当前目录为什么不能改
    var lockedReason: String? {
        canModify ? nil : "系统目录受保护，不能写入或压缩"
    }

    // 归档（右栏）
    @Published var archive: URL?
    @Published var entries: [ArchiveEntry] = []
    @Published var currentPath: String = ""
    @Published var selection: Set<UUID> = []
    @Published var status: String = "选择一个归档文件，或拖进来"
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
            status = "无法读取 \(url.lastPathComponent)：\(error.localizedDescription)"
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
        if e.isLink { status = "\(e.name) 是符号链接"; return }

        // 普通文件夹 → 左边导航（这才是「文件资源管理器」）
        // .app / .framework 这类包磁盘上是目录，但语义是「一个整体」，
        // 双击应该在右边展开看内部，而不是钻进去
        if e.isDir && !e.isBundle { loadFS(e.url); return }

        open(e.url)
    }

    func goUp() {
        let p = fsPath.deletingLastPathComponent()
        if p.path != fsPath.path { loadFS(p) }
    }

    // MARK: 归档
    func open(_ url: URL, fallbackToSystem: Bool = false) {
        busy = true; status = "读取中…"; archive = url; entries = []; currentPath = ""
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
                    self.status = "\(list.count) 个条目"
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
                        self.status = "已用系统默认程序打开 \(url.lastPathComponent)"
                    } else {
                        self.archive = nil
                        self.entries = []
                        self.status = "打不开：" + error.localizedDescription
                    }
                }
            }
        }
    }

    func extract(to dir: URL) {
        guard let a = archive else { return }
        var subset = entries.filter { selection.contains($0.id) && !$0.isDirectory }.map { $0.path }
        if subset.isEmpty { subset = [] }
        busy = true; status = "解压中…"
        let sub = subset
        Task.detached(priority: .userInitiated) {
            do {
                try ArchiveBackend.shared.extract(URL(fileURLWithPath: a.path), to: dir, subset: sub)
                await MainActor.run {
                    self.status = "已解压到 \(dir.lastPathComponent)"
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
        busy = true; status = "检查中…"
        Task.detached(priority: .userInitiated) {
            do {
                let r = try ArchiveBackend.shared.testDetailed(URL(fileURLWithPath: a.path))
                await MainActor.run {
                    self.status = r.summary
                    self.infoText = r.detail
                    self.busy = false
                }
            } catch {
                await MainActor.run { self.status = "检查失败：\(error.localizedDescription)"; self.busy = false }
            }
        }
    }

    /// 归档内复制 / 移动
    func moveOrCopy(from: String, to: String, copy: Bool) {
        guard let a = archive else { return }
        busy = true
        status = copy ? "复制中…" : "移动中…"
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
                    self.status = (copy ? "已复制到 " : "已移动到 ") + to
                    self.busy = false
                }
            } catch {
                await MainActor.run {
                    self.status = "失败：" + error.localizedDescription
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
                    self.status = "删除失败：" + error.localizedDescription
                } else {
                    self.status = "已移到废纸篓（\(urls.count) 项）"
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
            InfoRow(label: "文件", value: a.lastPathComponent),
            InfoRow(label: "归档大小", value: ByteCountFormatter.string(fromByteCount: size, countStyle: .file)),
            InfoRow(label: "条目", value: "\(entries.count) 个（\(dirs) 目录 / \(files) 文件）"),
            InfoRow(label: "原始大小", value: ByteCountFormatter.string(fromByteCount: raw, countStyle: .file)),
            InfoRow(label: "压缩后", value: ByteCountFormatter.string(fromByteCount: packed, countStyle: .file)),
            InfoRow(label: "压缩率", value: String(format: "%.1f%%", ratio))
        ]
        status = "归档信息"
    }

    func removeSelected() {
        guard let a = archive else { return }
        let sub = entries.filter { selection.contains($0.id) }.map { $0.path }
        if sub.isEmpty { status = "先选中要删除的条目"; return }
        busy = true; status = "删除中…"
        Task.detached(priority: .userInitiated) {
            do {
                try ArchiveBackend.shared.remove(URL(fileURLWithPath: a.path), items: sub)
                let list = try ArchiveBackend.shared.list(URL(fileURLWithPath: a.path))
                await MainActor.run {
                    self.entries = list
                    self.selection = []
                    self.status = "已删除 \(sub.count) 项"
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
    @State private var showExtract = false
    @State private var showInfoSheet = false
    @State private var showAbout = false
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
            if CommandLine.arguments.contains("--about") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { showAbout = true }
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
        .fileImporter(isPresented: $showExtract, allowedContentTypes: [.folder], allowsMultipleSelection: false) { r in
            if case .success(let u) = r, let f = u.first { model.extract(to: f) }
        }
        .sheet(isPresented: $showAbout) {
            AboutView()
        }
        .onReceive(AboutBus.shared.$open) { v in
            if v { showAbout = true; AboutBus.shared.open = false }
        }
        .sheet(isPresented: $showInfoSheet) {
            VStack(alignment: .leading, spacing: 16) {
                Text("归档信息").font(.headline)

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
                    Button("关闭") { showInfoSheet = false }
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
            tb("folder", "打开归档") { showOpen = true }
            tb("plus.square",
               model.canModify ? "把选中的文件/文件夹压缩成归档" : "系统目录受保护，不能在此压缩",
               disabled: !model.canModify) { askAndCreateArchive() }
            tb("arrow.down.doc",
               model.canModify ? "解压选中（未选则全部）" : "系统目录受保护，不能解压到此处") { showExtract = true }
                .disabled(model.archive == nil || !model.canModify)
            tb("checkmark.shield", "测试完整性", disabled: model.archive == nil) { model.test() }
            Divider().frame(height: 18)
            tb("doc.on.doc", "复制选中条目到归档内新路径",
               disabled: model.archive == nil) { askMoveCopy(copy: true) }
            tb("arrow.right.doc.on.clipboard", "移动/重命名选中条目",
               disabled: model.archive == nil) { askMoveCopy(copy: false) }
            tb("trash",
               model.canModify ? "删除选中" : "系统目录受保护，不能删除",
               disabled: model.archive == nil || !model.canModify) { model.removeSelected() }
            tb("info.circle", "显示归档信息", disabled: model.archive == nil) {
                model.showInfo(); showInfoSheet = true
            }
            Spacer(minLength: 24)

            // 右侧：常用位置导航
            HStack(spacing: 2) {
                quickPlace("桌面", "desktopcomputer", .desktopDirectory)
                quickPlace("下载", "arrow.down.circle", .downloadsDirectory)
                quickPlace("文稿", "doc.text", .documentDirectory)
                quickPlace("主目录", "house", nil)
                quickPlace("根目录", "externaldrive", nil, forced: "/")
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
                .buttonStyle(.borderless).help("上一级")

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
                TableColumn("名称") { e in
                    HStack(spacing: 6) {
                        Image(nsImage: e.icon)
                            .resizable()
                            .frame(width: 18, height: 18)
                        Text(e.name).lineLimit(1)
                    }
                    // 单击只选中（Table 原生），双击才进目录
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { model.enter(e) }
                    .contextMenu {
                        // 「打开」= 交给系统默认程序（和 Finder 一致）
                        Button("打开") {
                            NSWorkspace.shared.open(e.url)
                        }
                        // 能解析成归档的，额外给一个入口
                        if canTryAsArchive(e.url) {
                            Button("作为归档查看") {
                                model.open(e.url, fallbackToSystem: false)
                            }
                        }
                        if e.isDir {
                            Button("在 SilentZIP 中浏览") { model.loadFS(e.url) }
                        }
                        Divider()
                        Button("压缩为 7z…") { askCreate(items: [e.url], ext: "7z") }
                        Button("压缩为 zip…") { askCreate(items: [e.url], ext: "zip") }
                        Divider()
                        Button("在 Finder 中显示") {
                            NSWorkspace.shared.activateFileViewerSelecting([e.url])
                        }
                        Button("移到废纸篓") { model.trash([e.url]) }
                            .disabled(!model.canModify)
                    }
                    .help(e.url.path)
                }
                TableColumn("类型") { e in
                    Text(e.typeLabel).foregroundStyle(.secondary).font(.caption)
                }.width(90)
                TableColumn("大小") { e in
                    Text(e.sizeText).foregroundStyle(.secondary)
                        .monospacedDigit().font(.caption)
                }.width(75)
                TableColumn("修改") { e in
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
                    }.buttonStyle(.borderless).help("返回上级目录")
                }
                Text(model.archive?.lastPathComponent ?? "未打开归档").font(.caption).bold()
                if !model.currentPath.isEmpty {
                    Text("/" + model.currentPath).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            Divider()
            Table(model.visible, selection: $model.selection) {
                TableColumn("名称") { e in
                    HStack(spacing: 6) {
                        Image(systemName: e.isDirectory ? "folder" : "doc")
                            .foregroundStyle(e.isDirectory ? Color.accentColor : .secondary)
                        Text(e.name)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        if e.isDirectory { model.currentPath = e.path }
                    }
                    .contextMenu {
                        Button("解压选中项") { showExtract = true }
                        Divider()
                        Button("复制到…") { askMoveCopy(copy: true) }
                        Button("移动到…") { askMoveCopy(copy: false) }
                        Divider()
                        Button("测试完整性") { model.test() }
                        Button("显示归档信息") { model.showInfo(); showInfoSheet = true }
                        if let a = model.archive {
                            Button("在 Finder 中显示归档") {
                                NSWorkspace.shared.activateFileViewerSelecting([a])
                            }
                        }
                    }
                }
                TableColumn("大小") { e in
                    Text(e.isDirectory ? "—" : ByteCountFormatter.string(fromByteCount: e.size, countStyle: .file))
                        .foregroundStyle(.secondary).monospacedDigit()
                }.width(90)
                TableColumn("压缩后") { e in
                    Text(e.isDirectory ? "—" : ByteCountFormatter.string(fromByteCount: e.packedSize, countStyle: .file))
                        .foregroundStyle(.secondary).monospacedDigit()
                }.width(90)
                TableColumn("修改时间") { e in
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
            model.status = "先在右边选中一个条目"
            return
        }

        let alert = NSAlert()
        alert.messageText = copy ? "复制到（归档内路径）" : "移动到（归档内路径）"
        alert.informativeText = "例如 dir/newname.txt —— 只改归档内部结构，不动磁盘"
        alert.addButton(withTitle: "确定")
        alert.addButton(withTitle: "取消")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 380, height: 24))
        field.stringValue = first.path
        alert.accessoryView = field

        if alert.runModal() == .alertFirstButtonReturn {
            let newPath = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !newPath.isEmpty, newPath != first.path else { return }
            model.moveOrCopy(from: first.path, to: newPath, copy: copy)
        }
    }

    private func askAndCreateArchive() { askCreate(items: model.fsSelectedItems, ext: "7z") }

    /// 弹保存面板，选格式和位置
    private func askCreate(items: [URL], ext: String) {
        guard !items.isEmpty else {
            model.status = "先选中要压缩的文件或文件夹"
            return
        }

        let panel = NSSavePanel()
        panel.title = "创建归档"
        panel.prompt = "压缩"
        let base = items.first?.deletingPathExtension().lastPathComponent ?? "归档"
        panel.nameFieldStringValue = base + "." + ext
        panel.directoryURL = model.fsPath
        panel.canCreateDirectories = true

        var types: [UTType] = []
        for ext in ["7z", "zip", "tar", "gz", "xz", "bz2"] {
            if let t = UTType(filenameExtension: ext) { types.append(t) }
        }
        panel.allowedContentTypes = types

        panel.begin { resp in
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
            Text("\(model.fsItems.count) 项").font(.caption2).foregroundStyle(.tertiary)
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
                Button("关于 SilentZIP") {
                    AboutBus.shared.open = true
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
        }
    }
}
