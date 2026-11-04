# AUDIT-ROUND-9 · 第九轮：两份已漂移的实现 + 两份日期工厂的对齐

> 执行日期：2026-11-01 06:30 → 07:10（+08:00）
> 起点 `aa63769` → 终点 `662ba51`
> CI：build `errors=0`；golden **46 tests / 0 failures**

---

## 0. 结论摘要

| 项 | 数字 |
|---|---|
| 本轮修复 | **2 项**（重复实现合并 + 注释与现实不符） |
| 新增测试 | **7 条**（`FormatterConsistencyTests`） |
| 测试总数 | **46 条**，5 个文件 / 208 条断言 |
| 闸门 | 17 / 17 |
| 静态扫描 | P0 0 · P1 0 · P2 21 · P3 9 |

---

## 1. 两份 `parseLocal` 已经**漂移**了

上一轮为修时基 bug 新增了 `RecordSearch.parseLocal`，但 `CredentialOrg` 里**早就有**一个同名函数。
两份实现当时已经不一致：

| | `CredentialOrg.parseLocal` | `RecordSearch.parseLocal`（上轮新增） |
|---|---|---|
| 截断 | `String(s.prefix(19))` —— 容忍串尾带毫秒/时区 | 不截断 |
| 返回 | `Date?` | `Int64`（失败给 0） |

后果：台账串若带尾巴（例如 `2026-01-01 00:00:00.000`），一份能解析、另一份返回 0
⇒ 同一个字段在「越界窗口」页和「凭证统计」页得到**不同结论**。
已把 `RecordSearch.parseLocal` 改成复用 `CredentialOrg.parseLocal`（单一实现）。

同时清理了**与现实不符的注释**：`RecordSearchQuery` 顶部还写着
"parseStamp 返回 Int64，窗口对齐用它" —— 那个调用点上一轮已改走 `parseLocal`。
注释说 A、代码做 B，是下一处 bug 的温床。

---

## 2. `parseStamp` 现在是**生产代码零调用**

它不是死代码，而是"只被测试用"的**口径参照物**：

- 它实现的是 `Attribution.ms` 那条 JS 互操作语义（本地串按 UTC 读）—— 那个语义没错；
- 但**不能**用在"台账窗口 vs 日志时间"的比较里（上一轮的 bug 就是它）；
- 保留它是因为 `TimeBasisTests` 用它断言"两个口径的关系"（差值必须正好等于时区偏移）。

已在函数头写明"生产代码零调用 + 为什么保留 + 删之前先读这段"，避免下一个人
要么误以为它在用、要么当成死代码顺手删掉而破坏测试。

---

## 3. 新增：两份日期工厂必须产出同一结果

仓库里有两套日期格式化入口，都在用、都有正当理由：

| 工厂 | 用途 | 使用量 |
|---|---|---|
| `DF.cached` | 通用（format/timezone/locale 缓存），Engine 层 | 数十处 |
| `TimeFormat` | 时间口径唯一出口，钉公历 + POSIX + 本地时区 | **90 处** |

风险：两套各写一遍格式串，**改一处忘另一处** ⇒ 同一个时刻在两页显示不同。
这类不一致不崩、不报错，只在用户眼里显得"App 算错了"。

`FormatterConsistencyTests`（7 条）钉住：

| 测试 | 钉住什么 |
|---|---|
| `testClockFormatAgrees` | HH:mm 两条路径逐值一致（5 个样本含闰日/跨年/2038） |
| `testDayKeyFormatAgrees` | yyyy-MM-dd 一致 —— 分组检索全靠它，不一致会把同一天分到两组 |
| `testDayShortFormatAgrees` | MM-dd 一致 |
| `testTimeFormatCalendarIsGregorian` | 必须公历：用户把历法切成佛历会让 2026 变 2569 |
| `testEpochMillisToDate` | 毫秒→秒不丢精度；单位混用会塌回 1970 年代 |

---

## 4. 本轮我在测试里犯的错（写下来，因为它有代表性）

三处断言凭直觉写的，全部被实测推翻：

| 断言 | 实际 | 处置 |
|---|---|---|
| "秒当毫秒 ⇒ 时间 < 100000" | 1_767_225.6 秒，**不**小于 100000 | 改成用 `dayKey` 证明"塌回 1970 年代"，而不是拍阈值 |
| "2026-01-01T00:00Z 的 dayKey 就是 \"2026-01-01\"" | dayKey 用**本地时区**，UTC-5 上是 2025-12-31 | 改成断言年份落在 2025/2026（跨时区都成立） |
| 5 个 epoch 样本值 | 逐个用 Python 验算过，全部正确 | 保留 |

> 教训：时间断言必须**验算**，不能凭"应该差不多"。
> 而"CI 是 UTC"这件事，已经连续两轮把我写的正确实现判成红。

---

## 5. 网络中断（记录在案，不是借口）

本轮 `git fetch` / `git push` 反复失败：
`schannel: failed to receive handshake, SSL/TLS connection failed`。
TCP 443 可达（`Test-NetConnection` 返回 True），所以是 **TLS 握手层**的间歇故障。
处置：等待后重试（`-c http.version=HTTP/1.1` 无效），最终成功。
本地提交始终是完整的，没有丢工作。

---

## 6. 验证链

```
$ node Gates/allgates.js
… 17 道闸门全部通过
tests: 5 个测试文件，208 条断言

$ node Tools/static-audit.js
P0=0 P1=0 P2=21 P3=9

$ git show origin/ci-test:meta.txt
commit=662ba51… job=golden  test_executed=yes  test_ok=1  test_failed=0  tests_executed=46

$ git show origin/ci-log:meta.txt
commit=662ba51… errors=0  build_ok=1  archive_ok=1
```

---

## 7. 仍未闭环

### P2（6 项，均需设备/外部决定/平台限制）
- **SEC-01 残余**：Swift `String` 无法可靠清零（平台限制）。
- **SEC-18 残余**：手机钥匙撤销 `cmd08` 锁端失败时本机记录处置**需真机确认**。
- **SEC-22**：协议层 AES-128-ECB 无 IV/无认证、静态 ekey 可重放 —— **固件限制**。
- **SEC-26**：`ITSAppUsesNonExemptEncryption: NO` 出口合规归类**需法律复核**。
- **SEC-01 单测**：未签名测试宿主无钥匙串权限 ⇒ CI 上 `skipped`。
- **D-12 竖屏**：产品决定。

### P3
D-11 已确认**误报**（跨文件 `extension` 需要 internal，两处都有注释）。
D-14（DesignLab `<img>` 缺 alt）、`ForEach` 下标身份若干处、`.toolbar(.hidden, for:)` 软废弃。

### 工具
`hig_audit` / `hig_audit_file` 连续第三轮**超时**。HIG 结论以第七轮的人工逐条复核为准。

### 需要真机/人工的
SwiftUI 真实渲染与**浅色主题观感**、手势、触觉、BLE 回执、指纹录入、
**DFU 真实续传**、WebDAV 真实链路。
