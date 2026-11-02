#!/bin/bash
# SilentZIP DMG 打包 —— Silent 风格
set -euo pipefail
TAG="${2:-}"
VER=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "${1:-SilentZIP.app}/Contents/Info.plist" 2>/dev/null || echo 0.0.0)
cd "$(dirname "$0")/.."

APP="${1:-SilentZIP.app}"
VOL="SilentZIP"
STAGE="packaging/.stage$TAG"
RW="packaging/.rw$TAG.dmg"
OUT="packaging/SilentZIP-${VER}${TAG}.dmg"

echo "① 准备背景图"
if [ ! -f packaging/background.tiff ]; then
    SCALE=1 python3 packaging/gen-background.py packaging/bg.png
    SCALE=2 python3 packaging/gen-background.py packaging/bg@2x.png
    tiffutil -cathidpicheck packaging/bg.png packaging/bg@2x.png -out packaging/background.tiff
fi

echo "② 组装暂存目录"
rm -rf "$STAGE" "$RW"
mkdir -p "$STAGE/.background"
# 用 ditto 而不是 cp -R —— cp 会把 com.apple.FinderInfo 一起带进去，
# 那个属性会让 codesign --verify 报 "resource fork ... not allowed"
ditto --norsrc --noextattr "$APP" "$STAGE/$(basename "$APP")"
cp packaging/background.tiff "$STAGE/.background/background.tiff"
ln -s /Applications "$STAGE/Applications"

cat > "$STAGE/README.txt" <<'TXT'
SilentZIP
=========

安装
    把 SilentZIP 拖到左边的「应用程序」文件夹。

首次打开
    会自动接管 7z / zip / rar / tar / gz / tgz / bz2 / xz / zst / lzh，
    并注册 Finder 右键菜单。不需要任何手动配置。

    如果首次打开时提示「无法验证开发者」，右键点 app → 打开 → 再点「打开」。
    之后再打开就不会提示了。

被别的软件抢走默认打开方式
    SilentZIP 菜单栏 → 设为默认压缩工具。

卸载
    把 app 拖进废纸篓即可。系统里只留两处无害的偏好记录。

压缩引擎基于 7-Zip（LGPL）。SilentZIP 与 7-Zip 无隶属关系。
TXT

echo "③ 建立可读写 DMG"
hdiutil create -srcfolder "$STAGE" -volname "$VOL" -fs HFS+ \
    -fsargs "-c c=64,a=16,e=16" -format UDRW -size 40m "$RW" >/dev/null

echo "④ 挂载并排版"
MNT=$(hdiutil attach -readwrite -noverify -noautoopen "$RW" | grep -E '^\s*/dev/' | tail -1 | awk '{print $NF}')
sleep 2

osascript <<APPLESCRIPT >/dev/null 2>&1 || echo "   （Finder 排版跳过 —— 未获自动化权限）"
tell application "Finder"
    tell disk "$VOL"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 140, 820, 540}
        set vo to the icon view options of container window
        set arrangement of vo to not arranged
        set icon size of vo to 104
        set background picture of vo to file ".background:background.tiff"
        set position of item "$APP" of container window to {155, 200}
        set position of item "Applications" of container window to {465, 200}
        set position of item "README.txt" of container window to {310, 330}
        close
        open
        update without registering applications
        delay 1
    end tell
end tell
APPLESCRIPT

sync
hdiutil detach "$MNT" >/dev/null 2>&1 || hdiutil detach "$MNT" -force >/dev/null 2>&1

echo "⑤ 压缩"
rm -f "$OUT"
hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -o "$OUT" >/dev/null
rm -rf "$STAGE" "$RW"

echo
echo "完成：$OUT"
ls -lh "$OUT" | awk '{print "  体积 "$5}'
shasum -a 256 "$OUT" | awk '{print "  SHA-256 "$1}'
