// 备份工作室仅存的两块 —— 其余 (导出向导/恢复向导/换机迁移/本地文件/迁移提示卡) 已随大删波4移除。
//
// 为什么这两块留下:
//   · WebDAVStudioView — 坚果云同步的真实入口 (BackupView 经 sheet 打开), 用户自己填服务器与账号,
//     BackupStudio 引擎侧的 testWebdav/listRemote/rotateKey 都还在, 这页是它们的 UI。
//   · UIImageShareItem — DiagnosticsView 分享诊断截图用的 Transferable 包装。
// 删掉的是**向导流程** (ExportWizard/RestoreWizard/MigrationWizard/LocalFiles/MigrationPromptCard),
// 备份本体改由 BackupView 的「存到 iCloud 云盘 / 从文件选择」承担。
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct WebDAVStudioView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var root = ""
    @State private var acct = ""
    @State private var appPw = ""
    /// 2026-10-26: 与另一页共用 BackupPassphrase（同一份 zklock-backup.enc 的加密口令）。
    /// 原来是各自一个 @State，用户在工作室传上去、到这一页恢复还要再输一遍，且没人说明是同一个口令。
    private var encPw: Binding<String> {
        Binding(get: { BackupPassphrase.current }, set: { BackupPassphrase.current = $0 })
    }
    @State private var entries: [BackupStudio.RemoteEntry] = []
    @State private var testResult = ""
    @State private var dryRunResult = ""
    @State private var hint830 = false          // 830 首次连通成功的一次性加密说明条
    @State private var rotateMsg = ""
    @State private var rotPw = ""
    @State private var busy = false
    @State private var showRotate = false
    @State private var pendingDL: (b: BackupBundle, line: String)?   // 422 预演门: 下载→确认→入库

    private var ready: Bool { !root.isEmpty && !acct.isEmpty && !appPw.isEmpty }

    var body: some View { vkBody.destined(.webDAVStudio) }
    var vkBody: some View {
        NavigationStack {
            Form {
                Section("WebDAV 端点 (走用户自配账号, 仅 Basic Auth 运行时输入)") {
                    TextField("根地址", text: $root, prompt: Text(BackupStudio.webdavRoot))
                        .autocorrectionDisabled()
                    TextField("账号", text: $acct)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("应用专属密码 (非登录)", text: $appPw)
                    LabeledContent("连通测试") {   // 197 连通测试
                        Button(busy ? "测试中…" : "测试") { test() }
                            .vkFont(.subheadline)
                            .foregroundStyle(DS.Palette.accentText)
                            .frame(minHeight: DS.Hit.min)
                    }
                    if !testResult.isEmpty {
                        Text(testResult).vkFont(.caption).foregroundStyle(DS.Palette.textSub)
                    }
                    // 830 首次连通成功后的"备份将加密后上传"情境条。口径替代记在这: 原句要 3 秒自动收起,
                    // 而本仓有全仓级纪律 (HintOnce.swift:5)「提示不自动计时消失 —— 让它自己飘走,
                    // 等于用户还没读就被判定已看过」; 所以这里由用户点 X 关闭, 只出现一次 (走 HintOnce 记档)。
                    if hint830 {
                        HStack(spacing: DS.Space.xs) {
                            Image(systemName: "lock.shield")
                                .font(.system(size: DS.Icon.sm))
                                .foregroundStyle(DS.Palette.ok)
                                .accessibilityHidden(true)
                            Text("备份将加密后上传 · 加密在本机完成, 远端只见密文")   // 830 备份将加密后上传
                                .vkFont(.caption)
                                .foregroundStyle(DS.Palette.text)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: DS.Space.xs)
                            Button {
                                withAnimation(DS.Motion.soft) { hint830 = false }
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: DS.Icon.xs, weight: .semibold))
                                    .foregroundStyle(DS.Palette.textSub)
                                    .frame(width: 28, height: 28)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("关闭提示")   // 830 关闭提示
                            // 2026-10-14 布局审计 R5: 自绘 label 没写 minHeight ⇒ 没有 minHeight (< 44)。
                            // 补 44pt 触达: frame 只加竖直空间, 背景画在这两行之前 ⇒ 视觉不撑, 整块矩形可点。
                            .frame(minHeight: DS.Hit.min)
                            .contentShape(Rectangle())
                        }
                        .padding(.horizontal, DS.Space.s)
                        .padding(.vertical, DS.Space.xs)
                        .variantCallout(DS.Palette.ok, .control, wash: 0.12)
                    }
                }
                Section("远端备份 (哈希先行: 先拉 etag 再拉正文)") {
                    if !entries.isEmpty {
                        ForEach(entries) { e in
                            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                                Text(e.name).vkFont(.subheadline).foregroundStyle(DS.Palette.text)
                                HStack(spacing: DS.Space.xs) {
                                    Text("\(e.size / 1024) KB").vkFont(.caption).foregroundStyle(DS.Palette.textSub)
                                    Label(String(e.etag.prefix(8)), systemImage: "number")
                                        .vkFont(.caption)
                                        .foregroundStyle(DS.Palette.textSub)
                                    // 422 时间列: 服务端 getlastmodified (取不到就空, 不编)
                                    if !e.modified.isEmpty {
                                        Label(BackupStudio.humanDate(e.modified), systemImage: "clock")
                                            .vkFont(.caption)
                                            .foregroundStyle(DS.Palette.textSub)
                                    }
                                }
                                HStack(spacing: DS.Space.s) {
                                    Button("下载恢复") { download(e) }
                                        .vkFont(.caption)
                                        .foregroundStyle(DS.Palette.accentText)
                                        .frame(minHeight: DS.Hit.min)
                                    Button("演练") { dryRun(e) }   // 436 演练
                                        .vkFont(.caption)
                                        .foregroundStyle(DS.Palette.warn)
                                        .frame(minHeight: DS.Hit.min)
                                }
                            }
                        }
                    } else {
                    // 2026-10-26: 原文案写"先在导出向导生成并上传"，而导出向导已随大删波4 移除
                    // （见本文件头注）—— 用户在界面上找不到那个入口。改成只指向本页真实存在的按钮。
                    Text("暂无远端备份 — 点下方「上传」把本机当前备份传上去；若已有旧包，也可用「下载并验证」检查它是否可读")
                            .vkFont(.caption)
                            .foregroundStyle(DS.Palette.textSub)
                    }
                    Button("刷新列表") { Task { await refresh() } }
                        .vkFont(.subheadline)
                        .foregroundStyle(DS.Palette.accentText)
                    if !dryRunResult.isEmpty {
                        Text(dryRunResult).vkFont(.caption).foregroundStyle(DS.Palette.warn)
                    }
                }
                Section("策略与密钥") {
                    Button("上传当前备份 (含口令加密)") { upload() }
                        .vkFont(.subheadline)
                        .foregroundStyle(DS.Palette.accentText)
                    SecureField("加密口令 (上传/下载)", text: $encPw)
                    SecureField("新口令 (轮换后旧口令随即失效)", text: $rotPw)
                    Button("密钥轮换: 新口令重加密替换远端") { showRotate = true }   // 237 密钥轮换
                        .vkFont(.subheadline)
                        .foregroundStyle(DS.Palette.warn)
                        .frame(minHeight: DS.Hit.min)
                        .disabled(rotPw.isEmpty)
                    if !rotateMsg.isEmpty {
                        Text(rotateMsg).vkFont(.caption).foregroundStyle(DS.Palette.textSub)
                    }
                    Text("口令每次输入不落盘; 轮换后旧口令即失效, 请用新口令访问。")   // 237 口令每次输入不落盘
                        .vkFont(.caption)
                        .foregroundStyle(DS.Palette.textSub)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            // 2026-10-26: 改完即写。原先 persist() 只在 test()/upload() 里调 ——
            // 用户改完根地址/账号直接关窗就丢了，与备份页输入框"直写 Store"的口径不一致。
            // 三条挂在 Form 上（不是各自字段）：挂到某个字段上会让另两个字段的变化永远不触发。
            .onChange(of: root) { _, _ in persist() }
            .onChange(of: acct) { _, _ in persist() }
            .onChange(of: appPw) { _, _ in persist() }
            .navigationTitle("WebDAV 工作室")
            .variantList()
            .dsScreenBackground()
            .toolbar { ToolbarItem(placement: .navigationBarLeading) { Button("关闭") { dismiss() } } }
            .onAppear {
                root = DB.store.getString("kf_webdav_root", BackupStudio.webdavRoot)
                acct = DB.store.getString("kf_cloudcfg_acct")
                appPw = DB.store.getString("kf_cloudcfg_app")
            }
            .confirmationDialog("密钥轮换", isPresented: $showRotate) {   // 237 密钥轮换
                Button("轮换") { rotate() }
                Button("取消", role: .cancel) { }
            } message: {
                Text("将用新口令重新加密远端备份并替换。旧口令随即失效。")
            }
            // 422 恢复预演门: 下载只做校验与预演, 真正入库要在这里点头
            .confirmationDialog(pendingDL?.line ?? "", isPresented: Binding(
                get: { pendingDL != nil },
                set: { if !$0 { pendingDL = nil } }), titleVisibility: .visible) {
                Button("确认恢复入库") { commitDL() }
                Button("取消", role: .cancel) { pendingDL = nil }
            } message: {
                Text("预演不动真库")   // 422 预演不动真库
            }
        }
    }

    private func persist() {
        DB.store.set("kf_webdav_root", root)
        DB.store.set("kf_cloudcfg_acct", acct)
        DB.store.set("kf_cloudcfg_app", appPw)
    }
    private func test() {
        guard ready else { app.showToast("请填写根地址/账号/应用密码"); return }
        busy = true
        Task {
            testResult = await BackupStudio.testWebdav(acct: acct, appPw: appPw, root: root)
            persist()
            busy = false
            // 830 首次连通成功 ⇒ 视为"配置完成": 给一次加密说明情境条 (HintOnce 记档, 之后不再出现)
            if testResult.hasPrefix("连通"), !HintOnce.shown("830enc") {
                HintOnce.mark("830enc")
                withAnimation(DS.Motion.soft) { hint830 = true }
            }
        }
    }
    private func refresh() async {
        guard ready else { return }
        busy = true
        do {
            entries = try await BackupStudio.listRemote(acct: acct, appPw: appPw, root: root)
            // 430 滚动保留
            let keep = BackupStudio.rollingKeep
            if keep > 0 {
                let pruned = await BackupStudio.pruneRemote(acct: acct, appPw: appPw, root: root, keep: keep)
                if pruned > 0 { app.showToast("滚动保留: 已清理远端 \(pruned) 份超限") }   // 430 滚动保留
            }
        } catch {
            app.showToast(error.localizedDescription)
        }
        busy = false
    }
    private func upload() {
        guard !encPw.isEmpty else { app.showToast("请先填加密口令"); return }
        busy = true
        Task {
            do {
                let b = BackupStudio.bundleFor()
                let plain = BackupCanonical.exportText(b)
                BackupStudio.markExportSize(plain)   // 193: 上传路径也记尺寸
                let env = try CryptoBox.encryptText(plain, password: encPw)
                try await CloudSync.push(acct: acct, app: appPw, envelope: env)
                persist()
                Milestones.recordBackup()
                // 430 上传后自动滚动清理: 最近 N 份之外每月再保最新 1 份 (下载/恢复口不受影响)
                if BackupStudio.rollingKeep > 0 {
                    let n = await BackupStudio.pruneRemote(acct: acct, appPw: appPw, root: root, keep: BackupStudio.rollingKeep)
                    if n > 0 { app.showToast("滚动保留: 已清理远端 \(n) 份超限") }   // 430 滚动保留
                }
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                app.showToast("上传成功")
            } catch {
                app.showToast(error.localizedDescription)
            }
            busy = false
        }
    }
    private func download(_ e: BackupStudio.RemoteEntry) {
        busy = true
        Task {
            defer { busy = false }
            do {
                guard let url = BackupStudio.safeRemoteURL(root: root, name: e.name) else { throw DFUError.msg("地址非法 (远端条目名被护栏拒绝)") }
                // 423: 清单 etag 先行 — HEAD 比对, 清单过期就中止 (不支持 HEAD 时照常继续, 不假拦)
                var head = URLRequest(url: url); head.httpMethod = "HEAD"
                head.setValue(CloudSync.basicAuth(acct, appPw), forHTTPHeaderField: "Authorization")
                if let (_, hr) = try? await URLSession.shared.data(for: head),
                   let h = hr as? HTTPURLResponse, let now = h.value(forHTTPHeaderField: "ETag"),
                   !e.etag.isEmpty, now != e.etag {
                    app.showToast("远端文件已变 (清单 \(e.etag.prefix(8)) ≠ 现在 \(now.prefix(8))), 已中止 — 刷新后重下")   // 423 远端文件已变
                    return
                }
                var req = URLRequest(url: url)
                req.setValue(CloudSync.basicAuth(acct, appPw), forHTTPHeaderField: "Authorization")
                let (data, _) = try await URLSession.shared.data(for: req)
                let raw = String(data: data, encoding: .utf8) ?? ""
                // 422: 先预演后再入库 (parsePreview 内部先校哈希后解码, 不动真库)
                let (pv, b) = try BackupStudio.parsePreview(text: raw, password: encPw.isEmpty ? nil : encPw)
                pendingDL = (b, e.name + " · 校验通过 · " + pv.zones.joined(separator: "、"))
            } catch { app.showToast(error.localizedDescription) }
        }
    }
    private func commitDL() {
        guard let dl = pendingDL else { return }
        let r = BackupStudio.restore(dl.b, )
        if dl.b.globals?.appearance != nil { app.reloadAppearance() }
        app.loadDevices()
        app.showToast("恢复完成: 新增 \(r.imported), 覆盖 \(r.overwritten)")
        pendingDL = nil
    }
    private func dryRun(_ e: BackupStudio.RemoteEntry) {
        busy = true
        Task {
            dryRunResult = await BackupStudio.dryRunRemote(acct: acct, appPw: appPw,
                                                          root: root, name: e.name, password: encPw)
            busy = false
        }
    }
    private func rotate() {
        guard !encPw.isEmpty, !rotPw.isEmpty, encPw != rotPw else {
            app.showToast("需填旧口令(加密口令)与新口令"); return   // 237 需填旧口令
        }
        busy = true
        Task {
            rotateMsg = await BackupStudio.rotateKey(acct: acct, appPw: appPw,
                                                     root: root, oldPw: encPw, newPw: rotPw)
            busy = false
        }
    }
}

struct UIImageShareItem: Transferable {
    let image: UIImage
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { item in
            item.image.pngData() ?? Data()
        }
    }
    init(_ image: UIImage) { self.image = image }
}
