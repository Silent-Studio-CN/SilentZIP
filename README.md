# SilentZIP

**中文** · [English](README.en.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Русский](README.ru.md) · [Français](README.fr.md) · [Deutsch](README.de.md)

macOS 原生归档管理器。双栏布局，左栏浏览文件系统，右栏展开压缩包内部。

内置自行编译的 **7-Zip 26.05** 引擎，不依赖用户安装 Homebrew 或任何第三方工具。

---

## 特性

### 浏览

- 左栏：文件系统树，默认落在桌面，顶部有常用位置（桌面 / 下载 / 文稿 / 主目录 / 根目录）
- 右栏：归档内部结构，可逐层钻取
- 路径面包屑，任意一段可点
- 左右分栏可拖动，宽度、窗口位置、最后访问目录都会记住
- 系统真实图标（与 Finder 完全一致）

### 打开

- 双击普通文件夹 → 左栏进入
- 双击压缩包 / .app / .jar / .exe → 右栏展开内部
- 右键「作为归档查看」可强制按归档解析
- 支持拖入文件

### 操作

| 操作 | 说明 |
|---|---|
| 压缩 | 选中文件或文件夹 → 保存面板选格式（7z / zip / tar / gz / xz / bz2） |
| 解压 | 全部或选中项 |
| 测试 | 完整性校验，输出详细报告与退出码 |
| 复制 / 移动 | 归档内条目路径调整 |
| 嵌套浏览 | 归档内双击另一个归档，继续展开一层 |
| 临时打开 | 右键「打开」→ 临时解压后用系统程序打开，退出时自动清理 |

### 防护

系统目录（/System /usr /bin /private 等）只读：压缩、解压、删除按钮自动变灰，
状态栏显示锁标记。

---

## 引擎

| 项目 | 值 |
|---|---|
| 版本 | 7-Zip 26.05 (arm64) |
| 来源 | 官方源码自行编译 |
| 源码包 | https://www.7-zip.org/a/7z2605-src.7z |
| 编译产物 | Contents/Resources/7zz（2.68 MB） |
| 许可 | GNU LGPL + unRAR restriction |

**为什么自己编译**：7-Zip 官方提供的 macOS 二进制停在 23.01（2023-06-20），
而源码已更新到 26.05（2026-10-21）。自行编译以消除这个版本差。

**编译方式**（仅用 Apple 自带 clang）：

    cd CPP/7zip/Bundles/Alone2
    make -j8 -f makefile.gcc
    # 产物：CPP/7zip/Bundles/Alone2/_o/7zz

未对 7-Zip 源码作任何改动。

**支持格式**：94 种，含 7z / zip / rar / tar / gz / bz2 / xz / lzma / zst / iso /
cab / dmg / msi / wim / chm / vmdk / hfs / apfs / 旧版 Office（Compound）等。

---

## 系统集成

安装后首次启动自动完成：

- 10 种压缩格式的默认打开方式指向 SilentZIP
- Finder 右键服务注册（用 SilentZIP 打开 / 解压到此处）

不需要管理员权限。被其它软件抢走默认后，
可从菜单栏 **SilentZIP → 设为默认压缩工具** 抢回。

---

## 构建

    ./build.sh

产物：SilentZIP.app

依赖：Xcode Command Line Tools（swiftc 6.x）、macOS 13+

---

## 许可

SilentZIP 自身采用私有许可协议，见 [LICENSE.md](Resources/LICENSE.md)。

第三方组件许可原文随包分发：

- [THIRD-PARTY-7zip.txt](Resources/THIRD-PARTY-7zip.txt) —— 7-Zip 原始许可，未作修改
- [COPYING.LGPL-2.1.txt](Resources/COPYING.LGPL-2.1.txt) —— GNU LGPL 2.1 全文

---

## 项目结构

    SilentZIP/
    ├── Sources/              Swift 源码
    │   ├── App.swift           界面、模型、文件系统浏览
    │   └── ArchiveBackend.swift  引擎调用与输出解析
    ├── FinderExt/
    │   └── FinderSync.swift   Finder 扩展（需 Developer ID 签名才能启用）
    ├── Resources/
    │   ├── 7zz                  7-Zip 引擎二进制（自编译）
    │   ├── SilentZIP.icns       程序图标
    │   ├── LICENSE.md           项目许可协议
    │   ├── THIRD-PARTY-7zip.txt 7-Zip 原始许可（未修改）
    │   └── COPYING.LGPL-2.1.txt LGPL 2.1 全文
    ├── 7z-build/               引擎构建（给其他开发者）
    │   ├── build-7zip.sh        一条命令重新编译
    │   ├── README.md            编译说明与版本策略
    │   └── VERSION              当前引擎版本
    ├── docs/
    │   └── 安装包需求.md        分发方案与注册机制
    └── build.sh              一键构建

---

## 引擎版本策略

跟进 7-Zip 的每个新版本。

7-Zip 发布新源码后，升级：

    ./7z-build/build-7zip.sh

脚本会自动探测官方最新的源码版本、下载、编译、替换 Resources/7zz。

**判断依据是官方源码包的日期，不是 Windows 二进制版本号**，两者经常不同步。
例如 26.05 只有 Windows 版，源码最新仍是 26.05。

详细说明见 [7z-build/README.md](7z-build/README.md)。

---

## 已知限制

| 项目 | 状态 |
|---|---|
| Intel Mac | 当前引擎为 arm64 原生；Intel 机器会回退到系统已装的 7z |
| Finder 扩展 | 需 Developer ID 签名，ad-hoc 签名会被系统拒绝 |
| 右键菜单一级显示 | macOS 13+ 的 NSServices 可能归入「服务 ▸」子菜单 |
| 代码签名 | 目前 ad-hoc，首次打开会有「无法验证开发者」提示 |

---

## 相关文档

- [安装包需求](docs/安装包需求.md) —— DMG 方案、自动注册机制、验证清单
- [引擎说明](7z-build/README.md) —— 7-Zip 编译方法与版本策略
- [许可协议](Resources/LICENSE.md) —— 中英双语完整条款

---

## 声明

SilentZIP 是独立产品，与 7-Zip 官方无隶属关系，不使用其名称或商标进行宣传。

Copyright (C) SilentStudio / SilentCodeTeams™