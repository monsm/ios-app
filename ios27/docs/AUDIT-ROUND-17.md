# AUDIT-ROUND-17 · 第十七轮：我第 8 轮的"安全修复"其实让用户恢复不了自己的备份

> 执行日期：2026-11-01 09:00 → 09:40（+08:00）
> 起点 e631fc0 → 终点 0b0d397（+ 本文件所在提交）
> CI：build errors=0；golden **60 tests / 0 failures**

---

## 0. 结论摘要

| 项 | 数字 |
|---|---|
| 本轮修复 | **1 个我自己引入的回归**（SEC-14 的过度收紧）+ 1 条防复发闸门判据 |
| 新增测试 | 7 条（BackupRoundTripTests） |
| 测试 | 54 → **60**，8 文件 |
| 闸门 | 20 / 20 |

---

## 1. 回归：我把"校验和不一致"改成了硬拒绝

第 8 轮修 SEC-14 时，在三条恢复路径上加了：

    guard parsed.preview.checksum != .mismatch else {
        restoreError = "这份备份的校验和对不上 —— 已拒绝恢复。"
        return
    }

**这直接推翻了本仓早已写明的一条设计判断。** BackupStudioKit.swift 里 2026-10-14 的注释
（就在 checksumState 上方，我一直读得到）说得很清楚：

> 撤回"旧语义只对旧 schema 包放行"的收紧 —— 本仓旧版本导出的包恰恰是 schema 5 +
> 旧 (UTF-8) 语义校验和，按 schema 判会**把用户已有备份误判成篡改**（数据失踪级观感）。

也就是 .mismatch 有两种成因：

1. 包真被截断/改动过（该拦）；
2. **包是本 App 旧版本导出的**，键序不同，FNV 天然对不上（绝不该拦）。

硬拒绝把 (2) 一起杀掉。后果是**唯一的数据出口失效**：用户拿着自己几年前的合法备份，
App 说"你被篡改了"，恢复不了。**"恢复不了"比"被截断包覆盖"更糟** ——
前者是确定性伤害，后者只是概率性风险。

### 修法：二次确认，而不是硬拦

    // BackupStudioKit
    static func checksumNeedsAck(_ state: ChecksumState) -> Bool { state == .mismatch }

    // 三处恢复路径
    if BackupStudio.checksumNeedsAck(parsed.preview.checksum) && !checksumAcked {
        checksumAcked = true
        restoreError = "校验和对不上：可能是本 App 旧版本导出的包（键序不同，属正常），"
                     + "也可能真被截断/改动过。确认要继续请再点一次恢复。"
        return
    }

- 防误触与截断包意外覆盖：**需要两次点击**，文案说明两种可能；
- 保住兼容性：旧版本包**仍可恢复**；
- checksumNeedsAck(.absent) == false：更早没有校验和字段的包同样不被硬拦。

---

## 2. 防复发：privacy 闸门第 11 条判据

抓这个形状：guard parsed.preview.checksum != .mismatch else（回到硬拒绝的签名）。已验证抓得住：

    privacy: FAIL — 1 处回归
      Features/Settings/BackupScreen.swift:338 — 硬拒绝校验和不一致的备份
        → 改用 BackupStudio.checksumNeedsAck 做二次确认

---

## 3. 顺带：备份"导出→解析→恢复"第一次有了可执行验证

新增 BackupRoundTripTests（7 条）：确定性导出 / 凭证完整带回 / 归属丢弃纪律 /
合并只增不删 / 冲突未裁决保本机 / 非法 skey 整把跳过 / mismatch 只要求确认不硬拦。

### 我写这批测试时又错两处，CI 都判出来了

| 我的断言 | 实际 | 判定 |
|---|---|---|
| "owner 必须保留 m1" | restore 里 remap[o] ?? (DB.member(o) != nil ? o : nil)，本机没有 m1 就**故意**丢归属 | 测试错：留悬空成员会让记录页显示幽灵归属 |
| "两条密码必须都在"（实际 3） | 前一用例往同一 MAC 写了 alias 9，DB 是进程级单例 | 测试错：加 setUp 清台账 |

---

## 4. 验证链

    $ node Gates/allgates.js        -> 20 道闸门全部通过
    $ git show origin/ci-test:meta.txt
      commit=0b0d397  test_executed=yes  test_ok=1  test_failed=0  tests_executed=60
    $ git show origin/ci-log:meta.txt
      commit=0b0d397  errors=0  build_ok=1  archive_ok=1

---

## 5. 方法论（本轮最值得记的一点）

**"修一个安全风险"之前，必须先确认代码里有没有人为相反方向留过理由。**

checksumState 上方那段 2026-10-14 注释，就是前一轮为"不能硬拦"留下的论证。
我第 8 轮读到的是"校验和只是告警"这个**现状**，直接判定为缺陷并改成硬拦 ——
没有去问"为什么它是告警"。答案就写在 20 行上面。

所以本轮起加一条纪律：**把某个"宽松"改成"严格"之前，先在同一文件里找有没有
解释为什么宽松的判断**。本仓大量这种注释，且都带日期与原因。
