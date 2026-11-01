# SilentZIP

[中文](../../README.md) · **English** · [日本語](README.ja.md) · [한국어](README.ko.md) · [Русский](README.ru.md) · [Français](README.fr.md) · [Deutsch](README.de.md)

An archive manager for macOS. Double-click a compressed file to see what's inside — no need to extract first.

Your folders on the left, the archive contents on the right. The divider is draggable, and the window size and last-visited folder are remembered.

---

## About the engine

The compression core is 7-Zip. The official macOS build lags behind the source, so we compile it ourselves.

`7z-build/build-7zip.sh` does three things:

1. Asks GitHub for the latest 7-Zip release
2. Downloads the source and compiles it with your Mac's own clang
3. Drops the result into `Resources/7zz`

Run it once after cloning:

    ./7z-build/build-7zip.sh

It finds the version itself. To pin a specific one:

    ./7z-build/build-7zip.sh 2605

Whenever 7-Zip ships a new release, we run the script, test it, and publish a new version. You can just pull, or grab a prebuilt release.

**One gotcha**: judge freshness by the source date, not the Windows version number. They often diverge — 26.05 had only a Windows build for a while.

The binary is universal (arm64 + x86_64), so Intel Macs work too.

---

## What it does

**Browse**

Left pane is a file browser, opening at your Desktop. Quick jumps to Desktop, Downloads, Documents, Home, and Root are at the top.
Right pane is the archive contents. Folders drill down; every segment of the breadcrumb is clickable.

**Open**

Double-click a folder to enter it on the left.
Double-click an archive, .app, .jar, or .exe to expand it on the right.
Images, video, PDFs — anything that clearly isn't an archive — go straight to the system default app.

**Actions**

- Compress: select files or folders, hit plus, pick a format (7z / zip / tar / gz / xz / bz2)
- Extract: only what you selected. If nothing is selected, it tells you to pick something instead of silently unpacking everything. Full extraction has its own menu item.
- Test: integrity check with a report of files verified and any errors
- Copy / Move: restructure paths inside the archive
- Nesting: double-click an archive inside an archive to go one level deeper
- Add: drop more files into an existing archive
- Drag out: drag an entry to Finder to export it
- Temporary open: right-click and open, extracts to temp and launches the system app; cleaned up on quit

**Safety**

System directories (/System, /usr, /bin and friends) are read-only. Compress, extract, and delete buttons grey out, with a lock indicator in the status bar.

---

## Works out of the box

On first launch it does two things automatically:

- Makes SilentZIP the default handler for 10 archive formats
- Registers Finder services (Open with SilentZIP / Extract here)

No admin password, no digging through System Settings. Calling these APIs from inside the app avoids the confirmation dialogs you'd get from a shell.

If another app steals the association, **SilentZIP → Set as default archive tool** takes it back.

---

## Command line

Bundled inside the app as `sz`:

    sz list    archive.7z
    sz extract archive.7z ./out
    sz create  new.zip file1 file2
    sz test    archive.7z
    sz version

Install it to your PATH from the menu: **SilentZIP → Install command line tool…**

---

## Building

    ./build.sh

Produces `SilentZIP.app`. Requires Xcode Command Line Tools and macOS 13+.

For an Intel build:

    ARCH=x86_64 ./build.sh

---

## Layout

    SilentZIP/
    ├── Sources/              Swift sources
    ├── FinderExt/            Finder extension (needs a Developer ID)
    ├── CLI/                  sz command line tool
    ├── language/             UI translations (INI)
    ├── Resources/            7zz engine, icon, license texts
    ├── 7z-build/             engine build script and notes
    ├── docs/                 packaging requirements
    ├── packaging/            DMG build
    └── build.sh

---

## Translating

UI strings live in `language/*.ini` — plain `key = value` text, no programming needed.
See [CONTRIBUTING.md](CONTRIBUTING.md) for how to add a language.

README translations are welcome too; each language gets its own `README.xx.md`.

---

## Known limits

- Finder extension needs a Developer ID certificate; ad-hoc signing is rejected
- Right-click services may land under the "Services" submenu (macOS 13+ behavior)
- Builds are ad-hoc signed, so first launch shows an "unidentified developer" prompt

---

## License

SilentZIP's own terms: [Resources/LICENSE.md](Resources/LICENSE.md) (Chinese and English).

7-Zip's original license and the LGPL text ship alongside, unmodified.

SilentZIP is an independent product, not affiliated with the official 7-Zip project.

Copyright (C) SilentStudio / SilentCodeTeams™
