// L10n.swift —— 文案的 key 化出口（B65）。
//
// 目标不是「今天就出三种语言」，而是先把**出口**立起来：
//   · 文案不再散落在页面里，而是有一个 key → 文本的表；
//   · 页面写 `L("state.empty.title")` 而不是直接写中文；
//   · 闸门（Gates/l10n.js）查「用到的 key 在不在表里」，缺一个就红。
//
// 这样以后要出英文/繁中，只改表；页面一行都不用动。
//
// 纪律：
//   · 表里没有的 key **回落成 key 本身**（界面上会看到一串 key）——
//     这样漏译是**看得见**的，而不是悄悄显示空白。
//   · 带参数的文案用 `L("x", ["n": 3])` 占位，格式串统一 `{n}`。
import Foundation

enum L10n {
    /// key → 文本。
    static let table: [String: String] = [
        // 通用
        "common.ok": "好",
        "common.cancel": "取消",
        "common.close": "关闭",
        "common.retry": "再试一次",
        "common.refresh": "刷新",
        "common.done": "完成",
        "common.back": "返回",
        "common.more": "更多",
        "common.loading": "正在加载",
        "common.unknown": "未知",
        "common.dismiss": "知道了",

        // 状态模型
        "state.empty.title": "这里还没有内容",
        "state.failed.title": "没能完成",
        "state.stale.badge": "上次读取",
        "state.partial.title": "已完成一部分",
        "state.permission.bluetooth.title": "蓝牙没有开",
        "state.permission.bluetooth.detail": "门锁走的是蓝牙直连，不需要网络，但需要蓝牙开着。",
        "state.permission.notify.title": "通知没有授权",
        "state.permission.notify.detail": "凭证到期与低电提醒走通知。现在授权就不会漏掉。",

        // 开锁
        "unlock.failure.title": "没打开",
        "unlock.failure.steps": "先看这三样",
        "unlock.failure.step.distance": "靠近门锁一点",
        "unlock.failure.step.bluetooth": "确认蓝牙是开的",
        "unlock.failure.step.state": "看看锁是不是布防或反锁了",
        "unlock.receipt.title": "门开了",
        "unlock.receipt.autolock": "约 {n} 秒后自动上锁",
        "unlock.receipt.viewLog": "看这次开门记录",
        "unlock.maybeExecuted.title": "这条命令可能已经执行",

        // 链路
        "link.pill.ready": "已连接",
        "link.pill.connecting": "握手中",
        "link.pill.down": "未连接",
        "link.pill.noKey": "未绑定",
        "link.pill.rssi": "信号 {v}",

        // 记录
        "log.progress.title": "正在读门锁记录",
        "log.progress.page": "第 {n} / {m} 页",
        "log.progress.read": "已读 {n} 条",
        "log.interrupted": "连接中断，已保存读到的 {n} 条",
        "log.backgroundHint": "还有更早的记录，正在后台继续读",

        // 配对
        "pair.wizard.preflight": "配对前先确认",
        "pair.wizard.step.scan": "手机靠近门锁",
        "pair.wizard.step.reset": "门锁已恢复到配网状态",
        "pair.wizard.step.handshake": "正在与门锁握手",
        "pair.wizard.step.keys": "正在写入密钥",
        "pair.wizard.step.pins": "正在写入 PIN 池",
        "pair.wizard.step.done": "配对完成",
        "pair.wizard.rollback": "中止并回滚",

        // 凭证
        "pin.generator.title": "随机生成一个",
        "pin.generator.hint": "避开 123456、连号这类好猜的组合",
        "pin.share.title": "把临时码发给对方",
        "pin.share.expiry": "有效期到 {t}",

        // 恢复流程
        "recovery.title": "我锁在门外了",
        "recovery.intro": "按顺序走完下面这几步。每一步都会先说清风险。",
        "recovery.step.risk": "风险：{r}",
        "recovery.run": "做这一步",
        "recovery.needUser": "这一步要你到门锁上做",
        "recovery.done": "这一步完成了",

        // 健康检查
        "health.title": "健康检查",
        "health.summary.ok": "一切正常",
        "health.summary.warn": "有 {n} 项要注意",
        "health.summary.fail": "有 {n} 项异常",
        "health.fix": "去修",

        // 诊断
        "diag.bundle.title": "导出诊断包",
        "diag.bundle.detail": "设备、权限、链路、命令记录 —— 不含任何密码或密钥",
        "diag.crash.title": "异常退出记录",
        "diag.timeline.title": "最近的命令",
        "diag.replay.title": "回放这一帧（只解析，不发锁）",

        // 备份与存储
        "storage.health.title": "本机数据",
        "storage.health.ok": "存储正常",
        "storage.health.issue": "{n} 项数据读不出来",
        "storage.health.repair": "从备份恢复",
        "storage.health.residue": "导出残片",
        "storage.version": "存储版本 {v}",
    ]

    /// 取文案。表里没有就**回落成 key 本身**（看得见的缺译）。
    static func t(_ key: String, _ args: [String: String] = [:]) -> String {
        var text = table[key] ?? key
        for (k, v) in args {
            text = text.replacingOccurrences(of: "{\(k)}", with: v)
        }
        return text
    }

    /// 带数字参数的快捷写法。
    static func t(_ key: String, _ n: Int) -> String {
        t(key, ["n": String(n)])
    }
}

/// 页面里用的短名。
func L(_ key: String) -> String { L10n.t(key) }
func L(_ key: String, _ n: Int) -> String { L10n.t(key, n) }
func L(_ key: String, _ args: [String: String]) -> String { L10n.t(key, args) }
