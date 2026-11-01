#!/bin/bash
set -e
cd "$(dirname "$0")"

APP="SilentZIP.app"
BIN="$APP/Contents/MacOS/SilentZIP"
APPEX="$APP/Contents/PlugIns/SilentZIPFinder.appex"
APPEX_BIN="$APPEX/Contents/MacOS/SilentZIPFinder"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
mkdir -p "$APPEX/Contents/MacOS"

echo "编译主程序…"
swiftc -swift-version 5 -O Sources/*.swift -o "$BIN" \
    -framework SwiftUI -framework AppKit -framework UniformTypeIdentifiers

if [ -f Resources/SilentZIP.icns ]; then
  cp Resources/SilentZIP.icns "$APP/Contents/Resources/SilentZIP.icns"
fi
for f in LICENSE.md THIRD-PARTY-7zip.txt COPYING.LGPL-2.1.txt; do
  [ -f "Resources/$f" ] && cp "Resources/$f" "$APP/Contents/Resources/$f"
done

# 内置 7-Zip 引擎（自行编译，LGPL）
if [ -f Resources/7zz ]; then
  cp Resources/7zz "$APP/Contents/Resources/7zz"
  chmod +x "$APP/Contents/Resources/7zz"
  codesign --force --sign - "$APP/Contents/Resources/7zz" 2>/dev/null || true
fi

echo "编译 Finder 扩展…"
swiftc -swift-version 5 -O FinderExt/FinderSync.swift -o "$APPEX_BIN" \
    -framework Cocoa -framework FinderSync

cat > "$APPEX/Contents/Info.plist" <<'AEXPLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>SilentZIPFinder</string>
  <key>CFBundleDisplayName</key><string>SilentZIP</string>
  <key>CFBundleIdentifier</key><string>cn.silentstudio.silentzip.finder</string>
  <key>CFBundleVersion</key><string>0.3.0</string>
  <key>CFBundleShortVersionString</key><string>0.3.0</string>
  <key>CFBundleExecutable</key><string>SilentZIPFinder</string>
  <key>CFBundlePackageType</key><string>XPC!</string>
  <key>NSExtension</key>
  <dict>
    <key>NSExtensionPointIdentifier</key><string>com.apple.FinderSync</string>
    <key>NSExtensionPrincipalClass</key><string>FinderSync</string>
  </dict>
</dict>
</plist>
AEXPLIST

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>SilentZIP</string>
  <key>CFBundleDisplayName</key><string>SilentZIP</string>
  <key>CFBundleIdentifier</key><string>cn.silentstudio.silentzip</string>
  <key>CFBundleVersion</key><string>0.3.0</string>
  <key>CFBundleShortVersionString</key><string>0.3.0</string>
  <key>CFBundleExecutable</key><string>SilentZIP</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleIconFile</key><string>SilentZIP</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>(C) SilentStudio / SilentCodeTeams</string>

  <key>UTExportedTypeDeclarations</key>
  <array>
    <dict>
      <key>UTTypeIdentifier</key><string>cn.silentstudio.archive.zst</string>
      <key>UTTypeDescription</key><string>Zstandard Archive</string>
      <key>UTTypeConformsTo</key><array><string>public.data</string><string>public.archive</string></array>
      <key>UTTypeTagSpecification</key>
      <dict><key>public.filename-extension</key><array><string>zst</string><string>tzst</string></array></dict>
    </dict>
    <dict>
      <key>UTTypeIdentifier</key><string>cn.silentstudio.archive.lzh</string>
      <key>UTTypeDescription</key><string>LHA Archive</string>
      <key>UTTypeConformsTo</key><array><string>public.data</string><string>public.archive</string></array>
      <key>UTTypeTagSpecification</key>
      <dict><key>public.filename-extension</key><array><string>lzh</string><string>lha</string></array></dict>
    </dict>
  </array>

  <key>CFBundleDocumentTypes</key>
  <array>
    <dict>
      <key>CFBundleTypeName</key><string>Archive</string>
      <key>CFBundleTypeRole</key><string>Viewer</string>
      <key>LSHandlerRank</key><string>Alternate</string>
      <key>LSItemContentTypes</key>
      <array>
        <string>org.7-zip.7-zip-archive</string>
        <string>public.zip-archive</string>
        <string>com.rarlab.rar-archive</string>
        <string>public.tar-archive</string>
        <string>org.gnu.gnu-zip-archive</string>
        <string>org.gnu.gnu-zip-tar-archive</string>
        <string>public.bzip2-archive</string>
        <string>org.tukaani.xz-archive</string>
        <string>public.iso-image</string>
        <string>com.microsoft.cab</string>
        <string>cn.silentstudio.archive.zst</string>
        <string>cn.silentstudio.archive.lzh</string>
      </array>
    </dict>
  </array>

  <key>NSServices</key>
  <array>
    <dict>
      <key>NSMenuItem</key>
      <dict><key>default</key><string>用 SilentZIP 打开</string></dict>
      <key>NSMessage</key><string>openArchive</string>
      <key>NSPortName</key><string>SilentZIP</string>
      <key>NSRequiredContext</key>
      <dict>
        <key>NSApplicationIdentifier</key><string>com.apple.finder</string>
      </dict>
      <key>NSSendFileTypes</key>
      <array>
        <string>public.data</string>
        <string>public.folder</string>
        <string>org.7-zip.7-zip-archive</string>
        <string>public.zip-archive</string>
        <string>com.rarlab.rar-archive</string>
        <string>public.tar-archive</string>
        <string>org.gnu.gnu-zip-archive</string>
        <string>org.tukaani.xz-archive</string>
        <string>public.bzip2-archive</string>
      </array>
    </dict>
    <dict>
      <key>NSMenuItem</key>
      <dict><key>default</key><string>解压到此处（SilentZIP）</string></dict>
      <key>NSMessage</key><string>extractHere</string>
      <key>NSPortName</key><string>SilentZIP</string>
      <key>NSRequiredContext</key>
      <dict>
        <key>NSApplicationIdentifier</key><string>com.apple.finder</string>
      </dict>
      <key>NSSendFileTypes</key>
      <array>
        <string>public.data</string>
        <string>public.folder</string>
        <string>org.7-zip.7-zip-archive</string>
        <string>public.zip-archive</string>
        <string>com.rarlab.rar-archive</string>
        <string>public.tar-archive</string>
        <string>org.gnu.gnu-zip-archive</string>
        <string>org.tukaani.xz-archive</string>
        <string>public.bzip2-archive</string>
      </array>
    </dict>
  </array>
</dict>
</plist>
PLIST

# 先签扩展，再签整个 app（顺序不能反）
codesign --force --sign - --timestamp=none "$APPEX" 2>/dev/null || true
codesign --force --deep --sign - "$APP" 2>/dev/null || true

LSREG=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
"$LSREG" -f "$APP" 2>/dev/null || true

echo "完成：$(pwd)/$APP"
