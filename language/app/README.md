# 界面语言文件

软件的界面文字。纯文本 INI，`key = value` 格式。

| 语言 | 文件 | 状态 |
|---|---|---|
| 简体中文 | [zh-Hans.ini](zh-Hans.ini) | 完整，基准版本 |
| English | [en.ini](en.ini) | 待翻译 |
| 日本語 | [ja.ini](ja.ini) | 待翻译 |
| 한국어 | [ko.ini](ko.ini) | 待翻译 |
| Русский | [ru.ini](ru.ini) | 待翻译 |
| Français | [fr.ini](fr.ini) | 待翻译 |
| Deutsch | [de.ini](de.ini) | 待翻译 |

---

## 怎么填

打开对应文件，把等号右边的空填上：

    [toolbar]
    open = Open archive        ← 填这里
    extract = Extract selected files

**左边的 key 一个字都不要改。** 改了程序就找不到。

不确定怎么翻就留空，界面会退回显示中文。

---

## 加一门新语言

1. 复制 `en.ini`，改名成语言代码（`es.ini`、`pt.ini` 等）
2. 填内容
3. 在上面的表格里加一行
4. 提交 PR

---

## 测试自己的翻译

把文件放到：

    ~/Library/Application Support/SilentZIP/Languages/

这个位置优先于 app 内置的，重启就生效，软件升级也不会覆盖。

文件名必须和 app 里用的一致（比如 `ja.ini`）。
