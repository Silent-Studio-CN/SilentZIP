import AppKit

/// 带命令的弹窗。
///
/// NSAlert 的正文没法选中复制，遇到「请手动执行这条命令」的场景就很别扭。
/// 这里自己搭一个：说明文字 + 等宽可选中命令行 + 复制按钮。
final class CopyableAlert {
    static func show(title: String, message: String, command: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.addButton(withTitle: L10n.t("ui.ok", "好"))
        alert.addButton(withTitle: L10n.t("ui.copyCommand", "复制命令"))

        let msg = NSTextField(wrappingLabelWithString: message)
        msg.font = .systemFont(ofSize: 12)
        msg.textColor = .secondaryLabelColor
        msg.preferredMaxLayoutWidth = 420
        msg.frame = NSRect(x: 0, y: 0, width: 420, height: 48)

        let cmd = NSTextView(frame: NSRect(x: 0, y: 0, width: 420, height: 52))
        cmd.string = command
        cmd.isEditable = false
        cmd.isSelectable = true
        cmd.drawsBackground = true
        cmd.backgroundColor = .textBackgroundColor
        cmd.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        cmd.textContainerInset = NSSize(width: 8, height: 8)
        cmd.isVerticallyResizable = true
        cmd.isHorizontallyResizable = false
        cmd.textContainer?.widthTracksTextView = true

        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 420, height: 56))
        scroll.documentView = cmd
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder

        let stack = NSStackView(views: [msg, scroll])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.frame = NSRect(x: 0, y: 0, width: 420, height: 120)
        alert.accessoryView = stack

        if alert.runModal() == .alertSecondButtonReturn {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(command, forType: .string)
        }
    }
}
