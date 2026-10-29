// 指纹详情 + private extension Double.credDay()
// 2026-10-29 从 CredentialStudio.swift 拆出。credDay 是 private extension，只被 FpDetailStudio:2314 用，必须同文件
import SwiftUI
import UIKit
import AVFoundation

struct FpDetailStudio: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) var dismiss
    let batch: Int
    @State private var busy = false
    @State private var showRelink = false   // 319 重录入口 sheet
    private var mac: String { app.current?.mac ?? "" }
    private var f: LedgerFp? { DB.getFp(mac, batch) }

    var body: some View {
        if let f = f {
            NavigationStack {
                List {
                    // 2026-10-29 补：同 PwdDetailStudio —— 停用原因回显（没标记就不显示，不编）
                    if let mark = CredentialOrg.disableMarkText(mac, kind: "fp", key: f.batch) {
                        Section {
                            Label {
                                Text(mark).fixedSize(horizontal: false, vertical: true)
                            } icon: {
                                Image(systemName: "pause.circle.fill")
                            }
                            .vkFont(.caption)
                            .foregroundStyle(DS.Palette.warn)
                        }
                    }
                    // 324 冗余横条: 该成员名下仅剩此枚 → 提示补备用
                    if CredentialOrg.fpCountByOwner(mac, f.owner) == 1 {
                        Section {
                            Label("该成员名下仅剩 1 枚指纹, 建议补一枚备用", systemImage: "bell.badge")   // 324 该成员名下仅剩
                                .vkFont(.caption)
                                .foregroundStyle(DS.Palette.warn)
                        }
                        .listRowBackground(DS.Palette.warn.opacity(0.06))
                    }
                    // 316 档案三行统计 (⚠ 台账推断+积累, 标"约")
                    Section("档案 (约)") {
                        fpRow("登记", f.at > 0 ? "登记于 " + f.at.credDay() : "已登记在门锁内")
                        let useN = CredentialOrg.fpUseCount30d(mac)
                        if useN > 0 {
                            fpRow("近 30 天指纹开门", "约 \(useN) 次 (日志无指纹身份字段, 整锁推断)")
                        }
                        // 320 误识档案 (⚠ 锁端 type13 语义待实测, 只展示本地日志计数标"约")
                        let alarmN = CredentialOrg.fpAlarmLogCount(mac)
                        fpRow("指纹告警日志", alarmN > 0 ? "约 \(alarmN) 条 (type13, 语义待实测)" : "无 (type13)")
                    }
                    Section {
                        fpRow("名称", f.name)
                        fpRow("归属", CredentialOrg.ownerName(f.owner).isEmpty ? "未归属" : CredentialOrg.ownerName(f.owner))
                        fpRow("备注", f.note.isEmpty ? "无" : f.note)
                        fpRow("来源", f.src == "app" ? "本机录入" : "锁端发现")
                        fpRow("预警", f.isAlarm == true ? "预警指纹" : "普通")
                    }
                    Section {
                        // 319 重录入口: 卡里直接重录, 归属/替换旧枚自动带过去
                        Button { showRelink = true } label: {
                            Label("重录一枚替换它", systemImage: "arrow.clockwise")   // 319 重录一枚替换它
                        }
                        .vkFont(.subheadline)
                        .foregroundStyle(DS.Palette.accentText)
                    }
                    Section {
                        // 323 删除双签: 最后一枚需密码前缀验证
                        if busy {
                            ProgressView("删除中…")
                                .vkFont(.caption)
                                .foregroundStyle(DS.Palette.textSub)
                                .frame(minHeight: DS.Hit.min)
                        } else {
                            Button(role: .destructive) {
                                fpDoubleSignCheck(mac: mac, batch: batch, confirmTitle: "彻底删除") {
                                    Task { await delete() }
                                }
                            } label: {
                                // 210 图标一致: 「彻底删除」全仓统一 trash —— trash 已被「回收站」占住
                                // (CredentialsView 那一行 Label("回收站 (N)", systemImage: "trash")), 在回收站里
                                // 用同一枚垃圾桶画"不可逆地抹掉"等于让图标自己跟文字打架。
                                // 另一处同标签落点是 CredentialCenterView 的 swipeAction, 它就是 trash。
                                Label("彻底删除", systemImage: "trash")   // 323 彻底删除
                            }
                            .vkFont(.subheadline)
                            .foregroundStyle(DS.Palette.danger)
                        }
                    }
                }
                .navigationTitle(f.name)
                .variantList()
                .dsScreenBackground()
                .toolbar { ToolbarItem(placement: .navigationBarLeading) { Button("关闭") { dismiss() } } }
                .sheet(isPresented: $showRelink) {
                    FpStudio(prefillOwner: f.owner, prefillReplace: true)   // 319
                }
            }
        } else {
            EmptyState(systemImage: "touchid", title: "指纹不存在", message: "这条指纹可能已被删除（本机没有回收站，删除不可恢复）。")
        }
    }
    private func fpRow(_ k: String, _ v: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s) {
            Text(k)
                .vkFont(.subheadline)
                .foregroundStyle(DS.Palette.textSub)
            Spacer(minLength: DS.Space.m)
            Text(v)
                .vkFont(.subheadline)
                .foregroundStyle(DS.Palette.text)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
    private func delete() async {
        guard let kc = app.current, let f else { return }
        // 2026-10-13 对抗式排查: UInt32(越界 Int) 是 trap ⇒ 先安全转换, 越界直接中止并说明
        guard let b = f.batchU32 else {
            app.showToast("指纹「\(f.name)」批次号越界 (\(f.batch))，已中止 — 台账或备份来源可能损坏")
            return
        }
        busy = true
        defer { busy = false }
        do {
            try await app.lock.ensureConnected(mac: kc.mac)
            try await app.lock.fpDelete(b)
            // 同上: 锁端删的是入口捕获的那把锁，本机台账与回收站也必须记在同一把锁上
            // 确认口径：删除入口那一把按钮先过 fpDoubleSignCheck —— 最后一枚要前缀双签，
            // 其余也要走一遍确认，两支都不存在「一按就删」(第一百六十七批补的正是后半支)。
            DB.delFp(kc.mac, f.batch)
            app.flashReceipt("已写入本机")   // 508 已写入本机
            // 原来这句写死「回收站 30 天可找回」：30 天是 `kf_cbin_reclaim_days` 可调项 (写死就会在
            // 用户改成 7/90 天时说谎)，更要命的是「可找回」对指纹只成立一半 —— 回来的名称/备注/归属
            // 是档案，锁端那条模板已经删了，开门能力必须本人重录 (回收站页 670 早就把这句写明了)。
            app.showToast("指纹已删除：本机这条档案直接移除、不可找回，开门要本人到锁前重录")   // 670 界面文案
        } catch {
            app.showToast("删除失败: " + error.localizedDescription)
        }
    }
}

// Double 台账毫秒 → 本地日期串 (凭证页同源, 局部实现)
private extension Double {
    func credDay() -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: Date(timeIntervalSince1970: self / 1000))
    }
}

