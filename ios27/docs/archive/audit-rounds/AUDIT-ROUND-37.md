# AUDIT-ROUND-37 · 第三十七轮：callsig2 有个大盲区，我把它写进了它自己的文件头

> CI：`aeca8e4` 已验证（errors=0、build_ok=1）；`c12c91d` / `b0e4cac` 待回执

## 1. 正控结果（本轮 5 道，全部成立）

| 闸门 | 注入 | 前/中/后 | 结论 |
|---|---|---|---|
| `reducedmotion` | 无守卫的 `.animation(.easeInOut)` | 0/1/0 | ✅ |
| `destmap` | `Router.Dest` 加一个 `ghostDest`、`Destinations` 不映射 | 0/1/0 | ✅ |
| `swiftcheck` | `enum HexKit {` 后加孤立 `(` | 0/1/0 | ✅ |
| `crosprivate` | 在 `Parts` 文件里访问 `Screen` 的 `private var selectedPwds` | 0/1/0 | ✅ |
| `tests` | 临时移走 `ConcurrencyTests.swift` | 0/1/0 | ✅ |

（`tests` 的正控是"把文件改名再改回来"，中间 CI 不会读，属安全操作。）

## 2. `callsig2`：没红，而且原因不是"我注入错了"

我先试了三种注入，全部判绿：

| 注入 | 期望 | 实际 |
|---|---|---|
| `CredentialOrg.scheduleAlerts(mac, pwd, next)` → 少一个实参 | 红 | **绿** |
| `DB.listPwds(mac)` → `DB.listPwds()` | 红 | **绿** |
| `VActionButton(title:systemImage:)` → 少 systemImage | 红 | **绿** |

读代码后找到根因，第 439 行：

```js
if (prevChar === '.' || prevChar === '@' || prevChar === '#' || /\w/.test(prevChar)) continue;
```

**任何 `xxx.yyy(...)` 形式的调用都被整段跳过。** 原因是本闸门没有类型推断，
无法把 `DB` 解析成具体类型 —— 这是"做不到"，不是"忘了写"。

缺参检查本身是有的（第 520–523 行），只是永远轮不到点号调用。

## 3. 处置：不改能力，改"声称"

修它需要类型推断（工作量 >= 半个编译器），本轮不做。但**必须把盲区写在闸门自己的文件头**，
否则「callsig2 绿了 = 调用签名都对」这个误读会一直存在 —— 而它恰是本仓最常见的事故模式
（把"没报错"当成"没问题"）。

已写入 `Gates/callsig2.js` 头部「⚠ 已知盲区」段，并在 `docs/ARCHITECTURE.md` 的闸门表第 12 行注明。

## 4. 方法论

**一个闸门的价值 = 它能判红的东西 − 它声称能判的东西的差。**
盲区本身可以接受（受工具限制），**但盲区不写在闸门旁边就不可接受** ——
因为所有"绿"都会被读成"通过"。

这条同样适用于我前面写的那些新闸门：`privacy` 第 13–18 条都只做"同一文件内的形状检查"，
不覆盖跨文件的数据流。这一点已写在各条注释里，但还没写进 ARCHITECTURE —— 下一轮补。
