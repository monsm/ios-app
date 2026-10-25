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

    // `crc32` 转发第九十二批删除：CRC 的唯一实现是上面的 `enum CRC32`，本文件的三处调用
    // (:107/:348/:370) 都直连 `CRC32.crc32`，留一个零调用的同名转发等于留第二套"看起来能用"的 CRC 入口。

    // ---------- 691 store-only ZIP 写入器 ----------
    /// 只做**方法 0 (store, 不压缩)** 这一档: 写 deflate 要自己实现压缩器 (仓内只有解压侧
    /// `compression_decode_buffer`), 而 691 的要点是"打包 + 加密", 不是压缩率 —— CSV/PDF 本来已是紧凑文本。
    /// 格式简单且**可被自家读侧验证**: 写完立刻用本文件的 `parse` 往返读回 (CRC 逐条核), 读侧就是判据。
    static func write(entries: [(name: String, data: [UInt8])]) -> [UInt8] {
        var out: [UInt8] = []
        var central: [UInt8] = []
        var recs: [(name: [UInt8], crc: UInt32, size: Int, off: Int)] = []
        func u16(_ v: Int) -> [UInt8] { [UInt8(v & 0xff), UInt8((v >> 8) & 0xff)] }
        func u32(_ v: UInt32) -> [UInt8] {
            [UInt8(v & 0xff), UInt8((v >> 8) & 0xff), UInt8((v >> 16) & 0xff), UInt8((v >> 24) & 0xff)]
        }
        for e in entries {
            let nb = Array(e.name.utf8)
            let crc = CRC32.crc32(e.data)
            let off = out.count
            out += u32(0x04034b50)
            out += u16(20) + u16(0) + u16(0) + u16(0) + u16(0)          // 版本/标志/方法0/时间/日期
            out += u32(crc) + u32(UInt32(e.data.count)) + u32(UInt32(e.data.count))
            out += u16(nb.count) + u16(0)
            out += nb
            out += e.data
            recs.append((nb, crc, e.data.count, off))
        }
        let cdStart = out.count
        for r in recs {
            central += u32(0x02014b50)
            central += u16(20) + u16(20) + u16(0) + u16(0) + u16(0) + u16(0)
            central += u32(r.crc) + u32(UInt32(r.size)) + u32(UInt32(r.size))
            central += u16(r.name.count) + u16(0) + u16(0) + u16(0) + u16(0)
            central += u32(0)
            central += u32(UInt32(r.off))
            central += r.name
        }
        out += central
        out += u32(0x06054b50)
        out += u16(0) + u16(0) + u16(recs.count) + u16(recs.count)
        out += u32(UInt32(central.count)) + u32(UInt32(cdStart)) + u16(0)
        return out
    }

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
