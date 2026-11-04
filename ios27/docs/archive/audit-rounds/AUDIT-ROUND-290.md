# AUDIT-ROUND-290 · 第 290 轮：隔离错误已修（金标 82 用例全过）+ AppLock 策略核对

## 1. 红灯闭环

| 提交 | ci-log（build） | ci-test（golden） |
|---|---|---|
| `c70d0d3` | `errors=2`（`[#ActorIsolatedCall]`） | — |
| **`a2e8766`**（修复） | 回执尚未刷新 | **✅ `test_ok=1` / `tests_executed=82`** |

**为什么 golden 绿就证明修复有效**：golden job 自己会 `xcodegen generate` + `xcodebuild test`，
也就是**先编译 App 与测试目标**再跑断言。82 个用例全跑全过 ⇒ 编译通过 ✅。

（`ci-log` 那条 build 回执只是另一个 job 的输出，滞后而已 —— **两个分支都要看**，这是本轮再次验证的纪律。）

## 2. AppLock（应用锁）策略核对 —— 无缺陷

| 检查 | 结论 |
|---|---|
| 冷却中先拒后验 | ✅ `cooldownRemaining > 0` 直接返回 `.cooling`，**不验密码**（防时序侧信道） |
| 正常密码成功 | ✅ 清 `failStreak` / `cooldownUntil` 并落盘 |
| **胁迫码** | ✅ 解锁进伪装模式，**不清失败计数、不记日志**（注释：任何痕迹都可能暴露） |
| 失败计数 | ✅ `+1` 后按 `cooldownSeconds(for:)` 设冷却 |
| 冷却升级 | ✅ `<3` 无 / `3-4` 30s / `5-6` 300s / `7+` 1800s |
| 刷脸解锁 | ✅ 有胁迫码时**直接拒绝**（刷脸进不了伪装模式，会暴露）；成功后同样清冷却 |

最后一条尤其值得记：`unlockByBiometric` 里那四行清理**曾经写在 `return true` 之后**（永不执行），
是 CI 的 `code after return will never be executed` 告警抓到的 —— 现在注释还留着这段经过。

## 3. 方法论

**「哪个回执能证明什么」要分清楚：build 只证明 App 目标，golden 才证明测试目标 + 断言。**

| 回执 | 能证明 |
|---|---|
| `ci-log build_ok=1` | App 目标编译通过 |
| **`ci-test tests_executed=82`** | **测试目标也编过，且 82 条断言真的跑了** |

判据：**判断「改动能不能编译」，等 golden 比等 build 更快也更严 —— 它多编一个 target。**
