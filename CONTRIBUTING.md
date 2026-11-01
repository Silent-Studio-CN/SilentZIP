# 参与 SilentZIP

谢谢愿意帮忙。这里说明怎么提交语言文件和 README 翻译。

---

## 提交语言文件

语言文件在 `language/app/` 目录，是纯文本 INI 格式。不需要懂编程也能改。

### 格式

    ; 分号开头是注释
    ; 格式就是：key = value

    [toolbar]
    open = 打开归档
    extract = 解压选中的文件

段名（方括号那行）只是给人看的分组，程序只认 key。

### 新增一门语言

1. 复制 `language/app/zh-Hans.ini`，改名成对应的语言代码
2. 只改等号右边的内容，**左边一行都不要动**
3. 提交 PR

语言代码用标准的 BCP 47：

    简体中文    zh-Hans
    繁體中文    zh-Hant
    英语        en
    日语        ja
    韩语        ko
    俄语        ru
    法语        fr
    德语        de
    西班牙语    es
    葡萄牙语    pt
    意大利语    it

### 几条硬规矩

- **左边不能改**。改了 key，程序找不到，界面会显示兜底的中文
- **一行一个 key**。不要合并成一行
- **不要删 key**。某个词不会翻就保留原文，或者留空
- **不要加 BOM**。保存成 UTF-8 无 BOM
- 等号两边各留一个空格，跟现有文件保持一致

### 怎么验证

改完之后把文件放到：

    ~/Library/Application Support/SilentZIP/Languages/

这个位置的文件优先级高于 app 内置的，重启 app 就能看到效果，而且不会被软件升级覆盖。

---

## 提交 README 翻译

README 按语言拆文件，命名规则：

    README.md（仓库根目录）   简体中文
    language/readme/README.en.md   英语
    language/readme/README.ja.md   日语
    language/readme/README.ko.md   韩语
    language/readme/README.ru.md   俄语
    language/readme/README.fr.md   法语
    language/readme/README.de.md   德语

提交时**只改自己那份**，别动别人的，也别动主 README。

---

## PR 会被自动检查

仓库配了 GitHub Actions，会检查你的 PR 是不是只动了应该动的文件：

- 改语言文件 → 只能改 `language/` 下的
- 改 README 翻译 → 只能改对应的 `README.xx.md`

如果动了别的文件，CI 会标红并告诉你动了哪些。

这是为了防止误操作，不是你做错了什么。

---

## 不接受的类型

- 改代码（先开 issue 讨论）
- 改 LICENSE 或 Resources 下的第三方许可
- 动 `Resources/7zz`（这是编译好的引擎）
- 把 key 翻译成别的意思（比如把 "delete" 翻成 "保存"）

---

## 关于署名

语言文件的贡献者会记在 `language/CONTRIBUTORS.md` 里。
提交 PR 时在描述里写上你希望显示的名字就行。
