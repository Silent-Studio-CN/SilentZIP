# SilentZIP

[中文](../../README.md) · [English](README.en.md) · [日本語](README.ja.md) · **한국어** · [Русский](README.ru.md) · [Français](README.fr.md) · [Deutsch](README.de.md)

> 요약본입니다. 자세한 내용은 [영어판](README.en.md) 또는 [중국어판](../../README.md)을 참고하세요.

macOS용 압축 관리 프로그램. 압축 파일을 더블클릭하면 바로 안을 볼 수 있습니다. 먼저 풀 필요가 없습니다.

왼쪽은 폴더, 오른쪽은 압축 파일 내용. 구분선은 드래그로 조절합니다.

---

## 엔진

압축 엔진은 7-Zip입니다. 공식 macOS 빌드가 소스보다 뒤처져 있어서 직접 컴파일합니다.

    ./7z-build/build-7zip.sh

GitHub에서 최신 릴리스를 찾아 소스를 내려받고 clang으로 빌드해 `Resources/7zz`에 넣습니다.

바이너리는 universal(arm64 + x86_64)이라 Intel Mac에서도 동작합니다.

---

## 기능

- **탐색** — 파일 브라우저와 압축 내용 2단 구성
- **압축 풀기** — 선택한 항목만. 아무것도 선택하지 않으면 확인창이 뜹니다
- **압축** — 7z / zip / tar / gz / xz / bz2
- **검사** — 무결성 확인과 리포트
- **추가·삭제·이동** — 압축 파일 내부 편집
- **중첩** — 압축 안의 압축을 이어서 열기
- **드래그 내보내기** — Finder로 끌어내기

시스템 폴더(/System, /usr 등)는 읽기 전용입니다.

---

## 설치 후 바로 사용

첫 실행 시 자동으로:

- 10가지 압축 형식을 SilentZIP으로 연결
- Finder 서비스 등록

관리자 암호도, 시스템 설정 변경도 필요 없습니다.

---

## 명령줄

앱 안에 `sz`가 들어 있습니다:

    sz list    archive.7z
    sz extract archive.7z ./out
    sz create  new.zip file1 file2
    sz test    archive.7z

메뉴 **SilentZIP → 명령줄 도구 설치…** 에서 PATH에 추가할 수 있습니다.

---

## 빌드

    ./build.sh

macOS 13 이상과 Xcode Command Line Tools가 필요합니다.

---

## 번역

UI 문구는 `language/*.ini` (`key = value` 형식)에 있습니다.
자세한 내용은 [CONTRIBUTING.md](CONTRIBUTING.md)를 보세요.

---

## 라이선스

SilentZIP 자체는 [Resources/LICENSE.md](Resources/LICENSE.md).
7-Zip 라이선스와 LGPL 전문도 함께 들어 있습니다.

Copyright (C) SilentStudio / SilentCodeTeams™
