// LinkSense · 重连阶梯（预热 / 自动重连 / 退避 / 唤醒失败归因）
// 2026-10-29 从 LinkSenseKit.swift 拆出。
import Foundation
import UIKit

extension LinkSense {
    func preconnect() async {
        guard !DiagFlags.silent else { return }   // 127 静默排查模式: 暂停全部自动连接
        let app = self.app
        guard let mac = app?.currentMac, !mac.isEmpty, sceneActive,
              app?.unlockState == .idle, lockSvc.connectedMAC != mac else { return }
        guard DB.store.getBool("kf_link_auto_" + mac, true) else { return }
        do {
            let dev = try await scan(mac: mac, timeoutMs: 6000)
            if let rssi = dev?.rssi { updateRssi(rssi) }
            guard let dev = dev else {
                BleTelemetry.recordAttempt(mac: mac, ok: false, reason: "未发现 (不在广播范围或锁未广播)")
                BleTelemetry.recordEvent("预握手： 未发现 " + String(mac.prefix(6)), ok: false)
                lockSvc.log("warn", "预握手： 扫描未发现 \(mac), 不在广播范围")   // 134/130 预握手
                reconnectAttempt += 1
                return
            }
            let fence = LinkSense.rssiFence
            if dev.rssi < fence {
                BleTelemetry.recordAttempt(mac: mac, ok: false, reason: "RSSI \(dev.rssi) 低于围栏 \(fence), 跳过预热")
                BleTelemetry.recordEvent("预握手： 信号弱跳过", ok: false)
                lockSvc.log("info", "预握手： RSSI \(dev.rssi) 低于围栏 \(fence), 低信号不浪费电量")   // 93 预握手
                reconnectAttempt += 1
                return
            }
            let t0 = CFAbsoluteTimeGetCurrent()
            try await lockSvc.ensureConnected(mac: mac)
            let ms = Int((CFAbsoluteTimeGetCurrent() - t0) * 1000)
            connectSource = "预热"
            markReady(ms: ms, rssi: dev.rssi)
            lockSvc.log("info", "预握手完成： 耗时 \(ms)ms (只预热不执行， 96)")
            // 276: 同一次节律里顺手把其余常用锁也扫一遍 —— 不另开定时器 (预握手本身就是节律入口),
            // 也不改上面那条单锁链的任何判断 (它仍然只决定当前锁要不要预热)。
            if !Task.isCancelled { await preconnectOthers() }
            if dev.rssi >= -55, let host = AppState.hostRef, !(CareSchedule.quietOn && CareSchedule.isQuietHour()) {   // 99 近场轻提醒 (274 免扰时段静默)
                Task { @MainActor in DS.Haptics.tick.impactOccurred() }
                host.showToast("锁就在附近， 已就绪")   // 99 锁就在附近
            }
            BleTelemetry.recordAttempt(mac: mac, ok: true, reason: "预握手 \(ms)ms")
            BleTelemetry.recordEvent("预握手完成 \(ms)ms", ok: true)
            DiagOps.record("预握手 \(mac.prefix(6))")
        } catch {
            let kind = classifyFailure(error)
            BleTelemetry.recordAttempt(mac: mac, ok: false, reason: kind.name + " " + error.localizedDescription)
            BleTelemetry.recordEvent("预握手失败 \(kind.name)", ok: false)
            lockSvc.log("warn", "预握手失败 (\(kind.name)): \(error.localizedDescription)")   // 536 预握手失败
            reconnectAttempt += 1
        }
    }

    func autoReconnectTick() {
        guard !DiagFlags.silent else { return }
        let app = self.app
        guard let mac = app?.currentMac, !mac.isEmpty, sceneActive else { return }
        // 靠近自动开锁 (AUTOOPEN): 2s tick 驱动 F3 滤波与全门判定。
        // 注意: 早期写过的「静置满 3s」(F2' 停留判定) **已从实现删除** —— 现在只按 RSSI 回差武装,
        // 不再要求停留时长; tickDwell 只做推进与超时, 不做静置门。
        // 全门不过 = 静默拒绝 + 审计 (绝不自动开锁, 96 铁律由 AutoOpenController 内部门控兜底)
        AutoOpenController.shared.tickDwell(mac: mac)
        // 已连上这把锁: 门锁一旦连接就**停止广播**, didDiscover 那一侧不再产生样本 ——
        // 于是自动开锁的武装位 (feedRssi) 收不到新数, 表现就是用户报的两条:
        //   · 连上之后"信号再也不更新";
        //   · 开完锁走开再回来, 不会再自动开 (armed 回不来)。
        // 解法: 从**已建立的连接**上按节拍取一次 RSSI (readLinkRSSI → didReadRSSI), 喂回同一条
        // saveRssi → updateRssi → feedRssi 链。与安卓 BleUnlocker.observeSignal 的 readRemoteRssi 同解。
        // 只在已连接、前台 (sceneActive, 上面已 guard)、非静默档时取 —— 后台不测不扫, 不耗电。
        if lockSvc.connectedMAC == mac {
            BLEService.shared.readLinkRSSI { rssi in
                guard let rssi else { return }   // 读不到就不发明数据 (与安卓同一口径)
                // saveRssi 是 @MainActor 上的静态方法, 而这个闭包由 BLEService 调用 (非隔离类型);
                // 运行时它确实落在主线程 (CBCentralManager 建在 queue: .main), 但**类型上不保证** ——
                // 显式跳一次, 与本文件 saveRssi 里喂 feedRssi 的写法同构, 不靠"大概都在主线程"。
                Task { @MainActor in Self.saveRssi(mac: mac, rssi: rssi) }
            }
            return
        }
        guard DB.store.getBool("kf_link_auto_" + mac, true) else { return }
        if Date().timeIntervalSince(lastLadderAt) < nextLadderInterval() { return }
        lastLadderAt = Date()
        let kind = reconnectAttempt
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await self.lockSvc.ensureConnected(mac: mac)
                BleTelemetry.recordAttempt(mac: mac, ok: true, reason: "回连成功 (第 \(kind + 1) 轮)")
                BleTelemetry.recordEvent("回连成功 (第 \(kind + 1) 轮)", ok: true)
                // 274 免打扰时段: 回连是系统替用户跑的动作, 夜里不该凭它震一下 (与 :111 近场提醒同一把闸)
                if !(CareSchedule.quietOn && CareSchedule.isQuietHour()) {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
                self.lastReconnectAt = Date()
                if kind > 0 {
                    AppState.hostRef?.showToast("回到锁身边")   // 132 回到锁身边
                }
                self.connectSource = "回连"
                self.markReady(ms: self.connectMs, rssi: self.lastRssi)
            } catch {
                BleTelemetry.recordAttempt(mac: mac, ok: false, reason: "回连失败 (第 \(kind + 1) 轮) \(self.classifyFailure(error).name)")
                BleTelemetry.recordEvent("回连失败 (第 \(kind + 1) 轮)", ok: false)
                self.reconnectAttempt = min(kind + 1, LinkSense.ladderSeconds.count)
            }
        }
    }

    /// 三态切换时记一笔 (LinkPill 宿主 onChange 调用), 封顶 5 条
    func noteStateHop(_ name: String) {
        var list = LinkSense.history()
        list.insert(StateHop(at: DiagTime.mmddHHmm(), to: name), at: 0)
        if list.count > 5 { list = Array(list.prefix(5)) }
        DB.store.setCodable("kf_link_hist", list)
    }

    /// 95 进页预热入口 (DeviceHomeView.task 调用): 静默 ensureConnected, 成功后顺手 135 补发。
    func enterPage() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.preconnect()
        }
    }

}
