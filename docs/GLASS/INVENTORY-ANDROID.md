# INVENTORY-ANDROID — Android 界面地毯式清点

> 作者：android-inventory（teammate）· 只读清点，未修改任何 `.kt` / `.swift` / `tools/*.js`
> 唯一产出：本文件 `docs/GLASS/INVENTORY-ANDROID.md`
> 取证面：`android-app/app/src/main/java/com/aapk/kfkey/` 全 9 个 .kt（MainActivity 914 行全读）+ `AndroidManifest.xml` + `res/values/*.xml` + `app/build.gradle.kts`；对照面：`App/Core/Theme.swift`、`App/UI/HomeConsole.swift`、`App/UI/LocksPage.swift`、`App/UI/MePage.swift`、`App/UI/ShareToAndroidView.swift`、`App/UI/FindArrowLayer.swift`；规范面：`ios-glass-design-spec/references/design-spec.md` §0/§1/§3/§4/§5/§6/§7/§8/§11/§13/§14/§15。

## 0. 口径、证据分档与三条勘误

**证据分档**（每行都标）：
- **E1** = 我实际跑了命令并有输出（命令 + 关键输出写在该行）。
- **E2** = 我读了源码，当行内容可复现（`文件:行` 即证据）。
- **E3** = 从别的文档/外部知识转述（必须写出处）。
- 「未读到」= 我没读到对应源码，不猜。

**E1 环境（本轮实测）**：
```
$ java / javac / gradle / kotlinc / adb / swift / swiftc / xcodebuild  -> 全部 NOT FOUND
$ node --version -> v25.2.1
```
⇒ 本仓**没有任何本地编译/渲染通道**能验证 Android UI（与 `tools/kotlinlocal.js:9-10` 注释一致：「只编那 4 个非 UI 文件 … UI 层仍只有 CI 能验」）。

**E1 闸门静默跑过（只读，不写文件）**：
- `node tools/kotlinshadow.js` -> exit 0，**0 个 FAIL**，末行「全部通过」；其中 **A8 共 21 条断言直接把 `MainActivity.kt` 源码当输入**（`tools/kotlinshadow.js:104-164`）。⇒ 改 UI 会**踩到闸门**，见 §6。
- `node tools/uxaudit.js` -> 输出 A 112 处 / B 23 处 / C 5 处 / D 102 处；但 `tools/uxaudit.js:29` 的 `walk('App')` 只收 `.swift` ⇒ **Android 侧 0 条触达/动效/触觉审计覆盖**。

### 0.1 任务卡勘误（三处，必须先纠正再排施工单）

| # | 任务卡说法 | 实测 | 证据 |
|---|---|---|---|
| 勘误-1 | 「没有 BackHandler：浮层打开时返回键不会先收浮层」 | **已经有 BackHandler**，且按「AirTag 层 -> 二级菜单 -> 默认退出」顺序消费返回键 | E2 `MainActivity.kt:9`(import)、`MainActivity.kt:144-152`（含判据 `airTagLayerUp`）；判据与 `MainActivity.kt:332` 的 `airTagShowing` 同表达式 |
| 勘误-2 | 「S3 设置抽屉」 | 手法是**全屏遮罩 + 底部对齐卡片**（不是 BottomSheet，无 sheet 语义、无拖拽、无部分展开态） | E2 `MainActivity.kt:417-458`（`AnimatedVisibility` + `fillMaxSize` + `Arrangement.Bottom`） |
| 勘误-3 | 「Tokens.kt 注释自称与 iOS 逐字相同」 | 注释是**假的**（三个圆角值全错、引用的 iOS 文件已删除、消费点行号过期） | 见 §3.4 逐条 |

### 0.2 文件盘点（E1：逐个 read 取 totalLines）

| 文件 | 行数 | 是否 UI | 证据 |
|---|---|---|---|
| MainActivity.kt | 914 | **是**（全部界面） | E1 read 返回 totalLines=914 |
| SignalArrow.kt | 225 | **是**（@Composable 在 128-184） | E1 |
| KfTheme.kt | 79 | **是**（色板/主题） | E1 |
| Tokens.kt | 36 | **是**（间距/圆角） | E1 |
| Haptics.kt | 39 | 半 UI（触觉） | E1 |
| BleUnlocker.kt | 682 | 否（BLE 链路） | E1 + 域判定见 §6 |
| KfProtocol.kt | 231 | 否（字节层） | E1 |
| AutoOpenKit.kt | 52 | 否（纯函数判据，但被 UI 读常量） | E1 |
| LockStore.kt | 98 | 否（存储 + 二维码解析） | E1 |

**全部 @Composable 清单（12 个，逐个核实真实名字与职责）**：

| # | 函数 | 文件:行 | 职责 |
|---|---|---|---|
| 1 | `KfApp(unlocker)` | MainActivity.kt:107-516 | 根：20+ 个 remember 状态、权限、生命周期、自动开锁状态机、**四层界面的装配** |
| 2 | `Header(lock: LockInfo?)` | MainActivity.kt:518-540 | 锁名 + MAC（空态时显示 App 名） |
| 3 | `UnlockDial(busy, onClick)` | MainActivity.kt:543-651 | 自绘开锁圆盘（300dp 柔光 + 232dp 金属圆盘） |
| 4 | `EmptyState(onScan)` | MainActivity.kt:653-681 | 未绑定空态（自绘二维码角框 + 文案 + 主按钮） |
| 5 | `ProximityCard(on,onToggle,onRescan,onUnbind,onClose)` | MainActivity.kt:683-760 | 设置抽屉里的唯一卡片 |
| 6 | `GearButton(modifier,onClick)` | MainActivity.kt:763-793 | 右下齿轮入口（56dp 圆 + 自绘 8 齿轮） |
| 7 | `PillButton(text,onClick)` | MainActivity.kt:795-807 | 胶囊主按钮 |
| 8 | `AirTagLayer(12 参数)` | MainActivity.kt:810-875 | 全屏绿精确查找层 |
| 9 | `CircleIconButton(label,onClick)` | MainActivity.kt:877-889 | 52dp 圆形文字按钮（✕ / 🔊） |
| 10 | `ProximityBeep(fill,soundOn,foreground)` | MainActivity.kt:892-914 | **无 UI**：ToneGenerator 循环（LaunchedEffect） |
| 11 | `SignalArrow(11 参数)` | SignalArrow.kt:128-184 | 自绘信号箭头（含 3D 视差 + 无限摆动） |
| 12 | `KfTheme(dark, content)` | KfTheme.kt:72-79 | `CompositionLocalProvider` 下发深浅双档色板 |

> 注：任务卡给的已知行号 107/518/543/653/683/763/795/810/877/892 **全部正确**（E2）。另外 SignalArrow.kt 与 KfTheme.kt 各还有 1 个 @Composable，任务卡未列出。

---

## §1 屏与层总表

分层模型（自下而上，按 Compose 兄弟节点绘制顺序，后面的盖前面的）：根画布 -> S2/S1 -> 齿轮 -> S3 抽屉 -> D1 Dialog（独立窗口） -> S4 AirTag 层。**S4 的绘制在 S3 之后**（`MainActivity.kt:493` > `:417`），见 AND-S-005 的可疑点。

| 编号 | 屏/层 | 触发条件 | 文件:行 | 承载控件 | 关闭方式 | 可返回？ | 可疑度(0-3) |
|---|---|---|---|---|---|---|---|
| AND-S-001 | 应用根画布（常驻底层） | 进程存活即存在 | `MainActivity.kt:338-342`（`Box.fillMaxSize().background(Brush.verticalGradient)`）；渐变两端 `KfTheme.kt:37-38` `#0A0C10 -> #141A22` | 无控件，仅纵向渐变底 | 不关 | 否 | **2**：❌ 规范 G1 / §14-3 —— 页面底必须 `#000000`，且「黑色是画布，不是背景色」（§0 总则 1）；此处是**渐变底** |
| AND-S-002 | **S1 空态屏**（未绑定） | `lock == null` | 分支 `MainActivity.kt:351-352`；组件 `MainActivity.kt:653-681` | `Header`(显示 App 名) + `EmptyState`(自绘二维码角框/文案/`PillButton`) | 无（只能扫码离开） | 否（`BackHandler` 未覆盖此屏 ⇒ 返回键直接 finish App，`MainActivity.kt:150`） | **2**：空态屏**不渲染 status 文本** ⇒ 扫码失败/权限被拒的提示静默丢失（见 AND-S-008） |
| AND-S-003 | **S2 主解锁屏**（已绑定） | `lock != null` | 分支 `MainActivity.kt:353-405` | `Header`(:349) + `SignalArrow`(:357-370, sizeDp=208) + `UnlockDial`(:371) + 状态行(:373-383) + 信号提示行(:385-394) + 调试 trace 行(:395-404) + `GearButton`(:411-413) | 无 | 否（返回键 finish） | **3**：①**单击即开**（:573）无蓄力/无二次确认；②把 dBm 裸露给用户（:388-389）；③全部文本无 semantics（全仓仅 SignalArrow.kt:174 有） |
| AND-S-004 | **S3 设置抽屉** | `showSettings == true && lock != null` | `MainActivity.kt:417-458`；卡片 `MainActivity.kt:683-760` | 全屏遮罩(`Color(0xB3050709)`=70% 不透明, :425) + `ProximityCard`(Switch/重新扫码/解绑/完成) | 点遮罩(:427)、点「完成」(:737)、返回键(:150-152) | **是**（返回键先收它） | **3**：①不是玻璃浮层而是实色暗遮罩（§6.3 要求浮层=玻璃+0.5pt 描边）；②**点卡片任何非可点区域 = 点遮罩 = 关闭抽屉**（:422-431 的 clickable 挂在全屏 Column，卡片本体无 pointer 输入，推断）；③解绑无二次确认（:444-453） |
| AND-S-005 | **S4 AirTag 精确查找层** | `proximity && rssi != null && !airTagDismissed`（:332） | `MainActivity.kt:493-515`；组件 `MainActivity.kt:810-875` | 纯色绿全屏 + 标题区 + `SignalArrow`(sizeDp=300) + 距离/方向 + `CircleIconButton` x2 + `ProximityBeep` | 点 ✕(:867)、返回键(:150-152) | **是**（返回键优先收它） | **3**：①**纯色全屏底**（§14-24 精神：全屏彩色底必须是亮头+暗板两层渐变）；②✕ / 🔊 / 🔇 是 **emoji 当图标**（§14-18 明令禁止）；③**只要有第一帧 RSSI 就自动盖住主界面**（:332），用户想手动点圆盘会先被这层挡 |
| AND-S-006 | **D1 换绑/覆盖确认弹窗** | `pending != null`（扫码时已有绑定，:214） | `MainActivity.kt:461-488`（material3 `AlertDialog`） | 标题 + 正文 + `TextButton` x2（覆盖/换绑、取消） | 取消(:485)、点外部(`onDismissRequest`:464)、确认后自动关 | 是（Dialog 窗口自己消费返回键，E3：Compose Dialog 默认行为） | **1**：功能正确，但外观是 material3 默认（`containerColor=colors.surface` 只换了底色，:465-467），脱离设计体系 |
| AND-S-007 | **S5 系统扫码页**（zxing） | `launchScan()`（:218-226） | 外部 Activity：`com.journeyapps.barcodescanner`（依赖 `app/build.gradle.kts:124`）；调用点 `MainActivity.kt:202-216` | zxing 自带取景页；仅 4 个可配项：格式 QR / 提示语「对准 iOS 上的钥匙二维码」/ 关闭蜂鸣 / 不锁方向（:221-224） | 系统返回 | 是 | **2**：全屏取景页的底色/文案样式**不在本仓**（未读到，不可改）；能改的只有 :222 一句 prompt |
| AND-S-008 | 权限弹窗与「静默提示」通道 | `LaunchedEffect(Unit)` 首次组合即申请三项权限（:173-180） | `MainActivity.kt:161-180`；文案落在 `say()`（:154-157） | 系统权限弹窗（非自绘） | 系统 | 是 | **2**：被拒后的提示写进 status，但 status **只在 S2 渲染**（:373-383）；在 S1 上用户什么也看不到 —— 空态无出路 |
| AND-S-009 | 靠近提示音（无视觉层） | `soundOn && level>=0 && foreground`（:901-902） | `MainActivity.kt:892-914` | `ToneGenerator`，TONE_PROP_BEEP 110ms，周期 240/420/700/1100ms 四档（:904） | 关开关 / 退后台 / level<0 | — | **1**：与 §11.4 触感/听觉体系无耦合，但是独立通道，改造时要决定它去留 |

---

## §2 每屏控件逐条

**口径（硬要求）**：iOS 最小触达 = **44pt**（`App/Core/Theme.swift:148` `XHit.min = 44`）；Android 最小触达 = **48dp**（Material/无障碍口径，E3：`tools/uxaudit.js:16,63,109` 的判据注释）。**两者不合并成一个数**，下表 Android 列一律 dp，注明 iOS 值时写 pt。
「触达」栏：加 `近似` 的是**按 Compose 默认行高 1.2x 字号推算**（E3 推算，未渲染验证），不加的是代码里写死的 dp。

### 2.1 S1 空态屏（AND-S-002）

| 编号 | 屏 | 控件 | 文件:行 | 类型 | 作用 | 触达尺寸(dp) | 触觉 | 现状规格 | 规范 §7 对应 | 差距 |
|---|---|---|---|---|---|---|---|---|---|---|
| AND-C-001 | S1 | App 名标题「离线锁钥匙」 | `MainActivity.kt:522-528`（`text = lock?.name ?: "离线锁钥匙"`） | 文本 | 空态时当标题 | 不可点 | 无 | 22sp / Light / letterSpacing 1sp / 居中 / `colors.ink` | §7.1 LargeTitleHeader（30 Bold / -0.4 字距 / 左边距 29pt） | 字号小 8sp、字重差 2 档（Light vs Bold）、**居中 vs 左对齐**、字距符号相反 |
| AND-C-002 | S1 | 二维码角框 | `MainActivity.kt:658-670` | 自绘 Canvas | 视觉锚点（「这里要扫」） | 不可点 | 无 | 120dp 方框，4 角各 2 条线，线宽 3dp、臂长 26dp、`accent@0.85`（:659-661） | §7.17 EmptyState（图标 28pt） | 尺寸 120dp vs 28pt；规范要求「图标」而这里是自绘框；§6.4.1 I3「没素材用单色占位」——自绘矢量线可接受 |
| AND-C-003 | S1 | 空态标题「还没有绑定门锁」 | `MainActivity.kt:672` | 文本 | 说明状态 | 不可点 | 无 | 20sp / Light / `colors.ink` | §7.17（标题 14 Semibold）+ §12「空态标题说原因不说状态」 | **文案违规**：还没有绑定门锁 是状态不是原因（规范例句 No Sleep Data）；字号大 6sp、字重 Light |
| AND-C-004 | S1 | 空态说明（两行） | `MainActivity.kt:674-677` | 文本 | 告诉用户去哪生成码 | 不可点 | 无 | 13sp / 行高 20sp / 居中 / `colors.inkSub` | §7.17（说明 12 Regular / 居中） | 字号 +1；颜色用 inkSub 而规范是 textTertiary |
| AND-C-005 | S1 | 主按钮「扫码添加门锁」 | `MainActivity.kt:679` -> `PillButton` at `:796-807` | 自绘（Box+clip+clickable） | 唯一出路 | 宽=文字+56dp，**高约 46dp**（15sp 行高 18 + vertical 14x2） | **无** | `RoundedCornerShape(50)`（固定 50dp，非 rPill 999）/ 底 `colors.accent` / 字 `onAccent` 15sp Medium / padding h28 v14 | §7.0.6 主按钮（48pt 高 / 白底黑字 / r999）；§7.20.3 次按钮 32pt | **触达 46dp < 48dp**；圆角令牌写死 50 而非 999；底色用 accent 而规范主按钮是白底黑字（应用体内不许白卡 ⇒ 需规范侧裁定）；**无触觉**（对照 iOS 同位置 `XHaptics.tick`，`HomeConsole.swift:265`） |
| AND-C-006 | S1 | 权限被拒提示 | `MainActivity.kt:166-172`（`say(...)`） | 文本（**不渲染**） | 解释缺哪项权限 | — | — | 写进 status，但 S1 无渲染点 | §7.20.3 ErrorState（图标+标题+说明+重试按钮） | **完全缺失**：S1 上用户看不到这句（E2 对照 :373-405 只在 else 分支内） |

### 2.2 S2 主解锁屏（AND-S-003）

| 编号 | 屏 | 控件 | 文件:行 | 类型 | 作用 | 触达尺寸(dp) | 触觉 | 现状规格 | 规范 §7 对应 | 差距 |
|---|---|---|---|---|---|---|---|---|---|---|
| AND-C-007 | S2 | 锁名 | `MainActivity.kt:522-528` | 文本 | 身份 | 不可点 | 无 | 26sp / Light / 字距 1sp / 居中 | §7.1（30 Bold / -0.4 / 左 29pt） | 字重 Light、**正字距**（规范是负字距） |
| AND-C-008 | S2 | MAC 文本 | `MainActivity.kt:531-537` | 文本 | 便于核对设备 | 不可点 | 无 | 12sp 等宽 / 字距 1.5sp / `inkSub@0.75` | §4.2 footnote 12 / §7.16 单位排版 | 对比度 **3.83:1**（E1 计算，`inkSub@0.75 on surface #161C24`）< 4.5 ⇒ 不合格（§13.2） |
| AND-C-009 | S2 | 信号箭头 SignalArrow | `MainActivity.kt:357-370`（参数 sizeDp=208 / okColor=colors.ok / outlineColor=colors.ink） | 自绘 Canvas + graphicsLayer | 找方向 | 208dp（**不可点**） | 无 | 见 AND-A-005 | 规范无对应组件（借用 FindMy 外形）；最近似 §7.8 末条自检「渐变+辉光+零投影」 | 含**无限摆动**与 **3D 视差**，命中 §11.2 两条禁止项（详见 AND-A-005） |
| AND-C-010 | S2 | **开锁圆盘 UnlockDial** | `MainActivity.kt:371` -> `:543-651` | 自绘 Canvas x2 | **唯一主操作** | 232dp 可达圆（:570）／300dp 柔光不可点 | **仅结果触觉**（ok/fail，在 :197，不在按下时） | 见 AND-A-001 | §7.8 Ring 形态 1（缺口大弧 / 线宽 42pt / 18pt 游标） | ①**单击触发**（:573 clickable -> onClick），iOS 是**按住 1.05s**（`HomeConsole.swift:96,480`）；②按下无触觉（iOS `beginPress` 里 `XHaptics.tick`，`HomeConsole.swift:788`）；③无「已开锁/失败」图标态（iOS `centerGlyph` 四态，`HomeConsole.swift:542-549`） |
| AND-C-011 | S2 | 状态行 | `MainActivity.kt:373-383` | 文本 | 结果反馈 | 不可点 | 无 | 15sp / 居中 / 三档色：bad->`colors.bad`、含「成功」或「已开锁」->`colors.ok`、否则 `inkSub`（:375-380） | §7.20.3 ErrorState（15 Semibold 标题 + 12 说明 + 32pt 按钮） | 无图标、无「怎么修」的说明、无重试入口；**颜色靠 contains("成功") 字符串判定**（:378）——改文案即改配色语义 |
| AND-C-012 | S2 | 信号提示行 | `MainActivity.kt:385-394` | 文本 | 距离/武装状态 | 不可点 | 无 | 12sp 等宽 / `inkSub@0.7` / 文案含原始 dBm（:388-389） | §4.2 footnote 12 / §12 文案规范 | 对比度 **3.74:1**（E1，`inkSub@0.7 on bgTop`）< 4.5；**把 dBm 暴露给普通用户**（iOS 只在 DevicePage 明细里给，`DevicePage.swift:124,317`） |
| AND-C-013 | S2 | 调试 trace 行 | `MainActivity.kt:395-404` | 文本 | 排障留痕 | 不可点 | 无 | 11sp 等宽 / `inkSub@0.55`；只在失败时非空（:194） | §14-11「11pt 以下禁止」 | 11sp 处在**禁用边界**；对比度 **2.73:1**（E1）远低于 4.5 —— §14-12「30% 白承载信息」的同类问题 |
| AND-C-014 | S2 | 齿轮入口 | `MainActivity.kt:411-413` `align(BottomEnd).padding(24dp)` -> `:763-793` | 自绘 Canvas | 打开 S3 | **56dp** 圆（:768）✓ >=48dp | **无** | 底 `surface@0.92`（:770）；Canvas 30dp 内 8 齿；线宽/半径写的是**裸像素** `3.5f / 2.5f / 4f / 5f / 7.5f`（:784-790）而非 dp.toPx() | §7.15 CircularChevronButton（26pt 圆 + chevron / 触达 44pt） | ①芯片级问题：**裸 px 在不同密度上粗细不一致**（3x 屏上 3.5px 约 1.17dp）；②齿轮 = 纯色描边环，触 §14-9 精神（环必须渐变/分色）；③**无 contentDescription**（TalkBack 读不出）；④无触觉 |
| AND-C-015 | S2 | 状态色文字「信号已满…马上自动开」 | `MainActivity.kt:388` | 文本 | 告知将自动开 | 不可点 | 无 | 与 AND-C-012 同一样式 | §13.3「不靠颜色单独表意」 | 靠颜色 + 文案双通道，此项合规；但「马上自动开」与真实闸门（回差/闩锁/冷却，`AutoOpenKit.kt:32-51`）不完全等价，属文案过度承诺 |

### 2.3 S3 设置抽屉（AND-S-004）

| 编号 | 屏 | 控件 | 文件:行 | 类型 | 作用 | 触达尺寸(dp) | 触觉 | 现状规格 | 规范 §7 对应 | 差距 |
|---|---|---|---|---|---|---|---|---|---|---|
| AND-C-016 | S3 | 全屏遮罩 | `MainActivity.kt:422-431` | 自绘 Box | 点击关闭 / 压暗底层 | 全屏 | 无 | `Color(0xB3050709)`（A=179/255 约 70.2%）纯色，无模糊、无描边；clickable + indication = null（:427） | §6.2 玻璃配方（`blur(24px) saturate(1.6)` + 0.5pt 白描边）、§6.3「浮层 = 玻璃 + 0.5pt 描边，禁止实色+投影」 | **违反 §6.3**：实色暗遮罩，非玻璃；无 backdrop blur（Compose 需 Modifier.blur 或自绘取样，本仓 0 处 .blur，E1 grep） |
| AND-C-017 | S3 | 卡片容器 | `MainActivity.kt:693-699` | 自绘（clip+background） | 承载设置项 | 整卡可穿透点击（见 §1 AND-S-004 ②） | 无 | `RoundedCornerShape(KfTokens.Radius.card=22dp)`（:696）/ 底 `colors.surface` / padding 16dp（:698）/ **无描边、无投影** | §5.2 rCard=24、§3.1 surface=#1C1C1E、G2「零投影」 | 半径 22 vs 24（差 2）；底色 #161C24 vs #1C1C1E；零投影 ✓ 合规 |
| AND-C-018 | S3 | 标题「靠近自动开锁」 | `MainActivity.kt:702` | 文本 | 功能名 | 不可点 | 无 | 15sp / `colors.ink` | §4.2 headline 16 Semibold | 少 1sp、字重未设（默认 Regular） |
| AND-C-019 | S3 | 说明两段（含阈值数字） | `MainActivity.kt:706-709`、`:711-715` | 文本 | 解释闸门 | 不可点 | 无 | 12sp / 行高 17sp / 第二段 `inkSub@0.75`；数字取自 `AutoOpenKit.BASE` / `disarmThreshold()`（**动态**） | §4.2 footnote 12 / §12 文案 | ✓ 数值动态取自常量（:704-705 注释明确「写死数字…就变成假话」）——**这是全仓最好的一处规范实践**；但 `inkSub@0.75 on surface` = **3.83:1**（E1）不合格 |
| AND-C-020 | S3 | 靠近开关 Switch | `MainActivity.kt:717-728` | material3 | 开/关自动开锁 | Switch 本体：默认 M3 尺寸约 52x32，M3 自带 48dp 最小触达（E3：Material3 组件默认 minimumInteractiveComponentSize，本仓未覆写） | **无** | 自定义 5 个颜色：`checkedThumb=bgTop`、`checkedTrack=accent`、`uncheckedThumb=inkSub`、`uncheckedTrack=inkSub@0.30`、`uncheckedBorder=inkSub@0.45`（:720-727） | §7 无 Switch 组件 | ①未使用 LocalKfColors 以外的 M3 主题（全仓 0 处 MaterialTheme，E1 grep 仅 KfTheme.kt:18 注释）⇒ 这个 Switch 是「半 M3 半自绘」；②无触觉（iOS 对应 XToggle 有 XHaptics，E3：`MePage.swift:227` 入口 + 全仓 51 处 Toggle） |
| AND-C-021 | S3 | 「门锁设置」小标签 | `MainActivity.kt:731` | 文本 | 分组标签 | 不可点 | 无 | 12sp / `inkSub@0.60` | §7.11 SectionHeaderLink 14 Regular textSecondary | 对比度 **2.91:1**（E1，`inkSub@0.6 on surface`）不合格 |
| AND-C-022 | S3 | 「完成」 | `MainActivity.kt:732-738` | 文本 + clickable | 关闭抽屉 | padding v10 h12 ⇒ **高约 36dp** | 无 | 13sp / `accent@0.9`；**注释声称「用 padding 把触达撑到 44dp 以上」（:736）** | §7.0.4 CloseButton（视觉 36pt / **命中 44pt**） | ❌ **注释与实现不符**：13sp 行高约 16 + 20 = 36dp，达不到 44pt，更达不到 Android 48dp；且 accent@0.9 在浅色档会掉对比度 |
| AND-C-023 | S3 | 「重新扫码绑定」 | `MainActivity.kt:742-749` | 文本 + clickable | 重扫二维码 | padding v6 ⇒ **高约 28dp** | 无 | 13sp / `accent@0.9`；与「解绑」间距 `spacedBy(20dp)`（:741） | §7.11（14 Regular / 行内 44pt 命中） | **触达 28dp**，远低于 48dp（iOS 也低于 44pt）；无 indication 抑制 ⇒ 默认 ripple |
| AND-C-024 | S3 | 「解绑」 | `MainActivity.kt:750-757` | 文本 + clickable | 清本机绑定 | padding v6 ⇒ **高约 28dp** | 无 | 13sp / `colors.inkSub`（**无危险色**） | §7.20.3 危险动作应有语义色 + 确认 | ①**无二次确认直接执行**（:444-453）；②用中性灰而非 bad 色；③iOS 同一动作有 confirmationDialog「解除绑定？」+ 不可撤销说明（`LocksPage.swift:142-152`） |
| AND-C-025 | S3 | 抽屉进出动画 | `MainActivity.kt:419-420` | AnimatedVisibility | 转场 | — | — | enter fadeIn(160ms)+slideInVertically(220ms){it/3}；exit fadeOut(140ms)+slideOutVertically(200ms){it/3} | §11.1「Sheet 弹出 .spring 0.42/0.88」 | 曲线族不同（tween vs spring）；**只滑 1/3 高度**，规范无此形态；时长 220ms 在 §11.2 的 1.2s 上限内 ✓ |

### 2.4 S4 AirTag 精确查找层（AND-S-005）

| 编号 | 屏 | 控件 | 文件:行 | 类型 | 作用 | 触达尺寸(dp) | 触觉 | 现状规格 | 规范 §7 对应 | 差距 |
|---|---|---|---|---|---|---|---|---|---|---|
| AND-C-026 | S4 | 全屏底色 | `MainActivity.kt:833-840` | 自绘 Box | 定性「绿=可开」 | — | — | **纯色**：`#0B6B3A`（未武装）/ `#0E7A42`（武装）；注释记录 Q21 为过 WCAG AA 从 #1CC964/#12B24A 压暗（:836-838） | §3.5 / §7.14（全屏彩色底必须是 #015500 亮头 + #022803 暗板**两层** + 渐变） | ❌ **单层纯色**，命中 §14-24 的同类问题；全 App 唯一允许的彩色底是 sports 且必须两层 |
| AND-C-027 | S4 | 「正在查找」 | `MainActivity.kt:843` | 文本 | 状态 | 不可点 | 无 | 15sp Medium / White@0.85；padding(start=28, top=56)（:842） | §7.1 LargeTitleHeader（上留白 8 / 左 29pt） | 上留白 56dp 写死，**未用 WindowInsets/安全区**（全仓 grep WindowInsets = 0，E1）⇒ 刘海/挖孔机型会撞 |
| AND-C-028 | S4 | 锁名大字 | `MainActivity.kt:845` | 文本 | 身份 | 不可点 | 无 | 30sp Bold / 纯白；间距 2dp（:844） | §4.2 largeTitle 30 Bold ✓ | 字号字重对齐 ✓（全仓唯一一处字阶对上的） |
| AND-C-029 | S4 | 中央箭头 | `MainActivity.kt:848-859`（sizeDp=300） | 自绘 Canvas | 找方向 | 300dp（不可点） | 无 | 同 AND-A-005；**此处用默认 okColor = KfDarkColors.ok**（`SignalArrow.kt:140`）而 S2 传的是主题色（:360） | §7.12 AmbientGlow / §13.4 深色 | ①默认参数把暗色档写死 ⇒ 浅色档下 S4 的箭头色不受主题控制（S4 底是绿，问题被掩盖，但仍是隐患）；②无限摆动 + 3D 视差同 AND-A-005 |
| AND-C-030 | S4 | 距离大字 | `MainActivity.kt:862`；换算 `SignalArrow.kt:84-88` | 文本 | 粗估距离 | 不可点 | 无 | 34sp Bold 白；文案「N 厘米 / N.N 米 / 测距中…」（:828-832） | §4.2 display 36 Bold / §7.16 单位排版 | ①**与 iOS 立场冲突**：iOS 明确「距离…显示很近/近/远，**不显示米数**」（`FindArrowLayer.swift:13`），Android 显示到 0.1 米（:831）；②单位与数字之间无空格（§12 要求空一格） |
| AND-C-031 | S4 | 方向文字 | `MainActivity.kt:863`；判据 `SignalArrow.kt:91-92` | 文本 | 前/左前/右前 | 不可点 | 无 | 26sp SemiBold 白 | §4.2 title2 19 Bold | 字号大 7sp；§12 未定义方位文案 ✓ |
| AND-C-032 | S4 | ✕ 关闭按钮 | `MainActivity.kt:866-868` -> `:877-889` | 自绘 + **emoji 文本** | 收起本层 | **52dp** ✓ | 无 | 52dp 圆 / White@0.22 底 / 字 20sp / clickable 无 indication | §7.0.4 CloseButton（视觉 36pt / 命中 44pt / xmark 图标） | ❌ **emoji「✕」当图标**（§14-18）；视觉 52dp > 36pt 建议值；无 xmark 矢量 |
| AND-C-033 | S4 | 🔊/🔇 提示音开关 | `MainActivity.kt:870-872` | 自绘 + **emoji 文本** | 开关蜂鸣 | **52dp** ✓ | 无 | 同 AND-C-032，文案 `if (soundOn) "🔊" else "🔇"`（:871） | §10 图标系统（SF Symbols / 单色矢量） | ❌ **emoji 当图标**（§14-18）；语义上还应是 Toggle 而非两态字符串 |
| AND-C-034 | S4 | 蜂鸣 | `MainActivity.kt:874, 892-914` | 无 UI | 找锁提示音 | — | — | level 由 fill 四档（:894-900），周期 240/420/700/1100ms（:904） | §11.4 未定义声音 | 规范无对应；与 §11.2「禁止渐变循环流动」不同域，不违规 |
| AND-C-035 | S4 | 层进出动画 | `MainActivity.kt:495-496` | AnimatedVisibility | 转场 | — | — | enter fadeIn(180)+slideInVertically(260){it}；exit fadeOut(150)+slideOutVertically(220){it}（全高滑动） | §11.1 Sheet 弹出 spring 0.42/0.88 | 曲线族不同；全高上滑 + fade 更接近 iOS 模态，可接受 |

### 2.5 D1 确认弹窗（AND-S-006）

| 编号 | 屏 | 控件 | 文件:行 | 类型 | 作用 | 触达尺寸(dp) | 触觉 | 现状规格 | 规范 §7 对应 | 差距 |
|---|---|---|---|---|---|---|---|---|---|---|
| AND-C-036 | D1 | 标题 | `MainActivity.kt:468` | material3 Text | 问句 | — | 无 | 默认 titleLarge（E3：M3 默认 22sp）；颜色 `colors.ink`（:466）；`FontWeight.Medium` | §4.2 title2 19 Bold | 字号/字重与体系不一致（未指定 fontSize） |
| AND-C-037 | D1 | 正文（两种文案分支） | `MainActivity.kt:469-475` | material3 Text | 解释后果 | — | 无 | 默认 bodyMedium；颜色 `colors.inkSub`（:467）；same 分支与换绑分支文案不同（:471-474） | §12 文案规范 | ✓ 文案质量好（说清「原来那把锁要重新扫码」）；❌ 占位符用硬换行（:472），大字号下会挤 |
| AND-C-038 | D1 | 确认按钮（覆盖/换绑） | `MainActivity.kt:477-483` | material3 TextButton | 执行 | M3 TextButton 默认 48dp 高 x24dp 内边距（E3） | 无 | `color = colors.accent`；文案随分支变（:482） | §7.20.3 危险动作 | 覆盖一把能开门的钥匙属**危险动作**，应为 destructive 色（`colors.bad`）而非 accent |
| AND-C-039 | D1 | 取消按钮 | `MainActivity.kt:484-486` | material3 TextButton | 放弃 | 同上 | 无 | `color = colors.inkSub` | — | ✓ 合理 |

### 2.6 S5 系统扫码页（AND-S-007）与全局

| 编号 | 屏 | 控件 | 文件:行 | 类型 | 作用 | 触达尺寸(dp) | 触觉 | 现状规格 | 规范 §7 对应 | 差距 |
|---|---|---|---|---|---|---|---|---|---|---|
| AND-C-040 | S5 | 取景提示语 | `MainActivity.kt:222` `.setPrompt("对准 iOS 上的钥匙二维码")` | 外部页内文本 | 引导 | 外部页 | 无 | zxing 默认样式 + 本仓一句 prompt | §12 文案规范 | ✓ 文案合格（动词 + 对象）；❌ 外部页底色/字体**不可控**（未读到源码，属第三方 AAR） |
| AND-C-041 | S5 | 蜂鸣/方向 | `MainActivity.kt:223-224` `.setBeepEnabled(false)` `.setOrientationLocked(false)` | 配置 | — | — | — | 不响、不锁方向 | — | 与 `AndroidManifest.xml:27` `screenOrientation="portrait"` 冲突：Activity 锁竖屏，扫码页却允许旋转（未验证实际表现，**标未读到**） |
| AND-C-042 | 全局 | 系统栏配色 | `res/values/themes.xml:4-8` | XML 主题 | 避免启动白闪 | — | — | windowBackground/statusBar/navigationBar = #0A0C10；windowLightStatusBar=false | §7.19 StatusBar（内容一律白色 / 安全区由系统给） | 底色 #0A0C10 vs 规范 #000000；无 edge-to-edge 适配（`build.gradle.kts:60` 注释：targetSdk 刻意停 34） |
| AND-C-043 | 全局 | 线程/安全区 | 全仓 | — | — | — | — | WindowInsets/statusBars/systemBars 命中 **0 次**（E1 grep） | §13.6 / §7.19「不要手写 54pt」 | ❌ 全靠 `MainActivity.kt:346` 的 `padding(horizontal=24, vertical=28)` 硬边距 ⇒ 有状态栏机型顶部会压字 |
| AND-C-044 | 全局 | 无障碍语义 | 全仓 | — | — | — | — | semantics/contentDescription 命中 **3 次，全在 SignalArrow.kt:33,34,174**（E1 grep） | §13.5 VoiceOver（每个可操作元素都要标签） | ❌ 圆盘/齿轮/两个圆形按钮/三个文本按钮**全部无标签**（TalkBack 只能读文本内容，圆盘完全无内容 ⇒ 不可用） |
| AND-C-045 | 全局 | 触觉覆盖 | `Haptics.kt:18-38`；唯一调用点 `MainActivity.kt:197` | 触觉 | 结果反馈 | — | 2 档（ok=12ms/90、fail=35ms/180，`Haptics.kt:21,24`） | ✓ 有 hasVibrator/runCatching 兜底（:34-37） | §11.4 触感四事件表 | ❌ **全 App 只有「开锁结果」一处触觉**；按下/切换/翻页/弹层全无（iOS 有 102 处调用点，E1：uxaudit.js D 段输出） |

**§2 分项计数**：控件/规格条目 45 条（AND-C-001…045）。触达尺寸不达标：**4 条**（AND-C-005 46dp、AND-C-022 36dp、AND-C-023 28dp、AND-C-024 28dp）；emoji 当图标：**2 条**（AND-C-032、AND-C-033）；对比度不达标：**5 条**（AND-C-008 3.83、AND-C-012 3.74、AND-C-013 2.73、AND-C-019 3.83、AND-C-021 2.91）；无无障碍语义：**全局**。

---

## §3 令牌对照表

### 3.1 KfColors 逐字段（9 字段 x 深浅双档）

规范基准：§3.1 应用体（canvas #000000 / surface #1C1C1E / surfaceRaised #24242A / separator rgba(255,255,255,0.08)）、§3.3 文本（textPrimary #FFFFFF / textSecondary #8D8D93 / textTertiary #6A6A6E）、§3.4 强调色（语义绑定）、§13.4「应用体只做深色，不提供 App 内明暗切换」。
「差多少」列：Δ 为 RGB 通道差（我按 #RRGGBB 逐通道相减的最大值，E1 手算）+ 对比度（E1：node 实算 WCAG）。

| 编号 | 令牌 | 现状值（暗） | 规范对应 | 差多少（暗） | 现状值（浅） | 规范对应（浅） | 差多少（浅） | 谁在消费（文件:行） |
|---|---|---|---|---|---|---|---|---|
| AND-T-001 | bgTop | #0A0C10（`KfTheme.kt:37`） | canvas #000000（§3.1） | Δ=(10,12,16)，非纯黑；**违反 §14-3** | #F7F5F1（:55） | **规范不允许浅色应用体**（§13.4） | 概念性冲突 | `MainActivity.kt:341`（渐变起点）、`:721`（Switch 选中拇指色）、`:790`（齿轮轴心） |
| AND-T-002 | bgBottom | #141A22（:38） | —（规范无二段底色，只有单一 #000000） | 整条纵向渐变都无规范依据 | #EDE9E1（:56） | 同上 | 同上 | `MainActivity.kt:341`（渐变终点） |
| AND-T-003 | surface | #161C24（:39） | surface #1C1C1E（§3.1，实测 #1E1E20） | Δ=(6,2,6)；偏冷偏暗 | #FFFFFF（:57） | 应用体卡片**禁止**白（§0 总则 4 / §14-1） | ❌ 方向性错误 | `MainActivity.kt:465`（Dialog 底）、`:697`（卡片底）、`:770`（齿轮底 @0.92） |
| AND-T-004 | ink | #F3F6FA（:40） | textPrimary #FFFFFF（§3.3） | Δ=(12,9,5)；对比 #0A0C10 = **18.06:1**（E1） | #17140F（:58） | shellTextPrimary #1C1C1E（仅展示壳） | 应用体不该有此档 | `MainActivity.kt:360`（箭头描边）、`:466`、`:524`、`:672`、`:702` |
| AND-T-005 | inkSub | #8B96A8（:41） | textSecondary #8D8D93（§3.3，on #000 = 6.36） | Δ=(2,9,21)（蓝向偏移）；对比 bgTop = **6.55:1**（E1）✓ | #5C5245（:59） | 同上 | — | `MainActivity.kt:379,391,398,467,485,533,676,708,714,723,725,726,731,753,784,789` |
| AND-T-006 | accent | #E8B45C 暖金（:42） | §3.4 语义色表（accentBlue #0090FC 等 11 个，**无金色**） | 色相完全不同；对比 bgTop = **10.36:1**（E1）✓ | #8F6119（:60，注释称对白 5.40:1 —— E1 复算 **5.40:1** ✓ 注释诚实） | 同上 | 同上 | `MainActivity.kt:482,561,624,634,639,661,722,734,743,801` |
| AND-T-007 | onAccent | #14181E（:43） | 规范无此令牌（§3.4 只有强调色本身） | 对比 accent = **9.43:1**（E1）✓ | #FFFFFF（:61） | — | — | `MainActivity.kt:805`（PillButton 文字） |
| AND-T-008 | ok | #6EE7A8（:44） | accentGreen #30D158（§3.4） | Δ=(62,22,80) 偏薄荷；对比 bgTop = **12.73:1**（E1）✓ | #15803D（:62） | accentGreen | — | `MainActivity.kt:360`（箭头）、`:378`（成功文案） |
| AND-T-009 | bad | #F87171（:45） | accentRed #FF3B30（§3.4） | Δ=(7,60,52)；对比 bgTop = **7.08:1**（E1）✓ | #B91C1C（:63） | accentRed | — | `MainActivity.kt:376` |
| AND-T-010 | （缺）separator | 不存在 | rgba(255,255,255,0.08) | 缺令牌 | — | — | — | 全仓 0 处（E1 grep） |
| AND-T-011 | （缺）stroke（玻璃描边） | 不存在 | rgba(255,255,255,0.12) | 缺令牌 | — | — | — | 全仓 0 处（E1 grep）；§6.2 玻璃配方无法落地 |
| AND-T-012 | （缺）surfaceRaised | 不存在 | #24242A | 缺令牌 | — | — | — | 全仓 0 处 |
| AND-T-013 | （缺）textTertiary | 不存在（用 `inkSub.copy(alpha=…)` 冒充） | #6A6A6E | **关键缺口**：靠叠 alpha 造三级灰 ⇒ 4 处对比度跌破 4.5（E1：见 AND-T-014/015） | — | — | — | `MainActivity.kt:391,398,531,708,714,731` |
| AND-T-014 | inkSub@0.7（派生灰） | #646D7A 等效 | textTertiary（3.90:1） | **3.74:1**（E1）< 4.5 | — | — | — | `MainActivity.kt:391` |
| AND-T-015 | inkSub@0.55/0.60/0.75（派生灰） | #515864 / #5C6573 / #6E7887 等效 | §12「空值/辅助」需 >=4.5 | **2.73 / 2.91 / 3.83**（E1）全不合格；0.45 版 = **2.20:1**，恰是 §3.3 明令「禁止承载信息」的 textQuaternary 2.24 同级 | — | — | — | `MainActivity.kt:398(0.55), 533(0.75), 714(0.75), 731(0.60), 725(0.30), 726(0.45)` |

**结论（E1+E2）**：9 个字段里，**1 个方向性违规**（浅色档存在本身违反 §13.4）、**2 个色值偏离规范且无规范对应物**（accent 金、ink 冷白）、**5 个缺令牌**（separator/stroke/surfaceRaised/textTertiary/surfaceSunken）、**1 个系统性缺陷**（用 alpha 派生灰度替代 textTertiary，直接把 5 处文字打到 4.5:1 以下）。

### 3.2 KfTokens.Space / KfTokens.Radius 逐成员

| 编号 | 令牌 | 现状值 | 规范值 | 差多少 | 谁在消费（文件:行） |
|---|---|---|---|---|---|
| AND-T-016 | Space.xxs | 2dp（`Tokens.kt:20`） | 规范无 2（s1=4 是最小） | 规范外 | **零消费**（E1 grep） |
| AND-T-017 | Space.xs | 4dp（:21） | s1=4 ✓ | 0 | **零消费** |
| AND-T-018 | Space.s | 8dp（:22） | s2=8 / s3=8 ✓ | 0 | **零消费** |
| AND-T-019 | Space.m | 12dp（:23） | s3h=12 ✓ | 0 | **零消费** |
| AND-T-020 | Space.l | 16dp（:24） | s4=16（卡内边距）✓ | 0 | `MainActivity.kt:698`（横竖各一次） |
| AND-T-021 | Space.xl | 24dp（:25） | 规范无 24（s7=28） | 规范外 | **零消费** |
| AND-T-022 | Space.xxl | 32dp（:26） | s8=40 / s7=28 | 规范外 | **零消费** |
| AND-T-023 | Space.gutter | 16dp（:27） | **s5 = 14（页面左右边距）** | **+2（偏宽 14%）** | **零消费** —— 实际页边距写死在 `MainActivity.kt:346` 的 horizontal = 24dp（**比规范宽 10**） |
| AND-T-024 | （缺）s5=14 | 不存在 | 14（页面边距，根 token） | 缺 | 硬编码 24dp（`MainActivity.kt:346`） |
| AND-T-025 | （缺）s6=29 | 不存在 | 29（= s5+s4 文字对齐线，§5.4） | 缺 | 未实现（Android 全用居中排版，无左对齐线） |
| AND-T-026 | （缺）s7=28 | 不存在 | 28（区块之间） | 缺 | 用 `Spacer(22.dp)`（:372）、28.dp（:671,:678）、22/6/4/10/12 散值 |
| AND-T-027 | （缺）s8=40 | 不存在 | 40（页面顶部留白） | 缺 | 硬编码 28dp（:346） |
| AND-T-028 | Radius.card | **22dp**（`Tokens.kt:32`） | **rCard = 24**（§5.2，实测 23.6pt） | **-2** | `MainActivity.kt:696`（S3 卡片） |
| AND-T-029 | Radius.control | 16dp（:33） | 规范无 16（最近 rChip=14 / rInner=12） | 规范外 | **零消费**（E1 grep） |
| AND-T-030 | Radius.tile | 18dp（:34） | 规范无 18（最近 rBadge=10 / rCard=24） | 规范外 | **零消费** |
| AND-T-031 | （缺）rPill/rCardLg/rChip/rInner/rShell/rDevice/rBadge | 不存在 | 999/34/14/12/40/44/10 | 7 个全缺 | PillButton 用 `RoundedCornerShape(50)` 硬编码（`MainActivity.kt:800`） |

### 3.3 硬编码值（绕过令牌的地方，E1 grep 全量）

| 编号 | 值 | 文件:行 | 规范应取 |
|---|---|---|---|
| AND-T-032 | 页边距 24.dp / 28.dp | `MainActivity.kt:346` | s5=14 左右 / s8=40 顶 |
| AND-T-033 | 圆盘 300dp / 232dp | `MainActivity.kt:558, 570` | 大环 = 屏宽-28pt（§7.8） |
| AND-T-034 | 箭头 208dp / 300dp | `MainActivity.kt:368, 857` | 规范无此组件 |
| AND-T-035 | 齿轮 56dp / Canvas 30dp / 裸 px 3.5f·2.5f·4f·5f·7.5f | `MainActivity.kt:768, 775, 784-790` | §7.15 26pt 视觉 / 44pt 命中 |
| AND-T-036 | 空态框 120dp / 线 3dp / 臂 26dp | `MainActivity.kt:658-660` | §7.17 图标 28pt |
| AND-T-037 | 圆形按钮 52dp / White@0.22 | `MainActivity.kt:881-883` | §7.0.4 36pt 视觉 / 44pt 命中 |
| AND-T-038 | 遮罩 `Color(0xB3050709)` | `MainActivity.kt:425` | §6.2 玻璃配方 |
| AND-T-039 | AirTag 双绿 #0B6B3A / #0E7A42 | `MainActivity.kt:839` | §3.5 sportsGradient 两停 |
| AND-T-040 | 字号 15/22/26/20/13/12/11/34/30sp（14 处） | `MainActivity.kt:381,393,399,525,534,672,676,702,708,713,731,735,745,752,805,843,845,862,863,887` | §4.2 字阶 11/12/14/16/18/19/30/36/56 |

### 3.4 「注释真实性」审计 —— Tokens.kt 的自称逐条对账（本节是本文件最重要的结论之一）

| 编号 | 注释原文 | 文件:行 | 实测 | 判定 |
|---|---|---|---|---|
| AND-T-041 | 「与 iOS 的 App/Core/DesignSystem.swift **数值逐字相同**（D9/D14）」 | `Tokens.kt:6` | ①该文件**已不存在**（E1：glob `App/**/DesignSystem.swift` 0 命中；`App/Core/Theme.swift:394` 记载「2026-10-21 从**已删的** DesignSystem.swift 迁入」）；②现行 iOS 令牌在 `App/Core/Theme.swift:119-152` | **假**：引用幽灵文件 |
| AND-T-042 | 「Radius —— 与 iOS DS.Radius 同值（**card 22 / control 16 / tile 18**）」 | `Tokens.kt:30` | iOS XRadius：card = 16（`Theme.swift:139`）、control = 12（:140）、tile = 14（:141）、min = 8（:142） | ❌ **三个值全错**：22≠16、16≠12、18≠14。差 +6 / +4 / +4（37.5% / 33% / 28.6%） |
| AND-T-043 | 「Space —— 与 iOS DS.Space 同值」 | `Tokens.kt:18` | iOS XSpace：xxs2/xs4/s8/m12/l16/xl24/xxl32/gutter16 ✓ 全对上；但 iOS 还多 card=16（:130）、control=12（:131）、tile=14（:132）三个成员，Android 没有 | ✓ 已列的 8 个**同值**；❌ 少 3 个成员（后加的三项没同步） |
| AND-T-044 | 「Space <- MainActivity.kt:**687**（Space.l x2）；Radius <- MainActivity.kt:**685**」 | `Tokens.kt:10-11` | 实际消费点：`MainActivity.kt:696`（Radius.card）、`:698`（Space.l x2） | **行号过期**（漂移 +11 / +9）：注释指的行上分别写着 `onClose` / `Column(`（E2 逐行核对） |
| AND-T-045 | 「原文件 82 行，其中 Hit/Icon/Duration/Curve/Text 五个 object **零引用，已删**。只保留**真有消费点**的两组」 | `Tokens.kt:8-12` | 现存 11 个成员里**只有 2 个有消费点**（Space.l、Radius.card）；Space 其余 7 个 + Radius.control/tile 共 **9 个零引用**（E1 grep `KfTokens.` 全仓仅 2 处命中） | **半假**：删了 5 个 object，却在留下的两个 object 里留着 9 个零引用成员 |

**结论（给 Lead 直接可用的判断）**：`Tokens.kt` 目前**不能作为「与 iOS 对齐」的依据**，它的三句关键注释（AND-T-041/042/045）都不成立。改造时应当把 `Tokens.kt` **整体重写**为规范值（§5.1/§5.2），而不是「微调」。

---

## §4 自绘资产清单

| 编号 | 名称 | 文件:行 | 画了什么（逐层） | 尺寸 | 动效 | 符合规范？ |
|---|---|---|---|---|---|---|
| AND-A-001 | **UnlockDial 开锁圆盘** | `MainActivity.kt:543-651` | **共 6 层**：①外圈柔光：radialGradient(accent@0.16 -> Transparent)（:558-566）②金属倒角：sweepGradient **8 个停点** #FEFDFB/#C3BCB1/#FBF9F5/#B6AFA4/#EFEBE3/#C8C1B6/#FCFDFA/#C3BCB1（:583-596）③深色玻璃面：radialGradient **4 个停点** #3A4044->#202528->#0F1214->#080A0B，光源偏移 (-0.24R, -0.46R)、radius=1.2R（:599-607）④斜向镜面高光：linearGradient(Transparent->White@0.52->Transparent) 的 drawArc 200°~290°，线宽 = 0.55x内径（:610-620）⑤锁形字形：drawCircle(accent, r=0.126R) + Path 梯形（:623-635）⑥忙碌环：drawArc -90° 起 300°、2dp 描边（:637-647） | 柔光 300dp；可点圆 **232dp** | 按下 scale 1->0.972、tween(100ms)、CubicBezierEasing(0.42,0,0.58,1)（:550-554） | **大部分合规**（罕见的高质量自绘）：✓ 3 层以上叠加、✓ 纯渐变非纯色、✓ **零投影**（全仓 .shadow = 0 命中，E1）只用柔光 —— 正合 §7.8 末条「环不得有投影，只用辉光」；❌ 线宽/游标/缺口形态不属于 §7.8 三种环形态任何一支（它是「实心盘」不是「环」）；❌ 按压无触觉、无成功/失败图标态 |
| AND-A-002 | **GearButton 齿轮** | `MainActivity.kt:763-793` | **3 层**（均在 30dp Canvas 内）：①8 条齿：drawLine 从 rOut-5px 到 rOut，strokeWidth=3.5f（裸 px，:778-788）②内圈：drawCircle 描边 rOut-7.5px、width=2.5f（:789）③轴心：实心圆 r=4f，色 bgTop（:790） | 容器 56dp / 图形 30dp | **无** | ⚠ **纯色描边画环**触 §14-9 精神（环要有渐变/分色）；⚠ **裸 px 不随密度**（3x 屏上 3.5px 约 1.17dp）；✓ 3 层结构够；✓ 无投影 |
| AND-A-003 | **EmptyState 二维码角框** | `MainActivity.kt:658-670` | **1 层**：4 个角 x 2 条 drawLine（共 8 条），圆头 | 120dp | 无 | ⚠ 单层纯色（accent@0.85）；✓ 与 §6.4.1 I3「没素材用单色占位」精神一致（矢量线非假渐变）；❌ 与 §7.17 空态结构（28pt 图标）差一个数量级 |
| AND-A-004 | **PillButton 胶囊** | `MainActivity.kt:795-807` | 1 层：RoundedCornerShape(50) 实色底 + 文本 | 高约 46dp | 无（clickable 默认 indication，无按压缩放） | ❌ 圆角写死 50 而非 rPill=999；❌ 无按压反馈（iOS 全用 PressableScaleStyle 0.96/120ms，`HomeConsole.swift:1061-1068`） |
| AND-A-005 | **SignalArrow 信号箭头** | `SignalArrow.kt:128-184`（Composable）+ `:190-225`（DrawScope） | **3 层**：①内部填充：clipRect 只画 fill 高度那截，色 #0B6B33（:208-213）②轮廓：描边 len*0.05；武装时再加一层 okColor@0.28 的粗描边 len*0.14 当外发光（:216-220）③箭头上方「目标点」：两个同心圆 r=len*0.10 / len*0.055（:221-224） | 208dp（S2）/ 300dp（S4） | ①**无限摆动**：-8°<->+8°、tween(1500, LinearEasing)、RepeatMode.Reverse（:154-157）②**3D 视差**：rotationX = pitch*0.22、rotationY = roll*0.22，各夹 ±12°，cameraDistance = 40*density（:168-170）③忙时 alpha 0.55（:171）④reduceMotion 检测 ANIMATOR_DURATION_SCALE==0（:145-149） | ⚠ **混合**：✓ 3 层叠加、✓ 渐变/双层描边、✓ 零投影、✓ 尊重 reduceMotion；❌ **无限循环摆动**命中 §11.2「旋转 / 3D 翻转 / **视差**」+「超过 1.2s 的动画」（1500ms）；❌ 3D 视差命中同一条；❌ 默认参数写死暗色 okColor = KfDarkColors.ok（:140）绕过主题 |
| AND-A-006 | 状态环（UnlockDial 内 busy 弧） | `MainActivity.kt:637-647` | 1 层：drawArc 300° + 2dp 圆头，**纯色 accent@0.9** | 232dp 圆内 | **静态**（无旋转/无进度插值） | ❌ **纯色画环**（§14-9 明令：纯色描边画环 = 禁止）；❌ 无进度语义（iOS 是 1.05s 蓄力弧，`HomeConsole.swift:419-432` 用 AngularGradient 三停） |
| AND-A-007 | 全屏绿底（AirTag 层） | `MainActivity.kt:833-840` | 1 层纯色 | 全屏 | 无（切换靠 AnimatedVisibility 整体滑入） | ❌ 见 AND-C-026 |

**自绘资产小结（E1+E2）**：7 件自绘里，**1 件达到「可保留」水准**（AND-A-001 圆盘：多层渐变 + 零投影 + 柔光），**2 件需重画**（AND-A-002 齿轮裸 px/纯色环、AND-A-005 箭头的无限摆动 + 3D 视差），**4 件需换组件**（AND-A-003/004/006/007）。

---

## §5 与 iOS 的对齐 / 背离清单

> iOS 侧一律给 `App/...` 的 文件:行；Android 侧给 `MainActivity.kt` 等。判定「建议以谁为准」时，**技能规范 > iOS 现状 > Android 现状**（因为本轮目标是按 ios-glass-design-spec 重做两端，iOS 现状本身也不合规范 —— 见 AND-P-012）。

| 编号 | 主题 | iOS 做法（文件:行） | Android 做法（文件:行） | 一致？ | 建议以谁为准 |
|---|---|---|---|---|---|
| AND-P-001 | **开锁交互** | **按住 1.05s 蓄力**：chargeDuration = 1.05（`HomeConsole.swift:96`）、onLongPressGesture(minimumDuration: 1.05, maximumDistance: 44)（`:480-484`）、蓄力弧用 AngularGradient 三停 + trim（`:419-432`） | **单击即开**：clickable(...) { onClick() }（`MainActivity.kt:573`）+ onClick = { doUnlock(auto = false) }（`:371`） | ❌ 完全不一致 | **iOS**（按住防误触是安全属性；Android 单击 = 口袋误触即开门）。但规范 §11.1 有「按压缩放 0.12s 1->0.97」，两条都要落 |
| AND-P-002 | **开锁四态表达** | 四态 idle/charging/unlocked/failed -> 图标 lock.fill/lock.open.fill/checkmark/xmark + 文案（`HomeConsole.swift:1025-1052, 542-558`）+ 弧色随态变（`:1045-1052`） | **无态机**：只有 busy: Boolean + 一段字符串 status（`MainActivity.kt:119, 373-383`）；圆盘只多画一条 300° 弧（`:637-647`） | ❌ | **iOS**（四态是「仪器感」的信息骨架） |
| AND-P-003 | **连接/信号状态显示** | 页眉 20pt 高：6pt 圆点 + 13pt Semibold 文案（`HomeConsole.swift:236-245`）；dBm **只在明细页**（`DevicePage.swift:124,317`） | 第二提示行 12sp 等宽，**直接把 dBm 印在主屏**（`MainActivity.kt:386-394`） | ❌ | **iOS**（dBm 是工程量，不是用户语言） |
| AND-P-004 | **设置入口** | 首页 5 个管理瓦片 LazyVGrid 62pt 高（`HomeConsole.swift:729-764`）；细项在「我的」列表（`MePage.swift:181-241`） | 右下角**单个齿轮** -> 全屏抽屉（`MainActivity.kt:411-413, 417-458`） | ❌ 信息架构不同 | **Android**（极简版定位，2 个设置项不需要网格）；但入口必须补 contentDescription + 触觉 |
| AND-P-005 | **靠近自动开锁开关** | 二级页 AutoCalView，入口行带状态值「已开启/已关闭」（`MePage.swift:224-232`）；且有 F0/F1/F3/F4/F5/F6 六道闸（`AutoOpen.swift:215-241`） | 抽屉里 Switch（`MainActivity.kt:717-728`）；闸门只有 前台/回差/闩锁/冷却（`MainActivity.kt:271-302` + `AutoOpenKit.kt:32-51`） | ⚠ 形态不一致，**协议判据一致**（E1：kotlinshadow.js C 段 5 条全绿，含「与 iOS 同式」） | 开关 UI 以 **Android**（就地可切）；判据以 AutoOpenKit（已被闸门锁死，勿动） |
| AND-P-006 | **解绑安全确认** | confirmationDialog「解除绑定？」+ 正文「将从本机删除…**不可撤销**。门锁里的密码/指纹不受影响」（`LocksPage.swift:142-152`） | **无确认**，点「解绑」立即 LockStore.clear + 清空内存态 + release()（`MainActivity.kt:444-453`） | ❌ | **iOS**（破坏性动作必须二次确认） |
| AND-P-007 | **覆盖/换绑确认** | confirmationDialog「这把锁已经添加过」（`AddLockPage.swift:93`） | AlertDialog，两套文案（同 MAC / 换锁）（`MainActivity.kt:461-488`） | ✓ 语义一致 | **iOS 形态 + Android 文案**（Android 的「原来那把锁要从这台手机重新扫码才能再用」比 iOS 更具体） |
| AND-P-008 | **空态文案与出路** | 「还没有门锁」+「配对之后，这里会变成你每天的开门台」+ 按钮「去配对门锁」（`HomeConsole.swift:249-279`） | 「还没有绑定门锁」+ 两行扫码指引 + 「扫码添加门锁」（`MainActivity.kt:672-679`） | ⚠ 结构一致、文案各写 | **规范 §7.17**（标题说原因；两端都要改） |
| AND-P-009 | **精确查找（AirTag 式）** | **只有注释与电源标记，无界面**：`FindArrowLayer.swift:1-39` 全文是设计说明 + FindArrowPower 静态闸，UI 未实现 | **完整实现**：S2 常驻箭头（`MainActivity.kt:357-370`）+ S4 全屏层（`:493-515, 810-875`）+ 3D 视差 + 蜂鸣（`:892-914`） | ❌ **Android 领先** | **Android**（iOS 要补）；但 Android 的「显示米数」与 iOS 立场冲突（`FindArrowLayer.swift:13`「不显示米数」）⇒ 采 **iOS 的诚实边界** |
| AND-P-010 | **触觉** | XHaptics 三档（`Theme.swift:336-352`），全仓 **102 处**调用点（E1：uxaudit.js D 段） | KfHaptics 两档（`Haptics.kt:21,24`），**1 处**调用点（`MainActivity.kt:197`） | ❌ 差 2 个数量级 | **iOS** 的覆盖密度 + §11.4 的四事件映射 |
| AND-P-011 | **动效** | 全部走 XMotion 令牌、三档 calm/standard/lively（`Theme.swift:245-318`）；按压 0.96/120ms（`HomeConsole.swift:1061-1068`） | 6 处 tween 裸写时长：100ms（:552）、160/220/140/200ms（:419-420）、180/260/150/220ms（:495-496）、1500ms（`SignalArrow.kt:156`）；**无 reduce-motion 统一入口**（仅 SignalArrow.kt:145-149 局部读系统设置） | ❌ | **iOS 的令牌化**，但曲线值按 §11.1 重定（easeOut/spring 0.5/0.85 等） |
| AND-P-012 | **页面底色（关键！两端都不合格）** | iOS XPalette.canvas 暗色 = #0A0A0B，AMOLED 模式才 .black（`Theme.swift:35`） | Android bgTop = #0A0C10 + 纵向渐变 #0A0C10->#141A22（`KfTheme.kt:37-38`、`MainActivity.kt:341`） | ✓ 两端「都不纯黑」是一致的，**但都不合规范** | **技能规范 §3.1 / G1 / A5**：#000000。**两端必须一起改**，只改一端会造成新的不一致 |
| AND-P-013 | **明暗双模** | iOS 有明文前提「应用体只做深色」（§13.4 采纳）+ XPalette 用 Color.adaptive 做明暗（`Theme.swift:406-410`） | Android 有**完整浅色档** KfLightColors（`KfTheme.kt:54-64`），跟系统 isSystemInDarkTheme()（`:74`） | ⚠ Android 实现得更「完整」，但方向违规 | **技能规范 §13.4**：应用体只做深色。⇒ 建议删除浅色档（这是本轮最大的一次「减法」） |
| AND-P-014 | **强调色** | 铜 #9C5A22/#D98B45，可被 kf_accent 六套覆盖（`Theme.swift:69-83`） | 暖金 #8F6119/#E8B45C（`KfTheme.kt:42,60`），不可换 | ⚠ 同族不同值 | **技能规范 §3.4**（语义色表，无金色）—— 但这是产品身份问题，需 Lead 拍：要么全盘接受规范色（丢暖金身份），要么把「暖金」登记为规范外扩展。**不要两端各自再走远** |

---

## §6 改造风险面

**判据**：该文件里有没有「字节层/链路层/存储层」的已验证逻辑。判断方法 = 读文件头注释 + 公开签名 + 分类只读判断，**未逐行读**的已在行内注明。

### 6.1 红线区（**UI 改造绝对不许碰**）

| 编号 | 文件 | 关键位置 | 为什么是红线 | 证据 |
|---|---|---|---|---|
| AND-R-001 | BleUnlocker.kt（682 行） | unlock():130、prewarm():291、runUnlock():325、verifyIdentity():452、writeChunked():586（20B 分片）、observeSignal():500、observeRssi():534、release():249 | GATT 链路 + 帧注入 + 身份复核 + 热链路复用。头注释明确「开锁成功后**不拆链路**」「所有 GATT 操作串行化(Mutex)」（:36-51） | E2 `BleUnlocker.kt:35-51`；无任何 androidx.compose import（E1 grep 全仓 compose 引用只在 MainActivity/KfTheme/SignalArrow/Tokens） |
| AND-R-002 | KfProtocol.kt（231 行） | injectToken():52、parse():77、unlockFrame():180、tokenFrame():185、statusFrame():192、parseAdv():216 | 逐字节对拍 vendor JS；rc=13 真机坑的修复点 | E2 `KfProtocol.kt:3-9`（头注释）；E1 kotlinshadow.js A1/A2/A3/A4/A5/A6/A7/A9 全绿 |
| AND-R-003 | AutoOpenKit.kt（52 行） | BASE = -40:19、disarmThreshold():28、rssiSample():32、COOLDOWN_MS = 6_000:48、coolReady():50 | 与 iOS AutoOpenKit 公式对拍锁定；**同时被 UI 读常量**（`MainActivity.kt:707,712` 文案、`SignalArrow.kt:56` 默认参数） | E1 kotlinshadow.js C 段 5 条 + 公式行「BASE=-40 武装线=-40 解除线=-43」；⚠ **改 UI 时不许把阈值文案改成写死数字** |
| AND-R-004 | LockStore.kt（98 行） | parseQr():72-97（KFA1: 契约、ekey 长度 16..510）、clear():61-66（**两个键同一次清**） | 跨端契约（iOS `AndroidPair.swift:11,24-37` 生成）；clear 的「两键同清」是 03 X-03 事故的修复 | E2 `LockStore.kt:54-66, 68-97`；E1 kotlinshadow.js 对 LockStore.kt 有断言（:59 读该文件） |
| AND-R-005 | AndroidManifest.xml | 权限 5 条（:5-12）、screenOrientation="portrait"（:27） | 权限少了 = 开锁/扫码直接失败（真机事故记录见 :9-11 注释） | E2 |
| AND-R-006 | app/build.gradle.kts | minSdk 33（:59）、targetSdk 34（:60，**刻意不升 35**）、签名（:74-86） | 升 targetSdk = 强制 edge-to-edge，而本界面**没有 inset 适配**（E1：WindowInsets 命中 0） | E2 :60 注释原文 |

### 6.2 半红线区（**可以动，但动法受闸门约束**）

| 编号 | 文件/位置 | 约束 | 违反后果 | 证据 |
|---|---|---|---|---|
| AND-R-007 | MainActivity.kt 的**自动开锁状态机**（:271-323） | 必须保留这些**源码形状**（正则级）：① armed = AutoOpenKit.rssiSample(prevArmed = armed, rssi = r)（:293）② if (!armed) { fired = false; prewarmStarted = false }（:295）③ if (!armed || fired) return（:296）④ if (!AutoOpenKit.coolReady(lastAuto, now)) return（:297）⑤ LaunchedEffect(proximity, …) 的 key 里必须含 busy 与 warming（:309）⑥ if (!proximity || busy || warming …) return@LaunchedEffect（:314）⑦ unlocker.release()（:246, :451）⑧ unlocker.prewarm(（:287） | node tools/kotlinshadow.js **直接判红**（A8 共 21 条断言把这份源码当输入） | E1 我跑过：全绿；E2 `tools/kotlinshadow.js:104-164` 逐条正则 |
| AND-R-008 | SignalArrow.kt 的**纯函数段**（:56-92） | signalFill / relativeBearing / peakUpdate / distanceMeters / directionLabel 是与闸门对拍的算术（:51-53 注释明写 tools/kotlinshadow.js 会抠）；实际 E1：当前 kotlinshadow.js 里**没有**这些断言（grep signalFill = 0）—— 注释**超前于实现** | 现在改不会红，但改了无人守；建议改造时**把这 5 个函数搬到独立文件**并保持签名 | E2 `SignalArrow.kt:51-53`；E1 grep 该工具内 signalFill/distanceMeters/peakUpdate/relativeBearing 均 0 命中 |
| AND-R-009 | SignalArrow.kt 的 @Composable（:128-184） | 函数签名 11 个参数（含默认值 okColor = KfDarkColors.ok、sizeDp = 260）被 2 处调用（`MainActivity.kt:358, 849`） | 改签名要同步 2 处；MainActivity.kt:358-369 传 10 个参数、:849-858 传 7 个 | E2 |
| AND-R-010 | KfTheme.kt / LocalKfColors | LocalKfColors.current 有 **7 个消费点**（`MainActivity.kt:337,520,545,655,692,765,797`） | 改 CompositionLocal 名/类型要同步 7 处 + `SignalArrow.kt:140` 的默认值 | E1 grep LocalKfColors = 7 处消费 |
| AND-R-011 | Haptics.kt | 只有 ok/fail 两档公开 API（:21,24），1 个调用点 | 扩展（加 tick/selection）是**安全**的；删改现有两档要动 `MainActivity.kt:197` | E2 |
| AND-R-012 | 构建期门禁 | 本地**无** Kotlin 编译（E1：java/gradle/kotlinc NOT FOUND）；`tools/kotlinlocal.js:26` 只编 4 个非 UI 文件；UI 层只有 CI gradle assembleDebug | **任何 Compose API 误用都要等 5 分钟 CI 才知道**；本轮改造必须逐文件人工复核 import/括号 | E1 + E2 `tools/kotlinlocal.js:9-14`；CI 作业见 `.github/workflows/ios.yml:301,337`（E3 转述 YAML） |

### 6.3 纯 UI 区（**可以随便改**）

| 编号 | 文件/范围 | 说明 |
|---|---|---|
| AND-R-013 | MainActivity.kt 的**渲染段**：:338-516（根布局 + 四层装配）、:518-916（除 271-323 状态机以外的全部 @Composable） | 全部是绘制/布局/文案，无协议副作用。⚠ 但 doUnlock(:182-199)、scan(:202-216)、launchScan(:218-226)、maybeAutoUnlock(:271-302) 属状态机（见 AND-R-007），**改造时只换外观不换调用顺序** |
| AND-R-014 | KfTheme.kt 全部（79 行） | 纯色板 + CompositionLocal。建议整体重写为规范的 ColorTokens（§3.1-3.5） |
| AND-R-015 | Tokens.kt 全部（36 行） | 纯令牌。**建议整体重写**（见 §3.4：现有注释三处为假） |
| AND-R-016 | res/values/themes.xml、colors.xml | 只影响窗口底色/系统栏；⚠ 与 targetSdk 34 的 edge-to-edge 约束耦合（AND-R-006） |
| AND-R-017 | res/values/strings.xml | 只有 1 条 app_name（:2）。**所有 UI 文案目前硬编码在 .kt 里**（E1），改造时可顺手外置，但非必需 |
| AND-R-018 | MainActivity.kt 里**未使用的 import** | CompositionLocalProvider（:23）在本文件 0 次使用（E1 grep 命中只在 KfTheme.kt:78）—— 改造时顺手清 |

### 6.4 施工顺序建议（可直接当排期）

1. **先做 AND-R-014/015（令牌层）**：KfTheme.kt + Tokens.kt 重写为规范值。理由：其余所有屏都读 LocalKfColors，令牌不动就改屏 = 二次返工。⚠ 必须保留 LocalKfColors 这个名字与 9 个字段名（7 个消费点 + SignalArrow 默认值，AND-R-010）。
2. **再做 AND-R-013 的 S2/S1**（主屏优先级最高）：圆盘（AND-A-001 基本可留）+ 箭头（AND-A-005 要重画）+ 状态行（补 ErrorState）。
3. **然后 S3/S4**：抽屉改玻璃浮层（补 separator/stroke 令牌后才有原料）；AirTag 层换 emoji、改两层渐变底。
4. **最后 S5/D1 与全局**：无障碍语义（AND-C-044）、触觉密度（AND-C-045）、inset 适配（AND-C-043）。
5. **每一步之后必须跑 node tools/kotlinshadow.js**（AND-R-007），**不要**等 CI。

---

## §7 未读到 / 无法验证（诚实边界）

| 项 | 状态 | 原因 |
|---|---|---|
| Compose 实际渲染尺寸、触达热区、对比度观感 | **未验证** | 无模拟器/无真机（E1：adb NOT FOUND） |
| S5 zxing 扫码页的实际外观与可配置项 | **未读到** | 第三方 AAR，源码不在本仓；只能读到 ScanOptions 的 4 个调用点（`MainActivity.kt:221-224`） |
| Compose 编译是否能通过（本轮任何改动后） | **无法本地验证** | 无 kotlinc/gradle（E1）；只有 CI（Android job 见 `.github/workflows/ios.yml:301,337`，E3 转述） |
| 「点卡片空白处会关闭抽屉」是否真实发生 | **推断**（E2 结构推断，非实测） | 需真机点一次；依据：MainActivity.kt:422-431 的 clickable 在全屏 Column 上，卡片本体（:693-699）无 pointer 输入 |
| 「扫码页允许旋转 vs Activity 锁竖屏」的实际表现 | **未读到** | `MainActivity.kt:224` .setOrientationLocked(false) 与 `AndroidManifest.xml:27` portrait 并存，行为依赖 zxing 实现 |
| iOS 侧精确查找层的完整 UI | **不存在** | `FindArrowLayer.swift` 全文 39 行只有注释 + FindArrowPower（E2 全读） |
| 规范 §15 的 72 项验收 | 只抽查了 A/B/C 三组（E2：design-spec.md:1622-1650） | 篇幅控制；剩余组建议 Lead 另开一张卡 |
