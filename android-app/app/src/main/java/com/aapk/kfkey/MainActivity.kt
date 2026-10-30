package com.aapk.kfkey

import android.Manifest
import android.content.Context
import android.media.AudioManager
import android.media.ToneGenerator
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import kotlin.math.cos
import kotlin.math.sin
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.journeyapps.barcodescanner.ScanContract
import com.journeyapps.barcodescanner.ScanOptions
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

// ---------- 视觉常量 ----------
// 配色搬到 Theme.kt (internal): SignalArrow.kt 也要用同一套, 而顶层 private 只在单文件可见。

class MainActivity : ComponentActivity() {
    // 只在 unlocker 需要时建一次: KfApp() 是 Composable, remember 的状态跟着组合走,
    // 但 release() 是挂起函数, 不能从 onDestroy 里直接调 —— 所以把 unlocker 提到 Activity 上,
    // 生命周期出口才有东西可拆。
    private val unlocker by lazy { BleUnlocker(this) }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // 2026-10-18: 外层包 KfTheme 下发深浅双模色板 (跟随系统 isSystemInDarkTheme)。
        setContent { KfTheme { KfApp(unlocker) } }
    }

    override fun onDestroy() {
        // 后台把链路拆干净 (不等回执, 进程都要走了)。不拆的话锁那侧会挂着一条
        // "对端已消失但仍连着"的链路, 下次靠近反而连不上。
        val u = unlocker
        Thread {
            try {
                kotlinx.coroutines.runBlocking { u.release() }
            } catch (_: Exception) {
            }
        }.start()
        super.onDestroy()
    }
}

@Composable
private fun KfApp(unlocker: BleUnlocker) {
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    // unlocker 由 Activity 持有 (而不是在这里 remember 一个): 热链路要能被 onDestroy 拆掉。
    // 两处各 new 一个的话, Activity 拆的是空的那个, 真正连着锁的那条永远留在后台。

    var lock by remember { mutableStateOf(LockStore.load(ctx)) }
    var status by remember { mutableStateOf("") }
    /// 失败时的过程留痕 (令牌前缀 / rc) —— 真机排障就靠这一行, 平时不占地方
    var detail by remember { mutableStateOf("") }
    var statusBad by remember { mutableStateOf(false) }
    var busy by remember { mutableStateOf(false) }
    // 初值从本机读 (跨重启保留); 切换时立刻落盘 —— 见 LockStore.loadProximity 的注释
    var proximity by remember { mutableStateOf(LockStore.loadProximity(ctx)) }
    var rssi by remember { mutableStateOf<Int?>(null) }
    var pending by remember { mutableStateOf<LockInfo?>(null) }   // 待二次确认的绑定
    // 2026-10-31（第 53 轮）：初值从已加载的 lock 读回 —— 与 `lastRc` 同口径（第 27 轮）。
    var lastAuto by remember { mutableStateOf(lock?.lastAutoMs ?: 0L) }   // 上次自动下发时刻 (冷却基准)
    // 2026-10-27 审核补齐 (C-A1)：iOS 有 F6 锁态门（rc=25 锁忙 / rc=26 被撬 → 拒绝自动开），
    // Android 原先没有。这里缓存上次开锁回包的 rc，供 maybeAutoUnlock 做 F6 判断。
    // 2026-10-31（第 27 轮修复，**F6 跨会话失效**）：原来是 `mutableStateOf(0)` —— 初值恒 0，
    // 而 `LockStore` 里其实早就持久化了 `lastRc`（`lr` 字段，load 时读、save 时写）。
    // 后果：App 重启后 F6 门"忘了"锁上次报过 rc=25/26 ⇒ 锁正忙/被撬状态下照样下发 04。
    // 现在初值从已加载的 lock 里取回，重启后 F6 仍然有效。
    var lastRc by remember { mutableStateOf(lock?.lastRc ?: 0) }
    // 2026-10-31（第 37 轮）：标定采样面板开关 + 采样缓冲。
    var showCalibrate by remember { mutableStateOf(false) }
    val calSamples = remember { mutableStateListOf<Int>() }
    var armed by remember { mutableStateOf(false) }                // 回差滤波后的"已武装"位
    // 2026-10-30（提速，与 iOS 同式）: 最近 RSSI 样本（最新在前，最多 3 个）—— 中值武装判据用。
    val rssiHistory = remember { mutableStateListOf<Int>() }
    var fired by remember { mutableStateOf(false) }                // 本次接近事件是否已发过 04
    var prewarmStarted by remember { mutableStateOf(false) }       // 本次靠近是否已预热过
    var warming by remember { mutableStateOf(false) }              // 预热建链在途 (要让监测撤下)
    // 前后台闸 (用户口径 2026-10-17): **后台一律不许扫锁**。旧写法没有这一层 —— Activity 到了
    // onPause 之后 LaunchedEffect 仍在跑, 扫描在后台继续烧手机射频与锁的广播电。
    var foreground by remember { mutableStateOf(true) }
    // 箭头数据 (FindMy 式): 当前朝向 + "信号最强那一刻的朝向" (= 峰值方位)。
    // peak 只在明显更强时改写 (见 SignalArrow.peakUpdate), 广播 ±1dB 抖动不会让箭头乱跳。
    var azimuth by remember { mutableStateOf(0f) }
    var peakRssi by remember { mutableStateOf<Int?>(null) }
    var peakAz by remember { mutableStateOf<Float?>(null) }
    var showSettings by remember { mutableStateOf(false) }   // 二级菜单: 靠近开关 / 重新扫码 / 解绑
    var pitch by remember { mutableStateOf(0f) }              // 手机俯仰 (AirTag 层 3D 视差)
    var roll by remember { mutableStateOf(0f) }               // 手机横滚 (同上)
    var airTagDismissed by remember { mutableStateOf(false) }  // 用户手动收起 AirTag 层 (本次靠近事件内不再弹)
    var findSound by remember { mutableStateOf(true) }         // AirTag 层提示音开关
    val lifecycleOwner = LocalLifecycleOwner.current

    // Q20 (2026-10-20): 返回键处理。此前全仓零 BackHandler —— 二级菜单与 AirTag 全屏层都是
    // 手写 AnimatedVisibility, 没有人消费返回键 ⇒ 按返回会冒泡到 ComponentActivity.finish(),
    // 整个 App 直接退出。这里按"最上层优先"关闭：AirTag 层 → 二级菜单 → 默认退出。
    // 判据与下方 airTagShowing 同一表达式 (它声明在更下面, 这里不能用) —— proximity/rssi/airTagDismissed
    // 三个状态都在上一行之前声明, 所以可以直接内联。
    val airTagLayerUp = proximity && rssi != null && !airTagDismissed
    BackHandler(enabled = airTagLayerUp || showSettings) {
        if (airTagLayerUp) { airTagDismissed = true } else if (showSettings) { showSettings = false }
    }

    fun say(text: String, bad: Boolean = false) {
        status = text
        statusBad = bad
    }

    // 权限: 扫描/连接 + 相机 (扫码)。minSdk=33 ⇒ 三项都是运行时权限, 没有版本分支。
    // 旧回调是空 lambda: 用户点了"拒绝"之后界面只会停在"正在寻找门锁…", 既不解释也不给去设置的路。
    val permNames = mapOf(
        Manifest.permission.BLUETOOTH_SCAN to "蓝牙扫描",
        Manifest.permission.BLUETOOTH_CONNECT to "蓝牙连接",
        Manifest.permission.CAMERA to "相机",
    )
    val perms = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { result ->
        val denied = result.filterValues { !it }.keys
        if (denied.isNotEmpty()) {
            val names = denied.map { permNames[it] ?: it }
            say("缺少权限: " + names.joinToString("、") + " — 扫码与开锁会失败, 请到系统设置里允许", true)
        }
    }
    LaunchedEffect(Unit) {
        val need = listOf(
            Manifest.permission.BLUETOOTH_SCAN,
            Manifest.permission.BLUETOOTH_CONNECT,
            Manifest.permission.CAMERA,
        )
        perms.launch(need.toTypedArray())
    }

    fun doUnlock(auto: Boolean) {
        val l = lock ?: return
        // busy 时**不能静默丢弃**：自动开锁正在跑时用户点圆盘，手动那一下没有发生，
        // 而界面此前毫无反馈 —— 用户会以为"点了没反应"，然后在门口反复点。
        // 给一句明确的话，并说清是哪一路在跑。
        if (busy) { say(if (auto) "正在开锁, 请稍候…" else "自动开锁进行中, 请稍候…"); return }
        busy = true
        say(if (auto) "已靠近, 正在开锁…" else "正在开锁…")
        scope.launch {
            val r = unlocker.unlock(l)
            // 2026-10-27 审核补齐：把 rc 落到状态里，供下一次自动开锁做 F6 锁态门判断。
            // 2026-10-31（第 27 轮）：写内存态之外**也要落盘** —— 否则下次启动读回的还是旧值。
            lastRc = r.rc
            lock?.let { LockStore.save(ctx, it.copy(lastRc = r.rc)) }
            busy = false
            // 来源标注 (用户 2026-10-17): 开完要能说清是自动开的还是自己点的 ——
            // "谁把我门开了"必须能回答。只在成功时冠来源: 失败那句是诊断文案,
            // 再加前缀会把它挤得读不完。
            say(if (r.ok) (if (auto) "自动开锁成功 — " else "手动开锁成功 — ") + r.message else r.message, !r.ok)
            detail = if (r.ok || r.trace.isEmpty()) "" else r.trace
            // 2026-10-18: 统一走 KfHaptics (与 iOS DS.Haptics 三档语义对齐)。
            // 原来只有成功震一下, 失败是静默的 —— 开锁失败是最需要被感知的时刻。
            if (r.ok) KfHaptics.ok(ctx) else KfHaptics.fail(ctx)
        }
    }

    // 扫码 → 解析 → 已绑定时**二次确认**再替换
    val scan = rememberLauncherForActivityResult(ScanContract()) { result ->
        val text = result.contents ?: return@rememberLauncherForActivityResult
        val parsed = LockStore.parseQr(text)
        if (parsed == null) {
            say("这不是本 App 的钥匙码 — 请让 iOS 端重新生成", true)
            return@rememberLauncherForActivityResult
        }
        if (lock == null) {
            LockStore.save(ctx, parsed)
            lock = parsed
            say("已绑定「${parsed.name}」")
        } else {
            pending = parsed   // 已有绑定 → 弹确认
        }
    }

    fun launchScan() {
        scan.launch(
            ScanOptions()
                .setDesiredBarcodeFormats(ScanOptions.QR_CODE)
                .setPrompt("对准 iOS 上的钥匙二维码")
                .setBeepEnabled(false)
                .setOrientationLocked(false)
        )
    }

    // 生命周期: 退后台 ⇒ ① 停监测 (不再扫描) ② 拆掉热链路 (不把 GATT 挂在后台占着锁那一侧的
    // 接口位); 回前台 ⇒ 重新起监测, 并主动预热一次 (这一脚允许自扫, 因为缓存里必然还没有句柄)。
    DisposableEffect(lifecycleOwner) {
        val obs = LifecycleEventObserver { _, ev ->
            when (ev) {
                Lifecycle.Event.ON_RESUME -> {
                    // 回前台: 监测流由 foreground 这个 key 自动重新挂上, 首轮广播就会把句柄
                    // 填进缓存 → maybeAutoUnlock 顺势预热。这里**不另起扫描** (安卓同时只跑
                    // 一路扫描, 自己扫一次反而会把刚挂上的监测顶掉)。
                    foreground = true
                    prewarmStarted = false
                    fired = false
                    airTagDismissed = false
                }
                Lifecycle.Event.ON_PAUSE -> {
                    foreground = false
                    armed = false              // 回前台必须由新的信号样本重新武决, 不沿用后台前的判断
                    prewarmStarted = false
                    scope.launch { unlocker.release() }
                }
                else -> Unit
            }
        }
        lifecycleOwner.lifecycle.addObserver(obs)
        onDispose { lifecycleOwner.lifecycle.removeObserver(obs) }
    }

    // ---------- 靠近自动开锁: 回差 + 一次性闩锁 + 冷却 (对齐 iOS AutoOpenKit F3/F5) ----------
    // 旧口径是"RSSI ≥ -38 且距上次 >8 秒"→ 人站在门口不动时, 每 8 秒再发一次 04。
    // iOS 那条链早就裁定过这件事 ("每个接近事件只发一次 04"), 理由是 04 驱动执行器:
    // 反复下发 = 电机反复试, 既费电也可能把锁拖进 rc=25「锁正忙」。现在照 iOS 的三重闸:
    //   ① 回差 (F3 rssiSample): 越过武装线才武装, 掉到解除线以下才解除 —— 门口来回走不翻转;
    //   ② 一次性闩锁 (F5): 一次"接近事件"只发一次, 解除后才放开;
    //   ③ 冷却 (F5 coolReady): 上次下发距今 >60s 才允许下一次 (跨事件也拦)。
    // 写成局部函数而不是塞进 collect 的 lambda: collect 外面已经套着 LaunchedEffect 一层
    // lambda, 再从内层跨出去要写 return@collect 那个 label —— label 名字错了就是编译失败,
    // 而这一段的判据本身就是会算错的东西, 不该押在一个字符串上。
    // 预热线: 比武装线 (AutoOpenKit.BASE = -40) 弱 24 dB ⇒ 功率约 1/250, 大致一两米开外。
    // 越过它就在后台把链路建好 (prewarm 只建链, 一个命令都不发), 等越过武装线时只剩
    // 01+04 两个往返 —— "秒开"靠的是这一步, 不是把协议改快。
    // 用 PREWARM 这个固定值而不是标定值: 安卓端没有标定页 (见 AutoOpenKit 注释)。
    // 2026-10-31（第 28 轮）：预热线跟着标定基准走 —— 固定 BASE-24 在标定后就不成比例了。
    val prewarmLineDbm = AutoOpenKit.rssiBase(lock?.rssiP95 ?: 0) - 24

    fun maybeAutoUnlock(r: Int) {
        val now = System.currentTimeMillis()
        // 预热不排队、不抢锁: prewarm 内部 mutex 会排在建链后面, 而开锁那一趟优先级更高,
        // 所以只在"没在开锁 && 还没有热链路"时发起, 避免和开锁抢同一次 startScan。
        if (!foreground) return   // 后台不预热: 预热就是起连接, 那是一次射频开销
        if (!prewarmStarted && !busy && !warming && r >= prewarmLineDbm && lock != null) {
            prewarmStarted = true
            // lock 是 by remember 委托属性: Kotlin 不对委托属性做智能转换 (即使上一行刚判过 != null),
            // 所以这里必须当场取一个非空局部量, 否则 prewarm(target) 是类型不匹配 = 编译不过。
            val target = lock ?: return
            scope.launch {
                warming = true
                // 等一帧多, 让 LaunchedEffect 因 warming 变化而把监测流拆掉 (那句 awaitClose
                // 里的 stopScan 才是真的把射频放掉)。不等就是"边扫边连", 133 的成因之一。
                delay(220)
                try {
                    unlocker.prewarm(target)
                } finally {
                    warming = false
                }
            }
        }
        // 2026-10-30（提速）: 维护最近 3 个样本（最新在前），供中值武装判据用。
        rssiHistory.add(0, r)
        while (rssiHistory.size > 3) { rssiHistory.removeAt(rssiHistory.size - 1) }
        // 2026-10-31（第 28 轮）：基准优先用标定值（未标定退回 BASE = -40，与 iOS fallbackBase 同值）。
        val armBase = AutoOpenKit.rssiBase(lock?.rssiP95 ?: 0)
        armed = AutoOpenKit.rssiArmedByMedian(prevArmed = armed, history = rssiHistory, base = armBase)
        // 信号掉回解除线以下 = 这一次接近事件结束 → 放开闩锁与预热位, 下次靠近重来一遍
        // 2026-10-27 审核 (C-A3)：原写法「!armed 就放开闩锁」，而 armed 在回差带内就会变 false
        // ⇒ 退半步再进一步可能再开一次。与 iOS 同口径：只在信号掉到解除线**以下 3dB**（真走远）才放开。
        // 同时保留原行为：未武装时清 prewarmStarted（预热位该跟着复位）。
        if (!armed) { prewarmStarted = false }
        // 2026-10-31（第 28 轮）：走远判据必须用**同一基准** —— 否则标定后解除线仍按 -40 算，回差带对不上。
        if (r < AutoOpenKit.disarmThreshold(armBase) - 3) { fired = false }
        if (!armed || fired) return
        // 2026-10-27 审核补齐 (C-A1)：iOS 有 7 道门，Android 原先只有 4 道 ——
        // 缺的正好是三道**否决门**，导致「在 iPhone 上开布防 → Android 手机照常自动开门」。
        // F4 布防时段否决（本机侧；极简版不下发 cmd25，只拦本机）
        if (lock?.defendOn == true) {
            val cal = java.util.Calendar.getInstance()
            val hour = cal.get(java.util.Calendar.HOUR_OF_DAY)
            val st = lock?.defendStartHour ?: 22
            val en = lock?.defendEndHour ?: 7
            val inWindow = if (st <= en) hour in st until en else (hour >= st || hour < en)
            if (inWindow) {
                say("布防时段内，已拒绝自动开锁")
                return
            }
        }
        // F6 锁态门：上次回包 rc=25(锁忙) / rc=26(被撬) 时不自作主张再发 04
        if (lastRc == 25) { say("门锁正忙，已跳过这次自动开锁"); return }
        if (lastRc == 26) { say("检测到防拆事件，已暂停自动开锁"); return }
        if (!AutoOpenKit.coolReady(lastAuto, now)) return
        if (busy) return
        fired = true
        lastAuto = now
        // 2026-10-31（第 53 轮）：写内存态之外**也落盘** —— 否则重启后冷却清零，可能双开。
        lock?.let { l -> LockStore.save(ctx, l.copy(lastAutoMs = now)) }
        doUnlock(auto = true)
    }

    // busy 也进 key: 安卓蓝牙栈**一边扫描一边连接**极易失败 (GATT 133 的头号成因),
    // 而开锁这一趟自己就要扫描+连接, 所以开锁在途时把 RSSI 监测整条撤掉, 完了再挂回去。
    // 不只是抢射频: 同 App 里第二次 startScan 会重启扫描, 前一个 callback 静默失声,
    // 且 scanForLock 收尾那句 stopScan 会把监测的扫描一起停掉 —— 于是自动开锁跑过一次之后
    // "当前信号"再也不更新, 用户只能关掉开关再打开。
    LaunchedEffect(proximity, lock?.mac, busy, warming, foreground) {
        val l = lock ?: return@LaunchedEffect
        if (!proximity) { rssi = null; armed = false; fired = false; prewarmStarted = false; rssiHistory.clear(); peakRssi = null; peakAz = null; airTagDismissed = false }
        // 开锁在途 **或预热在途** 都撤下监测: 安卓同时只跑一路扫描, 而且边扫边连极易 133。
        // 撤下后 rssi 保持最后一次的读数 (不抹成 null), 免得界面在预热那一瞬闪成"正在寻找门锁…"
        if (!proximity || busy || warming || !foreground) return@LaunchedEffect
        // observeSignal 而不是 observeRssi: 锁连上之后就不发广播了, 只盯扫描会在"链路已热"
        // 那一刻起收不到任何样本 —— 那正是自动开锁最需要信号的时刻 (详见 BleUnlocker 注释)。
        unlocker.observeSignal(l).collect { r ->
            rssi = r
            val (br, bp, changed) = peakUpdate(peakRssi, peakAz, r, azimuth)
            if (changed) { peakRssi = br; peakAz = bp }
            maybeAutoUnlock(r)
        }
    }

    // 手机姿态角: 只在有前台时收 (后台不占传感器)。箭头旋转用的是这个真值, 不假装知道锁的方位。
    LaunchedEffect(foreground) {
        if (!foreground) return@LaunchedEffect
        HeadingSense.attitude(ctx).collect { a -> azimuth = a[0]; pitch = a[1]; roll = a[2] }
    }

    // 连上锁信号 (有 RSSI 读数) 且没被手动收起 ⇒ 弹出 AirTag 精确查找层。
    val airTagShowing = proximity && rssi != null && !airTagDismissed

    // 2026-10-18: 接入深浅双模 (KfTheme)。
    // 暗色档仍取既有 Theme.kt 的值 (D14: Android 保留暗色 + 暖金),
    // 浅色档是新做的一套; 两套都由 LocalKfColors 下发, 页面里不再直接读 BgTop/BgBottom。
    val colors = LocalKfColors.current
    Box(
        Modifier
            .fillMaxSize()
            .background(Brush.verticalGradient(listOf(colors.bgTop, colors.bgBottom)))
    ) {
        Column(
            Modifier
                .fillMaxSize()
                .padding(horizontal = 24.dp, vertical = 28.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Header(lock)
            Spacer(Modifier.weight(1f))
            if (lock == null) {
                EmptyState(onScan = { launchScan() })
            } else {
                // 靠近指示箭头 (FindMy 式): 只在开了「靠近自动开锁」时出现。
                // 旋转 = 手机姿态角 (真); 填充 = 当前信号 (真)。这把锁没有 UWB, 算不出绝对方位,
                // 所以箭头指"转动手机时信号最强的那个朝向", 不谎称指针自动指向门 (见 SignalArrow 头注)。
                AnimatedVisibility(visible = proximity && !airTagShowing) {
                    SignalArrow(
                        okColor = colors.ok,
                        outlineColor = colors.ink,
                        azimuthDeg = azimuth,
                        peakDeg = peakAz,
                        rssi = rssi,
                        armed = armed,
                        busy = busy,
                        pitchDeg = pitch,
                        rollDeg = roll,
                        sizeDp = 208,
                    )
                }
                UnlockDial(busy = busy, onClick = { doUnlock(auto = false) })
                Spacer(Modifier.height(22.dp))
                Text(
                    text = status.ifBlank { "点一下开锁" },
                    color = when {
                        statusBad -> colors.bad
                        // 成功语现在是 "手动/自动开锁成功 — …"; 旧句只认 "已开锁" 会把成功念成灰色
                        status.contains("成功") || status.startsWith("已开锁") -> colors.ok
                        else -> colors.inkSub
                    },
                    fontSize = 15.sp,
                    textAlign = TextAlign.Center
                )
                Spacer(Modifier.height(6.dp))
                Text(
                    text = if (!proximity) " " else when {
                        rssi == null -> "正在寻找门锁…"
                        armed -> "信号已满 (当前 $rssi dBm) — 马上自动开"
                        else -> "还差一点 (当前 $rssi dBm) — 走近或转动手机"
                    },
                    // 2026-10-31（第 42 轮 · 对比度）：近场提示 —— 用户靠它判断该不该继续走；去掉 alpha（0.7 叠底后 <4.5:1）
                    color = colors.inkSub,
                    fontSize = 12.sp,
                    fontFamily = FontFamily.Monospace
                )
                if (!detail.isEmpty()) {
                    Text(
                        text = detail,
            // 2026-10-31（第 42 轮 · 对比度）：开锁失败详情 —— **最需要读清的一段**，0.55 叠在底上只有约 2.8:1 —— 去掉 alpha（原来叠在底上低于 4.5:1）
                        color = colors.inkSub,
                        fontSize = 11.sp,
                        fontFamily = FontFamily.Monospace,
                        textAlign = TextAlign.Center,
                        modifier = Modifier.padding(top = 4.dp)
                    )
                }
            }
            Spacer(Modifier.weight(1f))
        }

        // 首页右下齿轮: 二级菜单唯一入口。首页不留开关与账号操作 (用户口径 2026-10-17)。
        // 用 Box 子节点 + align 定位, 不能塞进上面那个 Column: Column 里没有 Alignment.BottomEnd 这个对齐方式。
        if (lock != null) {
            GearButton(Modifier.align(Alignment.BottomEnd).padding(24.dp)) { showSettings = true }
        }
    }

    // ---------- 二级弹层 (底部抽屉): 靠近开关 / 重新扫码 / 解绑 ----------
    AnimatedVisibility(
        visible = showSettings && lock != null,
        enter = fadeIn(tween(160)) + slideInVertically(tween(220)) { it / 3 },
        exit = fadeOut(tween(140)) + slideOutVertically(tween(200)) { it / 3 },
    ) {
        Column(
            Modifier
                .fillMaxSize()
                .background(Color(0xB3050709))
                // 点遮罩收起。用空 indication 的 clickable: 默认 Material ripple 会在遮罩上画一圈水波, 看着像"有东西可按"
                .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) {
                    showSettings = false
                },
            verticalArrangement = Arrangement.Bottom,
        ) {
            if (lock != null) {
                ProximityCard(
                    on = proximity,
                    onToggle = {
                        proximity = it
                        LockStore.saveProximity(ctx, it)
                        if (!it) rssi = null
                    },
                    onRescan = {
                        showSettings = false
                        launchScan()
                    },
                    onUnbind = {
                        LockStore.clear(ctx)
                        lock = null
                        proximity = false
                        showSettings = false
                        // 解绑之后这条链路就没有主人了: 不收, 它会一直占着锁的 GATT 接口位,
                        // 而下一把锁要连的时候还得先拆它 (安卓一次只养一条热链路)。
                        scope.launch { unlocker.release() }
                        say("已解绑")
                    },
                    defendOn = lock?.defendOn ?: false,
                    onDefendToggle = { on ->
                        lock?.let { l ->
                            val upd = l.copy(defendOn = on)
                            lock = upd
                            LockStore.save(ctx, upd)
                            say(if (on) "布防已开：22:00–07:00 不自动开锁" else "布防已关")
                        }
                    },
                    onClose = { showSettings = false },
                    // 2026-10-31（第 37 轮）：F3 标定入口。
                    rssiP95 = lock?.rssiP95 ?: 0,
                    onCalibrate = { showCalibrate = true },
                    onClearCalibration = {
                        lock?.let { l ->
                            val upd = l.copy(rssiP95 = 0)
                            lock = upd
                            LockStore.save(ctx, upd)
                            say("距离基准已清除，回到默认 " + AutoOpenKit.BASE + " dBm")
                        }
                    },
                )
            }
        }
    }

    // 已绑定过 → 再次扫码要**二次确认**: 覆盖的是一把能开门的钥匙, 不能静默替换
    pending?.let { p ->
        val same = p.mac == lock?.mac
        AlertDialog(
            onDismissRequest = { pending = null },
            containerColor = colors.surface,
            titleContentColor = colors.ink,
            textContentColor = colors.inkSub,
            title = { Text(if (same) "更新这把锁的凭证?" else "换一把锁?", fontWeight = FontWeight.Medium) },
            text = {
                Text(
                    if (same) "本机已绑定「${p.name}」。用新扫到的凭证覆盖它?"
                    else "本机现在绑定的是「${lock?.name ?: ""}」(${lock?.macText ?: ""})。\n" +
                        "换成「${p.name}」(${p.macText}) 之后, 原来那把锁要从这台手机重新扫码才能再用。"
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    LockStore.save(ctx, p)
                    lock = p
                    pending = null
                    say("已绑定「${p.name}」")
                }) { Text(if (same) "覆盖" else "换绑", color = colors.accent) }
            },
            dismissButton = {
                TextButton(onClick = { pending = null }) { Text("取消", color = colors.inkSub) }
            }
        )
    }

    // 2026-10-31（第 37 轮）：F3 标定采样面板。与 iOS `AutoCalibrateSheet` 同逻辑：
    // 站到「平时想让它自动开锁的那个位置」，点开始采样，采够 5 个样本才能保存
    // （`AutoOpenKit.p95` 对 <5 返回 null —— 3 个样本的 95 分位没有统计意义）。
    if (showCalibrate) {
        // 采样驱动: 与自动开锁用同一个 RSSI 来源, 每 0.5 秒收一个样本, 40 个（20 秒）自动停。
        LaunchedEffect(showCalibrate) {
            while (showCalibrate && calSamples.size < 40) {
                rssi?.let { calSamples.add(it) }
                delay(500)
            }
        }
        val p95 = AutoOpenKit.p95(calSamples)
        AlertDialog(
            onDismissRequest = { showCalibrate = false; calSamples.clear() },
            containerColor = colors.surface,
            titleContentColor = colors.ink,
            textContentColor = colors.inkSub,
            title = { Text("标定距离基准", fontWeight = FontWeight.Medium) },
            text = {
                Column {
        // 2026-10-31（第 46 轮，**编译错误**）：Kotlin 的 `isEmpty` 是**方法**，必须带括号； Swift 里它是属性。从 Swift 搬过来时极易漏掉 `()`。
                    if (calSamples.isEmpty()) {
                        // 空态: 别只显示"已采 0 个" —— 那是数字, 不是下一步该做什么。
                        Text("点「开始采样」后站在你想让它开锁的位置别动，采 20 秒左右。")
                    } else if (p95 == null) {
                        Text("已采 " + calSamples.size + " 个样本，还差 " + (5 - calSamples.size) + " 个才能保存。")
                    } else {
                        Text("已采 " + calSamples.size + " 个样本 → 基准 " + p95 + " dBm")
                    }
                    Spacer(Modifier.height(6.dp))
                    Text(
                        "说明：不标定也能用，默认按 " + AutoOpenKit.BASE + " dBm 触发。标定只是按这把锁实测的 P95 定线。",
                    // 2026-10-31（第 49 轮 · 动态字体）：删掉硬编码 `lineHeight` —— 它是**固定 sp**，
                    // 用户把系统字号调大后 `fontSize` 跟着变大而 `lineHeight` 不变 ⇒ 行距比例失调、文字互相挤。
                    // Compose 默认行高（约 1.2~1.5 倍字号）会随 fontScale 自动算，比固定值稳。
                        fontSize = 12.sp,
                    )
                }
            },
            confirmButton = {
                if (p95 != null) {
                    TextButton(onClick = {
                        lock?.let { l ->
                            val upd = l.copy(rssiP95 = p95)
                            lock = upd
                            LockStore.save(ctx, upd)
                            say("距离基准已保存：" + p95 + " dBm")
                        }
                        showCalibrate = false
                        calSamples.clear()
                    }) { Text("保存", color = colors.accent) }
                } else {
                    TextButton(onClick = { calSamples.clear() }) { Text("重新采样", color = colors.accent) }
                }
            },
            dismissButton = {
                TextButton(onClick = { showCalibrate = false; calSamples.clear() }) { Text("取消", color = colors.inkSub) }
            },
        )
    }

    // ---------- 上层: AirTag 精确查找层 (连上锁信号自动弹出, 可手动收起) ----------
    // 底层 = 手动解锁圆盘 (一直在, 齿轮/二级菜单都在那); 上层 = 全屏绿, 空心箭头随信号灌绿,
    // 满绿即达武装线自动开锁。点 ✕ 收起 (airTagDismissed), 本次靠近事件内不再弹, 回到底层手动操作。
    AnimatedVisibility(
        visible = airTagShowing,
        enter = fadeIn(tween(180)) + slideInVertically(tween(260)) { it },
        exit = fadeOut(tween(150)) + slideOutVertically(tween(220)) { it },
    ) {
        val l = lock
        if (l != null) {
            AirTagLayer(
                name = l.name,
                rssi = rssi,
                armed = armed,
                busy = busy,
                azimuthDeg = azimuth,
                peakDeg = peakAz,
                pitch = pitch,
                roll = roll,
                soundOn = findSound,
                foreground = foreground,
                onToggleSound = { findSound = !findSound },
                onClose = { airTagDismissed = true },
            )
        }
    }
}

@Composable
private fun Header(lock: LockInfo?) {
    val colors = LocalKfColors.current
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Text(
            text = lock?.name ?: "离线锁钥匙",
            color = colors.ink,
            fontSize = if (lock == null) 22.sp else 26.sp,
            fontWeight = FontWeight.Light,
            letterSpacing = 1.sp
        )
        if (lock != null) {
            Spacer(Modifier.height(6.dp))
            Text(
                text = lock.macText,
                // 2026-10-31（第 42 轮 · 对比度）：原来是 `inkSub.copy(alpha = 0.75f)` ——
                // 叠在底色上有效对比度只有 **3.63~4.13:1**（六种底全部低于 4.5:1，见 kotlincontrast 的 alpha 检查）。
                // 而 MAC 地址是**用户要核对的内容**（与门锁背面对号），不是装饰文字，必须达 4.5:1。
                color = colors.inkSub,
                fontSize = 12.sp,
                fontFamily = FontFamily.Monospace,
                letterSpacing = 1.5.sp
            )
        }
    }
}

/** 开锁圆盘: 自绘 (不用现成图标), 环 + 钥匙孔, 按下时整盘轻微收缩。 */
@Composable
private fun UnlockDial(busy: Boolean, onClick: () -> Unit) {
    val colors = LocalKfColors.current
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    // 2026-10-18: 按压用 CubicBezierEasing 而不是线性 tween ——
    // 线性在"按下→松手"两端都显得硬; 用与 iOS DS.Motion.quick 同族的曲线。
    val scale by animateFloatAsState(
        targetValue = if (pressed) 0.972f else 1f,
        animationSpec = tween(100, easing = CubicBezierEasing(0.42f, 0f, 0.58f, 1f)),
        label = "dial"
    )

    Box(contentAlignment = Alignment.Center) {
        // 外圈柔光
        Canvas(Modifier.size(300.dp)) {
            drawCircle(
                brush = Brush.radialGradient(
                    listOf(colors.accent.copy(alpha = 0.16f), Color.Transparent),
                    center = center, radius = size.minDimension / 2
                ),
                radius = size.minDimension / 2
            )
        }
        // 锁体: 凹槽 / 金属倒角(sweepGradient) / 深色玻璃 / 镜面高光 (对应 iOS LockPlate)
        Box(
            Modifier
                .size(232.dp)
                .scale(scale)
                .clip(CircleShape)
                .clickable(interactionSource = interaction, indication = null, enabled = !busy) { onClick() },
            contentAlignment = Alignment.Center
        ) {
            Canvas(Modifier.fillMaxSize()) {
                val dim = size
                val cx = size.width / 2
                val cy = size.height / 2
                val rOuter = dim.minDimension / 2 - 1.dp.toPx()

                // 第 1 层: 金属倒角 —— sweepGradient 让亮面随角度变化 (对应 iOS AngularGradient)
                drawCircle(
                    brush = Brush.sweepGradient(
                        0f to Color(0xFFFEFDFB),
                        0.11f to Color(0xFFC3BCB1),
                        0.26f to Color(0xFFFBF9F5),
                        0.44f to Color(0xFFB6AFA4),
                        0.58f to Color(0xFFEFEBE3),
                        0.74f to Color(0xFFC8C1B6),
                        0.88f to Color(0xFFFCFDFA),
                        1f to Color(0xFFC3BCB1),
                        center = Offset(cx, cy)
                    ),
                    radius = rOuter
                )

                // 第 2 层: 深色玻璃面 (光源在 26% / 4%)
                val inset = 9.dp.toPx()
                drawCircle(
                    brush = Brush.radialGradient(
                        listOf(Color(0xFF3A4044), Color(0xFF202528), Color(0xFF0F1214), Color(0xFF080A0B)),
                        center = Offset(cx - rOuter * 0.24f, cy - rOuter * 0.46f),
                        radius = rOuter * 1.2f
                    ),
                    radius = rOuter - inset
                )

                // 第 3 层: 斜向镜面高光
                drawArc(
                    brush = Brush.linearGradient(
                        listOf(Color.Transparent, Color.White.copy(alpha = 0.52f), Color.Transparent),
                        start = Offset(cx - rOuter, cy - rOuter),
                        end = Offset(cx + rOuter, cy + rOuter)
                    ),
                    startAngle = 200f,
                    sweepAngle = 90f,
                    useCenter = false,
                    style = Stroke(width = (rOuter - inset) * 0.55f, cap = StrokeCap.Round)
                )

                // 字形: 锁 (与既有语义一致, 不改交互)
                val g = rOuter * 0.30f
                drawCircle(color = colors.accent, radius = g * 0.42f, center = Offset(cx, cy - g * 0.32f))
                val top = cy + g * 0.06f
                drawPath(
                    path = androidx.compose.ui.graphics.Path().apply {
                        moveTo(cx - g * 0.22f, top)
                        lineTo(cx + g * 0.22f, top)
                        lineTo(cx + g * 0.38f, top + g * 1.0f)
                        lineTo(cx - g * 0.38f, top + g * 1.0f)
                        close()
                    },
                    color = colors.accent
                )

                if (busy) {
                    drawArc(
                        color = colors.accent.copy(alpha = 0.9f),
                        startAngle = -90f,
                        sweepAngle = 300f,
                        useCenter = false,
                        topLeft = Offset(1.dp.toPx(), 1.dp.toPx()),
                        size = Size(dim.width - 2.dp.toPx(), dim.height - 2.dp.toPx()),
                        style = Stroke(width = 2.dp.toPx(), cap = StrokeCap.Round)
                    )
                }
            }
        }
    }
}

@Composable
private fun EmptyState(onScan: () -> Unit) {
    val colors = LocalKfColors.current
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        // 二维码框: 四个角的自绘框, 比一个 stock 图标更像"待扫描"
        Canvas(Modifier.size(120.dp)) {
            val w = 3.dp.toPx()
            val len = 26.dp.toPx()
            val c = colors.accent.copy(alpha = 0.85f)
            fun corner(x: Float, y: Float, dx: Float, dy: Float) {
                drawLine(c, Offset(x, y), Offset(x + dx * len, y), strokeWidth = w, cap = StrokeCap.Round)
                drawLine(c, Offset(x, y), Offset(x, y + dy * len), strokeWidth = w, cap = StrokeCap.Round)
            }
            corner(0f, 0f, 1f, 1f)
            corner(size.width, 0f, -1f, 1f)
            corner(0f, size.height, 1f, -1f)
            corner(size.width, size.height, -1f, -1f)
        }
        Spacer(Modifier.height(28.dp))
        Text("还没有绑定门锁", color = colors.ink, fontSize = 20.sp, fontWeight = FontWeight.Light)
        Spacer(Modifier.height(10.dp))
        Text(
            // 2026-10-31（第 42 轮，**文案承诺与实际不符**）：原文案写「设置 → 门锁 → 分享给安卓」，
            // 而 iOS 侧那个入口 2026-10-29 已从「门锁」段**移到「工具」段**
            // （见 SettingsSections.swift:176-180 的注释与实现）。照旧文案走，用户点进「门锁」找不到。
            // 另外 iOS 设置页里没有叫「门锁」的段 —— 那是「管理这把锁」的入口名。
            "在 iOS 端「设置 → 工具 → 分享给安卓 (扫码开锁)」生成二维码，\n扫一次即可。之后开锁不再需要它。",
                    // 2026-10-31（第 49 轮 · 动态字体）：删掉硬编码 `lineHeight` —— 它是**固定 sp**，
                    // 用户把系统字号调大后 `fontSize` 跟着变大而 `lineHeight` 不变 ⇒ 行距比例失调、文字互相挤。
                    // Compose 默认行高（约 1.2~1.5 倍字号）会随 fontScale 自动算，比固定值稳。
            color = colors.inkSub, fontSize = 13.sp, textAlign = TextAlign.Center
        )
        Spacer(Modifier.height(28.dp))
        PillButton("扫码添加门锁", onScan)
    }
}

@Composable
private fun ProximityCard(
    on: Boolean,
    onToggle: (Boolean) -> Unit,
    onRescan: () -> Unit,
    onUnbind: () -> Unit,
    onClose: () -> Unit,
    // 2026-10-27 审核补齐 (C-A1)：iOS 有 F4 布防否决门，Android 原先没有入口。
    // 极简版不下发 cmd25（那需要 skey 会话），只做本机侧否决。
    defendOn: Boolean,
    onDefendToggle: (Boolean) -> Unit,
    // 2026-10-31（第 37 轮）：**F3 距离标定的 UI 入口**。iOS 第 29 轮补齐了同样的闭环；
    // Android 之前只有数据层（`LockInfo.rssiP95` + `AutoOpenKit.rssiBase`），没有地方写它 ——
    // 等于标定功能对用户不存在，永远走 -40 兜底线。不同型号门锁发射功率差异大，
    // 固定线在强锁上"走廊里就开"（误开），在弱锁上"站到门口还不够"（不开）。
    rssiP95: Int,
    onCalibrate: () -> Unit,
    onClearCalibration: () -> Unit,
) {
    // 2026-10-20: 这张卡此前整块读 Theme.kt 的固定暗色值 —— 浅色模式下是浅底 + 暗卡 + 浅字。
    val colors = LocalKfColors.current
    Column(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(KfTokens.Radius.card))
            .background(colors.surface)
            .padding(horizontal = KfTokens.Space.l, vertical = KfTokens.Space.l)
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text("靠近自动开锁", color = colors.ink, fontSize = 15.sp)
                Spacer(Modifier.height(3.dp))
                // 文案里的数值一律从 AutoOpenKit 取: 写死数字的注释/文案, 在阈值改动那天就变成假话
                // (这一句原来写的是 -38/-41, 阈值早就挪到 -40/-43 了, 界面却还在按旧数字承诺)。
                Text(
                    "开着它: 手机解了锁、App 在前台时, 靠近到 " + AutoOpenKit.BASE + " dBm 以内会自动开一次。",
                    // 2026-10-31（第 49 轮 · 动态字体）：删掉硬编码 `lineHeight` —— 它是**固定 sp**，
                    // 用户把系统字号调大后 `fontSize` 跟着变大而 `lineHeight` 不变 ⇒ 行距比例失调、文字互相挤。
                    // Compose 默认行高（约 1.2~1.5 倍字号）会随 fontScale 自动算，比固定值稳。
                    color = colors.inkSub, fontSize = 12.sp,
                )
                Spacer(Modifier.height(4.dp))
                Text(
                    "一次靠近只开一次: 要走开让信号掉到 " + AutoOpenKit.disarmThreshold() +
                        " dBm 以下, 隔 6 秒后再靠近才会再开。",
            // 2026-10-31（第 42 轮 · 对比度）：自动开锁规则说明（多近触发 / 多久能再触发） —— 去掉 alpha（原来叠在底上低于 4.5:1）
                    // 2026-10-31（第 49 轮 · 动态字体）：删掉硬编码 `lineHeight` —— 它是**固定 sp**，
                    // 用户把系统字号调大后 `fontSize` 跟着变大而 `lineHeight` 不变 ⇒ 行距比例失调、文字互相挤。
                    // Compose 默认行高（约 1.2~1.5 倍字号）会随 fontScale 自动算，比固定值稳。
                    color = colors.inkSub, fontSize = 12.sp,
                )
            }
            Switch(
                checked = on,
                onCheckedChange = onToggle,
                colors = SwitchDefaults.colors(
                    checkedThumbColor = colors.bgTop,
                    checkedTrackColor = colors.accent,
                    uncheckedThumbColor = colors.inkSub,
                    // 关闭态不能再用 bgBottom: 浅色档里底色与白卡几乎同色, 开关会"消失"。
                    uncheckedTrackColor = colors.inkSub.copy(alpha = 0.30f),
                    uncheckedBorderColor = colors.inkSub.copy(alpha = 0.45f)
                )
            )
        }
        // 2026-10-27 审核补齐：布防时段否决（22:00–07:00 默认，与 iOS 一致）。
        Spacer(Modifier.height(10.dp))
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text("布防时段内禁止自动开锁", color = colors.ink, fontSize = 15.sp)
                Spacer(Modifier.height(3.dp))
                Text(
                    "开启后，在 22:00–次日 07:00 之间不会自动开锁（本机侧拦截）。",
                    // 2026-10-31（第 49 轮 · 动态字体）：删掉硬编码 `lineHeight` —— 它是**固定 sp**，
                    // 用户把系统字号调大后 `fontSize` 跟着变大而 `lineHeight` 不变 ⇒ 行距比例失调、文字互相挤。
                    // Compose 默认行高（约 1.2~1.5 倍字号）会随 fontScale 自动算，比固定值稳。
                    color = colors.inkSub, fontSize = 12.sp,
                )
            }
            Switch(
                checked = defendOn,
                onCheckedChange = onDefendToggle,
                colors = SwitchDefaults.colors(
                    checkedThumbColor = colors.bgTop,
                    checkedTrackColor = colors.accent,
                    uncheckedThumbColor = colors.inkSub,
                    uncheckedTrackColor = colors.inkSub.copy(alpha = 0.30f),
                    uncheckedBorderColor = colors.inkSub.copy(alpha = 0.45f)
                )
            )
        }
        // 2026-10-31（第 37 轮）：F3 距离标定。已标定显示基准值 + 重标/清除；
        // 未标定显示"可选精修"入口，并说明默认兜底线（数值从 AutoOpenKit 取，不写死）。
        Spacer(Modifier.height(10.dp))
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text(
                    if (rssiP95 != 0) "距离基准：" + rssiP95 + " dBm（已标定）" else "距离基准（可选）",
                    color = colors.ink, fontSize = 15.sp,
                )
                Spacer(Modifier.height(3.dp))
                Text(
                    if (rssiP95 != 0) "按这把锁实测的 P95 定线，比默认值更贴你家的门。"
                    else "不标定也能用：默认按 " + AutoOpenKit.BASE + " dBm 触发。若发现「走廊里就开」或「站到门口不开」，标定一次更准。",
                    // 2026-10-31（第 49 轮 · 动态字体）：删掉硬编码 `lineHeight` —— 它是**固定 sp**，
                    // 用户把系统字号调大后 `fontSize` 跟着变大而 `lineHeight` 不变 ⇒ 行距比例失调、文字互相挤。
                    // Compose 默认行高（约 1.2~1.5 倍字号）会随 fontScale 自动算，比固定值稳。
                    color = colors.inkSub, fontSize = 12.sp,
                )
            }
            if (rssiP95 != 0) {
                Text(
                    "清除",
                    color = colors.inkSub, fontSize = 13.sp,
                    modifier = Modifier.clickable { onClearCalibration() }.padding(vertical = 10.dp, horizontal = 8.dp),
                )
            }
            Text(
                if (rssiP95 != 0) "重标" else "标定",
                color = colors.accent.copy(alpha = 0.9f), fontSize = 13.sp,
                // 文字按钮也要够按: padding 把触达撑到 44dp 以上（与上面「完成」同口径）
                modifier = Modifier.clickable { onCalibrate() }.padding(vertical = 10.dp, horizontal = 12.dp),
            )
        }
        Row(verticalAlignment = Alignment.CenterVertically) {
            // 2026-10-31（第 42 轮 · 对比度）：「门锁设置」分组标题 —— 去掉 alpha（原来叠在底上低于 4.5:1）
            Text("门锁设置", color = colors.inkSub, fontSize = 12.sp, modifier = Modifier.weight(1f))
            Text(
                "完成",
                color = colors.accent.copy(alpha = 0.9f),
                fontSize = 13.sp,
                // 文字按钮也要够按: 用 padding 把触达撑到 44dp 以上 (可点区最小尺寸是硬规)
                modifier = Modifier.clickable { onClose() }.padding(vertical = 10.dp, horizontal = 12.dp),
            )
        }
        Spacer(Modifier.height(12.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(20.dp)) {
            Text(
                "重新扫码绑定",
                color = colors.accent.copy(alpha = 0.9f),
                fontSize = 13.sp,
                modifier = Modifier
                    .clickable { onRescan() }
                    // 2026-10-31（第 39 轮 · 触达）：13sp 文字 + 6dp×2 ≈ 29dp，**低于 44dp 最小可点区**。
                    // 改成 14dp×2 ⇒ 17+28 = 45dp，且视觉上仍是一行文字按钮（与「完成」的 10dp 同口径）。
                    .padding(vertical = 14.dp)
            )
            Text(
                "解绑",
                color = colors.inkSub,
                fontSize = 13.sp,
                modifier = Modifier
                    .clickable { onUnbind() }
                    // 2026-10-31（第 39 轮 · 触达）：13sp 文字 + 6dp×2 ≈ 29dp，**低于 44dp 最小可点区**。
                    // 改成 14dp×2 ⇒ 17+28 = 45dp，且视觉上仍是一行文字按钮（与「完成」的 10dp 同口径）。
                    .padding(vertical = 14.dp)
            )
        }
    }
}

/** 首页右下齿轮: 二级菜单的唯一入口 (首页只留解锁相关, 开关与账号操作都收进来)。 */
@Composable
private fun GearButton(modifier: Modifier = Modifier, onClick: () -> Unit) {
    val colors = LocalKfColors.current
    Box(
        modifier
            .size(56.dp)
            .clip(CircleShape)
            .background(colors.surface.copy(alpha = 0.92f))
            .clickable { onClick() },
        contentAlignment = Alignment.Center,
    ) {
        // 自绘齿轮 (8 齿 + 内圈 + 轴心): 与首页圆盘、空态二维码框同一路子, 不借现成图标。
        Canvas(Modifier.size(30.dp)) {
            val c = Offset(size.width / 2f, size.height / 2f)
            val rOut = size.minDimension / 2f
            for (k in 0 until 8) {
                // toRadians 返回 Double, 而 Offset 的公开构造只吃 Float。少了 toFloat() 编译器会去挑那个
                // internal 的 Offset(packedValue: Long) 并报「无法访问」—— 括号平衡看不出这种类型错。
                val a = Math.toRadians((k * 45).toDouble()).toFloat()
                drawLine(
                    colors.inkSub,
                    Offset(c.x + cos(a) * (rOut - 5f), c.y + sin(a) * (rOut - 5f)),
                    Offset(c.x + cos(a) * rOut, c.y + sin(a) * rOut),
                    strokeWidth = 3.5f, cap = StrokeCap.Round,
                )
            }
            drawCircle(colors.inkSub, radius = rOut - 7.5f, center = c, style = Stroke(width = 2.5f))
            drawCircle(colors.bgTop, radius = 4f, center = c)
        }
    }
}

@Composable
private fun PillButton(text: String, onClick: () -> Unit) {
    val colors = LocalKfColors.current
    Box(
        Modifier
            .clip(RoundedCornerShape(50))
            .background(colors.accent)
            .clickable { onClick() }
            .padding(horizontal = 28.dp, vertical = 14.dp)
    ) {
        Text(text, color = colors.onAccent, fontSize = 15.sp, fontWeight = FontWeight.Medium)
    }
}

// ---------- AirTag 精确查找层 ----------
@Composable
private fun AirTagLayer(
    name: String,
    rssi: Int?,
    armed: Boolean,
    busy: Boolean,
    azimuthDeg: Float,
    peakDeg: Float?,
    pitch: Float,
    roll: Float,
    soundOn: Boolean,
    foreground: Boolean,
    onToggleSound: () -> Unit,
    onClose: () -> Unit,
) {
    val fill = signalFill(rssi)
    val bearing = relativeBearing(azimuthDeg, peakDeg).coerceIn(-30f, 30f)
    val dist = distanceMeters(rssi)
    val distText = when {
        dist < 0f -> "测距中…"
        dist < 1f -> (dist * 100).toInt().toString() + " 厘米"
        else -> ((dist * 10).toInt() / 10f).toString() + " 米"
    }
    Box(
        Modifier
            .fillMaxSize()
            // 原色 #1CC964 / #12B24A 配白字只有 2.19:1 / 2.80:1, 低于 WCAG AA 的 4.5:1。
            // 压暗到下面两档后: #0B6B3A 对白字 = 6.6:1, #0E7A42 = 5.4:1, 两档都达标。
            // 为什么不改成深色文字: 这是全屏查找层, 白字在强光下可读性更好; 压暗底色保色相不变 (仍是"绿=可开")。
            .background(if (armed) Color(0xFF0E7A42) else Color(0xFF0B6B3A))
    ) {
        // 顶部: 正在查找 + 锁名 (对齐 AirTag 精确查找的标题区)
        Column(Modifier.padding(start = 28.dp, top = 56.dp)) {
            // 2026-10-31（第 45 轮 · 对比度）：白对 #0B6B3A = 6.6:1，alpha 0.85 稀释后约 5.3:1（达标但余量小）。
            // 提到 0.95 ⇒ 约 6.1:1，与标题的视觉层级差靠字号而非透明度表达。
            Text("正在查找", color = Color.White.copy(alpha = 0.95f), fontSize = 15.sp, fontWeight = FontWeight.Medium)
            Spacer(Modifier.height(2.dp))
            Text(name, color = Color.White, fontSize = 30.sp, fontWeight = FontWeight.Bold)
        }
        // 中央: 空心箭头 (随信号从下往上灌绿, 满绿=可开)
        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            SignalArrow(
                azimuthDeg = azimuthDeg,
                peakDeg = peakDeg,
                rssi = rssi,
                armed = armed,
                busy = busy,
                pitchDeg = pitch,
                rollDeg = roll,
                sizeDp = 300,
            )
        }
        // 底部左: 粗估距离 + 方向 (诚实: 是估计值, 不是 UWB 测距)
        Column(Modifier.align(Alignment.BottomStart).padding(start = 28.dp, bottom = 116.dp)) {
            Text(distText, color = Color.White, fontSize = 34.sp, fontWeight = FontWeight.Bold)
            Text(directionLabel(bearing), color = Color.White.copy(alpha = 0.95f), fontSize = 26.sp, fontWeight = FontWeight.SemiBold)
        }
        // 左下: 收起 (回到手动底层)
        Box(Modifier.align(Alignment.BottomStart).padding(28.dp)) {
                CircleIconButton(label = "✕", contentDescription = "关闭", onClick = onClose)
        }
        // 右下: 提示音开关
        Box(Modifier.align(Alignment.BottomEnd).padding(28.dp)) {
                CircleIconButton(
                    label = if (soundOn) "🔊" else "🔇",
                    contentDescription = if (soundOn) "关闭提示音" else "打开提示音",
                    // 2026-10-31（第 45 轮，**编译错误**）：参数名是 `onToggleSound`（见函数签名），
                    // 内部却写成 `onToggle` —— unresolved reference，APK 编译必拒。
                    onClick = onToggleSound,
                )
        }
    }
    ProximityBeep(active = true, fill = fill, soundOn = soundOn, foreground = foreground)
}

// 2026-10-31（第 39 轮 · 无障碍）：原来只有 `label`（"✕"/"🔊"/"🔇"）—— 屏幕阅读器会把
// 这些符号**念成字符名或干脆不念**，视障用户不知道这个按钮做什么。
// 加 `contentDescription`（人话），label 仍用于视觉显示。
@Composable
private fun CircleIconButton(label: String, contentDescription: String, onClick: () -> Unit) {
    Box(
        Modifier
            .size(52.dp)
            .clip(CircleShape)
            .background(Color.White.copy(alpha = 0.22f))
            .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) { onClick() },
        contentAlignment = Alignment.Center
    ) {
        Text(
            label, color = Color.White, fontSize = 20.sp,
            // 符号本身对读屏无意义: 用语义把它替换成人话（`clearAndSetSemantics` 会连符号一起抹掉，
            // 这里用 `semantics` 保留视觉文本、只补描述）。
            modifier = Modifier.semantics { this.contentDescription = contentDescription },
        )
    }
}

/** 靠近提示音: 信号越强间隔越短 (AirTag 那种"滴滴滴"加速)。按 fill 分档, 档位不变就不重启协程。 */
@Composable
private fun ProximityBeep(active: Boolean, fill: Float, soundOn: Boolean, foreground: Boolean) {
    val level = when {
        fill > 0.85f -> 3
        fill > 0.6f -> 2
        fill > 0.3f -> 1
        fill > 0.05f -> 0
        else -> -1
    }
    LaunchedEffect(active, soundOn, level, foreground) {
        if (!active || !soundOn || level < 0 || !foreground) return@LaunchedEffect
        val tg = runCatching { ToneGenerator(AudioManager.STREAM_NOTIFICATION, 90) }.getOrNull() ?: return@LaunchedEffect
        val period = when (level) { 3 -> 240L; 2 -> 420L; 1 -> 700L; else -> 1100L }
        try {
            while (true) {
                runCatching { tg.startTone(ToneGenerator.TONE_PROP_BEEP, 110) }
                delay(period)
            }
        } finally {
            runCatching { tg.release() }
        }
    }
}
