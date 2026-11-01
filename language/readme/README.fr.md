# SilentZIP

[中文](../../README.md) · [English](README.en.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Русский](README.ru.md) · **Français** · [Deutsch](README.de.md)

> Version condensée. Voir la [version anglaise](README.en.md) ou [chinoise](../../README.md) pour les détails.

Gestionnaire d'archives pour macOS. Double-cliquez sur une archive pour voir son contenu — sans l'extraire d'abord.

Les dossiers à gauche, le contenu de l'archive à droite. La séparation se déplace à la souris.

---

## Le moteur

Le cœur de compression est 7-Zip. La version macOS officielle est en retard sur les sources, alors on le compile nous-mêmes.

    ./7z-build/build-7zip.sh

Le script interroge GitHub pour la dernière version, télécharge les sources, les compile avec clang et installe le binaire dans `Resources/7zz`.

Le binaire est universel (arm64 + x86_64), donc il tourne aussi sur Mac Intel.

---

## Fonctions

- **Navigation** — deux volets : fichiers et contenu de l'archive
- **Extraction** — uniquement la sélection. Sans sélection, une boîte de dialogue vous le signale
- **Compression** — 7z / zip / tar / gz / xz / bz2
- **Test** — vérification d'intégrité avec rapport
- **Ajout, suppression, déplacement** — édition à l'intérieur de l'archive
- **Imbrication** — ouvrir une archive contenue dans une autre
- **Glisser-déposer** — extraire vers le Finder par glissement

Les dossiers système (/System, /usr, etc.) sont en lecture seule.

---

## Prêt à l'emploi

Au premier lancement, automatiquement :

- 10 formats d'archives s'ouvrent avec SilentZIP
- Les services du Finder sont enregistrés

Aucun mot de passe administrateur, aucun réglage à faire.

---

## Ligne de commande

L'outil `sz` est inclus dans l'application :

    sz list    archive.7z
    sz extract archive.7z ./out
    sz create  new.zip file1 file2
    sz test    archive.7z

Ajoutez-le au PATH depuis le menu **SilentZIP → Installer l'outil en ligne de commande…**

---

## Compilation

    ./build.sh

Nécessite macOS 13+ et les Xcode Command Line Tools.

---

## Traductions

Les textes de l'interface sont dans `language/*.ini` — du texte brut `clé = valeur`.
Voir [CONTRIBUTING.md](CONTRIBUTING.md).

---

## Licence

Conditions de SilentZIP : [Resources/LICENSE.md](Resources/LICENSE.md).
La licence 7-Zip et le texte complet de la LGPL sont joints sans modification.

Copyright (C) SilentStudio / SilentCodeTeams™
