import Foundation

/// 菜单项要调用界面里的动作，但 SwiftUI 的 Commands 和 ContentView 之间没有直接引用，
/// 用这个单例当桥。ContentView 出现时把自己的方法挂上来。
@MainActor
final class AppActions: ObservableObject {
    static let shared = AppActions()

    var openArchive: (() -> Void)?
    var extractAll: (() -> Void)?
    var compressSelected: (() -> Void)?
    var refresh: (() -> Void)?
    var goUp: (() -> Void)?
    var goHome: (() -> Void)?
    var goDesktop: (() -> Void)?
    var testArchive: (() -> Void)?
    var showInfo: (() -> Void)?
    var languageChanged: (() -> Void)?
    var runBenchmark: (() -> Void)?
    var relaunch: (() -> Void)?
    var openHelp: (() -> Void)?
}
