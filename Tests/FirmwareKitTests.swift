// 固件包解析与降级闸单测 —— 纯逻辑，不依赖真机 DFU。
//
// 覆盖三件此前没有机器证据的事：
//   ① FirmwareKit.parse 的 CRC/尺寸/manifest 形状检查（构造合法与各类畸形包）
//   ② versionFromFileName 的三种命名（V5.2.9 / V5.2.9.zip / 无版本）
//   ③ downgradeBlocked 的降级闸（这条闸在 ZipKit 的注释里被提到过，但直到本轮才实现）
import XCTest
import Foundation
import Compression
@testable import OfflineLock

final class FirmwareKitTests: XCTestCase {

    // MARK: - 造一个最小合法 ZIP（stored，不压缩）

    /// 手搓 ZIP：本地文件头 + 数据 + 中央目录 + EOCD。
    /// 只支持 stored（method 0）—— 固件包解析只关心内容与 CRC，压缩算法另有 ZipKit 覆盖。
    private func makeZip(_ files: [(name: String, data: [UInt8])]) -> [UInt8] {
        var out: [UInt8] = []
        var central: [UInt8] = []
        for f in files {
            let nameBytes = Array(f.name.utf8)
            let crc = crc32(f.data)
            let offset = out.count
            // 本地文件头
            out += u32(0x0403_4b50) + u16(20) + u16(0) + u16(0) + u16(0) + u16(0)
            out += u32(crc) + u32(UInt32(f.data.count)) + u32(UInt32(f.data.count))
            out += u16(UInt16(nameBytes.count)) + u16(0) + nameBytes + f.data
            // 中央目录项
            central += u32(0x0201_4b50) + u16(20) + u16(20) + u16(0) + u16(0) + u16(0) + u16(0)
            central += u32(crc) + u32(UInt32(f.data.count)) + u32(UInt32(f.data.count))
            central += u16(UInt16(nameBytes.count)) + u16(0) + u16(0) + u16(0) + u16(0)
            central += u32(0) + u32(UInt32(offset)) + nameBytes
        }
        let cdOffset = out.count
        out += central
        out += u32(0x0605_4b50) + u16(0) + u16(0)
        out += u16(UInt16(files.count)) + u16(UInt16(files.count))
        out += u32(UInt32(central.count)) + u32(UInt32(cdOffset)) + u16(0)
        return out
    }
    private func u16(_ v: UInt16) -> [UInt8] { [UInt8(v & 0xff), UInt8(v >> 8)] }
    private func u32(_ v: UInt32) -> [UInt8] { [UInt8(v & 0xff), UInt8((v >> 8) & 0xff), UInt8((v >> 16) & 0xff), UInt8((v >> 24) & 0xff)] }
    private func crc32(_ bytes: [UInt8]) -> UInt32 {
        var c: UInt32 = 0xFFFF_FFFF
        for b in bytes {
            c ^= UInt32(b)
            for _ in 0..<8 { c = (c & 1) != 0 ? (c >> 1) ^ 0xEDB8_8320 : c >> 1 }
        }
        return c ^ 0xFFFF_FFFF
    }

    private func manifest(bin: String = "fw.bin", dat: String = "fw.dat") -> [UInt8] {
        let json = #"{"manifest":{"application":{"bin_file":"\#(bin)","dat_file":"\#(dat)"}}}"#
        return Array(json.utf8)
    }
    private var binBytes: [UInt8] { [UInt8](repeating: 0xAA, count: 1024) }   // ≥512 才合法
    private var datBytes: [UInt8] { [UInt8](repeating: 0xBB, count: 64) }     // ≥16 才合法

    // MARK: - 合法包

    func testParseValidPackage() throws {
        let zip = makeZip([("manifest.json", manifest()), ("fw.bin", binBytes), ("fw.dat", datBytes)])
        let p = try FirmwareKit.parse(zipData: zip, fileName: "KX_V5.2.9_20260101.zip")
        XCTAssertEqual(p.binSize, 1024)
        XCTAssertEqual(p.datSize, 64)
        XCTAssertEqual(p.version, "5.2.9", "文件名里的版本必须抽出来，否则降级闸失效")
        XCTAssertEqual(p.binHex.count, 1024 * 2, "binHex 是 hex 串，长度是字节数 ×2")
    }

    // MARK: - 畸形包：每一种都必须明确抛错，不能"能跑就行"

    func testParseRejectsMissingManifest() {
        let zip = makeZip([("fw.bin", binBytes), ("fw.dat", datBytes)])
        XCTAssertThrowsError(try FirmwareKit.parse(zipData: zip, fileName: "x_V1.0.0.zip"))
    }

    func testParseRejectsMissingBin() {
        let zip = makeZip([("manifest.json", manifest(bin: "nope.bin")), ("fw.dat", datBytes)])
        XCTAssertThrowsError(try FirmwareKit.parse(zipData: zip, fileName: "x.zip"))
    }

    /// bin 小于 512B 必须拒 —— 这是"明显不是固件"的下限
    func testParseRejectsTooSmallBin() {
        let zip = makeZip([("manifest.json", manifest()),
                           ("fw.bin", [UInt8](repeating: 0xAA, count: 100)),
                           ("fw.dat", datBytes)])
        XCTAssertThrowsError(try FirmwareKit.parse(zipData: zip, fileName: "x.zip"))
    }

    /// dat 小于 16B 必须拒
    func testParseRejectsTooSmallDat() {
        let zip = makeZip([("manifest.json", manifest()),
                           ("fw.bin", binBytes),
                           ("fw.dat", [UInt8](repeating: 0xBB, count: 4))])
        XCTAssertThrowsError(try FirmwareKit.parse(zipData: zip, fileName: "x.zip"))
    }

    /// CRC 被改过必须拒（把 bin 内容改一个字节但不改 CRC）
    func testParseRejectsBadCRC() {
        var zip = makeZip([("manifest.json", manifest()), ("fw.bin", binBytes), ("fw.dat", datBytes)])
        // 找 bin 数据区并改一个字节（stored 模式下数据紧跟名字）
        if let idx = zip.firstIndex(of: 0xAA) { zip[idx] = 0xAB }
        XCTAssertThrowsError(try FirmwareKit.parse(zipData: zip, fileName: "x.zip"))
    }

    /// manifest 不是合法 JSON 结构
    func testParseRejectsBadManifestShape() {
        let zip = makeZip([("manifest.json", Array(#"{"nope":1}"#.utf8)),
                           ("fw.bin", binBytes), ("fw.dat", datBytes)])
        XCTAssertThrowsError(try FirmwareKit.parse(zipData: zip, fileName: "x.zip"))
    }

    // MARK: - 文件名版本

    func testVersionFromFileNameTable() {
        let cases: [(String, String?)] = [
            ("KX_V5.2.9_20260101.zip", "5.2.9"),
            ("KX_V5.2.9.zip", "5.2.9"),          // 尾随 .zip
            ("KX_V5.2.9", "5.2.9"),              // 无扩展名
            ("kx_v1.0.3_x.zip", "1.0.3"),
            ("firmware.bin", nil),               // 无版本
            ("V12.34.56.zip", "12.34.56"),
        ]
        for (name, want) in cases {
            XCTAssertEqual(FirmwareKit.versionFromFileName(name), want, name)
        }
    }

    // MARK: - 版本比较与降级闸

    func testVersionLtTable() {
        XCTAssertTrue(FirmwareKit.versionLt("1.0.2", "1.0.3"))
        XCTAssertFalse(FirmwareKit.versionLt("1.0.3", "1.0.3"))
        XCTAssertFalse(FirmwareKit.versionLt("1.0.4", "1.0.3"))
        XCTAssertTrue(FirmwareKit.versionLt("1.9.9", "2.0.0"))
        XCTAssertTrue(FirmwareKit.versionLt("1.0", "1.0.1"), "缺段补 0")
        XCTAssertFalse(FirmwareKit.versionLt("1.0.1", "1.0"))
    }

    /// 降级闸：包内版本 < 锁内版本 ⇒ 拒绝，且理由里带两个版本号（用户要能核对）
    func testDowngradeBlocked() {
        let pkg = FirmwarePackage(binHex: "", datHex: "", binSize: 1024, datSize: 64,
                                  version: "5.2.9", sourceName: "KX_V5.2.9.zip")
        let blocked = FirmwareKit.downgradeBlocked(current: "5.3.0", pkg: pkg)
        XCTAssertNotNil(blocked)
        XCTAssertTrue(blocked!.contains("5.2.9") && blocked!.contains("5.3.0"), blocked!)

        XCTAssertNil(FirmwareKit.downgradeBlocked(current: "5.2.9", pkg: pkg), "同版本放行")
        XCTAssertNil(FirmwareKit.downgradeBlocked(current: "5.2.8", pkg: pkg), "升级放行")
    }

    /// 无法判定时必须放行（读不到当前版本 / 包名无版本）——不能因为"判不了"就拦住正常升级
    func testDowngradeAllowsWhenUndecidable() {
        let noVer = FirmwarePackage(binHex: "", datHex: "", binSize: 1024, datSize: 64,
                                    version: nil, sourceName: "firmware.zip")
        XCTAssertNil(FirmwareKit.downgradeBlocked(current: "9.9.9", pkg: noVer))
        let pkg = FirmwarePackage(binHex: "", datHex: "", binSize: 1024, datSize: 64,
                                  version: "1.0.0", sourceName: "x_V1.0.0.zip")
        XCTAssertNil(FirmwareKit.downgradeBlocked(current: nil, pkg: pkg))
        XCTAssertNil(FirmwareKit.downgradeBlocked(current: "", pkg: pkg))
    }

    // MARK: - DFU 模式 MAC 启发式

    func testNextMac() {
        XCTAssertEqual(FirmwareKit.nextMac("aabbccddeeff"), "aabbccddee00", "末字节 +1 回绕")
        XCTAssertEqual(FirmwareKit.nextMac("aabbccddeef0"), "aabbccddeef1")
        XCTAssertEqual(FirmwareKit.nextMac("aabbccddeef0".uppercased()), "aabbccddeef1", "大写输入也要处理")
    }
}
