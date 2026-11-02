#!/bin/bash
# 通用二进制构建：arm64 + x86_64 合成一个 app
set -e
cd "$(dirname "$0")"

echo "① 编译 arm64"
ARCH=arm64 ./build.sh > /dev/null

echo "② 编译 x86_64"
ARCH=x86_64 ./build.sh > /dev/null

ARM="SilentZIP.app"
X64="SilentZIP-x64.app"
BIN_ARM="$ARM/Contents/MacOS/SilentZIP"
BIN_X64="$X64/Contents/MacOS/SilentZIP"
APPEX_ARM="$ARM/Contents/PlugIns/SilentZIPFinder.appex/Contents/MacOS/SilentZIPFinder"
APPEX_X64="$X64/Contents/PlugIns/SilentZIPFinder.appex/Contents/MacOS/SilentZIPFinder"

echo "③ 合成通用主程序"
lipo -create "$BIN_ARM" "$BIN_X64" -output "$BIN_ARM"

echo "④ 合成通用 Finder 扩展"
if [ -f "$APPEX_ARM" ] && [ -f "$APPEX_X64" ]; then
    lipo -create "$APPEX_ARM" "$APPEX_X64" -output "$APPEX_ARM"
fi

echo "⑤ 合成通用命令行工具 sz（如果有）"
SZ_ARM="$ARM/Contents/MacOS/sz"
SZ_X64="$X64/Contents/MacOS/sz"
if [ -f "$SZ_ARM" ] && [ -f "$SZ_X64" ]; then
    lipo -create "$SZ_ARM" "$SZ_X64" -output "$SZ_ARM"
fi

echo "⑥ 清理 x64 副本"
rm -rf "$X64"

echo "⑦ 签名"
# 三个坑叠在一起：
#   1. --deep 在 macOS 15+ 只签内层，最外层 Sealed Resources=none，verify 失败
#   2. app 上有 com.apple.FinderInfo 就报 "resource fork ... not allowed"
#   3. app 放在桌面时 Finder 会持续加 xattr，本地清完签名前又回来了
# 所以：整个流程搬到 /tmp 里做，签完再搬回来。
SIGNTMP="/tmp/szsign-$$"
rm -rf "$SIGNTMP"
mkdir -p "$SIGNTMP"
cp -R "$ARM" "$SIGNTMP/"
cd "$SIGNTMP"
xattr -cr "$ARM"

for comp in \
    "Contents/Resources/7zz" \
    "Contents/MacOS/sz" \
    "Contents/PlugIns/SilentZIPFinder.appex" \
    "Contents/MacOS/SilentZIP" ; do
    [ -e "$ARM/$comp" ] && codesign --force --sign - "$ARM/$comp" > /dev/null 2>&1
done
# 最后签整个 bundle（不带 --deep），这一步写下资源封印
codesign --force --sign - "$ARM" > /dev/null 2>&1

echo
echo "签名校验："
if codesign --verify --deep --strict "$ARM" 2>/dev/null; then
    echo "  ✓ valid on disk"
    SIGN_OK=1
else
    echo "  ✗ 签名无效"
    SIGN_OK=0
fi

# 直接打 DMG —— 不把裸 app 放回桌面，
# 否则 Finder 会立刻给 appex 加回 xattr，签名又白做。
cd - > /dev/null
VER=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString"       "$SIGNTMP/$ARM/Contents/Info.plist" 2>/dev/null || echo 0.0.0)

echo
echo "⑧ 打 DMG"
mkdir -p build
if [ "$SIGN_OK" = "1" ]; then
    ./packaging/make-dmg.sh "$SIGNTMP/$ARM" "-universal" > /tmp/dmg.log 2>&1 || {
        echo "  DMG 失败，看 /tmp/dmg.log"; tail -5 /tmp/dmg.log; }
    if ls packaging/SilentZIP-*universal*.dmg > /dev/null 2>&1; then
        mv packaging/SilentZIP-*universal*.dmg build/ 2>/dev/null
        echo "  ✓ build/$(ls build/ | grep universal | tail -1)"
    fi
else
    echo "  签名没过，跳过打包"
fi

rm -rf "$SIGNTMP"
[ "$SIGN_OK" = "1" ] || exit 1

echo
echo "完成。安装包在 build/：
$(ls -lh build/ 2>/dev/null | grep dmg | awk '{print "  " $9 "  " $5}')"
