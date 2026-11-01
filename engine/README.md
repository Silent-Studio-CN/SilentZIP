# 7-Zip 引擎

SilentZIP 的压缩引擎是 7-Zip 的命令行版本（7zz），由官方源码自行编译。

**当前版本**：见 [VERSION](VERSION)

---

## 为什么不用官方 macOS 二进制

7-Zip 官方提供的 macOS 构建停在 **23.01（2023-06-20）**，
而源码已更新到 **26.01（2026-04-27）**。Windows 版更是已到 **26.05**。

macOS 二进制拖了两年多，所以我们自己编译。

---

## 一条命令重新编译

    ./engine/build-7zip.sh

自动完成：探测最新源码版本 → 下载 → 解压 → 用系统 clang 编译 → 写入 Resources/7zz

**指定版本**：

    ./engine/build-7zip.sh 2601

**依赖**：

- Xcode Command Line Tools（clang / make）
- 任意版本的 7z（用于解压源码包；Homebrew 的 p7zip 即可，仅此一次需要）

---

## 手动编译

    # 1. 下载源码
    curl -LO https://www.7-zip.org/a/7z2601-src.7z

    # 2. 解压
    7z x 7z2601-src.7z

    # 3. 编译
    cd CPP/7zip/Bundles/Alone2
    make -j8 -f makefile.gcc

    # 4. 产物
    ls -la _o/7zz

    # 5. 拷贝
    cp _o/7zz ../../../../Resources/7zz

**仅使用 Apple 自带 clang，未修改 7-Zip 源码。**

---

## 源码版本对照

| 7-Zip 版本 | 源码包 | 日期 |
|---|---|---|
| 26.01 | https://www.7-zip.org/a/7z2601-src.7z | 2026-04-27 |
| 23.01 | https://www.7-zip.org/a/7z2301-src.7z | 2023-06-20 |
| 19.00 | https://www.7-zip.org/a/7z1900-src.7z | 2019-02-21 |

官方下载页：https://www.7-zip.org/download.html

---

## 版本更新策略

**我们会持续跟进 7-Zip 的每个新版本。**

流程：

1. 7-Zip 发布新版本 → 官方下载页出现新的 src 包
2. 运行 \`./engine/build-7zip.sh\`（不带参数，自动探测最新）
3. 验证：用样本归档跑一遍 列表 / 压缩 / 解压 / 完整性测试
4. 更新 \`engine/VERSION\`
5. 提交并发布新版本 SilentZIP

**判断依据**：官方源码包日期，不是 Windows 二进制版本号。
两者经常不同步（例如 26.05 只有 Windows 版，源码最新是 26.01）。

---

## 兼容性注意

7-Zip 21.00 之后 \`7z l -slt\` 的输出字段有变化：

    旧版（17.05）  Attributes = D_ 0rwxr-xr-x
    新版（21+）    Folder = +

SilentZIP 的解析器同时兼容两者，见 \`Sources/ArchiveBackend.swift\` 的 parse 方法。

如果升级到更新的版本后列表显示异常，先检查这个字段。

---

## 许可

7-Zip 依 **GNU LGPL** 发布，部分代码附带 **unRAR license restriction**。

- 原始许可文本：[../Resources/THIRD-PARTY-7zip.txt](../Resources/THIRD-PARTY-7zip.txt)
- LGPL 2.1 全文：[../Resources/COPYING.LGPL-2.1.txt](../Resources/COPYING.LGPL-2.1.txt)

**我们没有修改 7-Zip 的代码**，只是执行它自带的 makefile 编译。
因此分发二进制时提供官方源码包即可满足 LGPL 第 6 条。

---

## Intel Mac

当前产物是 **arm64 原生**。

如需 universal binary：

    make clean
    make -j8 -f makefile.gcc CXX="c++ -arch x86_64" CC="cc -arch x86_64"
    cp _o/7zz /tmp/7zz-x86_64

    make clean
    make -j8 -f makefile.gcc
    lipo -create /tmp/7zz-x86_64 _o/7zz -output Resources/7zz
