// SettingsScreen.swift —— 设置是索引，不是读数。它只回答"去哪里"。
import SwiftUI

@MainActor
struct SettingsScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss

    @State private var homeName = ""
    @State private var editingHome = false

    var body: some View {
        ScreenScroll {
            NavRow(kicker: "设置", subtitle: "\(app.locks.count) 把锁 · \(app.members.count) 位成员") {
                AnyView(
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(T.C.ink2)
                            .frame(width: 32, height: 32)
                            .background(T.C.hair, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("关闭")
                )
            }

            if editingHome {
                HStack(spacing: 10) {
                    FieldInput(placeholder: "这个家叫什么", text: $homeName)
                    Button {
                        SettingsStore.shared.setHomeName(homeName.isEmpty ? "我的家" : homeName)
                        editingHome = false
                    } label: {
                        Text("保存")
                            .type(T.F.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .frame(height: 44)
                            .background(T.C.brass, in: Capsule())
                    }
                    .buttonStyle(PressStyle())
                }
                .padding(.top, 18)
            } else {
                Button {
                    homeName = SettingsStore.shared.homeName
                    editingHome = true
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        DisplayLine(text: SettingsStore.shared.homeName, size: 34)
                        Image(systemName: "pencil")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(T.C.ink4)
                    }
                }
                .buttonStyle(.plain)
                .padding(.top, 14)
            }

            Text("一个家，和它的边界。")
                .type(T.F.footnote)
                .foregroundStyle(T.C.ink2)
                .padding(.top, 4)

            // 空壳里不显示只读试验：它读的是真实开关，而且指引「到安全里关掉」——
            // 那个开关在空壳的安全页里恰好是隐藏的，点了找不到。
            if app.trial && !DB.isDecoy {
                trialNote
                    .padding(.top, 18)
            }

            SectionHead(index: "01", title: "我的家")
            settingsRow(.locks, symbol: "lock", title: app.lock?.name ?? "还没有门锁",
                        subtitle: lockSubtitle)
            settingsRow(.security, symbol: "shield", title: "安全",
                        subtitle: securitySubtitle)
            Button {
                dismiss()
                router.tab = .access
            } label: {
                ContentRow(symbol: "person.2", tone: .cool, title: "成员与分工",
                           subtitle: "\(app.members.count) 位成员 · 在「通行」里管理", chevron: true)
            }
            .buttonStyle(.plain)

            SectionHead(index: "02", title: "设备与工具")
            settingsRow(.lockPolicy, symbol: "slider.horizontal.3", title: "门锁设置",
                        subtitle: "声音 · 双验 · 自动上锁 · 布防")
            // 「门锁信息」这一页一直存在（读数 / 校准锁钟 / 刷新），但全 App 没有入口 ——
            // 一个做完的页面没人到得了，等于没做。
            settingsRow(.lockInfo, symbol: "gauge.with.dots.needle.33percent", title: "门锁信息",
                        subtitle: app.lock.map { "电量 · 锁钟 · 容量 · 固件 \($0.firmware.isEmpty ? "—" : $0.firmware)" }
                            ?? "配一把锁之后可看读数")
            // 自动开门整页都在读真实偏好（开关档位、标定值、上次被否决的原因）。
            // 空壳里不摆这个入口：它既会泄漏"主人平时开不开自动开门"，开关本身也是真写。
            if !DB.isDecoy {
                settingsRow(.autoOpen, symbol: "figure.walk", title: "自动开门",
                            subtitle: AutoOpen.on ? "已开启 · 靠近时自动解锁" : "关闭 · 靠近时自动解锁")
            }
            settingsRow(.hardware, symbol: "key", title: "钥匙串与网关",
                        subtitle: hardwareSubtitle)
            settingsRow(.dfu, symbol: "arrow.up.circle", title: "固件升级",
                        subtitle: app.lock?.firmware.isEmpty == false ? "当前 \(app.lock?.firmware ?? "")" : "支持 Nordic DFU")
            // 诊断页会显示真实链路数据（RSSI / 握手耗时）并真的发 BLE 命令。
            // 空壳里整行不摆：这一页没有"只读展示"可以给，收起来最干净。
            if !DB.isDecoy {
                settingsRow(.diagnostics, symbol: "stethoscope", title: "维护与诊断",
                            subtitle: "链路 · 回声 · PIN 池 · 脱敏帧")
            }
            settingsRow(.pairing, symbol: "plus.circle", title: "配对新的门锁",
                        subtitle: "把锁恢复到配网状态后开始")

            SectionHead(index: "03", title: "数据")
            settingsRow(.backup, symbol: "archivebox", title: "备份与恢复",
                        subtitle: backupSubtitle)
            settingsRow(.appearance, symbol: "circle.lefthalf.filled", title: "外观",
                        subtitle: appearanceSubtitle)
            settingsRow(.about, symbol: "info.circle", title: "关于",
                        subtitle: "离线 · 无账号 · 数据在你手里")
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var lockSubtitle: String {
        guard let lock = app.lock else { return "还没有配对" }
        let battery = lock.battery >= 0 ? "\(lock.battery)%" : "电量未知"
        return "\(lock.model) · \(battery) · 固件 \(lock.firmware.isEmpty ? "—" : lock.firmware)"
    }

    private var securitySubtitle: String {
        var parts: [String] = []
        parts.append(DB.hasPasscode() ? "本机密码已设" : "未设本机密码")
        // 空壳里不能写「已设胁迫码」：这一行就摆在设置首页，
        // 等于告诉胁迫者"刚才那组数字可能是胁迫码，再逼一次"。
        if !DB.isDecoy, DB.hasDuressCode() { parts.append("已设胁迫码") }
        return parts.joined(separator: " · ")
    }

    private var hardwareSubtitle: String {
        let dongles = DB.dongles().count
        let gateways = DB.gateways().count
        if dongles == 0 && gateways == 0 { return "未绑定硬件" }
        return "\(dongles) 个钥匙串 · \(gateways) 个网关"
    }

    private var backupSubtitle: String {
        // 空壳里不显示真实备份时间（同上：它会暴露这台手机的历史）。
        if !DB.isDecoy, let last = Milestones.lastBackupAt {
            return "上次备份 \(When.ago(Int64(last.timeIntervalSince1970 * 1000))) · 已加密"
        }
        return "还没有备份过"
    }

    private var appearanceSubtitle: String {
        switch SettingsStore.shared.theme {
        case "light": return "日光 · 始终浅色"
        case "dark": return "暮色 · 始终深色"
        default: return "日光 · 跟随系统"
        }
    }

    private var trialNote: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 14))
                .foregroundStyle(T.C.danger)
            VStack(alignment: .leading, spacing: 3) {
                Text("只读试验模式开着")
                    .type(T.F.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(T.C.ink)
                Text("开锁、写凭证、改锁设置、刷固件都会被拦下。到「安全」里关掉。")
                    .type(T.F.caption)
                    .foregroundStyle(T.C.ink3)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(T.C.dangerWash, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func settingsRow(_ dest: Dest, symbol: String, title: String, subtitle: String) -> some View {
        Button {
            router.pushSettings(dest)
        } label: {
            ContentRow(symbol: symbol, tone: .brass, title: title, subtitle: subtitle, chevron: true)
        }
        .buttonStyle(.plain)
    }
}
