// LockService · 配对（握手 / 密钥交换 / 续配 / 配对提示）
// 2026-10-29 从 LockService.swift 拆出。
import Foundation

extension LockService {
    // ---------- 密钥面 ----------
    /// 配网尾链中断的提示。参数是"**本机有没有留存这一份密钥**", 而不是"换钥有没有发生":
    /// 留存过就不必去门锁键盘做重置 (再点一次配网会跳过换钥接着配完) —— 这是软砖后路的分水岭。
    static func pairWarning(_ resumable: Bool, _ msg: String) -> String {
        resumable
            ? "\(msg) — 本机已留存这一步的密钥 (skey/PIN/bkey), 再点一次配网会接着配完, 不必做键盘重置"
            : msg
    }

    /// 配网期的 rc → 该怎么办。刻意**不**复用 rcHint: 那一条是"已配对"语境 (rc=3 让你去快捷操作校时),
    /// 而配网期本机还没有钥匙串, 0E 校时根本发不出去 (校时链路要 skey) —— 同一句话在配网语境里是空头支票。
    static func pairHint(_ rc: Int) -> String {
        switch rc {
        case 3, 9: return "锁内时钟不准, 而配网期无法校时 (校时要密钥); 请在门锁键盘上重置后马上重试"
        case 7, 27: return "锁当前不在可配网状态, 请在门锁键盘上做一次重置再试"
        case 13: return "通讯过期: 锁不认这份通讯会话 (会话令牌无效/已过期), 不是距离或信号问题 — 请在门锁键盘上做一次重置, 3 声提示后尽快点配对 (重置后的可配网窗口有限, 一旦超时锁会退回不可配网)"
        default: return "锁可能不在重置态, 请在门锁键盘上重置后重试"
        }
    }

    func keys() throws -> (mac: String, skey: String) {
        let kc = DB.keychain(curMac)
        guard let kc, kc.skey.count == 32 else { throw BLEErrorX.msg("钥匙串缺少有效 skey (请先配对或导入)") }
        return (kc.mac.lowercased(), kc.skey.lowercased())
    }

    // ---------- 密码 ----------
    // 0A 响应 KLV#04 = alias (LE 2B)
    func aliasFrom(_ r: ExecResult) -> Int? {
        // JS: val.length >= 2, raw = len>=4 ? substr(0,4) : val → LE 解析
        guard let k = r.klvs.first(where: { $0.key == 0x04 }), k.val.count >= 2 else { return nil }
        let raw = k.val.count >= 4 ? String(k.val.prefix(4)) : k.val
        return Int(StatusParser.leHexToU32(raw))
    }

    // ---------- 配网编排 (重置后全流程, App devicereset 页) ----------
    func pair(deviceId: String, mac: String, progress: @escaping (String) -> Void) async throws -> Keychain {
        let m = mac.replacingOccurrences(of: ":", with: "").lowercased()
        pairMac = m
        // 把落盘的字节序先灌进协议层: 上次裁定的结果直接作为探针的第一个候选 (少一个来回),
        // 也让"续配"这条路径在重启后的第一帧就按已知顺序成帧。
        ZKProtocol.setMacOrder(m, DB.macOrder(m))
        if let old = DB.keychain(m), !old.skey.isEmpty {
            throw BLEErrorX.msg("该锁已有钥匙串 (MAC=\(old.mac)), 拒绝覆盖配网; 如需重配请先删除该设备")
        }
        try await connect(deviceId: deviceId)
        curMac = m
        defer { pairMac = nil }

        // 0. 续配: 上一次配网在换钥之后中断 (App 被杀 / 08·21·03 任一步失败 / 断链) 时, 锁内 skey
        //    就是本机留存的那一份 —— 先拿它把尾链走完。走不通 (锁被重新重置过, 密钥域已擦) 再回退整链。
        //    这是本 App 最接近"变砖"的那条后路: 没有它, 用户手上没锁 (或锁在门上) 就只能干等下次到锁跟前。
        if let pend = DB.pendingPair(m), !pend.skey.isEmpty, !pend.pins.isEmpty {
            progress("发现上次中断的配网记录 → 先试续配 (不重新换钥)")
            log("info", "续配尝试: 用留存密钥直接走尾链 (留存于 \(pend.pairedAt))")
            do {
                // 2026-10-17 夜: 这里原本先跑一遍只读 03 探针「裁定 MAC 字节序」——已删, 理由见 finishPairing
                // 开头那段: 读类命令证明不了字节序 (MAC 取错它也可能 rc=0), 探针会把错的值裁定成「已知」,
                // 之后这条链上每条写命令都回 rc=12。裁定权现在归真正带 MAC 校验的写命令: 08 批次 1。
                let kc = try await finishPairing(m: m, deviceId: deviceId, skey: pend.skey.lowercased(),
                                                bkey: pend.bkey, pins: pend.pins,
                                                trackid: pend.trackid.isEmpty ? String(KeyGen.genTrackId()) : pend.trackid,
                                                resumable: true, progress: progress)
                DB.clearPendingPair(m)
                connectedMAC = m
                progress("续配完成: \(kc.pidName.isEmpty ? "pid=\(kc.pid)" : kc.pidName) @ \(m)")
                return kc
            } catch {
                log("warn", "续配不通 (\(error.localizedDescription)) → 回退完整配网链 (锁可能已被再次重置)")
                progress("续配不通 (锁可能已再次重置) → 走完整配网")
            }
        }

        progress("步骤 1/7: 探测交换方式 (cmd 23)")
        let w = try await request(ZKCmdBuilder.cmd23ExKeyWay(), cmd: 0x23, needToken: false, retries: 3)
        let way = w.klvs.first(where: { $0.key == 0x01 }).map { StatusParser.intHex($0.val) } ?? 0
        guard way & 2 != 0 else { throw BLEErrorX.msg("交换方式不支持 (exSKeyWay=\(way)), 固件要求 bit1=1") }

        progress("步骤 2/7: 生成本地密钥 (skey/bkey/64 PIN)")
        // genSkey/genBkey 并不抛错, 旧写法套了 `try` (Swift 里是 "no calls to throwing functions" 告警)
        let skey = KeyGen.genSkey()
        let bkey = KeyGen.genBkey()
        let pins = try KeyGen.genPins(64)
        // 全零是"随机源故障"的特征值: 旧 KeyGen 丢弃 SecRandomCopyBytes 的状态码, 失败时返回全零缓冲,
        // 于是锁与本机都用 "0000…" 通信 —— 抓一帧即可解密, 而 7 步流程一路绿灯。此处 fail-closed 中止。
        guard !KeyGen.isAllZeroHex(skey), !KeyGen.isAllZeroHex(bkey),
              !pins.contains(where: { KeyGen.isAllZeroHex($0) }) else {
            throw BLEErrorX.msg("随机源异常: 生成的密钥族含全零字段, 已在换钥前中止 (锁未被改动, 可稍后重试)")
        }

        progress("步骤 3/7: cmd 05 交换密钥 (先建通讯会话)")
        // 2026-10-17 真机现象 + APK 逐字对照勘误: **05 必须带会话令牌**。
        //   APK 原文 (apk_raw/assets/www/build/main.js, 05 构造器 `Et`):
        //     l.call(this, Jn.ZKCCOMM_EXSECURITYKEY, !0, "0000")   ← 第二个实参 = needSSToken = **true**
        //   Java 侧据此执行 (cn.zelkova.ZKurlcsPlugin.lockprotocol.BleLockConnector.doExecute):
        //     if (data.needSessionToken()) { doRefreshSsToken(); token = ssToken.getToken(); }
        //     → LockCommBase.getBytes(token) 把令牌作为 KLV#0xEE **追加在帧尾**
        //   ⇒ 真机真序是: 23(免令牌) → 01(取令牌) → 05(带 KLV#0xEE) → ...
        //   本机 (与 vendor/app/utils/kernel/cmds.js:cmd05Exchange 的"免令牌明文"模型) 一直把 05 裸发,
        //   锁于是回 rc=13「通讯过期」—— 报的是**通讯会话**无效 (没有有效令牌), 而不是命令时间 (那是 rc=3)。
        //   真机复现: 锁重置后点配对 → rc13 → 锁随之退出可配网态, 反复都是 rc13。
        var r5 = try await request(ZKCmdBuilder.cmd05Exchange(skey), cmd: 0x05, needToken: true, retries: 3)
        var rc5 = extractRc(0x05, r5)
        if rc5 == 13 {
            // 13 = 通讯过期 = 会话令牌被判无效/已过期。rc≠0 ⇒ 锁**没有执行**换钥 (锁内 skey 未动),
            // 所以重开一次会话再发一帧是安全的 — 这是 rc13 唯一可安全重试的时机 (rc=0 之后再发就会
            // 二次擦写锁内密钥域)。request(needToken:true) 每轮都会重新走 01, 令牌必然是新的。
            log("warn", "05 rc=13 (通讯过期): 重开会话令牌后重试一次 · 回包 " + Self.klvShape(r5))
            r5 = try await request(ZKCmdBuilder.cmd05Exchange(skey), cmd: 0x05, needToken: true, retries: 1)
            rc5 = extractRc(0x05, r5)
        }
        if rc5 != 0 {
            // 真机报告 (2026-10-17): 用户报"锁重置后一直添加不成功", 而运行日志里只有 TX/RX 两行 ——
            // 05 被锁拒收的原因既没进日志、也没进任何台账, 于是现场只能靠回包长度反推。
            // 这里把判决 (rc + 人话 + 该做什么) 与证据 (回包 KLV 的键与长度, 值一概不写) 一起留下。
            log("error", "05 换钥被锁拒收: rc=\(rc5) (\(StatusParser.rcMessage(rc5))) · \(Self.pairHint(rc5))"
                + " · 回包 " + Self.klvShape(r5))
            throw BLEErrorX.msg("换钥失败 rc=\(rc5) (\(StatusParser.rcMessage(rc5))) — \(Self.pairHint(rc5))")
        }
        // rc=0 = 锁**已经执行**了交换 (vendor lock.js: 执行即擦旧钥域) ⇒ 从这一刻起锁内密钥就是新的。
        // (旧实现在这里还有一个 `keyExchanged = true` 旗子, 写在回显比对**之后** —— 于是回显异常那一支
        //  只报"已中止", 读起来像"锁没被动过"; 那个旗子现已全部换成"本机有没有留存密钥"，
        //  因为对用户真正要紧的不是换钥发没发生, 而是他还能不能不再跑一趟锁跟前。)
        if let echo = r5.klvs.first(where: { $0.key == 0x02 }), echo.val.lowercased() != skey.lowercased() {
// skey 明文绝不进错误文案：该串会写入 lastError → DiagLogs → kf.diag_logs（现已 isExcludedFromBackup，不随系统备份）与 UI 展示。
// 2026-10-27 审核修复 (AUDIT-B 2.8 #10)：原注释说「随系统备份」——
// D-44 那批已把 `kf_diag_logs` 迁到 `Caches/` 并设 isExcludedFromBackup，所以它不再出机。
// 但「不进错误文案」这条纪律不变：它仍会被导出中心带走、也会显示在界面上。
            log("error", "05 换钥回包密钥不一致: 回显 \(echo.val.count) 位 / 本地 \(skey.count) 位 · 回包 " + Self.klvShape(r5))
            // 回显不匹配时**不能**说"再点一次就能续配": 锁端那一份是本机读不懂的, 续配也白搭。
            // 这类必须去键盘重置 —— 文案与可续配那一族明确分开 (pairWarning(false, ...) 不追加续配承诺)。
            throw BLEErrorX.msg(Self.pairWarning(false,
                "换钥回显不匹配 (本地/回显长度 \(skey.count)/\(echo.val.count)) — 锁内密钥已是本机读不懂的一份, 无法续配; 请在门锁键盘上重置后重新配网"))
        }

        progress("步骤 4/7: 留存本次密钥 (配网中断可续配)")
        // 从 05 rc=0 这一刻起, 锁内 skey 已经是新的一份。旧实现要等到尾链全部成功才落盘 ⇒ 尾链任一步
        // 失败就只剩"去门锁键盘重置"一条路 (锁内部密钥对本机不可知 = 软砖)。现在换钥后立即留存,
        // 尾链走完再提升为正式钥匙串 (saveKeychain + clearPendingPair)。
        let pending = Keychain(version: 1, mac: m, skey: skey, bkey: bkey, pins: pins,
                               ekey: ZKCmdBuilder.buildEkeyOpen(skey, m, pins[0]),
                               trackid: String(KeyGen.genTrackId()), bleId: deviceId, fw: "",
                               pairedAt: ISO8601DateFormatter().string(from: Date()))
        let resumable = DB.savePendingPair(pending)
        if resumable {
            log("info", "已留存换钥后的密钥 (尾链若中断, 再点一次配网即续配, 无需键盘重置)")
        } else {
            log("error", "配网中断保护未能落盘 (系统 Keychain 写失败) — 尾链若中断只能靠门锁键盘重置恢复")
        }

        // 步骤 4.5/7 的「只读 03 探针」整块删除 (2026-10-17 夜; 依据 = 原版 APK 逐字 + 真机现象):
        //   ① 读类命令**证明不了**包络 MAC 的字节序 —— 03 即使 MAC 取错也可能回 rc=0, 于是探针会把一个
        //      错的取法裁定成「已知」并写进 `kf_macorder_<mac>`, 之后这条链上每条写命令都回 rc=12;
        //   ② 原版 APK 在 05 与第一批 08 之间**不发任何命令** (main.js: exchangeSKey → syncPins);
        //      我们插进去的 01+03 两个来回是自创动作。裁定权改为交给带 MAC 校验的写命令 08 批次 1
        //      (见 finishPairing)。

        let kc = try await BackgroundGuard.run("配网尾链") { try await finishPairing(m: m, deviceId: deviceId, skey: skey, bkey: bkey, pins: pins,
                                        trackid: pending.trackid, resumable: resumable, progress: progress) }
        DB.clearPendingPair(m)   // 尾链成功才摘掉中断记录 (先删再落库会造出"无保护"窗口)
        cleanWrongOrderTwin(m)
        connectedMAC = m
        return kc
    }

    /// 清掉一份"MAC 正好反过来"的幽灵台账。2026-10-17 的 rc=12 (mac地址不正确) 就是这么来的:
    /// 旧版把广播里的**线上序** macRaw 当 MAC 落库, 那份记录从未与锁对上过一次话, 却会一直挂在
    /// 设备页里 (同一把锁两条记录, 删了一条另一条还在)。配网成功后顺手清掉 ——
    /// 只在**配对确实成功**时做, 所以不会误删一份正在用的台账。
    func cleanWrongOrderTwin(_ mac: String) {
        let twin = HexKit.reversePairs(mac).lowercased()
        guard twin != mac, DB.keychain(twin) != nil else { return }
        DB.removeKeychain(twin)
        log("warn", "清掉一份 MAC 顺序相反的幽灵台账 (\(twin)) — 旧版把广播线上序当锁 MAC 留下的")
    }

    /// 配网尾链 (步骤 5~7 + 落库)。**完整配网与续配共用同一条尾链** ——
    /// 分开写迟早只改一条, 而"续配"漏一步的后果正好是软砖。
    func finishPairing(m: String, deviceId: String, skey: String, bkey: String, pins: [String],
                               trackid: String, resumable: Bool,
                               progress: @escaping (String) -> Void) async throws -> Keychain {
        log("info", "配网尾链 MAC 字节序 = \(ZKProtocol.macOrder(m).rawValue) (默认 = 原版 APK 语义, 显示序)")
        // 批大小 20 = 原版 APK 逐字 (main.js syncPins20: `o>20?20:o` + `generateRandomNumbers(64)`)
        // ⇒ 真机帧序列是 20/20/20/4 四批。旧版取 16("让单帧更小") 是自创: 锁端若按固定 20 槽位对位解析这一批,
        // 16 的批就会让后续字节错位 —— 而错位读出的"目标 MAC"正好会回 rc=12「mac地址不正确」。
        // 既然要求与 APK 完全一致, 这里不再打折。
        let batchSize = 20
        let batches = (pins.count + batchSize - 1) / batchSize
        progress("步骤 5/7: 同步 PIN 池 (\(pins.count) 个 / \(batches) 批)")
        var i = 0
        var n = 0
        while i < pins.count {
            n += 1
            let batch = Array(pins[i..<min(i + batchSize, pins.count)])
            let del = (i == 0) ? [KeyGen.delPinSentinel] : []
            guard let c = ZKCmdBuilder.cmd08SyncPinsBatch(m, skey, batch, delPins: del) else {
                throw BLEErrorX.msg("PIN 批次构建失败")
            }
            var rb = try await exec(c)
            // ---- 包络 MAC 字节序的**唯一**裁定点 (2026-10-17 夜) ----
            // 拿第一批当判据, 而不是另发一条只读探针: 08 是**带 MAC 校验的写命令**, 它的 rc=12 才是锁端
            // 真的比过那 6 字节后给出的答案; 而 rc≠0 的语义是"锁没执行"(见 docs/BRICK-AUDIT.md), 所以
            // 同一批换序重发是**安全重发**, 不是盲写两遍。只对第一批做: 后面的批次若也 rc=12, 那是别的问题,
            // 换序同样白搭 —— 不如立刻停手, 让用户少跑一趟锁跟前。
            if rb.rc == 12, n == 1 {
                let used = ZKProtocol.macOrder(m)
                let other = ZKProtocol.flipped(used)
                ZKProtocol.setMacOrder(m, other)
                log("warn", "PIN 批次 1 rc=12 (mac地址不正确) → 换一种包络 MAC 字节序 (\(other.rawValue)) 重发本批"
                    + " · 原序 " + used.rawValue + " · 回包 " + Self.klvShape(rb.frame))
                let rb2 = try await exec(c)
                if rb2.rc == 0 {
                    DB.setMacOrder(m, other)
                    log("info", "包络 MAC 字节序裁定 = \(other.rawValue) (08 批次 1 换序后 rc=0); 此后本机对这把锁一律按它成帧")
                    rb = rb2
                } else if rb2.rc == 18 {
                    // 18 = 不能设置重复的值 ⇒ 这一批其实已经写进锁里了: 原序是对的, rc=12 来自别的地方。
                    ZKProtocol.setMacOrder(m, used)
                    log("info", "PIN 批次 1 换序后 rc=18 (重复值) ⇒ 原序 \(used.rawValue) 有效, 本批视为已写入")
                    rb = ExecResult(frame: rb2.frame, rc: 0, klvs: rb2.klvs)
                } else {
                    ZKProtocol.setMacOrder(m, used)
                    log("error", "PIN 批次 1 两种字节序都被拒: 原序 rc=12 / 换序 rc=\(rb2.rc) — 不是字节序问题"
                        + " · 回包 " + Self.klvShape(rb2.frame))
                    rb = rb2
                }
            }
            if rb.rc != 0 {
                log("error", "PIN 批次 \(n) 被锁拒收: rc=\(rb.rc) (\(StatusParser.rcMessage(rb.rc))) · 回包 " + Self.klvShape(rb.frame))
                throw BLEErrorX.msg(Self.pairWarning(resumable, "PIN 批次 \(n) 失败 rc=\(rb.rc) (\(StatusParser.rcMessage(rb.rc)))"))
            }
            i += batchSize
        }

        progress("步骤 6/7: 设置 bkey (cmd 21)")
        let r21 = try await exec(ZKCmdBuilder.cmd21SetBkey(m, skey, bkey))
        if r21.rc != 0 {
            log("error", "21 bkey 被锁拒收: rc=\(r21.rc) (\(StatusParser.rcMessage(r21.rc))) · 回包 " + Self.klvShape(r21.frame))
            throw BLEErrorX.msg(Self.pairWarning(resumable, "bkey 失败 rc=\(r21.rc) (\(StatusParser.rcMessage(r21.rc)))"))
        }

        progress("步骤 7/7: 加密状态校验 (cmd 03)")
        let stR = try await exec(ZKCmdBuilder.cmd03StatusWrap(m, skey))
        let st = StatusParser.parseStatus(stR.klvs)
        if stR.rc != 0 {
            log("error", "03 加密回读校验被锁拒收: rc=\(stR.rc) (\(StatusParser.rcMessage(stR.rc))) · 回包 " + Self.klvShape(stR.frame))
            throw BLEErrorX.msg(Self.pairWarning(resumable, "配对校验失败 rc=\(stR.rc) (\(StatusParser.rcMessage(stR.rc)))"))
        }

        let kc = Keychain(version: 1, mac: m, pid: st.pid, pidName: st.pidName,
                          skey: skey, bkey: bkey, pins: pins,
                          ekey: ZKCmdBuilder.buildEkeyOpen(skey, m, pins[0]),
                          trackid: trackid, bleId: deviceId, fw: st.firmware,
                          pairedAt: ISO8601DateFormatter().string(from: Date()))
        DB.saveKeychain(kc)
        progress("配网完成: \(st.pidName.isEmpty ? "pid=\(st.pid)" : st.pidName) @ \(m)")
        return kc
    }

}
