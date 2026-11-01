import Foundation

/// 一套压缩参数。用户可以存几套常用的，压缩时直接选。
struct CompressPreset: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var format: String = "7z"
    var level: Int = 5          // 0 = 仅存储，9 = 极限压缩
    var password: String = ""
    var solid: Bool = true      // 7z 的固实压缩，压缩率高但随机访问慢

    /// 传给 7z 的参数
    var arguments: [String] {
        var a: [String] = []
        a.append("-mx=" + String(level))
        if !solid && format == "7z" { a.append("-ms=off") }
        if !password.isEmpty {
            a.append("-p" + password)
            a.append("-mhe=on")     // 加密文件名
        }
        return a
    }

    var summary: String {
        var s = format.uppercased() + " · 压缩级别 " + String(level)
        if !solid && format == "7z" { s += " · 非固实" }
        if !password.isEmpty { s += " · 加密" }
        return s
    }
}

/// 预设的存取。
enum PresetStore {
    private static let key = "compressPresets"

    /// 内置的几套，用户没自定义过时用这些
    static let builtins: [CompressPreset] = [
        CompressPreset(name: "标准 7z", format: "7z", level: 5),
        CompressPreset(name: "极限压缩", format: "7z", level: 9),
        CompressPreset(name: "快速打包", format: "7z", level: 0, solid: false),
        CompressPreset(name: "通用 zip", format: "zip", level: 5),
        CompressPreset(name: "tar 归档", format: "tar", level: 0),
    ]

    static var all: [CompressPreset] {
        get {
            guard let data = UserDefaults.standard.data(forKey: key),
                  let list = try? JSONDecoder().decode([CompressPreset].self, from: data),
                  !list.isEmpty else {
                return builtins
            }
            return list
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: key)
            }
        }
    }

    static var isCustomized: Bool {
        UserDefaults.standard.data(forKey: key) != nil
    }

    static func reset() {
        UserDefaults.standard.removeObject(forKey: key)
    }

    /// 按名字找
    static func find(_ name: String) -> CompressPreset? {
        all.first { $0.name == name }
    }
}
