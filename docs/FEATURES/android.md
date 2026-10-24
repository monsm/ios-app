# FEATURES — Android 端最小功能点清单

> 作者：android-inventory（teammate）· 任务 task-7 · **只读源码**，未改动任何 .kt
> 范围：`D:\aapk\ios-app\android-app\app\src\main\java\com\aapk\kfkey\` 全部 **9 个 .kt / 3338 行**（Lead 给的 3347 是快照值，本轮实测 3338）。
> 证据口径：每条带 `文件:行`。**未编译未渲染**（本机 java/javac/gradle/kotlinc/adb 全部 NOT FOUND，E1 实测），所有行为都是源码静态结论。
> 条目数：**117 条**（目标 80-150）。

## 0. 文件规模（E1：逐个 read 取 totalLines）

| 文件 | 行数 | 定位 |
|---|---|---|
| MainActivity.kt | 1682 | **全部 UI**：1 Activity + 1 根 Composable + 14 个子 Composable |
| BleUnlocker.kt | 682 | BLE 链路层（扫描/连接/订阅/令牌/开锁/预热/信号） |
| KfProtocol.kt | 231 | 字节层（帧/KLV/令牌注入/解析/rc 表/广播） |
| SignalArrow.kt | 230 | 自绘箭头 + 5 个纯函数 + 姿态传感器 |
| Tokens.kt | 221 | 设计令牌（Space/Radius/Hit/Hairline/Icon/渐变/字阶） |
| KfTheme.kt | 103 | 色板（只做深色）+ CompositionLocal |
| LockStore.kt | 98 | 本机存储（单锁）+ 二维码解析 |
| AutoOpenKit.kt | 52 | 自动开锁纯函数判据（F3 回差 / F5 冷却） |
| Haptics.kt | 39 | 触觉两档 |
| **合计** | **3338** | |

---

## 1. 页面级 / 组件级 / 无引用 速查（特别关注 1-3）

### 1.1 Composable 分类（17 个）

| Composable | 文件:行 | 类别 | 依据 |
|---|---|---|---|
| `KfApp(unlocker)` | MainActivity.kt:115 | **页面级（唯一页）** | 整个 App 只有这一棵 Compose 树；内部 `if (lock == null)` 切两屏 + 3 层 AnimatedVisibility 叠浮层 |
| `KfTheme(content)` | KfTheme.kt:97 | **页面级（壳）** | 只在 `setContent` 包一层（MainActivity.kt:97） |
| `EmptyState(onScan)` | MainActivity.kt:1077 | **页面级（S1 屏本体）** | 1 处调用（:396），即 `lock == null` 那一支 |
| `SettingsCard(lock,on,...)` | MainActivity.kt:1185 | **页面级构件（S3 本体）** | 1 处调用（:531） |
| `AirTagLayer(12 参数)` | MainActivity.kt:1526 | **页面级（S4 本体）** | 1 处调用（:645） |
| `UnlockDial(busy,success,rssi,onClick)` | MainActivity.kt:889 | **主视觉构件** | 1 处调用（:402），整屏唯一主角 |
| `SignalArrow(11 参数)` | SignalArrow.kt:129 | **组件级（跨文件）** | 2 处调用（:441 的 72dp、:1564 的 300dp） |
| `KfChip(label,value,tone,modifier)` | MainActivity.kt:671 | **组件级** | 2 处调用（:380、:386） |
| `SettingRow(title,subtitle,tint,onClick,divider)` | MainActivity.kt:1374 | **组件级（真复用）** | 2 处调用（:1305、:1312），注释明说为三处以后不漂而抽 |
| `GlyphButton(glyph,onClick,description)` | MainActivity.kt:1611 | **组件级** | 2 处调用（:1593、:1597） |
| `Header(lock)` | MainActivity.kt:843 | 组件级 | 1 处（:367） |
| `SignalMetric(armed,rssi,proximity,modifier)` | MainActivity.kt:1145 | 组件级 | 1 处（:436） |
| `ReceiptCard(lockName,auto)` | MainActivity.kt:722 | 组件级 | 1 处（:464），条件渲染 |
| `AutoUnlockCard(proximity,armed,onClick)` | MainActivity.kt:784 | 组件级 | 1 处（:471） |
| `GearButton(modifier,onClick)` | MainActivity.kt:1426 | 组件级 | 1 处（:496） |
| `PrimaryButton(text,onClick)` | MainActivity.kt:1471 | 组件级 | 1 处（:1139） |
| `ProximityBeep(fill,soundOn,foreground)` | MainActivity.kt:1661 | 组件级但**无 UI**（纯副作用） | 1 处（:1604），只跑 LaunchedEffect 发声 |

> 其中真正可跨屏复用的只有 4 个（SignalArrow / KfChip / SettingRow / GlyphButton），其余都是单点使用。

### 1.2 定义了但没有任何界面引用的（E1：逐个 grep 核过）

| 符号 | 文件:行 | 状态 |
|---|---|---|
| `distanceMeters(rssi,at1m,n)` | SignalArrow.kt:84 | **零调用**：S4 已改 `distanceTier` 档位词（MainActivity.kt:1517），按 iOS 诚实边界删掉米数 |
| `KfTokens.canvasGradient` | Tokens.kt:130 | **零消费**：根画布用 `colors.canvas` 纯黑实底（MainActivity.kt:358） |
| `KfTokens.cardSurface` | Tokens.kt:148 | **零消费**：卡片一律 `colors.surface` 平色 |
| `Type.displayNumber` | Tokens.kt:194 | **零消费**：环心读数用裸 `TextStyle(fontSize = 44.sp)`（MainActivity.kt:1031） |
| `Type.body` / `Type.hero` / `Type.small` | Tokens.kt:206 / 216 / 218 | **全部零消费** |
| `KfTokens.Space.xsm` | Tokens.kt:45 | **零消费**（6dp，注释却抄了 iOS `xs=4` 的出处行） |

### 1.3 屏的完整清单

| 屏 | 触发 | 实现 | 关闭 |
|---|---|---|---|
| S1 空态屏 | `lock == null`（MainActivity.kt:395） | `EmptyState`（:1077） | 只能扫码离开 |
| S2 主解锁屏 | `lock != null`（:397） | Header + 双 chip + UnlockDial + 状态行 + SignalMetric + ReceiptCard? + AutoUnlockCard + GearButton | — |
| S3 门锁设置（居中卡 + 72% 遮罩） | `showSettings`（:504） | `SettingsCard`（:1185） | 点遮罩 / 完成 / 返回键 |
| D1 换绑确认 | `pending != null`（:561） | `AlertDialog`（:563） | 取消 / 覆盖 |
| D2 解绑确认 | `showConfirmUnbind`（:599） | `AlertDialog`（:600） | 取消 / 解绑 |
| S4 AirTag 精确查找层 | `airTagShowing`（:346） | `AirTagLayer`（:1526） | ✕ / 返回键 |
| S5 zxing 扫码页 | `launchScan()`（:232） | **外部 Activity**（com.journeyapps） | 系统返回 |

---

## 2. 功能点总表

> 「冗余嫌疑」列：**空 = 无嫌疑**；有字写具体嫌疑。

### MainActivity.kt — 装配与状态

| ID | 功能点 | 触发方式 | 说明 | 冗余嫌疑 |
|---|---|---|---|---|
| F-AND-001 | 单 Activity 承载全部界面 | onCreate | `MainActivity : ComponentActivity`，`setContent { KfTheme { KfApp(unlocker) } }`（MainActivity.kt:88-98） |  |
| F-AND-002 | unlocker 提升到 Activity | `by lazy` | 为了让 `onDestroy` 能拆链（:92、:100-111） |  |
| F-AND-003 | 退出时后台线程拆链 | `onDestroy` | 起 `Thread` + `runBlocking { u.release() }`，不让主线程等 1.2s（:100-111） |  |
| F-AND-004 | 根 Composable | `KfApp(unlocker)` | 唯一 Compose 树（:115）；内部 `if (lock == null)` 切两屏 + 3 层 AnimatedVisibility 叠浮层 |  |
| F-AND-005 | 渲染状态组：绑定锁 + 结果文案 | 启动读 / `say()` | `lock`(:121) `status`+`statusBad`(:122-125) `detail`(:124) `receiptAuto`(:128) |  |
| F-AND-006 | 运行状态组：在途 / 信号 / 姿态 | 监测流与传感器写入 | `busy`(:129) `rssi`(:132) `azimuth/peakRssi/peakAz`(:144-146) `pitch/roll`(:151-152) |  |
| F-AND-007 | 自动开锁状态组：五道闸的载体 | `maybeAutoUnlock` 逐样本改 | `lastAuto`(:134) `armed`(:135) `fired`(:136) `prewarmStarted`(:137) `warming`(:138) |  |
| F-AND-008 | 浮层状态组 | 齿轮 / 二维码 / 返回键 | `showSettings`(:147) `showConfirmUnbind`(:150) `pending`(:133) `airTagDismissed`(:153) |  |
| F-AND-009 | 前后台闸 foreground | ON_RESUME / ON_PAUSE（:251、:257） | 后台不扫锁、不预热、不发声 |  |
| F-AND-010 | 统一提示入口 say() | 各处置位 | 一处改 status + statusBad（:167-170） |  |
| F-AND-011 | 返回键三层优先级 | 系统返回 | `BackHandler`：AirTag 层 → 设置层 → 默认退出（:162-165） |  |

### MainActivity.kt — 权限 / 扫码 / 生命周期

| ID | 功能点 | 触发方式 | 说明 | 冗余嫌疑 |
|---|---|---|---|---|
| F-AND-012 | 三项运行时权限申请 | 首帧 `LaunchedEffect(Unit)`（:186-193） | BLUETOOTH_SCAN / CONNECT / CAMERA |  |
| F-AND-013 | 权限被拒文案 | 权限回调（:179-185） | 列出被拒权限中文名 + 指路系统设置 | **S1 空态屏上永远看不到**（status 只在 S2 渲染），空态用户无出路 |
| F-AND-014 | 扫码回调三分支 | zxing 返回（:216-230） | 解析失败 / 首次绑定 / 已有绑定弹确认 |  |
| F-AND-015 | 扫码启动配置 | `launchScan()`（:232-240） | QR only / 提示语 / 不响 / 不锁方向 |  |
| F-AND-016 | 生命周期观察者 | `DisposableEffect`（:244-267） | 回前台复位 fired/prewarm/airTag；退后台停监测 + 拆链 |  |

### MainActivity.kt — 开锁 / 自动开锁（状态机）

| ID | 功能点 | 触发方式 | 说明 | 冗余嫌疑 |
|---|---|---|---|---|
| F-AND-017 | 手动开锁 | 点圆盘（:402 → :407） | `doUnlock(auto = false)` |  |
| F-AND-018 | 自动开锁 | 越过武装线（:315） | `doUnlock(auto = true)` |  |
| F-AND-019 | 开锁在途去重 + 来源标注 | `doUnlock` 内（:197、:206） | `if (busy) return`；成功语冠自动/手动前缀 |  |
| F-AND-020 | 结果触觉 | `doUnlock` 尾（:211） | `KfHaptics.ok` / `fail` —— **全 App 唯一触觉调用点** | 覆盖率极低：按下/切换/弹层全无反馈 |
| F-AND-021 | 预热线触发 + 延后一帧 | RSSI ≥ BASE−24（:283、:290、:299） | 预热前 `delay(220)` 让监测流先撤下，避免边扫边连 |  |
| F-AND-022 | 回差武装 | `AutoOpenKit.rssiSample`（:307） | 越线武装 / 掉到解除线才解除 |  |
| F-AND-023 | 一次性闩锁 + 6 秒冷却 | `fired`（:309-313）、`coolReady`（:311） | 一次接近事件只发一次 04；跨事件也拦 |  |
| F-AND-024 | 监测流挂载/撤下 | `LaunchedEffect(proximity, lock?.mac, busy, warming, foreground)`（:323-337） | 开锁在途 / 预热在途 / 后台 都撤下 |  |

### MainActivity.kt — 渲染（S1 空态 / S2 主屏）

| ID | 功能点 | 触发方式 | 说明 | 冗余嫌疑 |
|---|---|---|---|---|
| F-AND-025 | 纯黑画布 + 页级留白 | 常驻（:355-364） | `background(colors.canvas)`；`Space.gutter` + `Space.pageTop` |  |
| F-AND-026 | 标题区 | 常驻（:367） | `Header(lock)`：30sp Bold 锁名 + 12sp 等宽 MAC（:843-869） |  |
| F-AND-027 | 顶部双状态胶囊 | `lock != null`（:374-393） | 已武装 + 当前信号两枚 `KfChip`（:671-710，圆角 13dp 就地写死） | **信息三处冗余**：同一屏的 SignalMetric（:436）与 AutoUnlockCard（:784）都在讲信号/武装态 |
| F-AND-028 | 空态屏 | `lock == null`（:395-396） | `EmptyState`（:1077-1141）：蓝紫渐变 hero + 96dp 取景框 + 标题 + 说明 + 主按钮 | hero 三色 #4B5AE8 / #3D49C8 / #232B7A 未进色板，就地写死 |
| F-AND-029 | 开锁圆盘 | `lock != null`（:402-408） | `UnlockDial(busy, success, rssi)`：六层绘制（:889-1073） |  |
| F-AND-030 | 圆盘环心 RSSI 读数 | 主屏常驻（:1028-1045） | 44sp `TextStyle(fontSize = 44.sp)` + dBm | **Token 违规**：`Type.hero` 就是 44sp（Tokens.kt:216）却零消费 |
| F-AND-031 | 圆盘进度弧 | `busy` 或 `success`（:982-1013） | `rotate(-90f)` 对齐 12 点 + `linearGradient(dialStops/dialOKStops)` | 弧长恒 300°，**无进度语义**（装饰弧不是进度条） |
| F-AND-032 | 圆盘按压缩放 + 语义 | 按下（:894-898、:917） | 0.97 / 120ms；`contentDescription` 开锁/正在开锁 |  |
| F-AND-033 | 状态行 | 常驻（:413-424） | 15sp Semibold，三档色（bad / ok / text） |  |
| F-AND-034 | 信号仪表行 + 72dp 箭头 | 常驻（:432-454） | `SignalMetric`（:1145-1175）+ `SignalArrow(sizeDp=72)` | 见顶部双状态胶囊的冗余标注 |
| F-AND-035 | 开锁回执卡 | 仅成功态（:462-468） | `ReceiptCard`（:722-772）：谁·自动或手动·命令 04·触发方式·footer | 与状态行语义重叠（都在说开成功），但多说谁开的 |
| F-AND-036 | 自动开锁说明卡 | 常驻（:471-475） | `AutoUnlockCard`（:784-840），点击进设置 | **阈值文案写死且全错**：见下一条 |
| F-AND-037 | 说明卡阈值 vs 真实判据 | — | 文案 −38 dBm / 8 秒 / −55 dBm（:818、:833-834）；真实 BASE=-40（AutoOpenKit.kt:19）、disarmThreshold()=-43（:28-29）、COOLDOWN_MS=6000（:48） | **高**：同 App 两套数字。SettingsCard（:1274、:1279）用动态值，这张卡写死 → 卡片在骗人 |
| F-AND-038 | 失败留痕行 | `detail.isNotEmpty()`（:477-488） | 11sp 等宽 |  |
| F-AND-039 | 齿轮入口 | `lock != null`（:495-497） | `GearButton`（:1426-1457）：56dp 圆 + 26dp Canvas 8 齿 |  |

### MainActivity.kt — 三层浮层与两个弹窗

| ID | 功能点 | 触发方式 | 说明 | 冗余嫌疑 |
|---|---|---|---|---|
| F-AND-040 | S3 遮罩 + 居中可滚容器 | `showSettings && lock != null`（:504-530） | `canvas@0.72` 点击关闭；`verticalScroll` + `Arrangement.Center` |  |
| F-AND-041 | S3 设置卡 | 同上（:531-554） | `SettingsCard`（:1185-1366）：卡头完成 / 标题 / 靠近开关 / 提示音开关 / 说明两段 / 分隔线 / 凭证与绑定组 / 两个 SettingRow / footer / 当前绑定三行 | 「靠近会怎样」在此**又讲一遍**（:1274-1282、:1358-1363），与 AutoUnlockCard 重复 |
| F-AND-042 | S3 卡内行组件 | 设置卡内 2 处（:1305、:1312） | `SettingRow`（:1374-1422）：图标块 34dp + 主标题 + 副标题 + chevron，触达 ≥48dp | 无（本文件唯一真复用组件） |
| F-AND-043 | D1 换绑确认 | `pending != null`（:561-595） | 两套文案（同锁覆盖 / 换锁） | 换锁分支第二段（:577-579）讲的是**解绑**后果，与 D2 重复 |
| F-AND-044 | D2 解绑确认 | `showConfirmUnbind`（:599-633） | 三件事说清：删什么 / 能否找回 / 锁本体不受影响 |  |
| F-AND-045 | S4 查找层 | `airTagShowing`（:638-660） | `AirTagLayer`（:1526-1605）：三停深绿 + 标题 + 300dp 箭头 + 档位词 + 方向 + 两枚 GlyphButton |  |

### SignalArrow.kt

| ID | 功能点 | 触发方式 | 说明 | 冗余嫌疑 |
|---|---|---|---|---|
| F-AND-046 | `signalFill` 信号填充率 | 纯函数（:56-62） | −95..−40 dBm 线性映射到 0..1 |  |
| F-AND-047 | `relativeBearing` / `peakUpdate` 方位算术 | 纯函数（:65-77） | 差角归一；只在强 >1dB 时改写峰值 |  |
| F-AND-048 | `distanceMeters` 对数路径损耗 | **零调用**（:84-88） | 1m 基准 −59dBm / n=2.5 | **死代码**：S4 已改档位词，仓内无消费（E1 grep） |
| F-AND-049 | `directionLabel` 方位词 | 纯函数（:91-92） | ±18° 死区判前/左前/右前 |  |
| F-AND-050 | `HeadingSense.attitude` 姿态流 | S2 常驻（MainActivity.kt:342） | ROTATION_VECTOR → 3×3 矩阵 → yaw/pitch/roll（:95-120） |  |
| F-AND-051 | `SignalArrow` 组件（3 层绘制） | S2 72dp / S4 300dp | 灌绿填充 / 白描边 + 武装外发光 / 上方目标点（:129-189、:195-230） |  |
| F-AND-052 | 箭头无限摆动 | reduceMotion 关闭且无峰值时（:159-162） | −8° 到 +8° / 1500ms / RepeatMode.Reverse | **与规范 §11.2 冲突**（禁止旋转、禁止 >1.2s）；且峰值一到就静默停摆，行为不直观 |
| F-AND-053 | 3D 视差 | 常驻（:170-177） | rotationX/Y = pitch/roll × 0.22，夹 ±12°，cameraDistance = 40 × density | **与规范 §11.2 禁止视差直接冲突** |
| F-AND-054 | 减弱动态检测 | 首帧（:150-154） | 读 ANIMATOR_DURATION_SCALE == 0 | 只关摆动，**没关 3D 视差**（视差不看 reduceMotion） |
| F-AND-055 | 箭头无障碍描述 | 状态变化（:163-167、:179） | 三种 desc：找不到 / 信号已满 / 还差一点 dBm |  |

### KfProtocol.kt（字节层）

| ID | 功能点 | 触发方式 | 说明 | 冗余嫌疑 |
|---|---|---|---|---|
| F-AND-056 | NUS 服务/特征 UUID + hex/bytes 编解码 | 常量与工具（:11-26） | 6E400001/2/3；ByteArray 与小写 hex 互转 |  |
| F-AND-057 | 帧组装三件套 klv / frame | 工具（:29-40） | KLV = key+len+value；帧 = 87 00 lenLE16 cmd 000000 + KLV |  |
| F-AND-058 | `injectToken` 会话令牌注入 | 04 前调用（:52-68） | 追加 KLV#EE + 重算长度 + 8B/10B 头型自适应 | 无（这是 rc=13 真机坑的修复点） |
| F-AND-059 | `parse` / `parseKlv` 响应解析 | 收到通知（:77-107） | 按 version 选 KLV 起点顺序（1 用 8/7/10，否则 8/10/7） |  |
| F-AND-060 | `intHex` / `rc` / `klvShape` 取码与留痕 | 解析后（:116-139） | 前缀 hex（空串=0，与 JS 同口径）；rc 在 KLV#03，整项缺失才 −1；形状串不含值 |  |
| F-AND-061 | RC_NAME / RC_HINT / rcText 结果码三件套 | 常量 + 失败时（:142-177） | 27 条权威名 + 10 条可行动提示；输出顺序 = 怎么办→原文→码 | 无（rc=13 那条新写并如实标注：已自动重取仍被拒） |
| F-AND-062 | 三条命令帧构造 | 开锁/认锁 | `unlockFrame`（KLV#01 32 个 0 + KLV#02 ekey）/ `tokenFrame`(01) / `statusFrame`(03)（:180-192） |  |
| F-AND-063 | `u32le` / `pidOf` 锁自报身份 | 身份复核（:195-208） | KLV#34 小端 u32 |  |
| F-AND-064 | `parseAdv` / `normMac` 广播解析 | 扫描回调（:216-230） | fc bit2/3 双置位校验 + pid LE + MAC 逆序；MAC 归一去冒号小写 |  |

### BleUnlocker.kt（链路层）

| ID | 功能点 | 触发方式 | 说明 | 冗余嫌疑 |
|---|---|---|---|---|
| F-AND-065 | `Outcome` 结果三元组 | 每次开锁（:61） | ok / message / trace |  |
| F-AND-066 | `Session` 链路会话 + onLinkDown | 建链时 / 断链（:72-100） | 5 个 CompletableDeferred + volatile 句柄 + 身份位；断链让所有等待方立刻拿 false |  |
| F-AND-067 | 广播句柄缓存 seen | 扫描回调写（:118-119、:238-242） | mac 到 device+时刻的映射，TTL 10s |  |
| F-AND-068 | `unlock` 主流程 | 手动/自动开锁（:130-211） | 复用链路 → 冷路径 → 身份复核 → runUnlock；三段失败各有对症文案 |  |
| F-AND-069 | pickWarm / closeWarm / release / teardown 链路管理 | 内部（:220-268） | 可用性四判（同 MAC/未断/句柄在/60s 内）；teardown 必须 disconnect→等回执→close | 无（顺序反了会泄漏 GATT 接口位） |
| F-AND-070 | `prewarm` 预热建链 | RSSI 越预热线（:291-318） | 只建链**不发任何命令**，绝不自起扫描，失败静默 |  |
| F-AND-071 | `runUnlock` 01→04 两往返 | 开锁（:325-382） | 令牌 → 注入 → 帧尾护栏 → 写 → 等回执；rc 3/13 自动重取一次 |  |
| F-AND-072 | 双开红线两处 | runUnlock 内（:355-371） | ① 帧尾必须有 tokKlv 否则拒发；② 回执超时**绝不重发**，只报可能已执行 | 无（G4 红线） |
| F-AND-073 | `buildLink` 建链 | 冷路径 / 预热（:385-447） | connect → 服务 → 特征 → CCCD → MTU 256；停扫后 settle 80ms |  |
| F-AND-074 | `verifyIdentity` 连接后身份复核 | 每次开锁（同链路只一次）（:452-477） | 发 03 读 KLV#34 比 pid；pid≤0 时跳过（老配对放行） |  |
| F-AND-075 | `observeSignal` 统一信号流 | 监测流（:500-517） | 有活链路 → readRemoteRssi 200ms；否则扫广播 3s 一窗 | 无（这是秒开成不成立的关键） |
| F-AND-076 | `observeRssi` / `scanForLock` 两路扫描 | 无链路时 / 冷路径（:534-584） | 广播流无 filters（锁广播无服务 UUID）；定向扫描 3s 首命中即完成 |  |
| F-AND-077 | `writeChunked` / `awaitFrame` 收发 | 发帧 / 等回包（:586-644） | 20B/片 + 每片等 ack（4s）；帧组装重同步到 87 + 残帧留缓冲 |  |
| F-AND-078 | advOf / indexOfCompanyId / humanBle 兜底 | 扫描回调 / 异常（:650-677） | 兼容含或不含 2 字节厂商 ID 的两种机型；SecurityException 与其它分开说 |  |

### LockStore / AutoOpenKit / Haptics / KfTheme / Tokens

| ID | 功能点 | 触发方式 | 说明 | 冗余嫌疑 |
|---|---|---|---|---|
| F-AND-079 | `LockInfo` 单锁模型 | 数据类（LockStore.kt:7-10） | name/mac/pid/ekey + macText |  |
| F-AND-080 | `load` / `save` 读写锁 | 启动 / 扫码绑定（:21-41） | 校验 mac 12 位且 ekey 非空；紧凑 JSON n/m/p/e |  |
| F-AND-081 | `loadProximity` / `saveProximity` | 开关切换（:47-52） | 独立键，跨重启保留 |  |
| F-AND-082 | `clear` 解绑 | D2 确认（:61-66） | **两键同一次清**（lock + proximity） | 无（少清一个就是换锁后新锁默认自动开） |
| F-AND-083 | `parseQr` 二维码解析 | 扫码回调（:72-97） | KFA1: 前缀 / v==1 / mac hex / ekey 16..510 偶数 / 名字截 40 |  |
| F-AND-084 | AutoOpenKit 判据四件套 | 纯函数 | BASE=-40(:19) armThreshold/disarmThreshold≈−43(:26-29) rssiSample 回差(:32-36) coolReady 6s(:48-51) |  |
| F-AND-085 | `KfHaptics.ok` / `fail` / `buzz` | 开锁结果（Haptics.kt:21-38） | 12ms/90；35ms/180；无马达/无权限一律静默 |  |
| F-AND-086 | `KfColors` 16 字段色板 | 数据类（KfTheme.kt:22-45） | **全部有消费点**（E1 grep 核过，0 个零引用） |  |
| F-AND-087 | KfDarkColors 唯一色板 + LocalKfColors | 常量（:66-91） | **只做深色**，light 档已删；CompositionLocal 是唯一色板通道 |  |
| F-AND-088 | KfTheme 壳 | setContent（:97-103） | 签名留着 dark: Boolean = true 但内部恒 provide 深色 | **假开关**：参数不生效，调用点不传就不会出事，但看着像能切 |
| F-AND-089 | KfTokens.Space 10 成员 | 令牌（Tokens.kt:43-62） | xs/xsm/s/m/l/xl/gutter/section/pageTop/card | xsm(6dp) 零消费；gutter 上方**同时留着两段互相矛盾的注释**（:51 说 14 范式实测、:53 说 22 与 iOS 同源升级） |
| F-AND-090 | KfTokens.Radius 2 成员 | 令牌（:67-74） | card=26 / control=12 | **注释与值不符**：注释写 24(范式 5.2 实测 23.6)，值是 26 |
| F-AND-091 | KfTokens.Hit / Hairline / Icon | 令牌（:84-116） | Hit.min=48dp（Android 口径，iOS 44pt）/ metricRow=20dp / Hairline=0.5dp / Icon.md=20 / Icon.lg=28 | 无（均与 iOS 同值） |
| F-AND-092 | canvasGradient / cardSurface 两枚渐变 | **零消费**（:130-153） | 画布径向三停；卡片顶光三停 | **死令牌**：画布用纯黑实底（MainActivity.kt:358），卡片一律平色 colors.surface |
| F-AND-093 | dialStops / dialOKStops 环渐变 | 圆盘进度弧（:162-177） | 五段青绿到蓝；三段绿 |  |
| F-AND-094 | Type 字阶 12 档 | 令牌（:192-221） | displayNumber/display/largeTitle/title2/title3/headline/body/subhead/footnote/caption/hero/small | **5 档零消费**：displayNumber/body/hero/small；环心 44sp 用裸值不用 hero |

### 与 iOS 对照：Android 有、iOS 没有（只标注，深入对照 Lead 做）

| ID | 功能点 | 触发方式 | 说明 | 冗余嫌疑 |
|---|---|---|---|---|
| F-AND-095 | **AirTag 式精确查找全屏层** | airTagShowing（MainActivity.kt:638） | 三停深绿 + 300dp 箭头 + 档位词 + 方向 + 蜂鸣（:1526-1605） | iOS 的 FindArrowLayer.swift **全文 39 行只有注释 + FindArrowPower**，无任何 UI（E2 全读） |
| F-AND-096 | **变速提示音** | S4 内（:1661-1682） | 信号越强滴得越快：240/420/700/1100ms | iOS AlertTone.swift 只有固定 systemSound 单响/三响，无随 RSSI 变速循环 |
| F-AND-097 | **连接层测距驱动的信号流** | 监测流（BleUnlocker.kt:500-528） | 链路热起来后 readRemoteRssi 200ms 轮询 | iOS readLinkRSSI 有实现（BLEService.swift:306）但**无周期调用点** |
| F-AND-098 | **开锁回执卡** | 成功态（MainActivity.kt:722-772） | 谁 · 自动或手动 · 命令 04 · 触发方式 | grep 开锁回执 = 0 |
| F-AND-099 | **自动开锁规则说明卡** | 常驻（:784-840） | 主屏直接讲清触发条件 | grep AutoUnlockCard = 0；iOS 阈值在二级页 AutoCalView |
| F-AND-100 | **顶部双状态胶囊** | lock != null（:374-393） | 已武装 + 当前信号 | iOS 有 XStatChip（43 处）但无武装态+RSSI 这个组合 |
| F-AND-101 | **单锁极简存储** | LockStore.kt:17-19 | kf_key_v1 只存 lock / proximity 两键 | iOS 是多锁 + 钥匙串 + 大量 kf_* 键，无单锁极简模式 |
| F-AND-102 | **二维码导入绑定** | LockStore.kt:72-97 | 消费 KFA1 五字段载荷 | iOS 是**生成方**（AndroidPair.swift:24-37），不消费此载荷 |
| F-AND-103 | **返回键三层优先级消费** | MainActivity.kt:162-165 | AirTag 层 → 设置层 → 退出 | iOS 无返回键，无等价物 |
| F-AND-104 | 预热建链 prewarm | BleUnlocker.kt:291-318 | 只建链不发命令 | iOS 有 LinkSenseKit.preconnect（:95），**语义相近但实现路径不同** → 标形态不同，不算严格独有 |

### BLE 协议层与 iOS 是否等价

| ID | 功能点 | 触发方式 | 说明 | 冗余嫌疑 |
|---|---|---|---|---|
| F-AND-105 | NUS UUID / 帧头 / 分片 / 流控 | KfProtocol.kt:11-40、BleUnlocker.kt:586-608 | 6E400001/2/3；87 00 lenLE16 cmd 000000；**恒 20B 分片** + 每片等 ack | **等价**：iOS BLEService.swift:326-341 同为 8 字节头 + chunk 20 + 等 didWriteValueFor |
| F-AND-106 | 04 开锁帧 KLV#01 / KLV#02 | KfProtocol.kt:180-183 | KLV#01 = 32 个 0 字符；KLV#02 = ekey 小写 hex | **等价**：iOS ZKCmdBuilder.swift:96-101 fillZeroLeft(klv01Hex,32) + buildKLV(0x02, ekeyHex) |
| F-AND-107 | 令牌注入 KLV#EE | KfProtocol.kt:52-68 | 追加 + 重算长度 + 8B/10B 头型自适应；长度按字节 2..3 | **等价**：iOS ZKProtocol.swift:159 injectToken，同样字节 2..3（Android 注释明说同 vendor protocol.js:155） |
| F-AND-108 | 身份复核 | BleUnlocker.kt:452-477 | 连上后发 03 读 KLV#34 比 pid；pid≤0 跳过 | **等价**：iOS LockService.swift:104-112 同逻辑（已知 pid>0 才拦） |
| F-AND-109 | 开锁重试 | BleUnlocker.kt:375-378 | rc==3/13 且第一次 → 重取令牌再试一次 | **语义等价、次数口径需核**：Android 是 01+04 整趟重来一次，iOS 是 exec 层 retries 2；两者都只在锁明确回非 0 rc 时允许 |
| F-AND-110 | 回执超时不重发（双开红线） | BleUnlocker.kt:367-371 | 帧已出手机 → 只报可能已执行，绝不重发 | **等价**：Android 注释直接引用 G4 红线与 vendor lock.js |
| F-AND-111 | 链路复用（开锁后不拆） | BleUnlocker.kt:217、:249 | warm 保留 60s | **等价**：iOS unlock() 里无 disconnect（LockService.swift:470-484） |
| F-AND-112 | 广播厂商段解析 | KfProtocol.kt:216-227 | fc bit2/3 双置位 + pid LE + MAC 逆序 | **等价**：iOS ZKProtocol.swift:255-258（98ed 段） |
| F-AND-113 | 信号源：连上之后 | BleUnlocker.kt:500-528 | readRemoteRssi 200ms 轮询 | **不等价**：iOS 有 readLinkRSSI 但无周期调用点，自动开锁只能靠最后一条广播的陈旧值 |
| F-AND-114 | 结果码语义 | KfProtocol.kt:142-177 | 27 条权威名 + 10 条可行动提示，输出怎么办→原文→码 | **等价**：iOS StatusParser.rcHint/rcMsg；rc=13 那条 Android 新写并如实标注 |
| F-AND-115 | 协议覆盖面 | KfProtocol.kt:180-192 | **只有 01 / 03 / 04 三条命令** | **严重不等价**：iOS 有 31 个命令构造器（布防/校时/凭证/DFU/网关等） |
| F-AND-116 | 加密与凭证签发 | KfProtocol.kt:7-8 | **无 AES**，不持 skey，只消费二维码带来的 ekey | **不等价**：iOS 有 AESKit + skey + PIN 现签 ekey（ZKCmdBuilder.swift:114-119） |
| F-AND-117 | MTU | BleUnlocker.kt:444 | requestMtu(256) 但分片不变 | **Android 单方面**：iOS 无 MTU 相关调用（grep=0）；不影响正确性（分片都 20B） |

---

## 3. 冗余嫌疑汇总（按严重度）

| 级别 | 条目 | 证据 |
|---|---|---|
| **高（文案与代码不符）** | `AutoUnlockCard` 写死 −38 dBm / 8 秒 / −55 dBm，真实常量是 −40 / −43 / 6s | MainActivity.kt:818、:833-834 vs AutoOpenKit.kt:19、:28-29、:48 |
| **高（注释与值不符）** | `Radius.card` 注释写 24，值是 26 | Tokens.kt:68-69 |
| **高（注释自相矛盾）** | `Space.gutter` 上方同时留着 14 范式实测 与 22 与 iOS 同源升级 两段 | Tokens.kt:51-54 |
| **中（多入口表达同一信息）** | 信号/武装态在主屏出现 3 次：KfChip（:380/:386）、SignalMetric（:436）、AutoUnlockCard（:784） | — |
| **中（阈值说明重复）** | 靠近会怎样 在 AutoUnlockCard（:832-838）与 SettingsCard（:1274-1282、:1358-1363）各讲一遍 | — |
| **中（死代码 / 死令牌）** | `distanceMeters`、`canvasGradient`、`cardSurface`、`Type.displayNumber/body/hero/small`、`Space.xsm` | E1 逐个 grep |
| **低（假开关）** | `KfTheme(dark: Boolean = true)` 参数不生效 | KfTheme.kt:97-103 |
| **低（无持久化）** | `findSound` 有两个入口（S4 / S3），但关掉 App 再开又回到 true | MainActivity.kt:154、:535、:656 |
| **低（规范违规）** | 箭头无限摆动 + 3D 视差与设计规范 11.2 直接冲突 | SignalArrow.kt:159-177 |

---

## 4. 未读到 / 无法验证

| 项 | 状态 | 原因 |
|---|---|---|
| 任何运行时行为（点击、动画、声音） | **未验证** | 无模拟器无真机（E1：adb NOT FOUND） |
| Compose 能否编译 | **未验证** | 无 kotlinc/gradle（E1） |
| zxing 扫码页外观 | **未读到** | 第三方 AAR，源码不在本仓 |
| iOS 侧完整逐屏对照 | **只做 grep 级** | 按 Lead 要求「只标注，深入对照 Lead 做」 |
| `tools/kotlinshadow.js` 的 A8 断言 | 未在本轮重跑 | 本轮**未改任何 .kt**，理论上不受影响 |