# AUDIT-ROUND-304 · 第 304 轮：状态副本扫描 + 「HEAD 的 Swift 就是 CI 验过的那份」

> CI：`3672131` **build_ok=1**；`1ab06fd` golden **82 用例全过**。

## 1. 从持久层拷进 `@State` 的副本（12 处）

| 位置 | 性质 | 风险 |
|---|---|---|
| `LockKeeperApp`（2 处） | app 级单例引用 | ✅ 无 |
| `ModuleOrderSheet` / `QuickPoolEditSheet` | **sheet，每次呈现重建** | ✅ 无 |
| `KeysScreen.groupByOwner` | 分组偏好 | ✅ 无（写入即回写） |
| **`AccessibilityScreen`（6 处）** | 大字/大 OTP/长按/大格/圆盘/手势 | ✅ **有 `syncFromStore()` + `.onAppear`** |

`AccessibilityScreen:36-43` 的 `syncFromStore()` 把这 6 个**全部**重新读一遍，第 57 行 `.onAppear { syncFromStore() }` 调用它 ——
注释还写着来由：「E-13：从持久层重新同步，避免与外观页/重置动作不一致」。
**这是本仓第 147/269 轮那类「切了别处改了，这页还显示旧状态」的正解** ✅。

## 2. 一条链式证据：HEAD 的 Swift 就是 CI 验过的那份

| 项 | 值 |
|---|---|
| 最后一次 Swift 改动后的绿构建 | `3672131`（`build_ok=1`） |
| 此后到 HEAD 改过的文件 | `.github/workflows/ios27.yml`、`Gates/*.js`、`README/docs/*.md` |
| **`ios27/App` 与 `ios27/Tests` 的 diff** | **空** ✅ |

所以：**HEAD 的 App/测试代码与 CI 已验证为绿的那份逐字节相同**，不需要再等一轮构建来证明「HEAD 能编译」。

## 3. 方法论

**「CI 绿了」要说清绿的是哪个提交、以及之后的提交有没有碰过代码 —— 否则「绿」只是一条过期回执。**

| 说法 | 强度 |
|---|---|
| 「CI 绿了」 | 弱（可能绿的是 5 个提交之前） |
| 「CI 在 X 上绿，且 X..HEAD 无代码改动」 | **强（等价于 HEAD 也绿）** ✅ |

判据：**报 CI 状态时，永远带上两件事：回执的 commit、以及该 commit 到 HEAD 是否动过代码（`git diff --stat X..HEAD -- <code paths>`）。**
