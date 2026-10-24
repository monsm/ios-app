package com.aapk.kfkey

import android.Manifest
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
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
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
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
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
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.TextStyle
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
    // 开锁回执（对齐 android-proto 04-success）：成功那一刻记下"谁 · 怎么开的"，
    // 供主屏的回执卡展示。null = 本次会话还没成功过。
    var receiptAuto by remember { mutableStateOf(false) }
    var busy by remember { mutableStateOf(false) }
    // 初值从本机读 (跨重启保留); 切换时立刻落盘 —— 见 LockStore.loadProximity 的注释
    var proximity by remember { mutableStateOf(LockStore.loadProximity(ctx)) }
    var rssi by remember { mutableStateOf<Int?>(null) }
    var pending by remember { mutableStateOf<LockInfo?>(null) }   // 待二次确认的绑定
    var lastAuto by remember { mutableStateOf(0L) }                 // 上次自动下发时刻 (冷却基准)
    var armed by remember { mutableStateOf(false) }                // 回差滤波后的"已武装"位
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
    // 解绑确认框。放在二级菜单状态**旁边**而不是独立作用域:
    // 两者生命周期一致 (菜单关掉就该一起清), 分开放会出现"框还在、底下的卡没了"。
    var showConfirmUnbind by remember { mutableStateOf(false) }
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
        if (busy) return
        busy = true
        say(if (auto) "已靠近, 正在开锁…" else "正在开锁…")
        scope.launch {
            val r = unlocker.unlock(l)
            busy = false
            // 来源标注 (用户 2026-10-17): 开完要能说清是自动开的还是自己点的 ——
            // "谁把我门开了"必须能回答。只在成功时冠来源: 失败那句是诊断文案,
            // 再加前缀会把它挤得读不完。
            say(if (r.ok) (if (auto) "自动开锁成功 — " else "手动开锁成功 — ") + r.message else r.message, !r.ok)
            if (r.ok) receiptAuto = auto
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
    val prewarmLineDbm = AutoOpenKit.BASE - 24

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
        armed = AutoOpenKit.rssiSample(prevArmed = armed, rssi = r)
        // 信号掉回解除线以下 = 这一次接近事件结束 → 放开闩锁与预热位, 下次靠近重来一遍
        if (!armed) { fired = false; prewarmStarted = false }
        if (!armed || fired) return
        if (!AutoOpenKit.coolReady(lastAuto, now)) return
        if (busy) return
        fired = true
        lastAuto = now
        doUnlock(auto = true)
    }

    // busy 也进 key: 安卓蓝牙栈**一边扫描一边连接**极易失败 (GATT 133 的头号成因),
    // 而开锁这一趟自己就要扫描+连接, 所以开锁在途时把 RSSI 监测整条撤掉, 完了再挂回去。
    // 不只是抢射频: 同 App 里第二次 startScan 会重启扫描, 前一个 callback 静默失声,
    // 且 scanForLock 收尾那句 stopScan 会把监测的扫描一起停掉 —— 于是自动开锁跑过一次之后
    // "当前信号"再也不更新, 用户只能关掉开关再打开。
    LaunchedEffect(proximity, lock?.mac, busy, warming, foreground) {
        val l = lock ?: return@LaunchedEffect
        if (!proximity) { rssi = null; armed = false; fired = false; prewarmStarted = false; peakRssi = null; peakAz = null; airTagDismissed = false }
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


    // 2026-10-22 重做 (Glass Instrument / Black Canvas) —— 本节只改视觉, 协议与状态机一行没动。
    // 色板已换成 KfTheme.kt 的 canvas/surface/text/… 命名; 旧的 bgTop/bgBottom/ink/inkSub 已删。
    val colors = LocalKfColors.current

    // 画布: 纯黑实底。范式第一条总则「黑色是画布, 不是背景色」/ 验收 A5「页面底采样 = #000000」。
    // 旧实现是 #0A0C10 -> #141A22 的纵向渐变 —— 那是把画布当成了背景色, 已删。
    Box(
        Modifier
            .fillMaxSize()
            .background(colors.canvas)
    ) {
        Column(
            Modifier
                .fillMaxSize()
                .padding(horizontal = KfTokens.Space.gutter)
                .padding(top = KfTokens.Space.pageTop),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Header(lock)
            // 六图改造 (2026-10-23): 加**图 1 的顶部双 chip**。
            //
            // 图 1 Health Age 的顶栏是两枚玻璃胶囊：左「Overview / 1 Excellent」、
            // 右「Health Age / -4.7 years」。它们承担的是「这一屏的两个关键状态」，
            // 而不是装饰。本端对应的是「已武装」与「当前信号」—— 之前这两个信息
            // 一个藏在设置卡里、一个只有靠近时才在仪表行露面，进页面看不到。
            lock?.let {
                Spacer(Modifier.height(KfTokens.Space.m))
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(KfTokens.Space.s)
                ) {
                    KfChip(
                        label = "自动开锁",
                        value = if (proximity) "已武装" else "已关闭",
                        tone = if (proximity) colors.ok else colors.textTertiary,
                        modifier = Modifier.weight(1f)
                    )
                    KfChip(
                        label = "当前信号",
                        value = if (rssi != null) "$rssi dBm" else "未测到",
                        tone = if ((rssi ?: -99) >= -40) colors.ok else colors.textSub,
                        modifier = Modifier.weight(1f)
                    )
                }
            }
            Spacer(Modifier.weight(1f))
            if (lock == null) {
                EmptyState(onScan = { launchScan() })
            } else {
                // ── 主角: 开锁仪表盘 ──
                // 范式 9 / 14-13: 一屏只能有 1 个 >=200pt 的主视觉。旧版这里同时摆了 232dp 圆盘
                // 和 208dp 的大箭头 = 两个主角。现在箭头降级成仪表行旁的 72dp 指示器 (见下),
                // 主视觉只剩圆盘一个。
                UnlockDial(
                    busy = busy,
                    // 图 1 语言的成功态：环整圈转绿（与 iOS HomeConsole 的 phase == .unlocked 同义）
                    success = !statusBad && (status.contains("成功") || status.startsWith("已开锁")),
                    rssi = rssi,
                    onClick = { doUnlock(auto = false) }
                )

                Spacer(Modifier.height(KfTokens.Space.l))

                // 结果态: 范式 7.20.3 —— 15 Semibold, 说发生了什么; 失败色走语义 danger。
                Text(
                    text = status.ifBlank { if (busy) "开锁中…" else "待开锁" },
                    color = when {
                        statusBad -> colors.danger
                        // 成功语现在是 "手动/自动开锁成功 — …"; 旧句只认 "已开锁" 会把成功念成灰色
                        status.contains("成功") || status.startsWith("已开锁") -> colors.ok
                        else -> colors.text
                    },
                    fontSize = Type.subhead,
                    fontWeight = FontWeight.SemiBold,
                    textAlign = TextAlign.Center
                )

                Spacer(Modifier.height(KfTokens.Space.m))

                // ── 仪表行: 信号状态 (范式 7.7 MetricRow) ──
                // 注意 7.7 的硬规定: **视觉行高 20pt** 与 **触达 48pt** 是两个数, 不许合并。
                // 这一行不可点, 所以只约束视觉行高 (KfTokens.Hit.metricRow = 20dp);
                // 若将来给它加了点击, 必须另包 48dp 触达 (KfTokens.Hit.min)。
                Row(
                    Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    SignalMetric(armed = armed, rssi = rssi, proximity = proximity, modifier = Modifier.weight(1f))
                    // 方向指示器 (原 208dp 大箭头): 只在开了「靠近自动开锁」时出现。
                    // 旋转 = 手机姿态角 (真); 填充 = 当前信号 (真)。这把锁没有 UWB, 算不出绝对方位,
                    // 所以箭头指 "转动手机时信号最强的那个朝向", 不谎称指针自动指向门。
                    AnimatedVisibility(visible = proximity && !airTagShowing) {
                        SignalArrow(
                            azimuthDeg = azimuth,
                            peakDeg = peakAz,
                            rssi = rssi,
                            armed = armed,
                            busy = busy,
                            pitchDeg = pitch,
                            rollDeg = roll,
                            sizeDp = 72,
                            okColor = colors.ok,
                            outlineColor = colors.text,
                        )
                    }
                }

                // 审美对齐 android-proto 01-home 卡1「自动开锁」：
                // HTML 这张卡给了**规则原文 + footer 整句**，App 之前只有顶部一枚 chip。
                // chip 说"现在什么状态"，卡说"什么条件下会发生"——两者不是一件事。
                // 审美对齐 android-proto 04-success 卡「开锁回执」：
                // HTML 的成功态不只有"已开锁"三个字，还有一张回执卡说清
                // **谁 · 怎么开的 · 走的是哪条命令**。App 之前只有一行状态文字。
                if (!statusBad && (status.contains("成功") || status.startsWith("已开锁"))) {
                    Spacer(Modifier.height(KfTokens.Space.m))
                    ReceiptCard(
                        lockName = lock?.name ?: "这把锁",
                        auto = receiptAuto
                    )
                }

                Spacer(Modifier.height(KfTokens.Space.l))
                AutoUnlockCard(
                    proximity = proximity,
                    armed = armed,
                    onClick = { showSettings = true }
                )

                if (detail.isNotEmpty()) {
                    Spacer(Modifier.height(KfTokens.Space.xs))
                    // 排障留痕: 11sp 是范式 14-11 的字号下限; 用 textTertiary (深色档 4.51:1 on 次表面)
                    // 而不是再叠一层 alpha —— 旧版 inkSub@0.55 实测只有 2.73:1, 低于 AA。
                    Text(
                        text = detail,
                        color = colors.textTertiary,
                        fontSize = Type.caption,
                        fontFamily = FontFamily.Monospace,
                        textAlign = TextAlign.Center,
                        lineHeight = 15.sp,
                    )
                }
            }
            Spacer(Modifier.weight(1f))
        }

        // 右下齿轮: 二级菜单唯一入口。首页不留开关与账号操作。
        if (lock != null) {
            GearButton(Modifier.align(Alignment.BottomEnd).padding(KfTokens.Space.xl)) { showSettings = true }
        }
    }

    // ---------- 二级弹层: 门锁设置 (范式 7.0.6 plain 卡的排法, 应用体配色) ----------
    // 旧实现是「全屏暗遮罩 + 贴底卡」, 读起来像 BottomSheet 但没有 sheet 的任何语义。
    // 现在按 7.0.6 的 plain 卡骨架: 内容高 + 上下各 48, 垂直居中, 不超出屏幕。
    // 圆角用应用体的 rCard=24 而不是展示壳的 r40: 这是应用体里的浮层, 不是展示壳白卡。
    AnimatedVisibility(
        visible = showSettings && lock != null,
        enter = fadeIn(tween(160)) + slideInVertically(tween(220)) { it / 3 },
        exit = fadeOut(tween(140)) + slideOutVertically(tween(200)) { it / 3 },
    ) {
        Box(
            Modifier
                .fillMaxSize()
                .background(colors.canvas.copy(alpha = 0.72f))
                .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) {
                    showSettings = false
                },
            contentAlignment = Alignment.Center,
        ) {
            if (lock != null) {
                // 范式 7.0.6: 内容高 + 上下各 48, 垂直居中, **不超出屏幕**。
                // 内容比屏高时靠 verticalScroll 兜住 —— 而不是让卡片被裁掉一半。
                // 用 Column 而不是 Box: Box 在 verticalScroll 下会把超高的子项上下各溢出一半,
                // 顶部那截就滚不到了; Column 在空间不足时 Center 自然退化成顶对齐, 可滚。
                Column(
                    Modifier
                        .fillMaxSize()
                        .padding(vertical = KfTokens.Hit.min)
                        .verticalScroll(rememberScrollState()),
                    verticalArrangement = Arrangement.Center,
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    SettingsCard(
                        lock = lock,
                        on = proximity,
                        sound = findSound,
                        onSound = { findSound = it },
                        onToggle = {
                            proximity = it
                            LockStore.saveProximity(ctx, it)
                            if (!it) rssi = null
                        },
                        onRescan = {
                            showSettings = false
                            launchScan()
                        },
                        // 解绑是**不可逆的**: LockStore.clear 会删掉本机保存的 ekey,
                        // 删完之后这把锁只能回到键盘上做重置、再重新扫码配对。
                        //
                        // 改之前这里是**按下即执行**, 而这个按钮就在「靠近开锁」开关下面一行 ——
                        // 一次误触 = 一把锁要重新配网。iOS 侧同类动作全部有确认框,
                        // 本仓自己的纪律文件也写着「删除确认必须说清可不可以找回」。
                        // 这里补最轻的一档: 确认框 + 说清后果 (不可撤销 / 锁本体不受影响)。
                        onUnbind = { showConfirmUnbind = true },
                        onClose = { showSettings = false },
                    )
                }
            }
        }
    }

    // 已绑定过 -> 再次扫码要**二次确认**: 覆盖的是一把能开门的钥匙, 不能静默替换
    pending?.let { pendingLock ->
        val same = pendingLock.mac == lock?.mac
        AlertDialog(
            onDismissRequest = { pending = null },
            shape = RoundedCornerShape(KfTokens.Radius.card),
            containerColor = colors.surface,
            titleContentColor = colors.text,
            textContentColor = colors.textSub,
            title = { Text(if (same) "更新这把锁的凭证?" else "换一把锁?", fontWeight = FontWeight.SemiBold) },
            text = {
                Text(
                    // 文案对齐 android-proto 05-rebind：那张「换绑后果」卡给了**两段**后果 ——
                    // 一段说换绑之后旧锁会怎样，一段说解绑会删掉什么。
                    // App 之前只有第一段：用户看不到"如果我选解绑，会失去什么"。
                    if (same) "本机已绑定「${pendingLock.name}」。用新扫到的凭证覆盖它?"
                    else "本机现在绑定的是「${lock?.name ?: ""}」(${lock?.macText ?: ""})。\n\n" +
                        "换成「${pendingLock.name}」(${pendingLock.macText}) 之后, 原来那把锁要从这台手机重新扫码才能再用。\n\n" +
                        "解绑则删除「${lock?.name ?: ""}」的钥匙与全部本机设置, 删掉之后无法从本机找回 —— " +
                        "要再用这把锁, 得先在门锁键盘上重置、再重新扫码配对。门锁里的密码和指纹不受影响。"
                )
            },
            confirmButton = {
                // 覆盖一把能开门的钥匙是破坏性动作, 用 danger 而不是 accent。
                TextButton(onClick = {
                    LockStore.save(ctx, pendingLock)
                    lock = pendingLock
                    pending = null
                    say("已绑定「${pendingLock.name}」")
                }) { Text(if (same) "覆盖" else "换绑", color = colors.danger, fontWeight = FontWeight.SemiBold) }
            },
            dismissButton = {
                TextButton(onClick = { pending = null }) { Text("取消", color = colors.textSub) }
            }
        )
    }

    // 解绑确认 —— 与上面"换绑确认"同一条理由, 只是后果更重:
    // 换绑至少新锁已经扫到了; 解绑之后是一把锁都没有, 必须回到键盘上重置。
    if (showConfirmUnbind) {
        AlertDialog(
            onDismissRequest = { showConfirmUnbind = false },
            shape = RoundedCornerShape(KfTokens.Radius.card),
            containerColor = colors.surface,
            titleContentColor = colors.text,
            textContentColor = colors.textSub,
            title = { Text("解绑这把锁?", fontWeight = FontWeight.SemiBold) },
            text = {
                // 三件事必须在按下之前说清 (与 iOS 侧「删除确认」同一口径):
                //   ① 本机会删什么; ② 能不能找回; ③ 锁本体受不受影响。
                Text(
                    "本机会删除「${lock?.name ?: ""}」的钥匙与全部本机设置。\n" +
                        "删掉之后无法从本机找回 —— 要再用这把锁, 得先在门锁键盘上重置、再重新扫码配对。\n" +
                        "门锁里的密码和指纹不受影响。"
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    showConfirmUnbind = false
                    LockStore.clear(ctx)
                    lock = null
                    proximity = false
                    showSettings = false
                    // 解绑之后这条链路就没有主人了: 不收, 它会一直占着锁的 GATT 接口位,
                    // 而下一把锁要连的时候还得先拆它 (安卓一次只养一条热链路)。
                    scope.launch { unlocker.release() }
                    say("已解绑")
                }) { Text("解绑", color = colors.danger, fontWeight = FontWeight.SemiBold) }
            },
            dismissButton = {
                TextButton(onClick = { showConfirmUnbind = false }) { Text("取消", color = colors.textSub) }
            }
        )
    }

    // ---------- 上层: AirTag 精确查找层 (连上锁信号自动弹出, 可手动收起) ----------
    // 底层 = 手动解锁圆盘 (一直在, 齿轮/二级菜单都在那); 上层 = 深绿, 空心箭头随信号灌绿,
    // 满绿即达武装线自动开锁。点关闭收起 (airTagDismissed), 本次靠近事件内不再弹。
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

/**
 * 图 1 的顶部玻璃胶囊 —— 图标/状态点 + 两行文字（label 12 灰 / value 16 粗）。
 *
 * 与 iOS 的 XStatChip 同一语言：圆角 999、底 rgba(255,255,255,.055)、
 * 内描边 .5dp rgba(255,255,255,.07)。左端一枚语义色状态点，不画图标
 * —— 胶囊里塞图标会让 24dp 高度撑不开两行字。
 */
@Composable
private fun KfChip(
    label: String,
    value: String,
    tone: Color,
    modifier: Modifier = Modifier
) {
    val colors = LocalKfColors.current
    Row(
        modifier = modifier
            // 圆角对齐 HTML .chip CSS（高56/r18 圆角矩形）——按 KfChip 高度 42dp 等比 13dp
            .clip(RoundedCornerShape(13.dp))
            .background(Color.White.copy(alpha = 0.055f))
            .border(0.5.dp, Color.White.copy(alpha = 0.07f), RoundedCornerShape(13.dp))
            .padding(horizontal = KfTokens.Space.m, vertical = 9.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Box(
            Modifier
                .size(7.dp)
                .clip(CircleShape)
                .background(tone)
        )
        Column {
            Text(
                text = label,
                color = colors.textTertiary,
                fontSize = Type.footnote,
                maxLines = 1
            )
            Text(
                text = value,
                color = colors.text,
                fontSize = Type.headline,
                fontWeight = FontWeight.Bold,
                maxLines = 1
            )
        }
    }
}

/**
 * 「开锁回执」卡 —— 对齐 android-proto 04-success。
 *
 * HTML 结构：卡头「开锁回执」→ 主体「谁 · 手动/自动」→ 副「04 接近事件 · 一次靠近只开一次」
 *            → 两列「命令 04 / 触发 手动轻点」→ footer 整句。
 *
 * 为什么值得单独成卡：开锁是这个 App 唯一的高危动作。只给"成功"两个字回答不了
 * 「谁把我门开了」—— 而那正是用户回看这一屏时要问的问题。
 */
@Composable
private fun ReceiptCard(lockName: String, auto: Boolean) {
    val colors = LocalKfColors.current
    Column(
        Modifier
            .fillMaxWidth()
            .padding(horizontal = KfTokens.Space.l)
            .clip(RoundedCornerShape(KfTokens.Radius.card))
            .background(colors.surface)
            .padding(KfTokens.Space.card)
    ) {
        Text("开锁回执", color = colors.textSub, fontSize = Type.subhead)
        Spacer(Modifier.height(KfTokens.Space.m))
        Text(
            lockName + " · " + (if (auto) "自动" else "手动"),
            color = colors.text,
            fontSize = Type.title3,
            fontWeight = FontWeight.SemiBold
        )
        Text(
            "04 接近事件 · 一次靠近只开一次",
            color = colors.textSub,
            fontSize = Type.caption,
            modifier = Modifier.padding(top = 2.dp)
        )
        Spacer(Modifier.height(KfTokens.Space.m))
        Row(Modifier.fillMaxWidth()) {
            Column(Modifier.weight(1f)) {
                Text("命令", color = colors.textSub, fontSize = Type.footnote)
                Text("04", color = colors.text, fontSize = Type.footnote, fontWeight = FontWeight.SemiBold)
            }
            Column(Modifier.weight(1f)) {
                Text("触发", color = colors.textSub, fontSize = Type.footnote)
                Text(if (auto) "靠近自动" else "手动轻点", color = colors.text, fontSize = Type.footnote, fontWeight = FontWeight.SemiBold)
            }
        }
        Spacer(Modifier.height(KfTokens.Space.m))
        Box(
            Modifier
                .fillMaxWidth()
                .height(1.dp)
                .background(colors.hairline)
        )
        Spacer(Modifier.height(KfTokens.Space.m))
        Text(
            "手动与自动开锁成功都会在这里留一条回执 —— 谁把我门开了，一看便知。",
            color = colors.textTertiary,
            fontSize = Type.footnote,
            lineHeight = 18.sp
        )
    }
}

/**
 * 「自动开锁」说明卡 —— 对齐 android-proto 01-home 卡1。
 *
 * HTML 结构：卡头「自动开锁」+ chevron → 盾牌图标 + **已武装/已关闭** + 规则短句
 *            → sep → footer 整句（一次靠近只开一次，要走开再靠近）。
 *
 * 为什么值得单独成卡：chip 只说"现在是什么状态"，用户仍不知道**什么时候会自动开**。
 * 这条规则是"靠近会自动开门"这个功能的安全边界，必须写在主屏上，不能只藏在设置里。
 */
@Composable
private fun AutoUnlockCard(proximity: Boolean, armed: Boolean, onClick: () -> Unit) {
    val colors = LocalKfColors.current
    val on = proximity
    Column(
        Modifier
            .fillMaxWidth()
            .padding(horizontal = KfTokens.Space.l)
            .clip(RoundedCornerShape(KfTokens.Radius.card))
            .background(colors.surface)
            .clickable(onClick = onClick)
            .padding(KfTokens.Space.card)
    ) {
        // 卡头：14 Regular 灰 + chevron（范式 7.6）
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text("自动开锁", color = colors.textSub, fontSize = Type.subhead)
            Spacer(Modifier.width(KfTokens.Space.xs))
            Text("›", color = colors.textTertiary, fontSize = Type.subhead, fontWeight = FontWeight.SemiBold)
        }
        Spacer(Modifier.height(KfTokens.Space.m))
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                text = if (on) "已武装" else "已关闭",
                color = if (on) colors.ok else colors.textTertiary,
                fontSize = 16.sp,
                fontWeight = FontWeight.SemiBold
            )
            Spacer(Modifier.width(KfTokens.Space.s))
            Text(
                text = if (on) (if (armed) "已进入可触发区" else "等待靠近") else "靠近不会自动开门",
                color = colors.textSub,
                fontSize = Type.caption
            )
        }
        Text(
            text = "RSSI ≥ −38 dBm 且距上次 > 8 秒",
            color = colors.textSub,
            fontSize = Type.caption,
            modifier = Modifier.padding(top = 2.dp)
        )
        // sep
        Spacer(Modifier.height(KfTokens.Space.m))
        Box(
            Modifier
                .fillMaxWidth()
                .height(1.dp)
                .background(colors.hairline)
        )
        Spacer(Modifier.height(KfTokens.Space.m))
        Text(
            text = "开着它：手机解了锁、App 在前台时，靠近到 −38 dBm 以内会自动开一次。" +
                "一次靠近只开一次 —— 要走开让信号掉到 −55 dBm 以下，隔 6 秒后再靠近才会再开。",
            color = colors.textSub,
            fontSize = Type.caption,
            lineHeight = Type.caption * 1.6f
        )
    }
}

@Composable
private fun Header(lock: LockInfo?) {
    val colors = LocalKfColors.current
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        // 范式 7.1 LargeTitleHeader: 30 Bold / 字距 -0.4 / 颜色 text。旧值 26sp Light 差两档字重。
        Text(
            text = lock?.name ?: "离线锁钥匙",
            color = colors.text,
            fontSize = Type.largeTitle,
            fontWeight = FontWeight.Bold,
            letterSpacing = (-0.4).sp,
            textAlign = TextAlign.Center,
            maxLines = 2,
        )
        if (lock != null) {
            Spacer(Modifier.height(KfTokens.Space.xs))
            // 范式 4.2 footnote 12 / 颜色走 textTertiary (深色档 on 黑 6.13:1),
            // 旧值 inkSub@0.75 实测只有 3.83:1。
            Text(
                text = lock.macText,
                color = colors.textTertiary,
                fontSize = Type.footnote,
                fontFamily = FontFamily.Monospace,
                letterSpacing = 1.sp,
            )
        }
    }
}

/**
 * 开锁圆盘 —— 全屏唯一主角 (范式 9 权重唯一 / 14-13 大环不超过 1 个)。
 *
 * 分层 (由下到上):
 *   1 外圈柔光   radialGradient accent@0.16 -> 透明, 半径 = 150dp
 *                = 范式 7.12 AmbientGlow (透明度 0.12–0.20, 一屏 <=2 处)
 *   2 金属倒角   sweepGradient 8 停 (亮面随角度走)
 *   3 深色玻璃面 radialGradient 4 停, 光源偏左上
 *   4 斜向镜面高光 drawArc + linearGradient
 *   5 锁形字形 + 手势说明 (Composable 叠层, 不在 Canvas 里画字)
 *   6 外缘轨道 + 进度弧
 *                 —— 范式 7.8 通用自检「所有环必须渐变或分色, 纯色单环 = 不合格」:
 *                    进度弧改成 sweepGradient 多停 (对齐 iOS HomeConsole.swift:419-432 的
 *                    AngularGradient 三停), 不再是旧版的纯色 accent@0.9 平涂。
 *
 * 零投影: 全仓没有一处 .shadow —— 范式 6.3「应用体卡片靠明度差, 禁止投影」。
 */
@Composable
private fun UnlockDial(busy: Boolean, success: Boolean, rssi: Int?, onClick: () -> Unit) {
    val colors = LocalKfColors.current
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    // 范式 11.1「按压缩放 .easeOut 0.12s, scale 1 -> 0.97」
    val scale by animateFloatAsState(
        targetValue = if (pressed) 0.97f else 1f,
        animationSpec = tween(120, easing = CubicBezierEasing(0.42f, 0f, 0.58f, 1f)),
        label = "dial"
    )

    Box(contentAlignment = Alignment.Center) {
        // 1 外圈柔光 (不可点)
        Canvas(Modifier.size(300.dp)) {
            drawCircle(
                brush = Brush.radialGradient(
                    listOf(colors.accent.copy(alpha = 0.16f), Color.Transparent),
                    center = center, radius = size.minDimension / 2
                ),
                radius = size.minDimension / 2
            )
        }
        Box(
            Modifier
                .size(232.dp)
                .scale(scale)
                .clip(CircleShape)
                .clickable(interactionSource = interaction, indication = null, enabled = !busy) { onClick() }
                .semantics { contentDescription = if (busy) "正在开锁" else "开锁" },
            contentAlignment = Alignment.Center
        ) {
            // 2–4 盘面
            Canvas(Modifier.fillMaxSize()) {
                val dim = size
                val cx = size.width / 2
                val cy = size.height / 2
                val rOuter = dim.minDimension / 2 - 1.dp.toPx()

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

                val inset = 9.dp.toPx()
                drawCircle(
                    brush = Brush.radialGradient(
                        listOf(Color(0xFF3A4044), Color(0xFF202528), Color(0xFF0F1214), Color(0xFF080A0B)),
                        center = Offset(cx - rOuter * 0.24f, cy - rOuter * 0.46f),
                        radius = rOuter * 1.2f
                    ),
                    radius = rOuter - inset
                )

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
            }

            // 6 外缘轨道 + 进度弧 (轨道用 hairline, 进度弧用渐变, 都不是平涂)
            Canvas(Modifier.fillMaxSize()) {
                val rOuter = size.minDimension / 2 - 1.dp.toPx()
                val rim = 6.dp.toPx()
                val rimRadius = rOuter - rim / 2
                // 轨道也必须是渐变, 不是平涂 —— 范式 7.8 通用自检「纯色单环 = 不合格」。
                // 上暗下亮读成"凹进去的槽", 与 iOS HomeConsole.swift:406-414 那条
                // strokeBorder(surfaceAlt) + 上缘暗线 的做法同义。
                drawCircle(
                    brush = Brush.verticalGradient(
                        listOf(colors.surfaceSunken, colors.surfaceAlt),
                        startY = size.height / 2 - rimRadius,
                        endY = size.height / 2 + rimRadius
                    ),
                    radius = rimRadius,
                    style = Stroke(rim)
                )
                if (busy || success) {
                    // 弧: 12 点起、顺时针 300°。渐变要与弧**同起点**。
                    // iOS 用 AngularGradient(startAngle: .degrees(-90)) 一句话把 0 位对齐到 12 点;
                    // Compose 的 Brush.sweepGradient 没有 startAngle 参数, 0 位固定在 **3 点**。
                    // 两种对齐法:
                    //   A) 把 colorStops 整体平移 0.75 圈  —— 停点会绕回, 首尾接缝处会跳色
                    //   B) 用 drawArc 的 startAngle + 一个**旋转过的坐标系** —— 直接用 rotate(-90f) 包住
                    // 这里用 B: 先把画布转到 12 点朝右 (即 sweep 的 0 位), 再画一条从 0° 起、走 300° 的弧。
                    // 效果等价于 iOS 的 AngularGradient(startAngle: -90) + trim(0...progress)。
                    rotate(degrees = -90f, pivot = Offset(size.width / 2f, size.height / 2f)) {
                        // 六图改造 (2026-10-23): 进度弧改用**图 1 的五段连续渐变**。
                        // 成功态换成图 1 语言的绿色渐变（dialOKStops）——语义色不能被渐变盖掉，
                        // 用户要靠颜色判断"到底开没开"。
                        //
                        // 与 iOS HomeConsole 同步：图 1 Health Age 的环是青绿→蓝→深蓝的
                        // **连续**过渡（#4A9E96 → #2E8FC0 → #1E6AAE → #1560A8 → #0A84FF）。
                        // 之前这里是单色 accent 的三档透明度 —— 读起来像"进度条推着走"，
                        // 而连续渐变让环本身成为一个渐变物体，这是图 1 与普通进度环最本质的差别。
                        drawArc(
                            brush = Brush.linearGradient(
                                colorStops = (if (success) KfTokens.dialOKStops else KfTokens.dialStops).toTypedArray(),
                                start = Offset(0f, size.height),
                                end = Offset(size.width, 0f)
                            ),
                            startAngle = 0f,
                            sweepAngle = 300f,
                            useCenter = false,
                            topLeft = Offset((size.width - rimRadius * 2) / 2, (size.height - rimRadius * 2) / 2),
                            size = Size(rimRadius * 2, rimRadius * 2),
                            style = Stroke(width = rim, cap = StrokeCap.Round)
                        )
                    }
                }
            }

            // 5 字形 + 手势说明 + **图 1 的中心读数**
            //
            // 图 1 的环心是一个超大数字（-4.7 + YEARS）。本端环心原来是图标 + 文字，
            // 没有读数 —— 用户看不出"现在信号多强"，只能去别处找。
            // 现在把 RSSI 做成环心读数（与 Android 01-home HTML 原型一致）。
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                // 图 1 的环心读数：超大数字 + 单位。这里放 RSSI，与 01-home HTML 原型一致。
                // 没有信号时显示两个短横 —— 不假装有数据。
                Row(verticalAlignment = Alignment.Bottom) {
                    // Compose 的 Text 没有 fontFeatureSettings 参数 —— 等宽数字要走 TextStyle
                    // （CI 报 CompilationErrorException，就是这一行）
                    Text(
                        text = rssi?.toString() ?: "—",
                        style = TextStyle(
                            fontSize = 44.sp,
                            fontWeight = FontWeight.Bold,
                            color = colors.text,
                            // 数字等宽，否则扫描时数字跳动会把整行推来推去
                            fontFeatureSettings = "tnum"
                        )
                    )
                    Text(
                        text = " dBm",
                        fontSize = 13.sp,
                        fontWeight = FontWeight.Medium,
                        color = colors.textTertiary,
                        modifier = Modifier.padding(bottom = 7.dp)
                    )
                }
                Spacer(Modifier.height(10.dp))
                Canvas(Modifier.size(40.dp)) {
                    val g = size.minDimension * 0.30f
                    val cx = size.width / 2
                    val cy = size.height / 2
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
                }
                Spacer(Modifier.height(KfTokens.Space.xs))
                Text(
                    text = if (busy) "开锁中" else "轻点开锁",
                    color = colors.textSub,
                    fontSize = Type.footnote,
                )
            }
        }
    }
}

/** 空态三段式 —— 范式 7.17: 图标 28 / 标题 14 Semibold / 说明 12 Regular, 内间距 10 与 4, 上下各 24。 */
@Composable
private fun EmptyState(onScan: () -> Unit) {
    val colors = LocalKfColors.current
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        modifier = Modifier.padding(vertical = KfTokens.Space.xl)
    ) {
        // 六图改造 (2026-10-23): 取景框外面包一层**图 6 的蓝渐变 hero**。
        //
        // 图 6 Face Gallery 的「New Watch Faces」卡是一个蓝紫渐变容器，
        // 里面放主体视觉 + 一句引导。本屏的"主体视觉"就是那个取景框，
        // "引导"就是下面那句「对准 iOS 上的钥匙二维码」。
        // 之前这两样裸放在黑画布上，读起来像临时提示；包进渐变 hero 之后
        // 才是一张"卡片"——图 6 从不在黑底上裸放视觉主体。
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            modifier = Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(24.dp))
                .background(
                    Brush.verticalGradient(
                        colorStops = arrayOf(
                            0.00f to Color(0xFF4B5AE8),
                            0.42f to Color(0xFF3D49C8),
                            1.00f to Color(0xFF232B7A)
                        )
                    )
                )
                .padding(horizontal = 22.dp, vertical = 26.dp)
        ) {
        // 二维码角框: 保留 (它是真功能 —— 告诉用户"这里要扫一张码"), 不是装饰图标。
        // 范式 7.17 要求图标 28pt, 但这里的框承担「取景框」语义, 按 96dp 画; 见
        // docs/GLASS/ANDROID-REDESIGN.md 的偏离登记。
        Canvas(Modifier.size(96.dp)) {
            val w = 3.dp.toPx()
            val len = 24.dp.toPx()
            // 图 6 hero 内的取景框用白描边（在蓝底上铜色会糊掉）
            val c = Color.White.copy(alpha = 0.92f)
            fun corner(x: Float, y: Float, dx: Float, dy: Float) {
                drawLine(c, Offset(x, y), Offset(x + dx * len, y), strokeWidth = w, cap = StrokeCap.Round)
                drawLine(c, Offset(x, y), Offset(x, y + dy * len), strokeWidth = w, cap = StrokeCap.Round)
            }
            corner(0f, 0f, 1f, 1f)
            corner(size.width, 0f, -1f, 1f)
            corner(0f, size.height, 1f, -1f)
            corner(size.width, size.height, -1f, -1f)
        }
        Spacer(Modifier.height(10.dp))
        // 范式 12: 空态标题说**原因**, 不说状态。旧句「还没有绑定门锁」是状态。
        // hero 内文字必须走白色系 —— 深灰压在蓝渐变上读不清（图 6 的 hero 内也是纯白 + 78% 白）
        Text("本机还没有钥匙", color = Color.White, fontSize = Type.title2, fontWeight = FontWeight.Bold)
        Spacer(Modifier.height(KfTokens.Space.xs))
        Text(
            "在 iOS 端「设置 → 门锁 → 分享给安卓」生成二维码，扫一次即可导入。",
            color = Color.White.copy(alpha = 0.78f),
            fontSize = Type.footnote,
            textAlign = TextAlign.Center,
            lineHeight = 18.sp
        )
        }

        Spacer(Modifier.height(KfTokens.Space.xl))
        // 范式 7.0.6: 主按钮 48pt 高 / 白底黑字 / 圆角 999。
        PrimaryButton(text = "扫码添加门锁", onClick = onScan)
    }
}

/** 范式 7.7 MetricRow: 色点 8 + 名称 14 Regular 60% 灰 + Spacer + 值 14 Semibold 白。 */
@Composable
private fun SignalMetric(armed: Boolean, rssi: Int?, proximity: Boolean, modifier: Modifier = Modifier) {
    val colors = LocalKfColors.current
    val dot = when {
        !proximity -> colors.textSub
        rssi == null -> colors.textTertiary
        armed -> colors.ok
        else -> colors.warn
    }
    val value = when {
        !proximity -> "已关闭"
        rssi == null -> "寻找中"
        armed -> "信号已满"
        else -> "还差一点"
    }
    Row(
        modifier = modifier.heightIn(min = KfTokens.Hit.metricRow),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(Modifier.size(8.dp).clip(CircleShape).background(dot))
        Spacer(Modifier.width(KfTokens.Space.s))
        Text("信号", color = colors.textSub, fontSize = Type.subhead)
        Spacer(Modifier.weight(1f))
        Text(value, color = colors.text, fontSize = Type.subhead, fontWeight = FontWeight.SemiBold)
        if (rssi != null) {
            Spacer(Modifier.width(KfTokens.Space.s))
            // dBm 是**工程量**, 不是用户语言 —— iOS 只把它放在设备明细页 (DevicePage.swift:124,317)。
            // 这里保留是因为本端没有明细页, 但压到 11sp caption 档、textTertiary, 不抢主角。
            Text("${rssi} dBm", color = colors.textTertiary, fontSize = Type.caption, fontFamily = FontFamily.Monospace)
        }
    }
}

/**
 * 门锁设置卡 —— 范式 7.0.6 plain 卡的排法 (内容高 + 上下 48, 垂直居中, 不超出屏幕),
 * 配色走应用体 (surface #1C1C1E + r24), 不是展示壳白卡。
 *
 * 内部纵向节奏照范式 7.6 那张最容易漏的表:
 *   卡头 -> 标题 6 / 标题 -> 标签 12 / 标签 -> 值 2 / 值 -> 分隔线 14 / 分隔线 -> 下一组 12
 */
@Composable
private fun SettingsCard(
    lock: LockInfo?,
    on: Boolean,
    onToggle: (Boolean) -> Unit,
    sound: Boolean,
    onSound: (Boolean) -> Unit,
    onRescan: () -> Unit,
    onUnbind: () -> Unit,
    onClose: () -> Unit,
) {
    val colors = LocalKfColors.current
    Column(
        Modifier
            .fillMaxWidth()
            .padding(horizontal = KfTokens.Space.l)
            .clip(RoundedCornerShape(KfTokens.Radius.card))
            .background(colors.surface)
            // 描边: 范式 6.3 要求浮层「玻璃 + 0.5pt 描边」。本端做不了真玻璃 (见 ANDROID-REDESIGN §3 偏离-2),
            // 但"描边"这一半能做, 而且必须做 —— 卡片压在 72% 遮罩上, 没有边就是一块浮不起来的深色。
            // 用 hairlineStrong 而不是 hairline: 它是"玻璃的实色退路"这一语义位 (iOS XPalette:75), 正对当前处境。
            .border(1.dp, colors.hairlineStrong, RoundedCornerShape(KfTokens.Radius.card))
            // 吃掉整卡的点击: 遮罩层挂了 "点任意处关闭", 若不在这里消费, 点卡片空白也会关面板。
            // 空 interactionSource 是刻意的 —— 卡片本身不可点, 只是把事件拦住不让它冒泡。
            .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) {}
            .padding(KfTokens.Space.card)
    ) {
        // 卡头: 14 Regular 灰 + 右侧关闭 (范式 7.6 的卡头是灰色链接, 不是白色粗体标题)
        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
            Text("门锁设置", color = colors.textSub, fontSize = Type.subhead, modifier = Modifier.weight(1f))
            TextButton(
                onClick = onClose,
                modifier = Modifier.heightIn(min = KfTokens.Hit.min)
            ) {
                Text("完成", color = colors.accentText, fontSize = Type.subhead, fontWeight = FontWeight.SemiBold)
            }
        }

        Spacer(Modifier.height(6.dp))

        // 标题 19 Bold 白 (范式 7.6 标题档)
        Text("靠近自动开锁", color = colors.text, fontSize = Type.title2, fontWeight = FontWeight.Bold)

        Spacer(Modifier.height(KfTokens.Space.m))

        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
            // 标签 12 Regular textSub (范式 7.6 标签档)
            Text("当前状态", color = colors.textSub, fontSize = Type.footnote, modifier = Modifier.weight(1f))
            Switch(
                checked = on,
                onCheckedChange = onToggle,
                colors = SwitchDefaults.colors(
                    // 拇指压在 accent 轨道上 = 「强调色之上的前景」, 用的正是 onAccent 这个语义,
                    // 不是拿 canvas 顶替 (那会让浅色档的拇指变成浅灰底, 在铜轨道上看不见)。
                    checkedThumbColor = colors.onAccent,
                    checkedTrackColor = colors.accent,
                    uncheckedThumbColor = colors.textSub,
                    uncheckedTrackColor = colors.surfaceAlt,
                    uncheckedBorderColor = colors.hairline,
                )
            )
        }

        // 审美对齐 android-proto 03-settings 卡1 的第二行「提示音」。
        // App 里这个开关一直存在（findSound），但只在 AirTag 全屏层里露过面 ——
        // 设置面板里没有它，用户找不到"在哪儿关声音"。
        Spacer(Modifier.height(KfTokens.Space.s))
        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
            Column(Modifier.weight(1f)) {
                Text("提示音", color = colors.text, fontSize = Type.subhead)
                Text("开锁时「滴滴滴」", color = colors.textSub, fontSize = Type.caption)
            }
            Switch(
                checked = sound,
                onCheckedChange = onSound,
                colors = SwitchDefaults.colors(
                    checkedThumbColor = colors.onAccent,
                    checkedTrackColor = colors.accent,
                    uncheckedThumbColor = colors.textSub,
                    uncheckedTrackColor = colors.surfaceAlt,
                    uncheckedBorderColor = colors.hairline,
                )
            )
        }

        // 标签 -> 值 2pt: 这里是「值」组 (说明两行), 与上面的控件紧贴
        Spacer(Modifier.height(2.dp))

        // 文案里的数值一律从 AutoOpenKit 取: 写死数字的注释/文案, 在阈值改动那天就变成假话。
        Text(
            "开着它: 手机解了锁、App 在前台时, 靠近到 " + AutoOpenKit.BASE + " dBm 以内会自动开一次。",
            color = colors.textTertiary, fontSize = Type.footnote, lineHeight = 18.sp,
        )
        Spacer(Modifier.height(KfTokens.Space.xs))
        Text(
            "一次靠近只开一次: 要走开让信号掉到 " + AutoOpenKit.disarmThreshold() +
                " dBm 以下, 隔 6 秒后再靠近才会再开。",
            color = colors.textTertiary, fontSize = Type.footnote, lineHeight = 18.sp,
        )

        Spacer(Modifier.height(KfTokens.Space.m))
        // 分隔线 0.5pt, 卡内全宽 (范式 7.6 明令不内缩)
        Box(
            Modifier
                .fillMaxWidth()
                .height(KfTokens.Hairline.width)
                .background(colors.hairline)
        )
        Spacer(Modifier.height(KfTokens.Space.m))

        // 审美对齐 android-proto 03-settings：HTML 把「凭证与绑定」单独成卡（卡2），
        // 这里相当于该卡的卡内区。补一行卡头文字，让"这一段是凭证类动作"可被扫读认出来。
        Text("凭证与绑定", color = colors.textSub, fontSize = Type.subhead)
        Spacer(Modifier.height(KfTokens.Space.s))

        // 六图改造 (2026-10-23): 两个纯文字动作改成**图 2 的卡内行形态**。
        //
        // 图 2 Winding Down 的卡里从不裸放文字链接 —— 每个可点项都是
        // 「图标块 + 主标题 + 副标题 + 右侧 chevron」这一行。
        // 之前这里是两个并排的 15sp 文字：用户看不出"点哪"（没有边界），
        // 也看不出"点下去会发生什么"（没有副标题）。触达 48dp 是够了，可发现性不够。
        SettingRow(
            title = "重新扫码绑定",
            subtitle = "换一把锁，或更新这把锁的凭证",
            tint = colors.accentText,
            onClick = onRescan,
            divider = true
        )
        SettingRow(
            title = "解绑这把锁",
            subtitle = "删除本机钥匙与全部设置",
            tint = colors.danger,
            onClick = onUnbind,
            divider = false
        )

        // 图 2 的卡尾：一句说清后果的整句（不是"注意"两个字）
        Spacer(Modifier.height(KfTokens.Space.s))
        Text(
            "解绑只删本机，门锁里的密码与指纹不受影响 —— 下次要用，得在门锁键盘上重置后重新扫码。",
            color = colors.textTertiary,
            fontSize = Type.footnote,
            lineHeight = 18.sp
        )

        // ── 卡3「当前绑定」── 对齐 android-proto 03-settings 卡3
        // HTML 给的三行事实：门锁名 / 绑定方式 / 凭证类型 + 一条协议 footer。
        // 这些在 App 里都真实存在（LockInfo），只是此前只在主屏 Header 露出一行名字。
        if (lock != null) {
            Spacer(Modifier.height(KfTokens.Space.m))
            Box(
                Modifier
                    .fillMaxWidth()
                    .height(KfTokens.Hairline.width)
                    .background(colors.hairline)
            )
            Spacer(Modifier.height(KfTokens.Space.m))
            Text("当前绑定", color = colors.textSub, fontSize = Type.subhead)
            Spacer(Modifier.height(KfTokens.Space.s))
            Row(Modifier.fillMaxWidth()) {
                Text("门锁", color = colors.textSub, fontSize = Type.footnote, modifier = Modifier.weight(1f))
                Text(lock.name, color = colors.text, fontSize = Type.footnote, fontWeight = FontWeight.SemiBold)
            }
            Spacer(Modifier.height(KfTokens.Space.xs))
            Row(Modifier.fillMaxWidth()) {
                Text("凭证类型", color = colors.textSub, fontSize = Type.footnote, modifier = Modifier.weight(1f))
                Text("离线锁钥匙", color = colors.text, fontSize = Type.footnote, fontWeight = FontWeight.SemiBold)
            }
            Spacer(Modifier.height(KfTokens.Space.xs))
            Row(Modifier.fillMaxWidth()) {
                Text("协议", color = colors.textSub, fontSize = Type.footnote, modifier = Modifier.weight(1f))
                Text("04", color = colors.text, fontSize = Type.footnote, fontWeight = FontWeight.SemiBold)
            }
            Spacer(Modifier.height(KfTokens.Space.s))
            Text(
                "每个接近事件只发一次 04 命令 —— 秒开在 RSSI ≥ " + AutoOpenKit.BASE + " dBm 时触发。",
                color = colors.textTertiary,
                fontSize = Type.footnote,
                lineHeight = 18.sp
            )
        }
    }
}

/**
 * 图 2 的卡内行 —— 图标块 + 主标题 + 副标题 + chevron，触达 >= 48dp。
 *
 * 为什么单独抽出来：设置卡里原本每个动作各写一遍 Box + heightIn + clickable，
 * 三处以后就会开始漂（有的 44dp 有的 48dp、有的有副标题有的没有）。
 */
@Composable
private fun SettingRow(
    title: String,
    subtitle: String,
    tint: Color,
    onClick: () -> Unit,
    divider: Boolean
) {
    val colors = LocalKfColors.current
    Column {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .heightIn(min = KfTokens.Hit.min)
                .clickable { onClick() }
                .padding(vertical = KfTokens.Space.s),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(KfTokens.Space.m)
        ) {
            Box(
                Modifier
                    .size(34.dp)
                    .clip(RoundedCornerShape(10.dp))
                    .background(tint.copy(alpha = 0.14f)),
                contentAlignment = Alignment.Center
            ) {
                Box(
                    Modifier
                        .size(8.dp)
                        .clip(CircleShape)
                        .background(tint)
                )
            }
            Column(Modifier.weight(1f)) {
                Text(title, color = tint, fontSize = Type.headline, fontWeight = FontWeight.SemiBold)
                Text(subtitle, color = colors.textTertiary, fontSize = Type.footnote)
            }
            Text("›", color = colors.textTertiary, fontSize = Type.title2)
        }
        if (divider) {
            Box(
                Modifier
                    .fillMaxWidth()
                    .height(KfTokens.Hairline.width)
                    .background(colors.hairline)
            )
        }
    }
}

/** 首页右下齿轮: 二级菜单的唯一入口。 */
@Composable
private fun GearButton(modifier: Modifier = Modifier, onClick: () -> Unit) {
    val colors = LocalKfColors.current
    Box(
        modifier
            .size(56.dp)
            .clip(CircleShape)
            .background(colors.surface)
            .clickable { onClick() }
            .semantics { contentDescription = "门锁设置" },
        contentAlignment = Alignment.Center,
    ) {
        // 自绘齿轮: 8 齿 + 内圈 + 轴心。
        // 尺寸全部按半径比例算 —— 旧版写的是 3.5f / 2.5f / 4f / 5f 这种**裸像素**,
        // 在 3x 屏上 3.5px 只有 1.17dp, 粗细随密度漂移。
        Canvas(Modifier.size(KfTokens.Icon.lg)) {
            val c = Offset(size.width / 2f, size.height / 2f)
            val rOut = size.minDimension / 2f
            val stroke = rOut * 0.23f
            for (k in 0 until 8) {
                val a = Math.toRadians((k * 45).toDouble()).toFloat()
                drawLine(
                    colors.textSub,
                    Offset(c.x + cos(a) * (rOut - stroke * 1.6f), c.y + sin(a) * (rOut - stroke * 1.6f)),
                    Offset(c.x + cos(a) * rOut, c.y + sin(a) * rOut),
                    strokeWidth = stroke, cap = StrokeCap.Round,
                )
            }
            drawCircle(colors.textSub, radius = rOut - stroke * 2.4f, center = c, style = Stroke(width = stroke * 0.7f))
            drawCircle(colors.canvas, radius = rOut * 0.26f, center = c)
        }
    }
}

/**
 * 主按钮 —— 与 iOS XPrimaryButtonStyle (App/Core/Components.swift:263-292) 同一套做法:
 *   · accent 实底 + onAccent 前景 (深色档 6.97:1; 白字压铜只有 2.2:1, 所以不是白底黑字)
 *   · 圆角 XRadius.control (12), **不是胶囊** —— iOS 那边就是 control, 两端同一个形状
 *   · 最小高度 XHit.min (iOS 44pt / 本端 48dp), 横向内边距 XSpace.l
 *   · 按压时轻微缩放 + 降透明度 (iOS: scale 0.98 / opacity 0.82)
 *
 * 上一版这里是"白底黑字 + 胶囊", 抄的是范式 7.0.6 —— 但 7.0.x 整节是**展示壳**组件,
 * 而本 App 没有展示壳层 (docs/GLASS/DEVIATIONS.md §5 已裁定 iOS 侧删除 shellCard)。
 * 应用体里出现纯白卡片违反 §0 总则 4 / §14-1, 所以改成 accent 底。
 */
@Composable
private fun PrimaryButton(text: String, onClick: () -> Unit) {
    val colors = LocalKfColors.current
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    val scale by animateFloatAsState(
        targetValue = if (pressed) 0.98f else 1f,
        animationSpec = tween(120, easing = CubicBezierEasing(0.42f, 0f, 0.58f, 1f)),
        label = "primaryButton"
    )
    Box(
        Modifier
            .heightIn(min = KfTokens.Hit.min)
            .scale(scale)
            .clip(RoundedCornerShape(KfTokens.Radius.control))
            // 纯色填充之上压一层竖向高光 (上亮下透) —— 与 iOS XPrimaryButtonStyle 里那层
            // specular.opacity(0.10) 的 LinearGradient 同一个做法: 一点点深度差就能让按钮
            // 从"贴纸"变成"实体"。幅度刻意很小, 深色档下看不出分界。
            .background(
                Brush.verticalGradient(
                    listOf(colors.specular.copy(alpha = 0.10f), Color.Transparent)
                )
            )
            .background(colors.accent.copy(alpha = if (pressed) 0.82f else 1f))
            .clickable(interactionSource = interaction, indication = null) { onClick() }
            .padding(horizontal = KfTokens.Space.l),
        contentAlignment = Alignment.Center
    ) {
        Text(text, color = colors.onAccent, fontSize = Type.headline, fontWeight = FontWeight.SemiBold)
    }
}

// ---------- AirTag 精确查找层 ----------

/**
 * 查找层的底色 —— 范式 3.5 里全 App 唯一允许的彩色底 sportsGradient 的三停
 * (#003D12 / #00260A / #001505)。顶层写死而**不**进 KfColors:
 * 色板要与 iOS XPalette 一一对账, 而 iOS 侧没有这一屏, 塞进去会让两端色板出现单边成员。
 */
private val FindBgStops = listOf(Color(0xFF003D12), Color(0xFF00260A), Color(0xFF001505))

/**
 * 距离档位词 (范式 12 的文案纪律 + iOS FindArrowLayer.swift:13 的诚实边界:
 * 「距离是 RSSI 换算的粗估档，显示很近/近/远，**不显示米数**」)。
 *
 * 旧实现按对数路径损耗反推米数并显示到 0.1 米 —— BLE RSSI 抖动 +-6dB, 那个数字是假的精确。
 */
private fun distanceTier(fill: Float, rssi: Int?): String = when {
    rssi == null -> "还在找"
    fill > 0.85f -> "很近"
    fill > 0.6f -> "近"
    fill > 0.3f -> "有点远"
    else -> "远"
}

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
    val colors = LocalKfColors.current
    val fill = signalFill(rssi)
    val bearing = relativeBearing(azimuthDeg, peakDeg).coerceIn(-30f, 30f)
    val tier = distanceTier(fill, rssi)
    Box(
        Modifier
            .fillMaxSize()
            // 旧版是单层纯色 (#0B6B3A / #0E7A42)。范式 14-24 的同类问题: 全屏彩色底必须是
            // 亮头 + 暗板两层 / 渐变, 单层纯色读起来像一块贴纸。改用 sportsGradient 三停。
            .background(Brush.verticalGradient(FindBgStops))
    ) {
        // 顶部: 正在查找 + 锁名 (对齐 AirTag 精确查找的标题区)
        Column(
            Modifier.padding(
                start = KfTokens.Space.section,
                top = KfTokens.Space.pageTop + KfTokens.Space.l
            )
        ) {
            Text("正在查找", color = colors.text.copy(alpha = 0.85f), fontSize = Type.subhead, fontWeight = FontWeight.Medium)
            Spacer(Modifier.height(2.dp))
            Text(name, color = colors.text, fontSize = Type.largeTitle, fontWeight = FontWeight.Bold, letterSpacing = (-0.4).sp)
        }
        // 中央: 空心箭头 (随信号从下往上灌绿, 满绿=可开)。300dp 保留 —— 它是这一屏的主角。
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
                okColor = colors.ok,
                outlineColor = colors.text,
            )
        }
        // 底部左: 距离档位词 + 方向。**不显示米数** —— 见 distanceTier 的说明。
        Column(
            Modifier
                .align(Alignment.BottomStart)
                .padding(start = KfTokens.Space.section, bottom = 116.dp)
        ) {
            Text(tier, color = colors.text, fontSize = Type.display, fontWeight = FontWeight.Bold, letterSpacing = (-0.6).sp)
            Text(
                directionLabel(bearing),
                color = colors.text.copy(alpha = 0.92f),
                fontSize = Type.title2,
                fontWeight = FontWeight.Bold
            )
        }
        // 左下: 收起 (回到手动底层)
        Box(Modifier.align(Alignment.BottomStart).padding(KfTokens.Space.section)) {
            GlyphButton(glyph = Glyph.Close, onClick = onClose, description = "收起查找界面")
        }
        // 右下: 提示音开关
        Box(Modifier.align(Alignment.BottomEnd).padding(KfTokens.Space.section)) {
            GlyphButton(
                glyph = if (soundOn) Glyph.SoundOn else Glyph.SoundOff,
                onClick = onToggleSound,
                description = if (soundOn) "关闭提示音" else "打开提示音",
            )
        }
    }
    ProximityBeep(fill = fill, soundOn = soundOn, foreground = foreground)
}

/** 圆形按钮上的矢量字形。范式 14-18 明令禁止 emoji 当图标, 旧版是三个字符 "✕" / "🔊" / "🔇"。 */
private enum class Glyph { Close, SoundOn, SoundOff }

@Composable
private fun GlyphButton(glyph: Glyph, onClick: () -> Unit, description: String) {
    val colors = LocalKfColors.current
    Box(
        Modifier
            .size(52.dp)   // >= KfTokens.Hit.min (48dp)
            .clip(CircleShape)
            .background(colors.text.copy(alpha = 0.22f))
            .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) { onClick() }
            .semantics { contentDescription = description },
        contentAlignment = Alignment.Center
    ) {
        Canvas(Modifier.size(KfTokens.Icon.md)) {
            val w = size.width
            val h = size.height
            val stroke = w * 0.12f
            when (glyph) {
                Glyph.Close -> {
                    drawLine(colors.text, Offset(w * 0.18f, h * 0.18f), Offset(w * 0.82f, h * 0.82f), stroke, StrokeCap.Round)
                    drawLine(colors.text, Offset(w * 0.82f, h * 0.18f), Offset(w * 0.18f, h * 0.82f), stroke, StrokeCap.Round)
                }
                Glyph.SoundOn -> {
                    drawPath(speakerPath(w, h), color = colors.text)
                    drawArc(
                        color = colors.text, startAngle = -55f, sweepAngle = 110f, useCenter = false,
                        topLeft = Offset(w * 0.42f, h * 0.22f), size = Size(w * 0.44f, h * 0.56f),
                        style = Stroke(width = stroke * 0.8f, cap = StrokeCap.Round)
                    )
                }
                Glyph.SoundOff -> {
                    drawPath(speakerPath(w, h), color = colors.text)
                    drawLine(colors.text, Offset(w * 0.52f, h * 0.30f), Offset(w * 0.86f, h * 0.70f), stroke * 0.8f, StrokeCap.Round)
                }
            }
        }
    }
}

/** 喇叭本体 (SoundOn / SoundOff 共用): 一个矩形 + 一个向右的梯形。 */
private fun speakerPath(w: Float, h: Float) = androidx.compose.ui.graphics.Path().apply {
    moveTo(w * 0.14f, h * 0.38f)
    lineTo(w * 0.30f, h * 0.38f)
    lineTo(w * 0.50f, h * 0.20f)
    lineTo(w * 0.50f, h * 0.80f)
    lineTo(w * 0.30f, h * 0.62f)
    lineTo(w * 0.14f, h * 0.62f)
    close()
}

/** 靠近提示音: 信号越强间隔越短 (AirTag 那种"滴滴滴"加速)。按 fill 分档, 档位不变就不重启协程。 */
@Composable
private fun ProximityBeep(fill: Float, soundOn: Boolean, foreground: Boolean) {
    val level = when {
        fill > 0.85f -> 3
        fill > 0.6f -> 2
        fill > 0.3f -> 1
        fill > 0.05f -> 0
        else -> -1
    }
    LaunchedEffect(soundOn, level, foreground) {
        if (!soundOn || level < 0 || !foreground) return@LaunchedEffect
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
