// LockDataDeleteSheet.swift —— 删除「这一把锁」的本机数据（V8）
//
// 2026-11-05（地毯式对抗审查 · 最深的一处功能回退）：
// 这个能力在旧 V7 的 SettingsScreen.swift 里（deleteSection + DeleteDeviceSheet，
// 键入锁名才放行 + 全族清理 + 诚实后果说明）。43 个 Dest 迁 V8 时，整张 sheet 随
// SettingsScreen.swift 一起被删，**没有任何 V8 页承接它**：
//   · DB.removeDevice(_:) 的 20+ 个数据族清理（约 60 行，含回收站 / 版本快照 / 手机钥匙的
//     钥匙串副本）全仓零调用点，成了死代码；
//   · 用户再也无法从界面删除一把锁的本机数据 —— 只能用「删除本机数据」那一行，
//     而它指向 .dest(.security)，安全页根本没有删除动作（死链）。
//
// 这里按旧实现忠实移植到 V8：能力、确认纪律（键入锁名）、后果文案一字不少。
// 判据：只删本机 —— 锁端密钥与锁内日志不变，锁不需要重置，可以再次添加。
import SwiftUI

struct LockDataDeleteSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss
    @State private var typed = ""

    private var lockName: String { app.lock?.name ?? "" }
    private var canDelete: Bool { !lockName.isEmpty && typed == lockName }
    /// 空壳模式与只读试验都不许删：删的是本机真实数据，空壳下删掉的会是真的。
    private var blocked: Bool { DB.isDecoy }
    private var mac: String { app.lock?.id ?? app.currentMac }

    /// 真删除：钥匙串 + 该锁全部本机数据族（台账 / 日志缓存 / 快照 / 布防 / 自动上锁 /
    /// 锁档案 / 电池采样 / 校时 / OTP / 到期提醒…）一次清干净。
    /// 只执行 app.lock = nil 的旧实现会让数据留在本机 —— 用户以为删了，密钥还在。
    private func deleteLocalData() {
        guard !mac.isEmpty, !blocked else { return }
        DB.removeDevice(mac)
        app.lock = nil
        app.keys = []
        app.entries = []
        app.lastStatus = nil
        AppToast.shared.show("已删除这台锁的本机数据（锁端不变）", tone: .ok)
        Task { await app.reload(refreshStatus: false) }
    }

    var body: some View {
        NavigationStack {
            VPage(title: "删除「" + lockName + "」", lead: "只删本机数据 · 锁端密钥与锁内日志不变") {
                EmptyView()
            } content: {
                if blocked {
                    VCard2(style: .well) {
                        VCardHead(eyebrow: "删除设备", statement: "空壳模式不删除")
                        VDivider2()
                            .padding(.top, V8.S.gapM)
                        Text("空壳模式（胁迫码进入）下不删除任何本机数据 —— 这里删的是真实钥匙串与台账，空壳下删掉不会恢复。退出空壳请在本机密码界面输入正常密码。")
                            .font(V8.T.body)
                            .foregroundStyle(V8.C.ink3)
                            .lineSpacing(V8.L.body - V8.T.body.size)
                            .padding(.top, V8.S.gapM)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else if app.lock == nil {
                    VEmpty(
                        title: "还没有添加门锁",
                        reason: "这一页删的是「当前这把锁」的本机数据。先添加一把锁，这里才有东西可删。",
                        actionTitle: "添加门锁"
                    ) { router.request(.dest(.addLock)) }
                } else {
                    whatWillBeDeleted
                    typeToConfirm
                }
            }
            .background(V8.C.bg.ignoresSafeArea())
            .navigationTitle("删除设备")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var whatWillBeDeleted: some View {
        VCard2 {
            VCardHead(eyebrow: "会被删除", statement: "只在本机")
            VDivider2()
                .padding(.top, V8.S.gapM)
            // 2026-11-04（读实现发现 · 清单不全）：removeDevice 实际还会清掉
            // 回收站条目（CredBinStore.purgeSecretsForDevice）、版本快照
            // （CredHistoryStore.purgeSecretsForDevice，最多 10 份台账副本）、
            // 手机钥匙（MobileKeyService.purgeSecretsForDevice）—— 这三族都含开锁口令的
            // 钥匙串副本。而"会被删除"清单只列了三项，用户可能以为回收站里还能捞回来。补齐。
            VStatPair2(items: [
                VStatPair2.Item(label: "凭证", value: String(app.keys.count), unit: "枚"),
                VStatPair2.Item(label: "记录缓存", value: String(app.entries.count), unit: "条"),
                VStatPair2.Item(label: "本机密码", value: SettingsStore.shared.hasPasscode ? "已设" : "未设")
            ])
            .padding(.top, V8.S.gapM)
            VStatPair2(items: [
                VStatPair2.Item(label: "回收站", value: String(CredBinStore.all(app.currentMac).count), unit: "条 · 一并删除"),
                VStatPair2.Item(label: "版本快照", value: String(CredHistoryStore.all(app.currentMac).count), unit: "份 · 一并删除"),
                VStatPair2.Item(label: "手机钥匙", value: String(MobileKeyService.list(app.currentMac).count), unit: "把 · 一并删除")
            ])
            .padding(.top, V8.S.gapM)
            // 备份是**加密**的、还原点是**明文**的，不能合并成"备份里含母钥"——
            // 那会让设了口令的用户以为口令白设了。
            Text("删除后本机的密码台账与缓存记录无法找回；本机的备份文件（加密的）与还原点（明文，含母钥）也会一并删除 —— 留着等于没删干净。想留档请先把备份导出到别处（WebDAV 或复制文本）。锁本身不需要重置，可以再次添加。")
                .font(V8.T.footnote)
                .foregroundStyle(V8.C.ink3)
                .padding(.top, V8.S.gapM)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var typeToConfirm: some View {
        VCard2 {
            VCardHead(eyebrow: "键入锁名确认", statement: canDelete ? "可以删除" : "需与锁名完全一致")
            VDivider2()
                .padding(.top, V8.S.gapM)
            TextField(lockName, text: $typed)
                .font(V8.T.body)
                .foregroundStyle(V8.C.ink1)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .frame(minHeight: V8.H.min)
                .accessibilityLabel("键入锁名")
            VDivider2()
                .padding(.top, V8.S.gapS)
            Button {
                deleteLocalData()
                dismiss()
            } label: {
                Text("删除本机数据")
                    .font(V8.T.tab)
                    .foregroundStyle(V8.C.danger)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: V8.H.min)
                    .background(Capsule(style: .continuous).fill(V8.C.dangerTrack))
            }
            .buttonStyle(.plain)
            .disabled(!canDelete)
            .opacity(canDelete ? 1 : 0.4)
            .accessibilityLabel("删除本机数据")
            .padding(.top, V8.S.gapM)
            // 危险页只有一个实心主按钮；取消降级为描边，不能和危险按钮同级实心。
            VNavRow(title: "取消", detail: "什么都不做") { dismiss() }
                .padding(.top, V8.S.gapS)
        }
    }
}
