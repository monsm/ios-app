# docs 索引

> 61 份文档，按「什么时候该读它」分组，而不是按字母序。
> **注意**：本仓纪律是"文档不可当作既成事实"——每一条都应能追回到代码。
> 判据见 `tools/citecheck.js` 与 `tools/docpointers.js`（两者都在 CI 里）。

---

## 一、从这里开始

| 文档 | 什么时候读 |
|---|---|
| [HANDOFF.md](HANDOFF.md) | 接手这个仓的第一份。只写当场可复算的事实，每条给复算命令 |
| [OPEN-ISSUES.md](OPEN-ISSUES.md) | **2026-10-26 新增**。129 条未决项的逐条裁决台账（真缺陷 / 注释漂移 / 待真机 / 可忽略） |
| [CONSTRAINTS.md](CONSTRAINTS.md) | 平台与账号约束（免费开发者账号 / Personal Team）—— 决定了哪些能力做不了 |
| [CAPABILITY.md](CAPABILITY.md) | 锁端能力对照矩阵，任何"这功能能不能做"的问题先查这里 |
| [审核结论-2026-10-27.md](审核结论-2026-10-27.md) | **2026-10-27 新增**。五份审核报告 176 条条目的处理结论：156 已处理 / 20 判定不改 / 25 项物理不可能（逐条写明为什么） |

## 二、只能由人做的事（待你介入）

| 文档 | 内容 |
|---|---|
| [DEVICE-CHECKLIST-2026-10-26.md](DEVICE-CHECKLIST-2026-10-26.md) | **2026-10-26 新增**。布防 / 手机钥匙 / 固件升级 三项功能上真机的操作卡，含每步"怎么判失败" |
| [VERIFY-CHECKLIST.md](VERIFY-CHECKLIST.md) | 只能你在 Mac / 真机上验的清单（历史累积） |
| [DECISION-NEEDED.md](DECISION-NEEDED.md) | 26 项 ❌ 判定的决策单。**D-137 已于 2026-10-26 被推翻**（periodSec 改名） |
| [NEXT-DECISIONS.md](NEXT-DECISIONS.md) | 一次拍板清单（2026-10-09），每项给方案 + 推荐 |
| [DECISION-C-TERMS.md](DECISION-C-TERMS.md) | C 类 14 项的降级口径待拍板 |

## 三、与原版 APK 的对照（协议 / 功能）

| 文档 | 内容 |
|---|---|
| [APK-PROTOCOL-PARITY.md](APK-PROTOCOL-PARITY.md) | **2026-10-26 新增**。以 `apk_raw` 的 main.js + Java LockCommBase 为权威的协议对照。**记录了一个关键结论：令牌注入键是 0xEE，不是 main.js 枚举里的 F0（那是死常量）** |
| [PARITY-APK.md](PARITY-APK.md) | 原版 APK 功能 ↔ iOS 离线版 对照（2026-10-17） |
| [PARITY-FULL-AUDIT.md](PARITY-FULL-AUDIT.md) | 锁数据交互逐项对照（2026-10-17） |
| [PARITY-ADVERSARIAL-2026-10-17.md](PARITY-ADVERSARIAL-2026-10-17.md) | 对抗式逐行对拍（第三轮） |
| [PARITY-ADVERSARIAL-APK-2026-10-17.md](PARITY-ADVERSARIAL-APK-2026-10-17.md) | 简易安卓端对抗式地毯扫（第四轮） |
| [BRICK-AUDIT.md](BRICK-AUDIT.md) | 与门锁交互的**全部**代码：交互 / 逻辑 / 砖风险审计 |

## 四、功能清单与判定

| 文档 | 内容 |
|---|---|
| [FEATURE-TRIAGE.md](FEATURE-TRIAGE.md) | 1050 项创意的可行性判定 |
| [FUNCTION-MATRIX.md](FUNCTION-MATRIX.md) | 功能全量核查矩阵（2026-10-17 对抗式） |
| [IDEA-BANK.md](IDEA-BANK.md) | 设计创意库（1050 项） |
| [DEFERRED.md](DEFERRED.md) | 暂缓项清单。**注意**：部分 DFU 相关条目已被 2026-10-26 的实现解决，见 OPEN-ISSUES |
| [ROADMAP-DRAFT.md](ROADMAP-DRAFT.md) | 功能包（Epic）路线图草案 |

## 五、审计记录（历史，按批次）

| 文档 | 范围 |
|---|---|
| [AUDIT-A.md](AUDIT-A.md) | 创意 51–150 |
| [AUDIT-B.md](AUDIT-B.md) | 创意 301–550 |
| [AUDIT-C.md](AUDIT-C.md) | 创意 551–800 |
| [AUDIT-D.md](AUDIT-D.md) | 创意 801–1050 |
| [AUDIT-E.md](AUDIT-E.md) | 创意 201–300 补审 |
| [AUDIT-CODE.md](AUDIT-CODE.md) | 代码本体对抗式审计（第 5 轮，全新独立取证） |
| [AUDIT-DEADCODE.md](AUDIT-DEADCODE.md) | 零引用声明清单（现在是闸门，不是一次性报告） |
| [AUDIT-GAP-CAUSES.md](AUDIT-GAP-CAUSES.md) | 236 个未做/半做项的逐条成因：是难，还是没人做？ |
| [AUDIT-STATIC-SWEEP.md](AUDIT-STATIC-SWEEP.md) | 2026-10-15 四轮地毯式静态销案 |

> ⚠ 这批 AUDIT-* 里的 `file:line` 引用有相当比例已随代码删改漂移。
> `tools/citecheck.js` 会报"行号漂 / 搜不到 / 无此文件"，那是**已知**状态，不是新问题。

## 六、专题方案

| 文档 | 内容 |
|---|---|
| [AUTOOPEN-PLAN.md](AUTOOPEN-PLAN.md) | 靠近自动开锁方案（含验证计划） |
| [FASTUNLOCK-2026-10-17.md](FASTUNLOCK-2026-10-17.md) | 靠近秒开：延迟账本与两端现状 |
| [DESIGN-SPEC.md](DESIGN-SPEC.md) | 界面与交互设计规范 |
| [A11Y-FREQUENCY.md](A11Y-FREQUENCY.md) | 动效频率核查表（882 闪烁安全线, WCAG 2.3.1） |
| [API-VERIFY.md](API-VERIFY.md) | 用过的 Apple API 逐个撞官方文档的记录 |
| [ICONMAP.md](ICONMAP.md) | 图标对照清单（210 个） |
| [SKILLS.md](SKILLS.md) | Skill 应用清单 |

## 七、交接记录

| 文档 | 时间 |
|---|---|
| [HANDOFF.md](HANDOFF.md) | 2026-10-11 |
| [HANDOFF-2026-10-15-UI-SWEEP.md](HANDOFF-2026-10-15-UI-SWEEP.md) | 2026-10-15 UI/交互层对抗式走查 |
| [HANDOFF-2026-10-17.md](HANDOFF-2026-10-17.md) | 2026-10-17 |

---

## 维护规则

1. **新增文档必须在这里登记**，否则等于没写（没人会去 `ls docs/`）。
2. 文档里不要写"已实现"而不给 `file:line` —— `citecheck.js` 会核。
3. 行号会漂。写引用时优先写**符号名**（`LockService.setDefence`），行号作为辅助。
4. 被推翻的决策**不要删**，在原处追加「YYYY-MM-DD 推翻 + 原因」——D-137 就是这么处理的。


---

## 手动工具（不接 CI，按需运行）

2026-10-27 审核补记 (AUDIT-E 6.2)：`tools/` 里有 5 个脚本**从不被 CI 调用**，
且此前在文档里 0 提及 —— 那等于它们会慢慢腐烂而没人知道。
它们是**顾问级工具**（输出线索而非判决），刻意不接 CI（接了会制造噪音、且需要人读结果）。
需要时手动跑：

| 脚本 | 作用 | 什么时候跑 |
|---|---|---|
| `tools/bigfiles.js` | 大文件结构盘点（哪些视图类型、各有哪些分节） | 想了解 24k 行大文件的构成时；`--verbose` 打逐文件清单 |
| `tools/constscan.js` | 全仓符号索引 + 常量/属性零引用扫描 | 怀疑某个常量/属性没人用时 |
| `tools/kotlinlocal.js` | 本地 Kotlin 编译通道（不依赖 Compose，十几秒出结果） | 改了 `android-app/` 的协议/链路层，想不等 CI 先编一遍 |
| `tools/refgraph.js` | 引用图可达性分析，找「只被死代码引用的整片区域」 | 准备「一层层删」时；删完第一轮叶子后再跑一次 |
| `tools/uxaudit.js` | 交互层审核器（44pt 触达 / 8pt 间距 / 对比度 / 动画数量 / reduced-motion） | 改完 UI 后自查；输出的是线索不是判决，需人读 |

**CI 里跑的是 43 道判决型闸门**（见 `.github/workflows/ios.yml`）；
上面这 5 个是**线索型**，接进 CI 只会让红绿失去意义。