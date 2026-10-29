# 界面重构方案 · HIG 独立审核（Lead 自审）

审核人：Lead（按 `apple-design` skill 的 5 lens）
对象：`docs/界面重构方案.md`（10 节）
依据：`settings.md` / `tab-bars.md` / `toolbars.md` / `designing-for-ios.md` 原文（已读）

---

## Summary

**方向正确**：方案的核心论点「锁能力应在锁的详情页，不在 App 设置」有 HIG 原文直接支持。
**但这不是一份完整的设计方案**：它只做了信息架构（IA），没有做视觉、交互、无障碍。
评级：**Needs work** —— IA 层面 Good，其余三个 lens 是空的。

---

## Critical

**无。** 没有无障碍硬失败、没有平台惯例硬破坏。

---

## Improvements

### High 1 · 无障碍完全缺失

方案 10 节没有一个字提到 Dynamic Type、VoiceOver、触控尺寸、对比度。

**风险点**：`LockDetailView` 要合并 3 个页面（约 450-500 行），在 AX5 字号下会成为一条极长的滚动列表。VoiceOver 用户要划过 30+ 个元素才能到「删除设备」。

> `accessibility.md`: 文本必须随系统字号缩放，布局在最大字号下仍保持层级。

**建议**：
- 身份/状态/能力/高级/危险 五个区块用 `Section` + `header`，VoiceOver 可用「按标题导航」跳转
- 每个自定义行补 `accessibilityLabel`；`LabeledRow` 已有 `.combine`，迁移时不能丢
- 危险区（删除设备）**必须**距其它操作至少一个 Section，不能和「清空密码」相邻

### High 2 · 「锁详情」没有编辑态设计

`LockProfileView` 现在是 **Form 直接可编辑 + 底部「保存档案」按钮**。合并进「锁详情」后，如果整页都可编辑：
- 用户在「状态区」看到的是只读读数，但同一个 Form 里身份区可编辑 —— **心智模型混乱**
- 误触改到昵称没有「取消」

> `entering-data.md`: 数据录入应有明确的提交与取消路径。

**建议**：身份区用 **「编辑」按钮 → 进入编辑 sheet 或编辑模式 → 保存/取消**；状态区永远只读。这是 `LockProfileView` 的现有交互，不要因为合并而丢掉。

### High 3 · 方案只动 IA，可能不是用户要的「重构界面」

方案第七节明确写「不引入新的设计语言」。如果用户说的「重构界面」包含**视觉层面**（排版、色彩、卡片、间距），这份方案交付不了。

**建议**：在方案开头加一句边界声明，并单独出一份「视觉层评估」——或者明确告诉用户「这一版只动结构，不动皮」。

### Medium 1 · 「更多」菜单会成为新的垃圾桶

方案把凭证页的 4 个入口（分组 / 批量 / 工坊 / 月历）都塞进「更多」。

> `toolbars.md › Best practices`: "Add a More menu to contain additional actions. Prioritize less important actions for inclusion in the More menu."

4 项不算多，但「工坊」和「月历」是**目的地的入口**，不是"附加动作"。把页面入口放进 More 菜单，会让它们更难被发现。

**建议**：工坊保留在凭证页现有的显眼位置（`StudioHome` 已有入口）；月历进 More 菜单可以接受（低频）。

### Medium 2 · 协议测试「可见化」的度

方案把协议测试从彩蛋提到「关于页直接可见」。这解决了「找不到」，但带来反向风险：普通用户点进去看到「回声探测 / 附近设备 / KLV 原始值」，会以为是功能坏了。

> `settings.md › Best practices`: "Minimize the number of settings you offer... too many settings can make the experience feel less approachable."

**建议**：关于页放一行「协议测试（开发者工具）」，点进去**先给一段说明**（"这里只发送只读探测命令，不会改动门锁"），再进功能页。保持可见但不诱导。

### Medium 3 · 设置页 5 组 → 6 组，收益要说清

**更正**：现有 `SettingsGroup`（`Core/SettingsGroups.swift:18`）是 **5 组**（开门日常 / 凭证与成员 / 数据与安全 / 外观与辅助 / 帮助与关于），加「全部」chip 共 6 个 chip。

方案要改成 6 组（安全 / **开锁** / 数据 / 外观 / 家人与钥匙 / 关于）—— 是 **5 改 6**，新增的「开锁」组把 `unlockSection`（按住确认 / 误触围栏 / 双击直开 / 失败重试）与 `autoOpenSection` 从「开门日常」里摘出来。

**这个收益是真的**：现在这 5 个交互开关和「门锁」段挤在同一组里，用户要找「双击直开」得先在「开门日常」里翻过整段锁能力。单独成组是对的。

**但方案没写这个理由**，看起来像是重命名。建议补一句。

### Low 1 · 页面标题

「锁详情」的 `navigationTitle` 应该是什么？用锁名（`LockArchive.displayName`）还是「锁详情」？

> `toolbars.md › Titles`: "Write a concise title... under 15 characters."

**建议**：用锁名（用户能确认"我在看哪把锁"），副标题放场所。

---

## Craft notes

**有没有 point of view？** 方案本身没有视觉主张 —— 它是结构方案，这没问题。但它对「这个 App 长什么样」没有回答。

**一个可以成为 signature 的点**：这台 App 的核心对象是**一把锁**。如果「锁详情」能把「这把锁的一生」讲清楚（绑定 → 凭证 → 记录 → 维护），它会比现在的「设置里一堆开关」有性格得多。方案没说这一层。

**克制**：方案主动写了「不做的事」（第七节），这是好的克制。

---

## What works

1. **HIG 依据扎实**：`settings.md › Task-specific options` 的原文是"prefer letting people modify task-specific options without going to your settings area... disconnects it from its context" —— 这句话就是方案的核心论点。
2. **自查诚实**：第八节自己纠正了「17 个 Section」的错误，第十节主动列出合并冲突（电池档案两处编辑）。
3. **边界清晰**：第七节明确「不改功能语义、不删功能、不引入新设计语言」。
4. **不动 Tab 数量**：符合 `tab-bars.md`「fewer tabs」与「tab bar 支持导航不提供动作」。

---

## Platform notes

- **iPad**：`tab-bars.md` 说 iPadOS 上 TabView 会变成顶部 tab bar 或 sidebar（`sidebarAdaptable`）。方案没提 —— 但现状也没用，属于既有债，不是本次引入。
- **iPhone Duo / 折叠**：方案没提。如果目标设备包含折叠屏，`LockDetailView` 的双栏适配需要单独考虑。
- **Liquid Glass**：方案不动材质层，维持现状，OK。

---

## 结论

| Lens | 结论 |
|---|---|
| 1 无障碍 | ✗ 方案未涉及（High） |
| 2 平台惯例 | ✓ 有 HIG 原文支持 |
| 3 视觉/craft | ✗ 方案未涉及（Medium） |
| 4 交互 | ✗ 编辑态未设计（High） |
| 5 内容/文案 | ✗ 未涉及（Low-Medium） |

**建议**：IA 部分可以按方案执行；但实施前必须补 3 件事 ——
1. `LockDetailView` 的无障碍规格（Section 分块 + 危险区隔离）
2. 身份区的编辑/只读分离
3. 明确「本次只动结构、不动视觉」的边界，或者补一份视觉方案
