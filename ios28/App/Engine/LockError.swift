// LockError.swift —— 引擎侧的结构化错误分类（B17）。
//
// 协议层过去只抛 LocalizedError 的一句话，界面拿到的也就是一句话 ——
// 分不清「根本没连上」「锁拒了这条凭证」「本机存储坏了」。
// 这三种要做的下一步完全不同：前者让人靠近，后者让人换凭证或重配，
// 第三者让人别动手机、去找备份。错误必须带 kind，界面才能自己决定怎么讲。
//
// 纪律：错误**不自己编事实**。kind 是分类，title/detail 是「锁端或链路说了什么」，
// next 是「本机知道的下一步」—— 不知道就写 nil，不写猜测。
import Foundation

enum LockErrorKind: String {
    /// 链路：连不上 / 断链 / 超时 / 写失败
    case transport
    /// 凭证被拒（PIN 不对、令牌失效、指纹模糊）
    case auth
    /// 锁端明确回了 rc != 0
    case lockRejected
    /// 本机存储 / 台账 / Keychain
    case localStorage
    /// 权限（蓝牙、通知、面容）
    case permission
    /// 用户主动取消
    case cancelled
    case unknown
}

/// 引擎抛出的错误。带分类、带人话、带下一步。
struct LockError: Error {
    var kind: LockErrorKind
    /// 一句话：发生了什么。
    var title: String
    /// 细节（可以长）。
    var detail: String
    /// 下一步：可执行的一句话；本机不知道就 nil。
    var next: String?
    /// 能不能原样重试。
    var canRetry: Bool
    /// 命令**可能已经执行**（帧写出去了但没等到回执）。
    var mayHaveExecuted: Bool
    /// 锁端 rc（lockRejected 时有值）。
    var rc: Int?

    init(kind: LockErrorKind, title: String, detail: String = "", next: String? = nil,
         canRetry: Bool = true, mayHaveExecuted: Bool = false, rc: Int? = nil) {
        self.kind = kind
        self.title = title
        self.detail = detail
        self.next = next
        self.canRetry = canRetry
        self.mayHaveExecuted = mayHaveExecuted
        self.rc = rc
    }
}

// MARK: - 构造

extension LockError {
    /// 把协议层抛出的任意错误收成结构化错误。
    ///
    /// `cmd` 用来判「这条命令是不是写命令」——
    /// 写命令超时时**不能**说「重试一下」，因为锁可能已经执行了（F44）。
    static func from(_ error: Error, cmd: UInt8? = nil) -> LockError {
        if let le = error as? LockError { return le }
        if let be = error as? BLEErrorX {
            switch be {
            case .code(let c):
                return transport(c, cmd: cmd)
            case .msg(let m):
                // 引擎自己抛的中文消息：按关键词归类，不去猜别的。
                if m.contains("台账") || m.contains("存储") || m.contains("Keychain") {
                    return LockError(kind: .localStorage, title: "本机数据有问题",
                                     detail: m, next: "先别再写门锁。到「设置 → 备份与恢复」导出一份，再联系技术支持。",
                                     canRetry: false)
                }
                if m.contains("护栏") || m.contains("试验") {
                    return LockError(kind: .permission, title: "只读试验模式挡住了这次操作",
                                     detail: m, next: "在「设置 → 安全」里关掉只读试验模式后再试。",
                                     canRetry: false)
                }
                return LockError(kind: .unknown, title: m, detail: "", next: nil)
            }
        }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain || ns.domain == NSPOSIXErrorDomain {
            return transport(.underlying, cmd: cmd)
        }
        return LockError(kind: .unknown, title: ns.localizedDescription)
    }

    /// 链路错误。写命令超时的口径与只读命令**不一样**。
    static func transport(_ code: BLEError, cmd: UInt8? = nil) -> LockError {
        let unsafe = cmd.map { ZKProtocol.writeCmdsBlocked.contains($0) } ?? false
        // 写命令的「超时 / 写失败」= 字节可能已经到了锁端 —— 不重发，也不说「重试」。
        let maybeExecuted = unsafe && (code == .responseTimeout || code == .writeFailed)
        var next: String?
        switch code {
        case .notFound:
            next = "确认手机就在门锁旁边、门锁已通电，然后重试。"
        case .connectTimeout, .linkNotReady:
            next = "靠近门锁再试一次；连不上时先看「维护与诊断」里的链路读数。"
        case .responseTimeout:
            next = unsafe ? nil : "再试一次；如果连着超时，去「维护与诊断」导出一份。"
        case .writeFailed:
            next = unsafe ? nil : "再试一次。"
        case .parseFail:
            next = "这条多半是固件版本对不上。把固件版本记下来，去「固件升级」看看有没有新包。"
        default:
            next = nil
        }
        return LockError(kind: .transport,
                         title: code.message,
                         detail: unsafe && maybeExecuted
                            ? "这条命令已经发出去了，锁端可能已经执行，只是回执没回来。"
                            : "",
                         next: next,
                         canRetry: !maybeExecuted,
                         mayHaveExecuted: maybeExecuted)
    }

    /// 锁端回了 rc != 0。
    static func rejected(rc: Int, cmd: UInt8? = nil) -> LockError {
        let hint = StatusParser.rcHint(rc)
        let msg = StatusParser.rcMessage(rc)
        // rc=1/2/6/11 是凭证类拒绝；其余是锁端状态类。
        let isAuth = [1, 2, 6, 11].contains(rc)
        return LockError(kind: isAuth ? .auth : .lockRejected,
                         title: msg,
                         detail: hint ?? "",
                         next: hint,
                         canRetry: !isAuth,
                         mayHaveExecuted: false,
                         rc: rc)
    }

    static func permission(_ title: String, _ detail: String, next: String? = nil) -> LockError {
        LockError(kind: .permission, title: title, detail: detail, next: next, canRetry: false)
    }

    static func localStorage(_ title: String, _ detail: String, next: String? = nil) -> LockError {
        LockError(kind: .localStorage, title: title, detail: detail, next: next, canRetry: false)
    }

    static func cancelled(_ what: String) -> LockError {
        LockError(kind: .cancelled, title: "已取消\(what)", detail: "", next: nil, canRetry: true)
    }
}
