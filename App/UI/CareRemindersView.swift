// ================= 关怀提醒与公告板 =================
// 2026-10-20: 从被删除的 AchievementsView.swift 中独立出来 (Q11 只删成就页, 关怀提醒保留)。
import SwiftUI

// ================= 关怀提醒与公告板 (1010/991/1044) =================
struct CareRemindersView: View {
    @EnvironmentObject var app: AppState
    @State private var bulletin = Milestones.bulletin

    var body: some View { vkBody.destined(.careReminders) }
    var vkBody: some View {
        ZStack {
            XPalette.canvas.ignoresSafeArea()

            ScrollView {
                VStack(spacing: XSpace.l) {
            XPanel(kind: .group) {
                VStack(alignment: .leading, spacing: XSpace.m) {
                    secLabel("家庭公告板")
                TextField("写一句常驻家里的话", text: $bulletin)
                    .submitLabel(.done)
                    .onSubmit { Milestones.bulletin = bulletin.trimmingCharacters(in: .whitespacesAndNewlines) }
            } header: {
                Text("家庭公告板")
            } footer: {
                // 1044 消费点如实列名 (原句"各页面的空态"是超售): 设备页/记录页空态直挂,
                // 引导空态卡 (设置门锁空态、成就陈列架、维护历史、诊断日志) 经 GuidedEmptyView 消费。
                Text("这句便签已贴在这几处空态旁: 设备页、记录页, 以及走引导空态卡的页面 (设置门锁空态、成就陈列架、维护历史、诊断日志)。未接入的空态不会偷偷显示, 后续批次补。")
                    .xFont(.caption).foregroundStyle(XPalette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
                    Text("这句便签已贴在这几处空态旁: 设备页、记录页, 以及走引导空态卡的页面 (设置门锁空态、成就陈列架、维护历史、诊断日志)。未接入的空态不会偷偷显示, 后续批次补。")
                        .xFont(.caption2)
                        .foregroundStyle(XPalette.textSub)
                }
            }

            XPanel(kind: .group) {
                VStack(alignment: .leading, spacing: XSpace.m) {
                    secLabel("纪念日")
                LabeledRow("结缘日", Milestones.bondDay.isEmpty ? "添加门锁后自动记录" : Milestones.bondDay)
                XToggle("结缘纪念日提醒", isOn: Binding(
                    get: { CareReminders.annivOn },
                    set: { on in
                        DB.store.set("kf_care_anniv", on)
                        Task { await CareReminders.reschedule() }
                    }))
            } header: {
                Text("纪念日")
                }
            }

            XPanel(kind: .group) {
                VStack(alignment: .leading, spacing: XSpace.m) {
                    secLabel("成员生日")
                XToggle("成员生日提醒 (提前一天)", isOn: Binding(
                    get: { CareReminders.bdayOn },
                    set: { on in
                        DB.store.set("kf_care_bday", on)
                        Task { await CareReminders.reschedule() }
                    }))
                ForEach(DB.members()) { m in
                    HStack(spacing: XSpace.s) {
                        Text(m.name)
                        Spacer(minLength: XSpace.m)
                        Text(Milestones.memberBirthdays()[m.id] ?? "未填写")
                            .foregroundStyle(Milestones.memberBirthdays()[m.id] == nil
                                             ? XPalette.textSub : XPalette.text)
                            .monospacedDigit()
                    }
                }
            } header: {
                Text("成员生日")
            } footer: {
                Text("生日在 设置-成员管理-补全信息 里填写 (格式 MM-dd)。提醒通过本地通知送达, 全程离线, 不依赖任何服务器。")
                    Text("生日在 设置-成员管理-补全信息 里填写 (格式 MM-dd)。提醒通过本地通知送达, 全程离线, 不依赖任何服务器。")
                        .xFont(.caption2)
                        .foregroundStyle(XPalette.textSub)
                }
            }
                }
                .padding(.horizontal, XSpace.gutter)
                .padding(.vertical, XSpace.l)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("关怀提醒")
        .xList()
        .xScreen()
        .onDisappear { Milestones.bulletin = bulletin.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    private func secLabel(_ text: String) -> some View {
        Text(text)
            .xFont(.caption, weight: .semibold)
            .foregroundStyle(XPalette.textTertiary)
            .textCase(.uppercase)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
