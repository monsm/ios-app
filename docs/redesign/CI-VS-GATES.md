# CI 与本地闸门的区别 —— 一次误报的记录

> 2026-10-21。必须记下来，因为这件事影响了整整一轮的判断。

## 发生了什么

在这次会话里，我反复在提交信息里写「23 道本地闸门全绿」，
并在给用户的汇报里把这个当成「改动是正确的」的证据。

**但 CI 一直是红的。**

从 run #495 到 run #?（含 c471dc7 之前的 8 次），
每一次的结论都是 FAILURE。我从没查过。

## 为什么闸门查不出来

本地 23 道闸门全部是 `tools/*.js`，它们做的是**文本/结构级检查**：

| 闸门 | 检查什么 | 查不出什么 |
|---|---|---|
| `swiftcheck` | 括号平衡、文件行数 | 类型错误 |
| `swiftlint` | 硬编码颜色、历法、字体 | 类型错误 |
| `swiftshape` | @ViewBuilder 位置、参数标签个数 | 类型错误 |
| `declcheck` | 属性包装器死变量 | 类型错误 |
| `uicoverage` | 目的地覆盖率、自绘容器预算 | 类型错误 |

**它们没有类型系统。** 一个「类型上不存在的方法调用」，只要括号平衡、参数个数对得上，闸门一律放行。

## 真实错误是这样来的

```
error: value of type 'StatusSnapshotData' has no member 'fpInfoCapacity'
error: static member 'kindWords' cannot be used on instance of type 'StatsKit.StatModel'
error: no exact matches in call to instance method 'fileExporter'
error: cannot find 'thresholdCard' in scope
error: cannot find 'archivedFact' in scope
error: cannot find 'secLabel' in scope
error: the compiler is unable to type-check this expression in reasonable time
```

七类错误，**没有一类能被文本闸门发现**。

## 每个错误的成因

| 错误 | 成因 | 我自己当时的判断 |
|---|---|---|
| `fpInfoCapacity` | 我用了 `pwdInfoCapacity/fpInfoCapacity`，但 `StatusSnapshotData` 的真实字段是 `pwdCap/fpCap`（可选 Int）。前者在 `StatusParser` 的**另一个结构**上 | 「协议真实返回，肯定有」——没查类型 |
| `kindWords` | 它是 `static func`，不能用 `model.kindWords()` 调用 | 「缩进 8 = 实例方法」——**只看了缩进，没看 `static` 关键字** |
| `fileExporter` | `document:` 重载要 `FileDocument`；`Transferable` 要用 `item:` + `contentTypes:` | 「ExportCenter 有同款」——但那边用的是 `ShareLink`，不是 `fileExporter` |
| `thresholdCard` | AutoCalView 重写后 body 里留了个不存在的视图引用 | 写完没回头核对 body |
| `archivedFact` | 字符串替换命中了**文件中第一个** `secLabel`（在 MemberDetail360View 里），而不是 MemberArchivedView | 没验证插入位置 |
| `secLabel` | DevicePage 原本没有这个辅助函数 | 「其他页面都有」——没查 DevicePage |
| 类型检查超时 | 同一个带强制解包的三元表达式在 view 里重复三次 | 没意识到 @ViewBuilder 里表达式的组合爆炸 |

## 教训

1. **本地闸门绿 ≠ 能编译。** 必须用 `tools/cistat.js` 查 CI 的真实结论。
2. **判据要看全文，不能只看缩进。** `kindWords` 那次我只看缩进就下结论。
3. **字符串替换后必须验证插入位置。** `archivedFact` 被放进了错误的 struct。
4. **改完 body 要回头核对引用的视图都存在。**
5. **@ViewBuilder 里的复杂表达式要拆开** —— 类型检查器会超时。

## 现在的状态

- HEAD `c471dc7`
- CI run 39580979109 = **SUCCESS**（3 个 job 全过）
- 这是本次会话第一次编译成功

## 给下次的检查清单

提交前除了跑 23 道闸门，还必须：

- [ ] 本轮新增/修改的每个 API，对照其**定义**核验签名（不是凭印象）
- [ ] 字符串替换后 `git diff` 看插入位置
- [ ] body 里引用的视图属性都在同一 struct 内定义
- [ ] 复杂的三元/链式表达式拆成局部 `let`
- [ ] push 后用 `cistat.js` 查状态，**红了就用 `cilog.js <runId>` 取真实 error 行**
- [ ] 拿到 `error:` 原文之前，不要说"通过"

---

# 追加：怎么拿到**真实的编译报错**（2026-10-22）

## 上一次的教训

这一晚有三处类型归属错误（`RecordSearch.note` / `NamedView` / `Query.parse`），
本地 23 道闸门**一道都没响**，而我一连几轮在收尾里写「闸门全绿」。

CI 从 `8a2502b` 起就红了，我却是在**好几轮之后**才发现 —— 因为：

> `tools/cistat.js` 是从 Actions 页面 HTML 里正则抓状态的。
> 页面结构一变，它就抓不到 `error:` 行，只会给出 `FAILURE`。
> 于是我明知道红了，却不知道该改哪里。

## 现在怎么用

```bash
node tools/cilog.js <runId>
```

它做三件事：

1. `git credential fill` 取本机已存的 GitHub 凭证（不打印、不落盘）
2. 调 Actions API 列出该 run 的 job，挑 `conclusion=failure` 的
3. 下载失败 job 的日志（纯文本），抽 `error:` 行并去重

实测输出：

```
run 39646989370  共 3 个 job，失败 1 个

══ Build (iOS 27 SDK, unsigned IPA) ══
  .../App/UI/EventsPage.swift:179:62: error: type 'RecordSearch.Query' has no member 'parse'
```

**这一步的报错粒度是"文件:行:列 + 编译器原话"**，比任何本地静态检查都准。

## 踩过的坑（都写进工具里了）

| 坑 | 现象 | 修法 |
|---|---|---|
| 用 shell 管道喂 git | Windows 没有 bash → `ENOENT` | 改 `spawnSync` 直接给 stdin |
| 日志端点送 `text/plain` | `HTTP 415` | 一律用 `application/vnd.github+json`，`asJson` 只控解析 |
| 匿名调 API | `403 rate limit` | 走 credential fill 取 token |

## 纪律

**在拿到 CI 结论之前，不要用"闸门全绿"当作"能编译"。**

这两者是不同的东西：
- 闸门查括号平衡、形状、命名、对比度 —— **没有类型系统**
- CI 用真编译器 —— 但慢

所以顺序应该是：本地闸门过滤低级问题 → 推送 → **cilog 确认** → 才敢说"通过"。

