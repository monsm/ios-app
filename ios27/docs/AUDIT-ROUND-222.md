# AUDIT-ROUND-222 · 第 222 轮：`build_log=no` 到底是哪种失败 —— 让 CI 自己说清

> CI：`62a0ae5` 回执 `errors=0` 但 **`build_ok=0` / `build_log=no`**。

## 1. 这个组合意味着什么

| 字段 | 值 | 含义 |
|---|---|---|
| `errors` | 0 | 日志里没有 `error:` 行 |
| `build_log` | **no** | **`build/build.log` 根本不存在** |
| `build_ok` | 0 | 没有 `BUILD SUCCEEDED` |

`build/build.log` 是 `xcodebuild build ... | tee build/build.log` 生成的 ——
**文件不存在 ⇒ `xcodebuild` 从没运行** ⇒ 红在更早的步骤（Checkout / `brew install xcodegen` / `xcodegen generate`）。

而 `xcode-27` 是 preview 镜像，仓里已注明历史上抽风过（G-11）。**这次大概率是基础设施，不是源码。**

## 2. 但"大概率"不是证据 —— 补两个标记

ci-log 回执新增：

```
project=yes|no        # LockKeeper.xcodeproj 是否存在（xcodegen 成功没）
swift_files=<N>       # App 下 swift 文件数（checkout 完整没）
```

下次再出现 `build_log=no`，一眼可分三种：

| 组合 | 结论 |
|---|---|
| `project=no` + `swift_files=0` | Checkout 都没成功 |
| `project=no` + `swift_files=158` | `xcodegen` 挂了 |
| `project=yes` + `build_log=no` | 编译步骤本身没启动（runner 抽风） |

## 3. 顺带修正一个我自己的疏漏

**我一直只看 `ci-log`，从没看过 `ci-test`。** 这轮第一次看，`test_failed=2` 让我以为金标回归了 ——
翻 `test.log` 才发现那两条是**同一个编译错误**（`665183d` 早于修复），不是断言失败。

| 回执分支 | 我之前 | 应该 |
|---|---|---|
| `ci-log` | ✅ 每轮看 | ✅ |
| **`ci-test`** | ❌ **从没看** | ✅ **编译绿了才可能绿，但仍要看 `test_executed`** |

判据：**CI 有几个回执分支，就要看几个** —— 只看一个等于自我安慰。

## 4. 方法论

**"没有日志"本身是一种日志。**

`build_log=no` 不是"没有信息"，而是"失败发生在记录开始之前"这条信息。
判据：**任何"缺失即状态"的字段，都该配一个能区分"缺在哪一层"的旁证字段。**
