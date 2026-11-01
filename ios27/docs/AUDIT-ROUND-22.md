# AUDIT-ROUND-22 · 第二十二轮：D-14（设计总览页的 27 张匿名图）

> CI：`ffb0407` 已验证；`f772976` / `885371c` 待回执 —— 本轮**不改 Swift**，避免在未验证的改动上继续叠加

## 1. 为什么这轮不碰 Swift

上一轮与上上轮的改动（空壳清通知 + 退出重建）都还没拿到编译回执。
再堆 Swift 改动会让"出错时不知道是哪一条"的概率上升。
所以本轮做**零编译风险**的事：修第一轮 HIG 报告里唯一还没闭环的 P3 —— D-14。

## 2. D-14：DesignLab 总览页 27 个 `<img>` 全部缺 alt

HIG `voiceover`：「Provide alternative labels for all key interface elements」/
「Describe meaningful images」。这页是给人看的设计总览，
VoiceOver 读到的是 27 个匿名图形 —— 屏名只在 `<figcaption>` 里，图本身没有任何描述。

根因在**生成器**（`DesignLab/sheet.js`），不在产出物：
`out/` 是生成目录、不入版本库，所以改产出物没用，下次生成就没了。

修法：生成时带上 `alt="<屏名> <明暗> 截图"`。

## 3. 防复发：a11y 闸门加第 ⑤ 条

扫 `DesignLab/*.js`，任何 `<img ...>` 里没有 `alt=` 就判红。
**双向验证过**：

- 现状（已带 alt）→ 绿；
- 把 `sheet.js` 改回 `<img src=` → 立刻红：
  `DesignLab/sheet.js:26  <img> 缺 alt（屏幕阅读器只读到匿名图形）`

> 中途踩到一个坑：第一版正则写成了 `\\balt=`（多一层转义），
> 变成匹配"字面反斜杠 + b"，于是**任何** `<img>` 都被判缺 alt —— 误报。
> 这也是"必须双向验证"的意义：只测判红不够，还要确认修好后会转绿。

## 4. 现状

```
$ node Gates/allgates.js        -> 20 道闸门全部通过
$ node Gates/a11y.js            -> OK（含 DesignLab img alt 检查）
```

第一轮 HIG 报告的 15 条真实问题里，D-14 是最后一个可离线闭环的；
其余未闭环项均需要真机（观感/手势/触觉/蓝牙回执）或外部决定（出口合规、竖屏策略）。
