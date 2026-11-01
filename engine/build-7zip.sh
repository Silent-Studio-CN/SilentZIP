#!/bin/bash
# 编译 7-Zip 引擎 —— 任何 macOS 开发者都能跑
# 用法： ./engine/build-7zip.sh [版本号]
#        不给版本号则自动探测最新源码版本
set -e
cd "$(dirname "$0")/.."

WORK=$(mktemp -d)
trap "rm -rf $WORK" EXIT

detect_version() {
    curl -sL --max-time 30 https://www.7-zip.org/download.html \
      | grep -oE "a/7z[0-9]+-src\.7z" \
      | sed "s|a/7z||; s|-src\.7z||" \
      | sort -n | tail -1
}

VER="$1"
if [ -z "$VER" ]; then
    VER=$(detect_version)
fi
if [ -z "$VER" ]; then
    echo "无法探测版本，请手动指定：./engine/build-7zip.sh 2601"
    exit 1
fi

echo "目标版本：7-Zip $VER"

URL="https://www.7-zip.org/a/7z$VER-src.7z"
echo "下载源码：$URL"

cd "$WORK"
curl -sL --max-time 180 -o src.7z "$URL"
SIZE=$(stat -f%z src.7z)
if [ "$SIZE" -lt 100000 ]; then
    echo "下载失败（$SIZE 字节），版本号可能不存在"
    exit 1
fi

echo "解压源码…"
SEVENZ=""
for C in /opt/homebrew/bin/7z /usr/local/bin/7z /opt/homebrew/bin/7zz; do
    [ -x "$C" ] && SEVENZ="$C" && break
done
if [ -z "$SEVENZ" ]; then
    echo "需要 7z 来解压源码包：brew install p7zip"
    exit 1
fi
"$SEVENZ" x src.7z -o. -y >/dev/null

echo "编译（仅用系统 clang）…"
cd CPP/7zip/Bundles/Alone2
make -j"$(sysctl -n hw.ncpu)" -f makefile.gcc

if [ ! -f _o/7zz ]; then
    echo "编译失败，产物不存在"
    exit 1
fi

cd - >/dev/null
cp "$WORK/CPP/7zip/Bundles/Alone2/_o/7zz" Resources/7zz
chmod +x Resources/7zz
echo "$VER" > engine/VERSION

echo
echo "完成：Resources/7zz"
file Resources/7zz | sed "s/^/  /"
Resources/7zz 2>&1 | head -2 | sed "s/^/  /"
echo
echo "版本号已写入 engine/VERSION"
