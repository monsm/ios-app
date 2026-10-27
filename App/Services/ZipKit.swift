// ZIP 解压与 CRC32 —— 原住 DFUKit.swift (DFU 固件升级), 那部分已随本轮删减移除。
// 但这两件仍被金标测试用着: GoldenDiffTests 拿 ZipKit.inflate 与 node zlib 做字节对拍,
// 拿 CRC32.crc32 核对固件包校验 —— 删了测试就断了, 所以单独留在这个文件里。
import Foundation
import Compression
enum CRC32 {
    static let table: [UInt32] = {
        (0..<256).map { n -> UInt32 in
            var c = UInt32(n)
            for _ in 0..<8 { c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1) }
            return c
        }
    }()
    static func crc32(_ bytes: [UInt8]) -> UInt32 {
        var c: UInt32 = 0xFFFFFFFF
        for b in bytes { c = table[Int((c ^ UInt32(b)) & 0xff)] ^ (c >> 8) }
        return ~c
    }
}

struct ZipEntry {
    var name: String
    var data: [UInt8]
    var crcOk: Bool
}

enum ZipKit {
    static let maxEntrySize = 8 * 1024 * 1024
    static let maxEntries = 64

    // `crc32` 转发第九十二批删除：CRC 的唯一实现是上面的 `enum CRC32`，调用方都直连 `CRC32.crc32`，
    // 留一个零调用的同名转发等于留第二套"看起来能用"的 CRC 入口。
    // 2026-10-26: 原注释按行号点名"本文件 :107/:348/:370"，而本文件已因 DFU 流程删除缩到 200 行左右 ——
    //   行号引用会随删改持续失效。今后这类注释只写符号名，不写行号。


    // 原生 inflate (raw deflate) — 上限防护
    static func inflate(_ data: [UInt8], expected: Int) throws -> [UInt8] {
        guard expected <= maxEntrySize else { throw DFUError.zip("声称输出 \(expected)B 超上限 — 疑似 zip 炸弹") }
        var dst = [UInt8](repeating: 0, count: max(expected, 1))
        let written = data.withUnsafeBufferPointer { srcBuf -> Int in
            dst.withUnsafeMutableBufferPointer { dstBuf -> Int in
                compression_decode_buffer(dstBuf.baseAddress!, dstBuf.count,
                                          srcBuf.baseAddress!, srcBuf.count,
                                          nil, COMPRESSION_ZLIB)
            }
        }
        guard written > 0 else { throw DFUError.zip("inflate 失败 (输出 \(written)B)") }
        return Array(dst.prefix(written))
    }

    static func parse(_ data: [UInt8]) throws -> [ZipEntry] {
        // EOCD: 从尾部向前找 0x06054b50
        var eocd = -1
        let minOff = max(0, data.count - 22 - 65535)
        if data.count >= 22 {
            var i = data.count - 22
            while i >= minOff {
                if data[i] == 0x50, data[i + 1] == 0x4b, data[i + 2] == 0x05, data[i + 3] == 0x06 { eocd = i; break }
                i -= 1
            }
        }
        guard eocd >= 0 else { throw DFUError.zip("未找到目录结尾 (不是有效的 zip 文件)") }
        // UInt32 累加: Int 拼接在 ≥0x80000000 时返回负数 → 上层 guard 误放行 → 数组越界崩溃
        func u16(_ off: Int) -> Int {
            guard off >= 0, off + 1 < data.count else { return 0 }
            return Int(data[off]) | (Int(data[off + 1]) << 8)
        }
        func u32(_ off: Int) -> Int {
            guard off >= 0, off + 3 < data.count else { return 0 }
            let v = UInt32(data[off]) | (UInt32(data[off + 1]) << 8) | (UInt32(data[off + 2]) << 16) | (UInt32(data[off + 3]) << 24)
            return Int(v)
        }
        let count = u16(eocd + 10)
        guard count <= maxEntries else { throw DFUError.zip("条目数异常 (\(count))") }
        var off = u32(eocd + 16)
        var entries = [ZipEntry]()
        for _ in 0..<count {
            guard off + 46 <= data.count, u32(off) == 0x02014b50 else { throw DFUError.zip("中央目录损坏") }
            let method = u16(off + 10)
            let crcExpect = UInt32(u32(off + 16))
            let csize = u32(off + 20)
            let usize = u32(off + 24)
            let nameLen = u16(off + 28)
            let extraLen = u16(off + 30)
            let cmtLen = u16(off + 32)
            let lho = u32(off + 42)
            guard off + 46 + nameLen + extraLen + cmtLen <= data.count else { throw DFUError.zip("中央目录越界") }
            let name = String(bytes: data[(off + 46)..<(off + 46 + nameLen)], encoding: .utf8) ?? ""
            guard usize <= maxEntrySize, csize <= data.count else { throw DFUError.zip("条目解压尺寸异常 (\(name) 声称 \(usize)B)") }
            guard lho + 30 <= data.count, u32(lho) == 0x04034b50 else { throw DFUError.zip("本地文件头损坏 (\(name))") }
            let lNameLen = u16(lho + 26)
            let lExtraLen = u16(lho + 28)
            let dataOff = lho + 30 + lNameLen + lExtraLen
            guard dataOff + csize <= data.count else { throw DFUError.zip("条目数据越界 (\(name))") }
            let cdata = Array(data[dataOff..<(dataOff + csize)])
            var content: [UInt8]
            if method == 0 {
                content = cdata
            } else if method == 8 {
                guard !cdata.isEmpty else { throw DFUError.zip("空 deflate 条目 (\(name))") }
                content = try inflate(cdata, expected: usize)
            } else {
                throw DFUError.zip("不支持的压缩方式 \(method) (\(name))")
            }
            if usize != 0 && content.count != usize { throw DFUError.zip("解压长度不符 (\(name))") }
            entries.append(ZipEntry(name: name, data: content, crcOk: CRC32.crc32(content) == crcExpect))
            off += 46 + nameLen + extraLen + cmtLen
        }
        return entries
    }
    static func find(_ entries: [ZipEntry], _ name: String) -> ZipEntry? {
        let base = name.split(separator: "/").last.map(String.init)?.lowercased() ?? name.lowercased()
        if let exact = entries.first(where: { $0.name == name }) { return exact }
        return entries.first { $0.name.split(separator: "/").last.map(String.init)?.lowercased() == base }
    }
}

// ---------- 固件包解析 (原 DFUKit.swift, DFU 升级流程已删但解析仍被金标测试用) ----------
// GoldenDiffTests 拿 FirmwareKit.parse/nextMac/versionLt 与 vendor dfu.js 逐格对拍,
// 删了测试就断, 所以解析层跟 ZipKit 一起留在这个文件里。
struct FirmwarePackage {
    var binHex: String
    var datHex: String
    var binSize: Int
    var datSize: Int
    var version: String?   // 文件名 KX_V5.2.9_* → 5.2.9
    var sourceName: String
}

enum FirmwareKit {
    static let limits = (manifest: 4096, dat: 4096, bin: 8 * 1024 * 1024)
    static func parse(zipData: [UInt8], fileName: String) throws -> FirmwarePackage {
        let entries = try ZipKit.parse(zipData)
        guard let manifestE = ZipKit.find(entries, "manifest.json") else { throw DFUError.zip("固件包缺少 manifest.json") }
        guard manifestE.data.count <= limits.manifest else { throw DFUError.zip("manifest.json 异常过大") }
        // 2026-10-14: bin/dat 都验了 CRC, manifest 只验了大小 —— 补齐 (篡改但仍合法 JSON 的 manifest 会漏过)
        guard manifestE.crcOk else { throw DFUError.zip("manifest.json CRC 校验失败 (包损坏)") }
        guard let raw = String(bytes: manifestE.data, encoding: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any],
              let manifest = obj["manifest"] as? [String: Any],
              let app = (manifest["application"] as? [String: Any]) ?? (manifest["bootloader"] as? [String: Any]) else {
            throw DFUError.zip("manifest.json 不是有效结构")
        }
        // 别名对齐 vendor dfu.js: 个别厂商包用 binFilename/data_file
        let binName = app["bin_file"] as? String ?? app["binFilename"] as? String ?? ""
        let datName = app["dat_file"] as? String ?? app["data_file"] as? String ?? ""
        guard let binE = ZipKit.find(entries, binName), !binName.isEmpty else { throw DFUError.zip("固件包缺少固件文件 (\(binName))") }
        guard let datE = ZipKit.find(entries, datName), !datName.isEmpty else { throw DFUError.zip("固件包缺少 init packet (\(datName))") }
        guard binE.crcOk else { throw DFUError.zip("固件文件 CRC 校验失败 (包损坏)") }
        guard datE.crcOk else { throw DFUError.zip("init packet CRC 校验失败 (包损坏)") }
        guard binE.data.count >= 512, binE.data.count <= limits.bin else { throw DFUError.zip("固件尺寸异常 (\(binE.data.count)B)") }
        guard datE.data.count >= 16, datE.data.count <= limits.dat else { throw DFUError.zip("init packet 尺寸异常 (\(datE.data.count)B)") }
        // 2026-10-13 对抗式排查: ⚠ **固件包没有任何签名 / 来源校验**。
        // 这条链上已有的全都只是"一致性"检查 (CRC / 尺寸 / manifest 形状), 而"这个包是谁产的"
        // 完全没有判 —— manifest.json 与文件名都可构造, bin/dat 的 CRC 可以重算, 广播名带目标 MAC
        // 后 8 位的 "ZkDFU" 也照协议走。⇒ 构造一个 zip 就能把**任意固件**烧进锁,
        // 而删 App / 重新配对都清不掉它 (属持久控制, 供应链/社工即可)。
        // 真正根治要厂商签名 (公钥烧在锁里), 本仓拿不到; 拿到之前只做两件不假装已解决的事:
        //   ① 如上, 在代码里把"未认证"写明, 不让人误以为校验过;
        //   ② 至少拒绝**降级** (versionLt 自第一百九十六批起就存在, 但一直没用过一次) ——
        //      调用方见 `DFUKit.downgradeBlocked(current:pkg:)`。
        return FirmwarePackage(binHex: HexKit.hex(binE.data), datHex: HexKit.hex(datE.data),
                               binSize: binE.data.count, datSize: datE.data.count,
                               version: versionFromManifest(app) ?? versionFromFileName(fileName))
    }

    /// 从 manifest 里读固件版本 —— **优先于文件名**。
    /// 2026-10-27 审核修复 (AUDIT-D D-46)：原先版本号只从**文件名**取，
    /// 于是把旧固件改个名字（如 `KX_V9.9.9.zip`）就能绕过降级闸。
    /// manifest 里的版本字段是包内自述（虽然仍可构造，但比文件名难改 ——
    /// 改它要重算 CRC，而 CRC 校验在这条链上是真做了的）。
    /// 常见字段名：manifest.application.application_version / version / fw_version。
    static func versionFromManifest(_ app: [String: Any]) -> String? {
        for key in ["application_version", "version", "fw_version", "firmware_version"] {
            if let s = app[key] as? String, !s.isEmpty {
                // 只接受 x.y.z 形态（与 versionLt 的解析口径一致）
                if s.range(of: "^\\d+\\.\\d+\\.\\d+$", options: .regularExpression) != nil { return s }
            }
        }
        return nil
    }

    static func versionFromFileName(_ name: String) -> String? {
        // 2026-10-14: 旧式强制尾随 `_`, 遇 "KX_V5.2.9.zip" / "KX_V5.2.9" 匹配失败 => version=nil =>
        // 版本对比与降级判据整体静默失效。尾随改 `(_|\.|$)`。
        guard let m = name.range(of: "_?V?(\\d+\\.\\d+\\.\\d+)(?:_|\\.|$)", options: .regularExpression) else { return nil }
        let s = name[m]
        var digits = s.drop(while: { !$0.isNumber })
        while let last = digits.last, !last.isNumber { digits = digits.dropLast() } // 剥尾部 _ (P3-1)
        return digits.isEmpty ? nil : String(digits)
    }
    static func versionLt(_ a: String, _ b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<3 {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x < y }
        }
        return false
    }

    // 降级闸 —— 第 160 行那条注释里提到但一直没实现的那个入口。
    // 口径：**当前固件版本 > 包内版本** 就是降级，直接拒绝。
    // 为什么不给"允许降级"开关：这条链上没有任何签名校验（见 parse() 里那段说明），
    // 降级是攻击者把锁刷回存在已知漏洞的旧固件的最短路径；而普通用户降级的正当理由几乎没有。
    // 返回 nil = 放行；返回字符串 = 要原样展示的拒绝理由。
    static func downgradeBlocked(current: String?, pkg: FirmwarePackage) -> String? {
        guard let cur = current, !cur.isEmpty else { return nil }   // 读不到当前版本时不拦（无法判定）
        guard let target = pkg.version else { return nil }          // 包名里没有版本号时无法判定
        if versionLt(target, cur) {
            return "包内固件版本 \(target) 低于锁内版本 \(cur)，已拒绝降级"
                 + "（本仓无法校验固件签名，降级是刷入旧漏洞固件的最短路径）"
        }
        return nil
    }
}
