// 备份口令的会话级共享（一次输入，两页通用）。
//
// 为什么需要它：备份工作室（上传/下载/轮换）用 `encPw`，备份页的云端恢复用 `cloudPw` ——
// 两个 `@State` 各自持有，语义却是**同一个东西**（同一份 `zklock-backup.enc` 的加密口令）。
// 用户在工作室传上去，切到备份页恢复时要再输一遍，而且没有任何地方说"这是同一个口令"。
//
// 设计取舍：
//   · **只在内存**，不落盘。明文口令写偏好键等于把密钥写在磁盘上 —— 这与
//     `RemoteFrame`/`recentFrames` 不落盘是同一条纪律（见 LockService 的注释）。
//   · **进程内单例**，App 退到后台不清、被系统回收就没了 —— 那时用户重输一遍是合理的。
//   · 用完不主动清空：用户可能连续做"上传 → 下载验证 → 轮换"三件事，
//     每步都重输是骚扰。清空只发生在两处：用户主动点「清除」，或 App 进程结束。
//
// 这一条不改变任何加密行为，只让"同一口令"在界面上只有一个来源。
import Foundation

/// 备份加密口令（会话级，仅内存）。
@MainActor
enum BackupPassphrase {
    private static var value = ""

    static var current: String {
        get { value }
        set { value = newValue }
    }

    static var isEmpty: Bool { value.isEmpty }

    static func clear() {
        value = ""
        // 尽力擦一遍旧字符串（Swift 无法保证字符串不被复制，这里只做姿态，注释说明清楚，
        // 不假装"安全擦除"——真正的安全擦除在 Swift 里做不到）。
        value = ""
    }

    /// 给界面用的一句话说明（放在口令输入框的 footer）。
    static let note = "口令只存在于本次运行的记忆里：不落盘、不上传，App 被系统回收后需重输。"
}
