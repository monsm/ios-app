// BackupStudioTypes.swift —— 备份域的纯逻辑类型（从旧页搬出，内容原样）
//
// 为什么单独成文件（2026-11-04 · S4 前置）：
//   `BackupDoc`（BackupScreen.swift）、`SelfCheck` 与 `WebDAV`（BackupStudioScreen.swift）
//   都被新页引用。只要它们还住在旧页文件里，那两份旧页就删不掉。
//   搬出来之后，旧页与它的 V7 渲染层可以整份删除，逻辑不受影响。
//
// 纪律：本文件只有**纯逻辑 / 传输**，不含任何渲染层代码。
import SwiftUI
import UniformTypeIdentifiers

// MARK: - 文件导出/导入的文档包装

struct BackupDoc: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText, .json] }
    var text: String

    init(text: String) { self.text = text }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let text = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.text = text
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

// MARK: - 数据自检的基线指纹

enum SelfCheck {
    @MainActor static func fingerprint() -> String {
        BackupCanonical.fnv1a32Hex(BackupCanonical.exportText(BackupKit.collectAll()))
    }
}

// MARK: - WebDAV（只做单向上传）

enum WebDAV {
    static func test(base: String, user: String, password: String) async throws -> String {
        // 2026-11-01（Round 235）：与 `upload` 同一个坑 —— `URL(string:)` 遇到空格/中文返回 nil。
        // 走 `URLComponents` 让它负责百分号编码（用户粘贴的地址里带空格并不罕见）。
        guard let comps = URLComponents(string: normalized(base)), let url = comps.url
        else { throw BLEErrorX.msg("WebDAV 地址不是合法 URL") }
        var req = URLRequest(url: url)
        req.httpMethod = "PROPFIND"
        req.setValue("0", forHTTPHeaderField: "Depth")
        if !user.isEmpty { req.setValue("Basic " + auth(user, password), forHTTPHeaderField: "Authorization") }
        let (_, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw BLEErrorX.msg("没有收到 HTTP 响应") }
        guard (200 ..< 300).contains(http.statusCode) || http.statusCode == 207 else {
            throw BLEErrorX.msg("HTTP \(http.statusCode) — 检查地址、账号与应用密码")
        }
        return "HTTP \(http.statusCode)"
    }

    static func upload(text: String, base: String, path: String, user: String, password: String) async throws -> String {
        // 2026-11-01（Round 234）：原来用**字符串拼接** `base + "/" + path` 再 `URL(string:)` ——
        // 路径里一旦有空格或中文（备份文件名完全可能），`URL(string:)` 直接返回 nil，
        // 报出来的是「WebDAV 远端地址不是合法 URL」，而用户看着地址明明是对的。
        // 改用 URLComponents：`path` 接受未转义字符串，取 `.url` 时自动百分号编码。
        guard var comps = URLComponents(string: normalized(base)) else { throw BLEErrorX.msg("WebDAV 远端地址不是合法 URL") }
        let basePath = comps.path.hasSuffix("/") ? comps.path : comps.path + "/"
        let cleanPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        comps.path = basePath + cleanPath
        guard let url = comps.url else { throw BLEErrorX.msg("WebDAV 远端地址不是合法 URL") }
        var req = URLRequest(url: url)
        req.httpMethod = "PUT"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !user.isEmpty { req.setValue("Basic " + auth(user, password), forHTTPHeaderField: "Authorization") }
        req.httpBody = Data(text.utf8)
        let (_, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
            throw BLEErrorX.msg("上传失败：HTTP \((resp as? HTTPURLResponse)?.statusCode ?? -1)")
        }
        return path
    }

    /// SEC-20：只接受 https。旧实现允许 http:// —— 局域网下 WebDAV 账号与
    /// 完整备份（含 skey）会以明文过 Wi-Fi，同一网络的攻击者可直接读走。
    /// 例外只有本机回环（用户自建调试服务器），且仍会显示"明文"提示。
    private static func normalized(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("https://") { return t }
        if t.hasPrefix("http://") {
            let host = URL(string: t)?.host?.lowercased() ?? ""
            if host == "localhost" || host == "127.0.0.1" { return t }
            return "https://" + t.dropFirst("http://".count)
        }
        return "https://" + t
    }

    private static func auth(_ user: String, _ password: String) -> String {
        Data((user + ":" + password).utf8).base64EncodedString()
    }
}
