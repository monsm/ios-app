# AUDIT-ROUND-263 · 第 263 轮：MAC 归一化全链核对 —— 审过，无缺陷

> CI：**`9d4392f` build 全绿**；`9816328` / `bfc8d28` / `eb47535` 排队中。

## 1. 为什么查这条

本仓历史上真栽过一次「`kf_logsync_` 没归一化 ⇒ 同一个 MAC 写出两个键」（Round 177）。
而全仓有 **82 处** 键名 + mac 的字符串拼接 —— 一旦某处的入参不归一，就会重演。

## 2. 核对方法：沿「mac 从哪来」逆推

| 入参来源 | 归一化点 | 结论 |
|---|---|---|
| `DB.keychain(mac)` 返回值 | 表键 `normalizeMac(kc.mac)`、缓存键 `normalizeMac(kc.mac)` | ✅ 出口唯一 |
| `Keychain.init?(fromDict:)` | 读出 `d["mac"]`，而**写入侧** `saveKeychain` 用 `map[normalizeMac(kc.mac)]` | ✅ 表里存的键必是归一的 |
| `app.currentKeychain?.mac`（AutoOpen 等） | 来自 `DB.keychain(currentMac)` ⇒ 上式 | ✅ |
| `pendingPair` / `savePendingPair` | `"kf_pending_pair_" + normalizeMac(kc.mac)`、账号 `pair.<normalizeMac>.<field>` | ✅ |
| `removeKeychain` / `removeDevice` | 入口即 `normalizeMac` | ✅ |
| 备份恢复 `kc.mac` | `kc.mac = DB.normalizeMac(d.mac)` | ✅ |
| `DB.keychains()` 列表 | `Keychain.fromDict` + 缓存键归一 | ✅ |

## 3. 结论

**82 处拼接全部处在「mac 已被归一」的上下文里** —— 因为这些函数的入参都直接或间接来自
`DB.keychain()` / `currentMac` / `currentKeychain`，而那几个出口都做了归一。

不是「每处都记得归一」，而是**归一发生在入口，下游一律按已归一的约定使用**。
这是对的做法 —— 但前提是**没有新的旁路**。

## 4. 方法论

**验证「归一化是否彻底」不能逐个拼接点看，要看「有没有绕过归一化入口的入参」。**

| 查法 | 能发现什么 |
|---|---|
| 逐个拼接点看 | 82 处，看不过来 |
| **沿入参来源逆推** | 只需确认 6 个出口都归一 |

判据：**归一化的正确性由「入口数量」决定，不由「使用点数量」决定 —— 审入口。**
