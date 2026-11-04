# AUDIT-ROUND-275 · 第 275 轮：CI 回执确认了上一轮的判断（签名改动 → 金标红 → 已修）

## 1. 回执

| 提交 | build | golden |
|---|---|---|
| `77b60ca`（`restore` 改 `throws`） | ✅ `build_ok=1` | ❌ `test_ok=0` / `test_failed=2` / `tests_executed=0` |
| `1f84bca`（手势芯片） | ✅ | ✅ 82 用例 |
| `d287a34`（补 `try`） | 排队中 | 排队中 |

`77b60ca` 的 `test.log` 原文：

    Tests/BackupRoundTripTests.swift:110:13: error: call can throw but is not marked with 'try'
    …（128 / 143 / 162 同）

**与上一轮的预判完全一致** —— 不是别的原因，就是那 6 处调用没带 `try`。

## 2. 这说明什么

| 事实 | 含义 |
|---|---|
| build job 绿、golden job 红 | App 本体能编，**测试目标**编不过 |
| `tests_executed=0` | 一条用例都没跑（不是跑了失败） |
| `test_failed=2` | 是两个**编译错误**被计成失败，不是断言失败 |

**只看 `ci-log` 会以为这次提交没问题** —— 这正是本会话早期那轮「CI 有几个回执分支就要看几个」的再次兑现。

## 3. 顺带核对

| 检查 | 结论 |
|---|---|
| 新加的 `TrialGuard` 拦截会不会让测试抛错 | ❌ 不会：`Tests/` 全目录不碰 `kf_trial_guard`，默认 false |
| 全仓 `restore` 调用点 | ✅ 9 处全部带 `try`（3 UI + 6 测试） |

## 4. 方法论

**「build 绿」不等于「这次提交没问题」—— 测试目标可能根本没编过。**

| 回执 | 能证明什么 |
|---|---|
| `build_ok=1` | App 目标编译通过 |
| **`test_executed=yes` + `tests_executed>0`** | **测试目标也编过了，且真的跑了** |

判据：**每次看回执，先看 `tests_executed`；它等于 0 而 `test_failed>0`，那是编译错误不是测试失败。**
