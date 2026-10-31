// 凭证模型 · CredAlert / Diff / Advice / DisableMark / CredPackage / StudioDraft
// 2026-10-29 从 CredentialOrg.swift（743 行）拆出。
import Foundation

struct CredAlert: Codable {
    var day: Bool = false
    var d3: Bool = false       // 930: 到期前 3 天
    var d1: Bool = false       // 930: 到期前 1 天
    var h24: Bool = false
    var h2: Bool = false
    init(day: Bool = false, d3: Bool = false, d1: Bool = false, h24: Bool = false, h2: Bool = false) {
        self.day = day; self.d3 = d3; self.d1 = d1; self.h24 = h24; self.h2 = h2
    }
    enum CodingKeys: String, CodingKey { case day, d3, d1, h24, h2 }
    /// 930 新增 d3/d1 之后, 老包 `kf_calert_` 的 JSON 里没有这两个键。合成解码器遇到**缺键**是抛错,
    /// 一抛整组开关会被 `?? CredAlert()` 吞成"全关" —— 用户已经开好的 7 天/24 小时档会静默消失。
    /// 所以显式解码: 缺键 = 那一档关, 不牵动别的档 (与恢复包"缺字段=不动本机"同一条纪律)。
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        day = (try? c.decodeIfPresent(Bool.self, forKey: .day)) ?? false
        d3 = (try? c.decodeIfPresent(Bool.self, forKey: .d3)) ?? false
        d1 = (try? c.decodeIfPresent(Bool.self, forKey: .d1)) ?? false
        h24 = (try? c.decodeIfPresent(Bool.self, forKey: .h24)) ?? false
        h2 = (try? c.decodeIfPresent(Bool.self, forKey: .h2)) ?? false
    }
}

