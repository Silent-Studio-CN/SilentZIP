# SilentZIP

[中文](README.md) · [English](README.en.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Русский](README.ru.md) · [Français](README.fr.md) · **Deutsch**

> Gekürzte Fassung. Details in der [englischen](README.en.md) oder [chinesischen](README.md) Version.

Archivmanager für macOS. Doppelklick auf ein Archiv zeigt den Inhalt — ohne vorher zu entpacken.

Links die Ordner, rechts der Archivinhalt. Die Trennlinie lässt sich ziehen.

---

## Die Engine

Der Kern ist 7-Zip. Der offizielle macOS-Build hinkt den Quellen hinterher, also kompilieren wir selbst.

    ./7z-build/build-7zip.sh

Das Skript fragt GitHub nach der neuesten Version, lädt die Quellen, baut sie mit clang und legt das Ergebnis in `Resources/7zz` ab.

Das Binary ist universal (arm64 + x86_64), läuft also auch auf Intel-Macs.

---

## Funktionen

- **Ansehen** — zwei Bereiche: Dateien und Archivinhalt
- **Entpacken** — nur die Auswahl. Ohne Auswahl erscheint ein Hinweis
- **Packen** — 7z / zip / tar / gz / xz / bz2
- **Prüfen** — Integritätstest mit Bericht
- **Hinzufügen, Löschen, Verschieben** — Bearbeitung im Archiv
- **Verschachtelung** — Archiv im Archiv öffnen
- **Herausziehen** — per Drag & Drop in den Finder exportieren

Systemordner (/System, /usr usw.) sind schreibgeschützt.

---

## Sofort einsatzbereit

Beim ersten Start automatisch:

- 10 Archivformate öffnen mit SilentZIP
- Finder-Dienste werden registriert

Kein Admin-Passwort, keine Einstellungen nötig.

---

## Kommandozeile

`sz` liegt in der App bei:

    sz list    archive.7z
    sz extract archive.7z ./out
    sz create  new.zip file1 file2
    sz test    archive.7z

Über das Menü **SilentZIP → Kommandozeilenwerkzeug installieren…** zum PATH hinzufügen.

---

## Bauen

    ./build.sh

Braucht macOS 13+ und die Xcode Command Line Tools.

---

## Übersetzungen

Die Oberflächentexte liegen in `language/*.ini` — reiner Text `schlüssel = wert`.
Siehe [CONTRIBUTING.md](CONTRIBUTING.md).

---

## Lizenz

Bedingungen von SilentZIP: [Resources/LICENSE.md](Resources/LICENSE.md).
Die 7-Zip-Lizenz und der vollständige LGPL-Text liegen unverändert bei.

Copyright (C) SilentStudio / SilentCodeTeams™
