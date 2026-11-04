# AUDIT-ROUND-292 · 第 292 轮：点「凭证工坊」打开的是「新增凭证」

> CI：**`0ed8391` build 全绿（errors=0）** —— 之前那条隔离红已彻底闭环。

## 1. 怎么发现的（集合差 + 人工核对）

`runQuick` 的 switch 有 `default: break` —— 任何没写进去的快捷动作会**静默无反应**。
于是把两个集合求差：

| 集合 | 内容 |
|---|---|
| `QuickPool.all` 的 id | 10 个：`addPwd` `otp` `syncTime` `addFp` `studio` `again` `backup` `tailgate` `safemode` `dfu` |
| `runQuick` 的 case | 8 行（其中 `case "addPwd", "addFp", "studio"` 一行裹了三个） |

差集为空 ✅ —— 但**一行的分组写法掩盖了语义问题**：

    case "addPwd", "addFp", "studio":
        router.request(.dest(.keyCreate))

三者都去 `keyCreate`（**新增凭证**）。可 `studio` 的标签是「**凭证工坊**」——
点它打开的是「新增凭证」页，而不是凭证工作室。

## 2. 修法

    case "addPwd", "addFp":  router.request(.dest(.keyCreate))
    case "studio":           router.request(.dest(.credentialStudio))

（`.credentialStudio` 是既定目的地：凭证页那个「凭证工作室」入口就指向它。）

## 3. 为什么这种 bug 特别隐蔽

| 原因 | 说明 |
|---|---|
| 点下去**有反应** | 打开了另一个页面 —— 不像 `default: break` 那样毫无动静 |
| 目标页面**长得像** | 「新增凭证」与「凭证工坊」都在凭证域，用户会以为自己点错了 |
| 集合差查不出来 | 差集只看「有没有处理」，不看「处理得对不对」 |

## 4. 方法论

**「多个取值共用一个分支」是语义差异的藏身处 —— 集合差能证明覆盖，证明不了映射正确。**

| 检查层次 | 能发现什么 |
|---|---|
| 集合差（有没有 case） | ✅ 静默无反应 |
| **逐条核对「id ↔ 目的地」** | ✅ **映射错了**（本轮） |

判据：**凡是 `case "a", "b", "c":` 这种合并写法，都要逐条问「a、b、c 的目的地真的是同一个吗」。**
