# AUDIT-ROUND-177 · 第 177 轮：抓到一个「键拼法 + 值类型」双不一致的真 bug

> CI：**`42e1cd6` 已验证绿**（build_ok=1 errors=0 warnings=0）；`bab117d` 待回执。

## 1. 本轮用的判据：**同一键族是否两种拼法**

想法：如果 `"kf_x_" + mac` 和 `"kf_x_" + DB.normalizeMac(mac)` 同时存在，
那么**它们在 mac 带冒号或大写时会写到不同的键上** —— 一侧写、另一侧读不到，而且完全静默。

全仓扫「`"kf_..." + 表达式`」并分成 raw / normalized 两组，只有**一个键族**同时命中：

```
[kf_logsync_]
  raw : AppModel.swift:371   DB.store.set("kf_logsync_" + mac, Int(Date().timeIntervalSince1970 * 1000))
  norm: RecordsModels.swift:317  DB.store.getString("kf_logsync_" + DB.normalizeMac(rawMac))
        RecordsModels.swift:324  DB.store.set("kf_logsync_" + DB.normalizeMac(rawMac), String(at))
```

## 2. 这里其实是**两处**不一致，不是一处

| 维度 | 写方（`AppModel.readLogs`） | 读方（`RecordsSource.lastSync`） |
|---|---|---|
| **键** | `"kf_logsync_" + mac`（**未归一化**） | `"kf_logsync_" + DB.normalizeMac(mac)` |
| **值类型** | **`Int`**（毫秒） | **`getString`**（毫秒字符串） |

任一处不一致就足够让读取失败；两处同时不一致 ⇒ 几乎必然读不到。

## 3. 症状

「上次读取 · X 前」**恒显示「还没读取过锁内日志」**，即使刚刚读完。

为什么之前没暴露：`RecordsScreen.read()` 在 `app.readLogs()` **之后**还会调一次
`RecordsSource.markSynced(mac:at:)` —— 那一步用的是**正确口径**（归一化 + 字符串），
于是手动读取这条路"看起来是对的"。

但只要满足任一条，就会露出来：

| 条件 | 结果 |
|---|---|
| `currentMac` 带冒号或大写 | 写与读落在不同键上 |
| 任何**不经** `RecordsScreen.read()` 而直接调 `app.readLogs()` 的路径 | 只有那条错口径的写，`lastSync` 读不到 |

**这正是"两套口径并存"的典型危害：主路径被第二处写掩盖，旁路一出现就崩。**

## 4. 修法

```swift
// AppModel.readLogs（新）
DB.store.set("kf_logsync_" + DB.normalizeMac(mac),
             String(Int(Date().timeIntervalSince1970 * 1000)))
```

写 / 读 / 补记三处现在统一为：**归一化键 + 毫秒字符串**。

## 5. 本轮另外 5 项"审过、判定合理"

| 疑点 | 判定 |
|---|---|
| `expiringSoonCount` 只数密码、不数手机钥匙 | **有意** —— 注释写明与月历格、`dueSoonPwds` 同源同一把尺；指纹本来无到期 |
| 手机钥匙的到期不进角标 / 月历 / 通知 | **已知缺口**，不是本轮能单方面改的：只改角标会与月历口径分叉；要改需同时改三处（产品决定） |
| `CredAlert()` 默认全关（新建凭证没有到期提醒） | **有意** —— 显式解码是为了老包缺键时"不牵动别的档"；提醒按条手动开 |
| 170 处 `guard … else { return }` | **合法前置条件**（busy / 空 mac / 委托回调），判据精度太低，放弃 |
| `.onAppear { Task {` / 浮点 `==` | **0 处** |

## 6. 方法论

**「两套口径并存」比「一处写错」更危险，因为主路径会掩盖它。**

| 形态 | 表现 |
|---|---|
| 一处写错 | 第一次就暴露 |
| **两处口径不同** | **主路径因为有人补了一刀而正常；旁路一出现就静默失败** |

判据：**看到同一个语义（同一个键、同一个判据、同一个阈值）在两个文件里各写一遍时，
把两边的"键形态 / 值类型 / 归一化方式"逐项对比** —— 而不是只对比语义。
