# AUDIT-STATIC-SWEEP — 2026-10-15 四轮地毯式静态销案（对照重做逆向层）

> 会话背景：同日早些时候用同版 jadx 1.5.6 全新反编译 jzzns22561.apk 到 jzzns22561_v2/（1810 文件，
> 与旧产物 1796 字节一致 + 14 个 jadx 非确定性差异全在第三方 SDK、协议包 cn/zelkova+cn/justree+com/plugin
> 93/93 逐字节一致）。本文记录以该逆向层为基准、对 iOS App 做的四轮**静态**对抗扫描结论。
> 判据规矩与本仓其他台账一致：只写当场可复算的事实，每条带复算命令；"销案"= 扫过且判为无缺陷，
> 不等于"永不再坏"——改了对应代码就要重扫。

## 一、协议面对拍销案（对照 H5 权威 main.js + jadx Java 层）

| 面 | 结论 | 复算 |
|---|---|---|
| 命令集 | iOS/小程序 29 命令号 = H5 使用面（0D/0C/02 仅枚举零调用，原版 App 也不发；锁的 ZOTP 周期经 cmd03 KLV#05 读出） | main.js 搜 '="0D"' 全落枚举段; CAPABILITY.md 已升级证据 |
| cmd19 OPENZOTP | 布局字节级一致（ro 0x88 包络 → AES → KLV#02） | 金标 cmds.cmd19OpenZotp + cmdsshadow |
| cmd05 换钥 | 三 KLV (time LE4B/way 1B/skey 16B) 一致；way 位域门禁 H5 '2&way>>1==1' = iOS 'way&2'；needToken=false 是 V81 勘误 (Java 层从不检查 isExpire) | 金标 cmd05Exchange; lock.js:248 注释 |
| cmd08 PIN 批 | addCount/delCount/≤20每批/FFFFFFFF 哨兵一致 | 金标 cmd08SyncPins; LockService.pair 4×16 |
| cmd41 钥匙串 | 四 KLV (#01 mac6B / #02 type1B / #03 pid2B / #04 ekey) = H5 Eu 类逐字段; TrackId random, ValidTo 2118 | 金标 cmd41WriteEkey; main.js @545935 |
| cmd03 状态 24-key | 03/01/04/05/06/07/08/11/14/21-29/31-35 逐 key 一致 | StatusParser.parseStatus vs main.js @363322 判断链 |
| cmd04 开锁应答 | #03 rc / #04 surplusOpen(解析未消费,原版同) / #05 surplusVerify; rc=22 双验 = H5 同语义 | main.js @577111 |
| 录指纹四字段 | #04 orderIdx(1B 反转无损)/#05/#06/#07 反转 — leHexToU32 口径两侧同构 | lock.js:507; LockService.press |
| 广播解析 | 98ed 前缀/frameCtrl 门禁 0x0C/dfu=bit5 与 Java BLEAdData 逐位一致 | jzzns22561_v2/.../BLEAdData.java:131-157 |
| DFU init packet | 两侧消费锁端 .dat 不本地构造; Create→stream→CRC→Execute 同构 | dfu.test.js 真实固件包 |

## 二、修复落地（全部 CI success，含一笔台账）

| 提交 | 类型 | 内容 |
|---|---|---|
| f3cda0c | 台账 | CAPABILITY.md 02/0C/0D 证据升级 |
| e09e9bc | BUG | 双验模式 (verifyMode==1) rc==0 时补「第一道已过」提示 — H5 @577111 行为缺口, 此前对 B 模式谎报"门已打开" |
| 5101f0b | 性能 | CredentialsView.memberSections: ForEach 行级 O(M×N) 全量解码 → 提循环外 O(1) |
| 699337a | 性能 | segFilteredPwds/Fps + selectable + archivedStrip: filter 闭包逐条 isArchived/ext O(N²) 解码 → 集合一次取 |
| 667bfa6 | 性能 | MemberCenterView 认领/挂靠 Picker 数据源 O(M²) ext 解码 → archivedIDs() 外提 |

## 三、销案维度明细（扫描过、判无缺陷）

### 性能（行级热点清零后复扫）
- RecordsView 15 处 DB 调用全在计算属性级 (unhandledCount 有 alarmTick 失效设计); DiagKit/BackupStudioKit 高密度但全事件驱动。
  复算: grep -n 'alarmTick' App/UI/RecordsView.swift
- 循环内 firstIndex/first(where) 四处全为小 N 常数 (alpha 26 字母 / 别名数 / 自定义序数组)。

### 逻辑/数值边界
- 裸 UInt32( 强转 20 处: 常量/带 clamp/failable/布尔三元/数组 count — 无溢出路径; batchU32 负数 trap 已有历史修复 (Store.swift:169)。
- FNV 三套同名异构: AuditChain(unicodeScalars&0xFF) 仅活于 CryptoKit 不可用 #else 死分支; Store(utf8) 应用锁自洽; BackupCanonical 复刻小程序权威且 bundleshadow 锁定。
  复算: grep -rn 'fnv1a32' App --include=*.swift

### 强解包/崩溃点 (全仓 160+ 命中逐一模式归类, 零真崩溃)
- 守卫前置: CredentialOrg.diff (a==nil 提前 return 后才 a!); StatsKit.goldenSentence (total>0 才 top[0]); TimeFormat/BatteryCare/Milestones (count==N 守卫后下标)。
- 协议解析器 fail-closed: ZKProtocol.parseResponse guard count>=14 + bodyOff+len 守卫; FrameAssembler 同; injectToken guard count>=16。
- 常量闭合: DesignSystem.themeTable[role]! 的 role 全部来自同文件静态调用 (contrast.js 闸机兜底); amoledOverride 固定三键。
- 标准目录: FileManager urls(...)[0] iOS 永不空。Calendar date(byAdding:)! 对正常参数不失败 (惯用)。
- try!/as!/.first!/.last!: 全仓 0 命中。

### 内存/泄漏
- Timer.publish().autoconnect() 全部经 .onReceive 订阅 (视图生命周期托管)。
- NotificationCenter observer: ScreenCaptureWatch/LockKeeperApp.kfDeviceShake 全为单例进程期设计 (注释自证"存活期=进程期"), ScreenCare 双 token 陷阱已有历史修复。
- asyncAfter 全为短命 UI 反馈复位 (copied=false 类)。
  复算: grep -rn 'Timer.publish' App --include=*.swift

### 并发/竞态
- LockService/HardwareService @MainActor, BLEService/DFUKit enum 命名空间无实例态; BLE 传入统一 Task{@MainActor} (LockService:24)。
- TOCTOU 九候选全为追加式写入 (await 返回值 → DB.addXxx), 无 check-then-act; CredentialOrg.sendQueued restore 分支 alias 归位系历史修复。

### 备份互通
- iOS Device.Meta 五字段 (defend/tailgate/synctime/otpStatus/otpIdx) = 小程序 META_PREFIXES 五前缀, 收集(:240)/恢复(:418) 双向齐; iOS 侧另有超集扩展 (appearance 16 键/deviceOrg/otpKeys), schema=5 超前拒导入。
  复算: grep -n 'defend' App/Services/BackupKit.swift 对照 miniprogram bundle.js:12

## 四、无法在本机闭合的开口（与前轮交接书一致）
- 真机 10 张验收卡 (§7.9): 需装有 iOS 26.5 模拟器的 Mac。
- 产品拍板 4 条: Siri 暗语入审计 / 引导"上一步" / 995 欢迎卡 / CredBinEntry.id 方案。
复算: awk '/^## 7.9/,/^## 7.10/' docs/HANDOFF-2026-10-15-UI-SWEEP.md
