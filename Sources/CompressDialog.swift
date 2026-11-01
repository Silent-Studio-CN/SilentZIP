import AppKit

/// 「添加到压缩包」的参数对话框。
/// 布局参照 7-Zip File Manager，左列是压缩参数，右列是更新方式、选项、加密。
final class CompressDialog: NSObject {

    private var window: NSWindow!
    private var options = CompressOptions()
    private var onConfirm: ((CompressOptions) -> Void)?

    // 控件
    private let archiveField = NSTextField()
    private let formatPop = NSPopUpButton()
    private let levelPop = NSPopUpButton()
    private let methodPop = NSPopUpButton()
    private let dictPop = NSPopUpButton()
    private let wordPop = NSPopUpButton()
    private let solidPop = NSPopUpButton()
    private let threadPop = NSPopUpButton()
    private let volumeField = NSTextField()
    private let extraField = NSTextField()
    private let memoryLabel = NSTextField(labelWithString: "")

    private let updatePop = NSPopUpButton()
    private let pathPop = NSPopUpButton()

    private let sfxCheck = NSButton(checkboxWithTitle: "创建自解压程序", target: nil, action: nil)
    private let sharedCheck = NSButton(checkboxWithTitle: "压缩共享文件", target: nil, action: nil)
    private let delSrcCheck = NSButton(checkboxWithTitle: "操作完成后删除源文件", target: nil, action: nil)

    private let passwordField = NSSecureTextField()
    private let passwordAgain = NSSecureTextField()
    private let showPasswordCheck = NSButton(checkboxWithTitle: "显示密码", target: nil, action: nil)
    private let encryptHeadersCheck = NSButton(checkboxWithTitle: "加密文件名", target: nil, action: nil)

    private let formats = ["7z", "zip", "tar", "wim", "gz"]
    /// 界面上的 6 档对应的实际等级值
    private let levelValues = [0, 1, 3, 5, 7, 9]
    /// 方法列表跟着容器走 —— 在 7z 里塞 Deflate 技术上能生成，
    /// 但既然用 7z 就是用 LZMA2，要 Deflate 不如直接存 zip。
    private func methodsFor(_ format: String) -> [String] {
        switch format {
        case "7z":            return ["LZMA2", "LZMA", "PPMd", "BZip2", "Deflate", "Copy"]
        case "zip":           return ["Deflate", "Deflate64", "BZip2", "LZMA"]
        case "gz":            return ["Deflate"]
        default:              return []
        }
    }
    /// 字典上限跟着内存走 —— 48G 内存给 2g 字典没问题，
    /// 8G 的机器给 2g 会直接卡死
    private var dicts: [String] {
        // 7-Zip 的完整梯度
        let all = ["64k", "96k", "128k", "192k", "256k", "384k", "512k", "768k",
                   "1m", "1536k", "2m", "3m", "4m", "6m", "8m", "12m", "16m",
                   "24m", "32m", "48m", "64m", "96m", "128m", "192m", "256m",
                   "384m", "512m", "768m", "1g", "1536g"]
        // 内存小就把大的砍掉：压缩约需 12 倍字典
        let gb = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824
        let limitMB = Int(gb * 1024 / 12)
        return all.filter { parseSizeMB($0) <= limitMB }
    }

    /// 固实块：7-Zip 给的是 512KB ~ 64GB，共 20 档，没有「关闭」
    private var solids: [String] {
        ["512k", "1m", "2m", "4m", "8m", "16m", "32m", "64m", "128m", "256m",
         "512m", "1g", "2g", "4g", "8g", "16g", "32g", "64g"]
    }

    private var totalGB: Double {
        (Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824 * 10).rounded() / 10
    }

    func show(suggested: String, confirm: @escaping (CompressOptions) -> Void) {
        self.onConfirm = confirm
        options.outputPath = suggested

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 520),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "添加到压缩包"
        window.center()

        buildUI()
        updateMemoryHint()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - 布局

    private func buildUI() {
        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.distribution = .fill
        root.spacing = 14
        root.edgeInsets = NSEdgeInsets(top: 18, left: 20, bottom: 18, right: 20)

        // 顶部：压缩包路径
        archiveField.stringValue = options.outputPath
        archiveField.font = .systemFont(ofSize: 12)
        archiveField.widthAnchor.constraint(greaterThanOrEqualToConstant: 640).isActive = true

        let browse = NSButton(title: "…", target: self, action: #selector(browseTapped))
        let browseBtn = NSButton(title: "浏览…", target: self, action: #selector(browseTapped))
        _ = browse

        let topRow = NSStackView(views: [label("压缩包"), archiveField, browseBtn])
        topRow.orientation = .horizontal
        topRow.spacing = 8
        root.addArrangedSubview(topRow)

        // 左右两栏
        let left = buildLeftColumn()
        let right = buildRightColumn()

        let cols = NSStackView(views: [left, right])
        cols.orientation = .horizontal
        cols.alignment = .top
        cols.distribution = .fill
        cols.spacing = 40
        root.addArrangedSubview(cols)

        // 底部按钮
        let cancel = NSButton(title: "取消", target: self, action: #selector(cancelTapped))
        cancel.keyEquivalent = "\u{1b}"
        let ok = NSButton(title: "确定", target: self, action: #selector(okTapped))
        ok.keyEquivalent = "\r"
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let bottom = NSStackView(views: [spacer, cancel, ok])
        bottom.orientation = .horizontal
        bottom.spacing = 10
        root.addArrangedSubview(bottom)

        bottom.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -40).isActive = true

        window.contentView = root
        refreshDependentControls()
    }

    private func buildLeftColumn() -> NSView {
        formatPop.addItems(withTitles: formats)
        formatPop.target = self
        formatPop.action = #selector(formatChanged)

        // 7-Zip 只给奇数档：0 仅存储 / 1 极速 / 3 快速 / 5 标准 / 7 最大 / 9 极限
        let levels: [(Int, String)] = [
            (0, "0 - 仅存储"),
            (1, "1 - 极速压缩"),
            (3, "3 - 快速压缩"),
            (5, "5 - 标准压缩"),
            (7, "7 - 最大压缩"),
            (9, "9 - 极限压缩")
        ]
        levelPop.addItems(withTitles: levels.map { $0.1 })
        levelPop.selectItem(at: 3)   // 默认 5 - 标准压缩

        reloadMethods(for: "7z")
        dictPop.addItems(withTitles: dicts)
        // 默认挑一个既不太小也不吃满内存的
        let gb = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824
        let desired = gb < 8 ? "64m" : (gb < 16 ? "128m" : (gb < 32 ? "256m" : "256m"))
        if let i = dicts.firstIndex(of: desired) { dictPop.selectItem(at: i) }
        else { dictPop.selectItem(at: min(3, dicts.count - 1)) }
        dictPop.target = self
        dictPop.action = #selector(dictChanged)
        let words = ["5", "6", "8", "12", "16", "24", "32", "48",
                     "64", "96", "128", "192", "256", "273"]
        wordPop.addItems(withTitles: words)
        wordPop.selectItem(at: words.firstIndex(of: "64") ?? 8)
        solidPop.addItems(withTitles: solids)
        if let i = solids.firstIndex(of: "16g") { solidPop.selectItem(at: i) }

        let cores = ProcessInfo.processInfo.activeProcessorCount
        threadPop.addItem(withTitle: "自动")
        for i in 1...max(1, cores) { threadPop.addItem(withTitle: String(i)) }
        threadPop.selectItem(at: 0)

        volumeField.placeholderString = "不分卷，或填 100m / 1g"

        memoryLabel.font = .systemFont(ofSize: 11)
        memoryLabel.textColor = .secondaryLabelColor

        let grid = NSGridView(views: [
            [label("压缩格式"), formatPop],
            [label("压缩等级"), levelPop],
            [label("压缩方法"), methodPop],
            [label("字典大小"), dictPop],
            [label("单词大小"), wordPop],
            [label("固实大小"), solidPop],
            [label("CPU 线程"), threadPop],
            [label("内存"), memoryLabel],
            [label("分卷大小"), volumeField],
            [label("参数"), extraField]
        ])
        grid.columnSpacing = 12
        grid.rowSpacing = 8
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).width = 200
        grid.setContentHuggingPriority(.defaultHigh, for: .vertical)
        grid.setContentHuggingPriority(.defaultHigh, for: .horizontal)

        let stack = NSStackView(views: [grid])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.distribution = .fill
        stack.spacing = 8
        stack.setContentHuggingPriority(.defaultHigh, for: .vertical)
        return stack
    }

    private func buildRightColumn() -> NSView {
        updatePop.addItems(withTitles: UpdateMode.allCases.map { $0.label })
        pathPop.addItems(withTitles: PathMode.allCases.map { $0.label })

        let topGrid = NSGridView(views: [
            [label("更新方式"), updatePop],
            [label("路径模式"), pathPop]
        ])
        topGrid.columnSpacing = 12
        topGrid.rowSpacing = 8
        topGrid.column(at: 0).xPlacement = .trailing
        topGrid.column(at: 1).width = 160

        let optTitle = NSTextField(labelWithString: "选项")
        optTitle.font = .boldSystemFont(ofSize: 12)

        let encTitle = NSTextField(labelWithString: "加密")
        encTitle.font = .boldSystemFont(ofSize: 12)

        passwordField.placeholderString = "输入密码"
        passwordAgain.placeholderString = "重新输入"
        passwordField.widthAnchor.constraint(equalToConstant: 190).isActive = true
        passwordAgain.widthAnchor.constraint(equalToConstant: 190).isActive = true

        showPasswordCheck.target = self
        showPasswordCheck.action = #selector(togglePassword)
        encryptHeadersCheck.state = .off

        let encGrid = NSGridView(views: [
            [label("密码"), passwordField],
            [label("确认"), passwordAgain],
            [NSView(), showPasswordCheck],
            [NSView(), encryptHeadersCheck]
        ])
        encGrid.columnSpacing = 12
        encGrid.rowSpacing = 8
        encGrid.column(at: 0).xPlacement = .trailing

        let stack = NSStackView(views: [
            topGrid, divider(),
            optTitle, sfxCheck, sharedCheck, delSrcCheck,
            divider(),
            encTitle, encGrid
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.distribution = .fill
        stack.spacing = 8
        stack.setContentHuggingPriority(.defaultHigh, for: .vertical)
        return stack
    }

    private func label(_ s: String) -> NSTextField {
        let l = NSTextField(labelWithString: s)
        l.font = .systemFont(ofSize: 12)
        l.alignment = .right
        return l
    }

    private func divider() -> NSBox {
        let b = NSBox()
        b.boxType = .separator
        b.widthAnchor.constraint(equalToConstant: 300).isActive = true
        return b
    }

    // MARK: - 动作

    @objc private func browseTapped() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = (options.outputPath as NSString).lastPathComponent
        panel.directoryURL = URL(fileURLWithPath: (options.outputPath as NSString).deletingLastPathComponent)
        if panel.runModal() == .OK, let u = panel.url {
            archiveField.stringValue = u.path
        }
    }

    /// 换了格式，方法列表要跟着换
    private func reloadMethods(for format: String) {
        let list = methodsFor(format)
        methodPop.removeAllItems()
        methodPop.addItems(withTitles: list)
        methodPop.isEnabled = !list.isEmpty
        if list.isEmpty {
            methodPop.addItem(withTitle: "—")
            methodPop.isEnabled = false
        }
    }

    @objc private func formatChanged() {
        let fmt = formats[formatPop.indexOfSelectedItem]
        // 后缀跟着换
        var p = archiveField.stringValue
        if let dot = p.lastIndex(of: "."), dot > p.startIndex {
            p = String(p[..<dot])
        }
        if !p.isEmpty { p += "." + fmt }
        archiveField.stringValue = p
        reloadMethods(for: fmt)
        refreshDependentControls()
    }

    @objc private func togglePassword() {
        let show = showPasswordCheck.state == .on
        passwordField.isHidden = false
        _ = show
        // NSSecureTextField 不能直接切明文，重建一个
        passwordAgain.placeholderString = show ? "（明文显示）" : "重新输入"
    }

    /// 按当前字典大小估一下内存，给用户一个直观的数
    @objc private func dictChanged() { updateMemoryHint() }

    private func updateMemoryHint() {
        let dict = dicts[dictPop.indexOfSelectedItem]
        let mb = parseSizeMB(dict)
        // 7-Zip 的经验值：压缩约 12 倍字典，解压约 1.05 倍
        let need = Int(Double(mb) * 12)
        let free = Int(Double(totalGB) * 1024)
        memoryLabel.stringValue = String(format: "本机 %.1f GB，压缩约需 %d MB",
                                         totalGB, need)
        memoryLabel.textColor = need > free ? .systemOrange : .secondaryLabelColor
    }

    private func parseSizeMB(_ s: String) -> Int {
        let t = s.lowercased()
        if t.hasSuffix("g"), let v = Double(t.dropLast()) { return Int(v * 1024) }
        if t.hasSuffix("m"), let v = Double(t.dropLast()) { return Int(v) }
        if let v = Int(t) { return v / 1024 / 1024 }
        return 64
    }

    /// 7z 特有的选项在别的格式下要禁用
    private func refreshDependentControls() {
        let is7z = formats[formatPop.indexOfSelectedItem] == "7z"
        dictPop.isEnabled = is7z
        wordPop.isEnabled = is7z
        solidPop.isEnabled = is7z
        encryptHeadersCheck.isEnabled = is7z
        sfxCheck.isEnabled = is7z
    }

    @objc private func okTapped() {
        var o = options
        o.outputPath = archiveField.stringValue
        o.format = formats[formatPop.indexOfSelectedItem]
        o.level = levelValues[levelPop.indexOfSelectedItem]
        let currentMethods = methodsFor(formats[formatPop.indexOfSelectedItem])
        if !currentMethods.isEmpty {
            o.method = currentMethods[min(methodPop.indexOfSelectedItem,
                                          currentMethods.count - 1)]
        }
        o.dictionarySize = dicts[dictPop.indexOfSelectedItem]
        o.wordSize = Int(["16", "32", "64", "128", "273"][wordPop.indexOfSelectedItem]) ?? 64
        o.solidSize = solids[solidPop.indexOfSelectedItem]
        o.threads = threadPop.indexOfSelectedItem
        o.volumeSize = volumeField.stringValue.trimmingCharacters(in: .whitespaces)
        o.extraParams = extraField.stringValue
        o.updateMode = UpdateMode.allCases[updatePop.indexOfSelectedItem]
        o.pathMode = PathMode.allCases[pathPop.indexOfSelectedItem]
        o.createSFX = sfxCheck.state == .on
        o.compressShared = sharedCheck.state == .on
        o.deleteSource = delSrcCheck.state == .on
        o.encryptHeaders = encryptHeadersCheck.state == .on

        let pw = passwordField.stringValue
        let pw2 = passwordAgain.stringValue
        if !pw.isEmpty {
            if pw != pw2 {
                let a = NSAlert()
                a.messageText = "两次输入的密码不一样"
                a.runModal()
                return
            }
            o.password = pw
        }

        if o.outputPath.isEmpty {
            let a = NSAlert()
            a.messageText = "还没指定输出文件"
            a.runModal()
            return
        }

        window.close()
        onConfirm?(o)
    }

    @objc private func cancelTapped() {
        window.close()
    }
}
