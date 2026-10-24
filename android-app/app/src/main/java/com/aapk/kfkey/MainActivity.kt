package com.aapk.kfkey

import android.Manifest
import android.content.Context
import android.media.AudioManager
import android.media.ToneGenerator
import android.os.Bundle
import androidx.activity.ComponentActivity
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
    var pitch by remember { mutableStateOf(0f) }              // 手机俯仰 (AirTag 层 3D 视差)
    var roll by remember { mutableStateOf(0f) }               // 手机横滚 (同上)
    var airTagDismissed by remember { mutableStateOf(false) }  // 用户手动收起 AirTag 层 (本次靠近事件内不再弹)
    var findSound by remember { mutableStateOf(true) }         // AirTag 层提示音开关
    val lifecycleOwner = LocalLifecycleOwner.current

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
                    color = colors.inkSub.copy(alpha = 0.7f),
                    fontSize = 12.sp,
                    fontFamily = FontFamily.Monospace
                )
                if (!detail.isEmpty()) {
                    Text(
                        text = detail,
                        color = colors.inkSub.copy(alpha = 0.55f),
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
                    onClose = { showSettings = false },
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
                color = colors.inkSub.copy(alpha = 0.75f),
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
            "在 iOS 端「设置 → 门锁 → 分享给安卓」生成二维码,\n扫一次即可。之后开锁不再需要它。",
            color = colors.inkSub, fontSize = 13.sp, textAlign = TextAlign.Center, lineHeight = 20.sp
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
                    color = colors.inkSub, fontSize = 12.sp, lineHeight = 17.sp,
                )
                Spacer(Modifier.height(4.dp))
                Text(
                    "一次靠近只开一次: 要走开让信号掉到 " + AutoOpenKit.disarmThreshold() +
                        " dBm 以下, 隔 6 秒后再靠近才会再开。",
                    color = colors.inkSub.copy(alpha = 0.75f), fontSize = 12.sp, lineHeight = 17.sp,
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
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("门锁设置", color = colors.inkSub.copy(alpha = 0.6f), fontSize = 12.sp, modifier = Modifier.weight(1f))
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
                    .padding(vertical = 6.dp)
            )
            Text(
                "解绑",
                color = colors.inkSub,
                fontSize = 13.sp,
                modifier = Modifier
                    .clickable { onUnbind() }
                    .padding(vertical = 6.dp)
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
            .background(if (armed) Color(0xFF12B24A) else Color(0xFF1CC964))
    ) {
        // 顶部: 正在查找 + 锁名 (对齐 AirTag 精确查找的标题区)
        Column(Modifier.padding(start = 28.dp, top = 56.dp)) {
            Text("正在查找", color = Color.White.copy(alpha = 0.85f), fontSize = 15.sp, fontWeight = FontWeight.Medium)
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
            Text(directionLabel(bearing), color = Color.White.copy(alpha = 0.92f), fontSize = 26.sp, fontWeight = FontWeight.SemiBold)
        }
        // 左下: 收起 (回到手动底层)
        Box(Modifier.align(Alignment.BottomStart).padding(28.dp)) {
            CircleIconButton(label = "✕", onClick = onClose)
        }
        // 右下: 提示音开关
        Box(Modifier.align(Alignment.BottomEnd).padding(28.dp)) {
            CircleIconButton(label = if (soundOn) "🔊" else "🔇", onClick = onToggleSound)
        }
    }
    ProximityBeep(active = true, fill = fill, soundOn = soundOn, foreground = foreground)
}

@Composable
private fun CircleIconButton(label: String, onClick: () -> Unit) {
    Box(
        Modifier
            .size(52.dp)
            .clip(CircleShape)
            .background(Color.White.copy(alpha = 0.22f))
            .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) { onClick() },
        contentAlignment = Alignment.Center
    ) {
        Text(label, color = Color.White, fontSize = 20.sp)
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
