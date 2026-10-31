// BackupBundle.swift —— 备份包的数据结构（从上一版 BackupKit.swift:165-289 照搬）。
//
// 为什么单独拆出来：BackupCanonical（规范化与校验）与 BackupStudioKit（恢复编排）都要它，
// 而 BackupKit 本体原来带着 4 处对设计系统 HeroStats 的引用 —— 那个类型现在已搬进 Engine/HeroStats.swift。
// 数据结构是纯逻辑，拆出来就不必为了它把整个 UI 耦合拖进来。
struct BackupBundle: Codable {
    var type: String = "kf-bundle"
    var bundleVer: Int = 2
    // 414 版本头标注 (原句"semver"): 包头带 schema 版本号，恢复时按 v1→v5 **逐级**幂等迁移 (424 的升级链)，
    // 恢复预演页把"包内版本 → 当前版本"显示出来再决定是否执行。
    // 为什么用整数而不是 semver 三段: 本仓的备份结构靠序号驱动迁移，
    // 写成语义化版本会让读者以为 patch 位有含义 —— 那是要人猜的字段。
    var schema: Int = 5
    /// 本机支持的最高 schema (导入时拒绝更高的包, 防字段被误读且无告警)。
    static let currentSchema = 5
    var at: String
    var currentMac: String = ""
    var devices: [Device]
    var members: [Member]?
    var globals: Globals?
    struct Device: Codable {
        var mac: String
        var kc: Keychain
        var ledger: Ledger?
        var meta: Meta?
        struct Meta: Codable {
            var defend: DefendCfg?
            var tailgate: TailgateCfg?
            var synctime: Double?
            var otpStatus: OtpStatus?
            var otpIdx: OtpIdx?
            /// 手机钥匙（kf_mkey_<mac>）。与「蓝牙钥匙串」不同：这是发给成员手机的 ekey 记录，
            /// 含 pin / ekey / 归属成员 / 有效期。缺省 = 这次备份没带 = 恢复时不动本机（与其它字段同口径）。
            var mobileKeys: [MobileKey]?
            /// 记录页覆盖层（按行键挂在本机，2026-10-30 第 66 轮补）：
            ///   · 行备注（kf_rnote_）—— 用户手写的自由文本；
            ///   · 行标旗（kf_rflag_）；
            ///   · 行处置（kf_rdisp_）—— 「标记已处置 / 撤销」，告警排查的核心。
            /// 这三族此前既不进备份、也不进回滚。restore 会整表替换台账 / 重建成员 ⇒ 行键全部失效，
            /// 不收就等于「备注和旗标凭空没了」。缺省 = 这次备份没带 = 恢复时不动本机。
            var recNotes: [String: String]?
            var recFlags: [String]?
            var recDisps: [String: String]?
        }
    }
    struct Globals: Codable {
        var keychainDongles: [Dongle]?
        var gatewayList: [Gateway]?
        var passcode: PasscodeRec?   // JS 包互通: {s,d} 应用锁摘要
        /// 胁迫码摘要（kf_duress，与 passcode 同结构）。
        /// 2026-10-30 修复（第 64 轮）：这一项**从来没进过备份** —— 用户换机后胁迫码直接丢，
        /// 而「被胁迫时输它会进空壳模式」是一条安全承诺；承诺在换机后静默失效是「不正常」。
        var duress: PasscodeRec?
        var trace: TraceRec?         // JS 包互通: LOCK 日志恢复档 (原样存取)
        /// 894 外观随备份走: **typed 结构而不是自由字典**。
        /// 用字典就等于把"任意偏好键写入"重新开放给一个可伪造的 JSON 字段。
        /// 当初踩过的坑 (本文件 :239-253 的白名单就是为它加的)。typed 之后，包体能影响的键
        /// 只有下面这些，且每个值都还要过一遍档位白名单 (见 Appearance.apply)。
        /// 全部字段可选：缺字段 = 这次备份没带 = 恢复时不动本机，而不是"重置成默认"。
        var appearance: Appearance?
        struct Appearance: Codable {
            var theme: String?        // kf_theme  ""/light/dark/black
            var accent: String?       // kf_accent 六套品牌色之一
            var density: String?      // kf_density
            var radius: String?       // kf_radius (900)
            var hc: Bool?             // kf_hc (893)
            var weekStart: String?    // kf_week_start (912)
            var rowH: String?         // kf_row_h (901)
            var tlGap: String?        // kf_tl_gap (907)
            var motion: String?       // kf_motion (899)
            var heroTex: String?      // kf_hero_tex (889)
            var plain: Bool?          // kf_plain (1046)
            var recentCount: Int?     // kf_recent_count (910) → JSON 键名是 "recent"
            var heroStats: [String]?  // kf_hero_stats (909)
            // 2026-10-30 补（第 65 轮）：**无障碍与交互偏好**从来没进过备份。
            // 判据同外观那批：①用户主动拨的 ②App 靠它们改变行为。
            // 用户换了机、导了备份，却发现「大字模式 / 大格 / 长按时长 / 圆盘大小 / 手势」全部回到默认 ——
            // 对依赖无障碍档的人来说，这等于换机后 App 突然不可用。
            // 全部 Optional：缺字段 = 这次备份没带 = 恢复时不动本机。
            var axBigOtp: Bool?       // kf_ax_bigotp  OTP 大字
            var axBigPreview: Bool?   // kf_ax_bigpreview  大预览
            var axHold: String?       // kf_ax_hold  长按时长 (字符串形态 "0.9")
            var bigTile: Bool?        // kf_bigtile  2 列大格
            var dialSize: Int?        // kf_dial_size 圆盘直径 160/176/200
            var digitFont: String?    // kf_digit_font ""/plain
            var gestureMode: String?  // kf_gesture_mode 手势档
            var holdConfirm: Bool?    // kf_hold_confirm 长按确认
            var dbltapGuard: Bool?    // kf_dbltap_guard 双击防抖
            var elderMode: Bool?      // kf_elder_mode 长辈模式

            /// 显式的键映射 —— 只有 recentCount 一处的 Swift 名与 JSON 键不同。
            ///
            /// 修的 bug: canonical 写出的键是 "recent" (BackupCanonical:229 的
            /// av.append(("recent", ...)))，而合成的 Codable 按**字段名**解码，
            /// 找的是 "recentCount" → 永远 nil。
            /// 于是导入端重算 canonical 时少了这个字段 → checksum 必然对不上 → 整包被拒。
            ///
            /// 影响面: 只要备份包的外观段带 recent (即用户把"最近记录条数"设成 3/5/10)，
            /// 这份包**永远导不回来**。
            ///
            /// 为什么用 CodingKeys 而不是把字段改名成 recent:
            /// 字段名 recentCount 在 BackupKit / BackupStudioKit 里被多处引用，改名牵连面大；
            /// 而问题本质是 "JSON 键名与 Swift 名不同"，正是 CodingKeys 的用途。
            enum CodingKeys: String, CodingKey {
                case theme, accent, density, radius, hc, weekStart, rowH, tlGap
                case recentCount = "recent"
            }
        }
        /// D-36 (2026-10-11 拍板「同意进包」): 设备组织随包 —— 顺序 / 分组 / 分组折叠 / 隐藏。
        /// 四点写在这里, 免得下一个人照"包格式变更"的直觉去动 schema:
        ///  ① 这是 globals 里的**可选增量段**, 与 894 appearance 同先例; 旧读者忽略它, 缺字段 = 恢复时不动本机。
        ///  ② **不升 schema**: bundle.js 有一道 `schema > SCHEMA_VERSION` 的闸, 小程序端今天还是 v5 ——
        ///     升到 v6 会让它把整包判成"来自更新版本"直接拒收, 把一次可选增强变成互通性事故。
        ///  ③ 一律用**数组**而不是字典: 小程序 canonicalBundle 对 globals 内层是原样透传 (只对顶层键排序),
        ///     字典的键序在两端不可控; 数组没有这个问题, groups 按 mac 排与 devices 同口径。
        ///  ④ 落地侧逐项白名单 (只认本包里真有的 mac / 真存在的组名), 见 restoreAll。
        var deviceOrg: DeviceOrg?
        struct DeviceOrg: Codable {
            var order: [String]?      // kf_lock_order: mac 全序列 (小写无冒号)
            var groups: [GroupRec]?   // kf_lockmeta_<mac>.grp
            var folded: [String]?     // kf_group_folded: 被收起的组名
            var hidden: [String]?     // kf_lock_hidden_<mac> = true 的 mac
            struct GroupRec: Codable { var mac: String; var name: String }
        }
        struct PasscodeRec: Codable { var s: String; var d: String }
        struct TraceRec: Codable { var savedAt: Double?; var count: Int?; var chars: Int?; var lines: [String]? }
    }
    var checksum: String?
}

