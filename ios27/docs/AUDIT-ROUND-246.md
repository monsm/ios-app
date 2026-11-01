# AUDIT-ROUND-246 · 第 246 轮：钥匙串卡片显示「-1 %」，而且永远涂警告色

> CI：**`838fd66` build 全绿**（owner 写入点修复编译通过）。

## 1. 缺陷

`SettingsModel.dongles` 把「未知」映射成哨兵值：

    battery: d.stat?.power ?? -1,      // -1 = 没读到电量
    keys:    d.stat?.ekeyCount ?? 0,   // ← 错：ekeyCount 的哨兵也是 -1，0 是合法值

而 `HardwareScreen` 直接拼进字符串：

    .init(label: "电量", value: "\(d.battery)", unit: "%", tint: d.battery < 20 ? warning : text1)
    .init(label: "钥匙", value: "\(d.keys)", unit: "把")

| 现象 | 原因 |
|---|---|
| 卡片显示「**-1 %**」 | 哨兵值直接拼进字符串 |
| 电量**永远**涂警告色 | `-1 < 20` 恒真 |
| 页头「低电 N 台」恒报 | 同上（`tone` / `status` 两处） |
| 钥匙数未知时显示「0 把」 | `?? 0` 把未知和"真的一把都没有"混成一个值 |

## 2. 修法

| 位置 | 修法 |
|---|---|
| `SettingsModel.dongles` 的 `keys` | `?? -1`（与 `battery` 同口径） |
| 电量读数 | `d.battery >= 0 ? "\(d.battery)" : "—"`，单位同步省略 |
| 电量染色 | `d.battery >= 0 && d.battery < 20` |
| 钥匙读数 | `d.keys >= 0 ? "\(d.keys)" : "—"` |
| 页头 `tone` / `status` | 低电判定加 `>= 0` 前置 |

## 3. 方法论

**哨兵值（-1 / 0 / 空串）在「拼字符串」这一步最容易漏 —— 因为拼字符串不做任何判断。**

| 层 | 会不会漏哨兵 |
|---|---|
| 计算（`max()` / 比较） | 有时碰巧正确 |
| **插值进文案** | **一定漏** —— 它只是把数字变成字 |

判据：**任何 `"\(数值)"` 出现在界面文案里，都要先问「这个值有哨兵吗」。**
本轮 `battery` 与 `keys` 都有，而它们在 `SettingsModel` 里被映射成了两种不同的未知表示（-1 与 0）——
后者更糟，因为 0 本身是合法读数。
