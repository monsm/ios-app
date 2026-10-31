# AUDIT-ROUND-10 · 第十轮：HIG 参考换道 + 第 18 道闸门（命令失败必须说原因）

> 执行日期：2026-11-01 07:00 → 07:45（+08:00）
> 起点 `aa63769` → 终点 `c445049`
> CI：build `errors=0`；golden **46 tests / 0 failures**

---

## 0. 结论摘要

| 项 | 数字 |
|---|---|
| 本轮修复 | **2 个真缺陷**（用户动作失败却不说原因） |
| 新闸门 | **第 18 道** `feedback.js` |
| 闸门 | 17 → **18** |
| 测试 | 46 条 / 5 文件 / 208 断言 |
| 静态扫描 | P0 0 · P1 0 · P2 21 · P3 9 |

---

## 1. `hig-doctor` MCP 连续第四轮不可用 —— 换道解决

本轮实测：连 `hig_list_skills`（最轻量的接口）都返回
`The MCP server hig-doctor couldn't answer in time`。
为排除"整个 MCP 基础设施坏了"，我调了另一个 MCP（nuget）——
**它正常响应**。所以是 `hig-doctor` 这个服务本身的问题，不是环境问题。

**换道**：`apple-design` skill 自带 **123 个 HIG 参考页**（`references/hig/*.md`，
Apple 原文措辞与分节）。这不是"凑合替代"，而是**同一份素材的本地副本**。
本轮据此逐条核对了 `privacy` / `loading` / `feedback` 三页。

---

## 2. 两个真缺陷：命令失败，但界面不说原因

依据 HIG `feedback` › Best practices：
> "Show people when a command can't be carried out and help them understand why."

### F-01 · 靠近自动开锁的「标定」失败后什么都不说

```swift
private func calibrate() {
    ...
    try? await LockService.shared.ensureConnected(mac: mac)   // ← 连不上被吞掉
    var samples: [Int] = []
    for _ in 0 ..< 5 { /* 采 RSSI */ }
    if AutoOpen.saveAutocal(mac, samples: samples) != nil { ... } else {
        store.calibrationAt = nil                                 // ← 只是把状态退回"未标定"
    }
    calibrating = false
}
```

用户看到的是：**点按钮 → 转圈 → 什么都没变**。
既不知道"没连上锁"，也不知道"采不到信号"。而这一页的说明还写着
"没标定就打开自动开锁，门内走动也可能触发" —— 用户以为标定成功了会更糟。

修法：`do/catch` + `calibrationError` 状态，失败原因（连不上 / 只采到 N/5 个样本）
直接显示在该卡片里。

### F-02 · 锁信息页检测到锁钟偏差，但自动校时失败无声

```swift
if let drift, abs(drift) > 2 {
    if let res = try? await LockService.shared.syncTime() {   // ← 失败被吞
        outcome = "已自动校时 · ..."
    }
}   // 失败时 outcome 保持空串
```

界面已经把偏差（例如 37 秒）显示出来了，但校时没成功时**没有任何提示** ——
用户以为已经校好了，实际锁钟还是错的（而锁钟是临时码有效性的判据）。

修法：失败时写 `"检测到锁钟偏差 37 秒，但自动校时失败：<原因>"`。

---

## 3. 第 18 道闸门：`Gates/feedback.js`

这类缺陷的共同形状是 **`try? await <会失败的调用>` + 函数体内没有任何错误通道**。
它不崩、不报错、不影响编译，只让用户"点了没反应" —— 静态扫描和编译器都抓不到。

闸门判据：
- 只看**用户动作**函数（名字以 calibrate/connect/sync/save/restore/import/export/
  start/stop/toggle/issue/revoke/delete/add/write/send/… 开头）；
- 函数体里存在 `try? await`（**排除** `Task.sleep` —— 那是取消语义不是失败）；
- 排除 `throws` 函数（它把错误抛给调用方，通道在别处）；
- 排除纯后台函数（reload/refresh/poll/prefetch）；
- 剩下的必须出现至少一个错误通道词
  （`catch` / `errorText` / `outcome` / `AppToast` / `VStatusLine(tone: .critical)` …）。

**当场验证它抓得住**：把 `calibrate()` 的 `do/catch` 拆掉并抹掉所有 `calibrationError`
引用后，闸门立刻红：

```
feedback: FAIL — 1 处"命令失败但不说原因"（HIG feedback）
  App/Features/Settings/AutoOpenScreen.swift:174  private func calibrate() {
```

> 第一次尝试"证明它抓得住"时其实没抓住 —— 因为我的回退版还留着
> `calibrationError = nil` 这一行，那**确实**是个错误通道。闸门是对的，我的验证方法不对。
> 把通道彻底抹掉之后才红。这个细节值得记：**验证闸门时，要真的把"正确做法"拆干净**。

---

## 4. 顺带核对的 HIG 条目（本轮无需改动）

| HIG 页 | 核对结论 |
|---|---|
| `privacy` | 4 条 purpose string 都合格（具体、主动语态、句号结尾）；Face ID 确实在用（`LAContext.evaluatePolicy`），不是白写的权限 |
| `loading` | "Show something as soon as possible" —— 23 处 `VBusyRow`/`ProgressView` 覆盖了所有长操作 |
| `feedback` | 见上，两处真缺陷已修 |

---

## 5. 验证链

```
$ node Gates/allgates.js
… 18 道闸门全部通过
feedback: OK — 用户动作里的 try? await 都有错误通道
tests: 5 个测试文件，208 条断言

$ node Tools/static-audit.js
P0=0 P1=0 P2=21 P3=9

$ git show origin/ci-log:meta.txt
commit=c445049… errors=0  build_ok=1  archive_ok=1
```

---

## 6. 仍未闭环

### P2（6 项，均需设备/外部决定/平台限制）
SEC-01 残余（Swift `String` 无法清零）· SEC-18 残余（需真机）·
SEC-22（固件 AES-ECB 限制）· SEC-26（出口合规需法律复核）·
SEC-01 单测（未签名宿主无钥匙串权限 ⇒ CI skipped）· D-12（竖屏产品决定）。

### P3
D-11 已确认误报（跨文件 extension 需要 internal）。D-14（DesignLab `<img>` 缺 alt）、
`ForEach` 下标身份若干处、`.toolbar(.hidden, for:)` 软废弃。

### 工具
`hig-doctor` MCP **连续第四轮超时**（已确认是服务本身，非环境）。
改用 `apple-design` skill 自带的 123 页 HIG 本地副本 —— 等价素材，可持续使用。

### 需要真机/人工的
SwiftUI 真实渲染与浅色主题观感、手势、触觉、BLE 回执、指纹录入、
DFU 真实续传、WebDAV 真实链路。
