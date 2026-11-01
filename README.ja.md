# SilentZIP

[中文](README.md) · [English](README.en.md) · **日本語** · [한국어](README.ko.md) · [Русский](README.ru.md) · [Français](README.fr.md) · [Deutsch](README.de.md)

> これは簡易版です。詳細は [英語版](README.en.md) または [中国語版](README.md) を参照してください。

macOS 用のアーカイブ管理アプリ。圧縮ファイルをダブルクリックすると中身がそのまま見えます。先に解凍する必要はありません。

左がフォルダ、右がアーカイブの中身。仕切りはドラッグで動かせます。

---

## エンジンについて

圧縮エンジンは 7-Zip。公式の macOS ビルドはソースより遅れているため、自分でビルドしています。

    ./7z-build/build-7zip.sh

GitHub から最新リリースを探し、ソースを落として clang でビルドし、`Resources/7zz` に配置します。

バイナリは universal（arm64 + x86_64）なので Intel Mac でも動きます。

---

## できること

- **閲覧** — ファイルブラウザとアーカイブ内容の 2 ペイン
- **解凍** — 選択したものだけ。未選択なら確認が出ます
- **圧縮** — 7z / zip / tar / gz / xz / bz2
- **検査** — 整合性チェックとレポート
- **追加・削除・移動** — アーカイブ内の編集
- **入れ子** — アーカイブ内のアーカイブをさらに開く
- **ドラッグ書き出し** — Finder へドラッグで取り出し

システムディレクトリ（/System、/usr など）は読み取り専用です。

---

## 初期設定不要

初回起動時に自動で行います：

- 10 種類の圧縮形式を SilentZIP に関連付け
- Finder のサービスを登録

管理者パスワードも、システム設定を開く必要もありません。

---

## コマンドライン

アプリ内に `sz` が入っています：

    sz list    archive.7z
    sz extract archive.7z ./out
    sz create  new.zip file1 file2
    sz test    archive.7z

メニューの **SilentZIP → コマンドラインツールをインストール…** から PATH に追加できます。

---

## ビルド

    ./build.sh

macOS 13 以降と Xcode Command Line Tools が必要です。

---

## 翻訳

UI の文言は `language/*.ini`（`key = value` 形式）にあります。
詳しくは [CONTRIBUTING.md](CONTRIBUTING.md) を参照してください。

---

## ライセンス

SilentZIP 自体は [Resources/LICENSE.md](Resources/LICENSE.md)。
7-Zip のライセンスと LGPL 全文も同梱しています。

Copyright (C) SilentStudio / SilentCodeTeams™
