# AUDIT-ROUND-69 · 第六十九轮：把 `privacy` 里剩下的固定窗口全换成结构划界

> CI：`ee4b04e` 已验证；`db94f4d` / `74bd21e` / `d62c9c8` 待回执。本轮本地提交。

## 1. 扫出的 7 处固定窗口

按上一轮末的判据 `grep "slice(i, i + N)"` 扫全 `Gates/`：

| 位置 | 用途 | 处置 |
|---|---|---|
| `privacy.js:92` | WebDAV http:// 仅本机回环 | 保留（向后 6 行是**豁免**判断，误判只会更严） |
| `privacy.js:103` | 备份目录必须 isExcludedFromBackup | **改结构划界** |
| `privacy.js:119` | 空壳读取口必须有 isDecoy | **改结构划界** |
| `privacy.js:129` | saveLedger 必须过 ledgerForPlist | **改结构划界** |
| `privacy.js:135` | MobileKeyService.save 必须过 SecretStore | **改结构划界** |
| `privacy.js:149` | saveLedger 必须有 isDecoy 守卫 | **改结构划界** |
| `a11y.js:56` | 图标按钮判定（30 行） | 待查（下一轮） |

改法：新增 `bodyEndOf(lines, i)` —— 按缩进找函数体闭合 `}`，整个函数体参与判定。

## 2. 双向验证

**（a）长注释不该误判红**
在 `saveLedger` 函数体开头插入 12 行注释，把 `isDecoy` 推远 ⇒ 新规则**保持绿**（旧规则会误判红）。

**（b）真去掉守卫仍要判红**
删掉那段 `if isDecoy { ... }` ⇒

```
privacy: FAIL — 1 处回归
  Engine/StoreLedger.swift:112 — saveLedger 缺空壳守卫（空表会覆盖真实台账）
```

两个方向都验过，才说明"放宽"没有变成"漏判"。

## 3. 方法论

**放宽一条检查时，必须同时证明它还能判红。**
只做 (a) 会得到一个永远绿的规则 —— 那比没有更糟（它给人虚假的安心）。

这也补上了我之前的一个坏习惯：改判据时只跑"当前代码变绿"，不跑"注入缺陷仍红"。
从本轮起，**每次放宽判据都要跑双向验证**。
