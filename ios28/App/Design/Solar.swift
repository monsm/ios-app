// Solar.swift —— 日光场的「真实时刻」（F28）。
//
// 日光场原来只按一套固定色温画。设计语言说的是「日光穿过玻璃」——
// 而日光是**随时刻和季节变**的：清晨偏冷、正午偏白、黄昏偏暖。
//
// 这里本地算太阳的高度角与方位角（不联网、不查 API），把结果映射成
// 日光场的暖冷与强度。算式是标准的太阳位置近似，误差在十几分钟量级 ——
// 对「色温」这件事绰绰有余。
//
// 纬度默认取东八区中部（上海附近）。用户在不在这条纬线上不影响可用性，
// 只影响色温偏一点。
import Foundation

struct SolarPhase: Equatable {
    /// 太阳高度角（度）：正数在地平线以上。
    var elevation: Double
    /// 方位角（度）：0 = 正北，顺时针。
    var azimuth: Double
    /// 是否在地平线以上。
    var isDaylight: Bool
    /// 暖度：0 = 冷（正午），1 = 暖（黄昏/清晨）。
    var warmth: Double
    /// 亮度：0…1（夜里接近 0）。
    var brightness: Double
    /// 一句话（调试/诊断用）。
    var label: String
}

enum Solar {
    /// 默认位置：东八区中部。
    static let defaultLatitude: Double = 31.23
    static let defaultLongitude: Double = 121.47

    /// 算某一刻的太阳位置。
    static func phase(at date: Date = Date(),
                      latitude: Double = defaultLatitude,
                      longitude: Double = defaultLongitude) -> SolarPhase {
        // 时角：0 = 正午，每 4 分钟 1 度。
        let dayOfYear = Double(Calendar(identifier: .gregorian).ordinality(of: .day, in: .year, for: date) ?? 1)
        let utc = Calendar(identifier: .gregorian).dateComponents([.hour, .minute, .second], from: date)
        let utcSeconds = Double((utc.hour ?? 12) * 3600 + (utc.minute ?? 0) * 60 + (utc.second ?? 0))
        let localSeconds = utcSeconds + Double(TimeZone.current.secondsFromGMT())
        let hourAngle = (localSeconds / 3600.0 - 12.0) * 15.0

        // 赤纬（近似）。
        let declination = 23.44 * sin(2 * Double.pi * (dayOfYear - 81) / 365.0)

        let latRad = latitude * .pi / 180
        let decRad = declination * .pi / 180
        let haRad = hourAngle * .pi / 180

        let sinElevation = sin(latRad) * sin(decRad) + cos(latRad) * cos(decRad) * cos(haRad)
        let elevation = asin(max(-1, min(1, sinElevation))) * 180 / .pi

        // 方位角（自正北顺时针）。
        let cosAz = (sin(decRad) - sin(elevation * .pi / 180) * sin(latRad))
            / (cos(elevation * .pi / 180) * cos(latRad))
        var azimuth = acos(max(-1, min(1, cosAz))) * 180 / .pi
        if hourAngle > 0 { azimuth = 360 - azimuth }

        // 暖度：太阳越低越暖（大气散射把蓝光散掉），正午最白。
        let warmth = max(0, min(1, 1 - (elevation + 6) / 40.0))
        // 亮度：地平线附近趋于 0。
        let brightness = max(0, min(1, (elevation + 6) / 34.0))

        let label: String
        if elevation > 50 { label = "正午" }
        else if elevation > 15 { label = "白天" }
        else if elevation > 0 { label = azimuth > 180 ? "傍晚" : "清晨" }
        else if elevation > -6 { label = "暮色" }
        else { label = "夜里" }

        return SolarPhase(elevation: elevation, azimuth: azimuth,
                          isDaylight: elevation > 0, warmth: warmth,
                          brightness: brightness, label: label)
    }

    /// 暖度 → 日光场的两团光的混合比例。
    ///
    /// 暖光团在右下（西边），冷光团在左上 —— 与窗外的方位一致。
    static func warmOffset(_ phase: SolarPhase) -> CGFloat {
        // 太阳偏西（azimuth > 180）时暖光团往左挪一点，反之往右。
        let westness = phase.azimuth > 180 ? 1.0 : 0.0
        return CGFloat(0.34 - 0.16 * westness)
    }

    /// 夜间：日光场整体压暗（亮度低）。
    static func dim(_ phase: SolarPhase) -> Double {
        0.35 + 0.65 * phase.brightness
    }
}
