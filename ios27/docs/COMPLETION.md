# 完成报告 · ios27

> 2026-10-31 · 全新建屏（不是缝补）

---

## 一、交付了什么

`D:\aapk\ios27\` —— 一份从 0 重做的 iOS 27 App 工程。

| 项 | 数量 | 说明 |
|---|---|---|
| Swift 文件 | **113** | 界面层全部新写 |
| 代码量 | **≈1.12 MB / 21,775 行** | 上一版 1.94 MB（其中大量是注释与重复结构） |
| 目的地（屏幕） | **26** | 5 个 Tab 根 + 21 个子页 |
| 设计组件 | **14** | Panel / Reading / ReadingGrid / FieldRow / Dial / StateDot / StatusLine / ChipRow / PrimaryAction / SecondaryAction / EmptyPanel / BusyRow / LedgerRow / LedgerDayHeader |
| 静态闸门 | **11** | 每道都有正控 |
| 视觉验收截图 | **54 张** | 27 屏 × 明暗双模 |
| 引擎文件 | **66** | 协议/密码学/存储/BLE，从上一版照搬（已验证）+ 依赖补齐 |

---

## 二、设计上到底改了什么（这是重点）

### 2.1 换了隐喻：从「画一扇门」到「读一台仪器」

| | 上一版 | 这一版 |
|---|---|---|
| 隐喻 | 一扇门（门扇/门缝/锁体/推门而入） | 一台仪器（刻度/读数/游标/台账） |
| 为什么 | 那是**画** | 这是**读** —— 刻度必须量到真东西，读数必须来自真协议 |
| 配色 | 暖金 + 奶油底 | 冷石墨 + 冷纸底 + **铜锈绿**（唯一品牌色） |
| 数字 | 各处写法不一 | 一律等宽右对齐（`Reading`），换值不跳宽 |
| 卡片 | 圆角 + 阴影堆 | 面板靠 **0.5pt 蚀刻描边 + 明度差**分层，只有一级阴影 |
| 玻璃 | 卡片上也用 | **内容层永不用玻璃**，只在系统控件（Tab/工具栏/sheet） |
| 动效 | 弹簧到处弹 | 仪表动效：无回弹；进度弧用**真实进度**，失败停在断点 |

### 2.2 signature：刻度盘（Dial）

一圈 **60 格蚀刻刻度** + 一段**真实进度弧** + 中心定宽读数。

- 进度弧走的是**真命令链**：查钥匙(0.18) → 连 BLE(0.46) → 下发 cmd04(0.72) → 回执(1.0)
- 失败时弧停在 **0.72** 并变朱红 —— **不假装成功**
- 进度为 0 时不画轨道（画了会读成"装饰圆"而不是"待触发的仪器"）
- 静止 → 推进 → 成功/失败，四态都有截图

### 2.3 三条反模板纪律

1. 不用暖奶油 + 衬线 + 陶土色（上一版就是）
2. 不用近黑 + 荧光强调色（强调色是**铜锈绿** —— 铜锁氧化的颜色，来自产品材料）
3. 不用细线大报排版（刻度线只出现在**有量**的地方）

---

## 三、验证：怎么证明它真的不一样

### 3.1 十一一道机器闸门（本地可跑，CI 同款）

```
swiftparse  OK — 113 文件语法树无 ERROR（tree-sitter-swift 真解析）
types       OK — 249 顶层类型无重复声明，Engine 无未解析类型引用
swiftcheck  OK — 113 文件括号/字符串/注释平衡
tokens      OK — 113 文件，0 处硬编码颜色/间距/圆角/字号
contrast    OK — 48 条 WCAG 断言（明暗各一套）
glass       OK — 内容层 0 处玻璃；同屏 ≤2
motion      OK — 全部 .animation 带 value，无裸时长
a11y        OK — 图标按钮有 label，无 <44pt 可点区
callsig     OK — 全部组件调用实参顺序符合声明
lineage     OK — 0 处上一版设计系统残留（18 个旧符号）
destmap     OK — 26 个 Dest ↔ 26 个 View 一一对应
```

**每道闸门都做过正控**（故意注入缺陷，确认它会红）：
- `swiftparse`：少一个右括号 → 红
- `types`：同一类型声明两次 → 红
- `contrast`：单位小字 3.22:1 → 红（据此把 inkFaint 从 #8A9098 改到 #61676E）
- `callsig`：`Reading(tint:value:size:)` 顺序错 → 红
- `a11y`：图标按钮无 label → 红

### 3.2 在这一轮里被闸门抓到的**真实编译阻塞**（全部已修）

这些是"本地看着没事、云端编译必红"的那种：

| 缺陷 | 怎么发现的 | 修法 |
|---|---|---|
| `Member` 重复声明 | types 闸门 | UI 投影改名 `MemberCard`，Engine 保留存储模型 |
| `ToneColor` 不存在 | types 闸门 | 在 Engine 里补一份语义词表（Engine 不该 import SwiftUI） |
| `BackupBundle` 重复声明 | types 闸门 | 拆出独立文件，从 BackupKit 删除 |
| `CredPackage`/`AlarmMeta`/`LockArchive`/`StatsKit`/`AutoOpenKit` 缺失 | types 闸门 | 从上一版抽取纯逻辑补进 Engine |
| `AppState` 被塞进 Engine 签名 | types 闸门 | 引入 `EngineHost` 协议，AppModel 实现它 |
| `SettingsGroups`（纯 UI）混进 Engine | types 闸门 | 删除（新 App 不用） |
| `CryptoBox`/`DFUError` 缺失 | types 闸门 | 随 BackupKit 一起补 |
| `swiftparse` 3 处误报 | 人工核对 | 是 grammar 盲区（`if let x = try await` 等），用**换源再解析**处理，不按行豁免 |

### 3.3 视觉验收台（54 张截图 + 1 张总览图）

总览图：`DesignLab/shots/_sheet.png`（27 屏一屏一张，浅色）。

本地没有 Mac/模拟器 ⇒ SwiftUI 渲染不了。但"观感差"必须被看见。

`DesignLab/` 把 `Tokens.swift` **现场解析**成 CSS 变量（不重写颜色），
再用镜像组件渲染每屏，Edge headless 截图。

**能验**：版式/层级/间距/色彩/密度/空态/加载态/失败态/明暗双模。
**不能验**：手势手感、真实液态玻璃折射、PingFang 中文度量（Windows 用雅黑近似）。

---

## 四、页面清单（26 屏）

| Tab | 根 | 子页 |
|---|---|---|
| 门 | DoorScreen（刻度盘） | LockStatus / AddLock（四步配网）/ Gateway（五步）/ SyncTime / Defend（三档） |
| 钥匙 | KeysScreen（凭证台账） | KeyDetail / KeyCreate（四步工坊）/ KeyCalendar / MobileKey / ShareToAndroid |
| 台账 | RecordsScreen（时间轴） | RecordDetail / RecordExport（PNG+CSV+vCard） |
| 家 | HouseholdScreen（成员） | MemberDetail（360）/ MemberCreate（向导）/ MemberArchive |
| 设置 | SettingsScreen | Appearance / Security / Backup / AutoOpen / Hardware / About |

---

## 五、诚实的边界（未验的就是未验）

| 项 | 状态 | 说明 |
|---|---|---|
| **真机编译** | ✅ **CI 已通过** | 本机 Windows 无 Xcode；改用 `xcode-27` 镜像。run [41161655697](https://github.com/monsm/ios-app/actions/runs/41161655697)：闸门 11 道 + 编译全绿 |
| **真机手感** | ⚠️ **未验证** | 刻度盘按压跟手度、进度弧节奏、触觉反馈 |
| **真实玻璃折射** | ⚠️ **未验证** | DesignLab 用 `backdrop-filter` 近似 |
| **动态字体极端值** | ⚠️ **未验证** | 静态只保证字号走令牌；最大字号截断需真机 |
| **Engine ↔ 页面接线** | 🔧 **部分** | 页面里 `TODO(engine)` 标注的字段是 AppModel 种子数据；引擎已可编译并解耦 |
| **横屏 / iPad** | ❌ **不支持** | 锁竖屏（`UISupportedInterfaceOrientations` 只有 Portrait） |

### 未接真数据的部分（页面里都如实标了 `TODO(engine)`）

- 开锁链：现在是相位机（`runUnlockChain`），接 `LockService` 的真 cmd04 链
- 凭证写入：cmd0A/0B/13/14 未下发，页面写"已加入本机台账，待下发"
- 记录读取：cmd16 翻页未接，只装载 `kf_logcache_`
- 配网：`AddLockScreen` 的 7 条写锁帧是逐条留痕的相位机，未真连 BLE
- 备份：`CryptoBox`（PBKDF2+AES-CBC+HMAC）已搬进 Engine，但 UI 侧只做了明文导出
- 布防/校时/网关：`DefendService`/`cmd0E`/`cmd30-35` 已在 Engine 就位，UI 侧未接线

---

## 六、怎么继续

1. ~~先把 CI 跑绿~~ **已完成**（run 41161655697）。三轮迭代修掉了 6 类真编译错误：泛型参数与 `enum T` 撞名、`some View` 上挂 `.fill()`、`Tone` 缺 Hashable、`stale` 未定义、静态 `shared` 非 Sendable、通知回调缺 `host`。
   语言模式暂用 Swift 5（并发问题是告警），下一步按告警清单迁到 Swift 6。
2. **真机跑一遍门页**：刻度盘尺寸、按压跟手度、深色观感。
3. **按 `TODO(engine)` 清单逐条接线**：开锁链 → 凭证下发 → 记录读取 → 配网 → 备份。
4. **每接一条，跑一次 `node Gates/allgates.js`** —— 闸门会挡住回退。