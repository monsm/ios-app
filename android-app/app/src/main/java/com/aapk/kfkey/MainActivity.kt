package com.aapk.kfkey

import android.Manifest
import android.content.Context
import android.os.Build
import android.os.Bundle
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
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
private val BgTop = Color(0xFF0A0C10)
private val BgBottom = Color(0xFF141A22)
private val Surface = Color(0xFF161C24)
private val Ink = Color(0xFFF3F6FA)
private val InkSub = Color(0xFF8B96A8)
private val Accent = Color(0xFFE8B45C)     // 暖金: 钥匙/黄铜的联想, 不是"科技蓝紫"
private val Ok = Color(0xFF6EE7A8)
private val Bad = Color(0xFFF87171)

class MainActivity : ComponentActivity() {
    // 只在 unlocker 需要时建一次: KfApp() 是 Composable, remember 的状态跟着组合走,
    // 但 release() 是挂起函数, 不能从 onDestroy 里直接调 —— 所以把 unlocker 提到 Activity 上,
    // 生命周期出口才有东西可拆。
    private val unlocker by lazy { BleUnlocker(this) }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent { KfApp(unlocker) }
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

    fun say(text: String, bad: Boolean = false) {
        status = text
        statusBad = bad
    }

    // 权限: 扫描/连接 (Android 12+) + 相机 (扫码)
    val perms = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { }
    LaunchedEffect(Unit) {
        val need = mutableListOf(Manifest.permission.BLUETOOTH_SCAN, Manifest.permission.BLUETOOTH_CONNECT)
        if (Build.VERSION.SDK_INT >= 33) need += Manifest.permission.CAMERA
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
            say(r.message, !r.ok)
            detail = if (r.ok || r.trace.isEmpty()) "" else r.trace
            if (r.ok) vibrate(ctx)
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
    // 预热线: 比武装线 (AutoOpenKit.BASE = -38) 弱 24 dB ⇒ 功率约 1/250, 大致一两米开外。
    // 越过它就在后台把链路建好 (prewarm 只建链, 一个命令都不发), 等越过武装线时只剩
    // 01+04 两个往返 —— "秒开"靠的是这一步, 不是把协议改快。
    // 用 PREWARM 这个固定值而不是标定值: 安卓端没有标定页 (见 AutoOpenKit 注释)。
    val prewarmLineDbm = AutoOpenKit.BASE - 24

    fun maybeAutoUnlock(r: Int) {
        val now = System.currentTimeMillis()
        // 预热不排队、不抢锁: prewarm 内部 mutex 会排在建链后面, 而开锁那一趟优先级更高,
        // 所以只在"没在开锁 && 还没有热链路"时发起, 避免和开锁抢同一次 startScan。
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
    LaunchedEffect(proximity, lock?.mac, busy, warming) {
        val l = lock ?: return@LaunchedEffect
        if (!proximity) { rssi = null; armed = false; fired = false; prewarmStarted = false }
        // 开锁在途 **或预热在途** 都撤下监测: 安卓同时只跑一路扫描, 而且边扫边连极易 133。
        // 撤下后 rssi 保持最后一次的读数 (不抹成 null), 免得界面在预热那一瞬闪成"正在寻找门锁…"
        if (!proximity || busy || warming) return@LaunchedEffect
        unlocker.observeRssi(l).collect { r ->
            rssi = r
            maybeAutoUnlock(r)
        }
    }

    Box(
        Modifier
            .fillMaxSize()
            .background(Brush.verticalGradient(listOf(BgTop, BgBottom)))
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
                UnlockDial(busy = busy, onClick = { doUnlock(auto = false) })
                Spacer(Modifier.height(22.dp))
                Text(
                    text = status.ifBlank { "点一下开锁" },
                    color = when {
                        statusBad -> Bad
                        status.startsWith("已开锁") -> Ok
                        else -> InkSub
                    },
                    fontSize = 15.sp,
                    textAlign = TextAlign.Center
                )
                Spacer(Modifier.height(6.dp))
                Text(
                    text = if (proximity) (rssi?.let { "当前信号 $it dBm" } ?: "正在寻找门锁…") else " ",
                    color = InkSub.copy(alpha = 0.7f),
                    fontSize = 12.sp,
                    fontFamily = FontFamily.Monospace
                )
                if (!detail.isEmpty()) {
                    Text(
                        text = detail,
                        color = InkSub.copy(alpha = 0.55f),
                        fontSize = 11.sp,
                        fontFamily = FontFamily.Monospace,
                        textAlign = TextAlign.Center,
                        modifier = Modifier.padding(top = 4.dp)
                    )
                }
            }
            Spacer(Modifier.weight(1f))
            if (lock != null) {
                ProximityCard(
                    on = proximity,
                    onToggle = {
                        proximity = it
                        LockStore.saveProximity(ctx, it)
                        if (!it) rssi = null
                    },
                    onRescan = { launchScan() },
                    onUnbind = {
                        LockStore.clear(ctx)
                        lock = null
                        proximity = false
                        // 解绑之后这条链路就没有主人了: 不收, 它会一直占着锁的 GATT 接口位,
                        // 而下一把锁要连的时候还得先拆它 (安卓一次只养一条热链路)。
                        scope.launch { unlocker.release() }
                        say("已解绑")
                    }
                )
            }
        }
    }

    // 已绑定过 → 再次扫码要**二次确认**: 覆盖的是一把能开门的钥匙, 不能静默替换
    pending?.let { p ->
        val same = p.mac == lock?.mac
        AlertDialog(
            onDismissRequest = { pending = null },
            containerColor = Surface,
            titleContentColor = Ink,
            textContentColor = InkSub,
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
                }) { Text(if (same) "覆盖" else "换绑", color = Accent) }
            },
            dismissButton = {
                TextButton(onClick = { pending = null }) { Text("取消", color = InkSub) }
            }
        )
    }
}

@Composable
private fun Header(lock: LockInfo?) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Text(
            text = lock?.name ?: "离线锁钥匙",
            color = Ink,
            fontSize = if (lock == null) 22.sp else 26.sp,
            fontWeight = FontWeight.Light,
            letterSpacing = 1.sp
        )
        if (lock != null) {
            Spacer(Modifier.height(6.dp))
            Text(
                text = lock.macText,
                color = InkSub.copy(alpha = 0.75f),
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
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    val scale by animateFloatAsState(if (pressed) 0.965f else 1f, tween(120), label = "dial")

    Box(contentAlignment = Alignment.Center) {
        // 外圈柔光
        Canvas(Modifier.size(300.dp)) {
            drawCircle(
                brush = Brush.radialGradient(
                    listOf(Accent.copy(alpha = 0.16f), Color.Transparent),
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
                .background(Brush.radialGradient(listOf(Color(0xFF1D2530), Color(0xFF0E1319))))
                .clickable(interactionSource = interaction, indication = null, enabled = !busy) { onClick() },
            contentAlignment = Alignment.Center
        ) {
            Canvas(Modifier.fillMaxSize()) {
                val dim = size
                val r = dim.minDimension / 2 - 1.dp.toPx()
                // 细环: 两层, 外层极淡 (描边), 内层一道亮弧做"锁孔高光"
                drawCircle(
                    color = Color.White.copy(alpha = 0.10f),
                    radius = r,
                    style = Stroke(width = 1.dp.toPx())
                )
                drawArc(
                    color = Accent.copy(alpha = if (busy) 0.9f else 0.45f),
                    startAngle = -90f,
                    sweepAngle = if (busy) 300f else 70f,
                    useCenter = false,
                    topLeft = Offset(1.dp.toPx(), 1.dp.toPx()),
                    size = Size(dim.width - 2.dp.toPx(), dim.height - 2.dp.toPx()),
                    style = Stroke(width = 2.dp.toPx(), cap = StrokeCap.Round)
                )
                // 钥匙孔
                val cx = size.width / 2
                val cy = size.height / 2
                drawCircle(color = Accent, radius = 13.dp.toPx(), center = Offset(cx, cy - 10.dp.toPx()))
                val top = cy + 2.dp.toPx()
                val halfTop = 7.dp.toPx()
                val halfBottom = 12.dp.toPx()
                val bottom = cy + 34.dp.toPx()
                drawPath(
                    path = androidx.compose.ui.graphics.Path().apply {
                        moveTo(cx - halfTop, top)
                        lineTo(cx + halfTop, top)
                        lineTo(cx + halfBottom, bottom)
                        lineTo(cx - halfBottom, bottom)
                        close()
                    },
                    color = Accent
                )
            }
        }
    }
}

@Composable
private fun EmptyState(onScan: () -> Unit) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        // 二维码框: 四个角的自绘框, 比一个 stock 图标更像"待扫描"
        Canvas(Modifier.size(120.dp)) {
            val w = 3.dp.toPx()
            val len = 26.dp.toPx()
            val c = Accent.copy(alpha = 0.85f)
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
        Text("还没有绑定门锁", color = Ink, fontSize = 20.sp, fontWeight = FontWeight.Light)
        Spacer(Modifier.height(10.dp))
        Text(
            "在 iOS 端「设置 → 门锁 → 分享给安卓」生成二维码,\n扫一次即可。之后开锁不再需要它。",
            color = InkSub, fontSize = 13.sp, textAlign = TextAlign.Center, lineHeight = 20.sp
        )
        Spacer(Modifier.height(28.dp))
        PillButton("扫码添加门锁", onScan)
    }
}

@Composable
private fun ProximityCard(on: Boolean, onToggle: (Boolean) -> Unit, onRescan: () -> Unit, onUnbind: () -> Unit) {
    Column(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(22.dp))
            .background(Surface)
            .padding(horizontal = 18.dp, vertical = 16.dp)
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text("靠近自动开锁", color = Ink, fontSize = 15.sp)
                Spacer(Modifier.height(3.dp))
                // 文案如实描述现在的三闸 (旧句"信号强于 -38 时自动开锁"会让人以为站在门口会一直开):
                // 一次靠近只开一次, 要走开让信号掉回 -41 以下再靠近, 才会再开。
                Text("靠近到 -38 dBm 时自动开一次锁; 要再开得先走开一点再靠近", color = InkSub, fontSize = 12.sp)
            }
            Switch(
                checked = on,
                onCheckedChange = onToggle,
                colors = SwitchDefaults.colors(
                    checkedThumbColor = BgTop,
                    checkedTrackColor = Accent,
                    uncheckedThumbColor = InkSub,
                    uncheckedTrackColor = Color(0xFF232A34),
                    uncheckedBorderColor = Color.Transparent
                )
            )
        }
        Spacer(Modifier.height(10.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(20.dp)) {
            Text(
                "重新扫码绑定",
                color = Accent.copy(alpha = 0.9f),
                fontSize = 13.sp,
                modifier = Modifier
                    .clickable { onRescan() }
                    .padding(vertical = 6.dp)
            )
            Text(
                "解绑",
                color = InkSub,
                fontSize = 13.sp,
                modifier = Modifier
                    .clickable { onUnbind() }
                    .padding(vertical = 6.dp)
            )
        }
    }
}

@Composable
private fun PillButton(text: String, onClick: () -> Unit) {
    Box(
        Modifier
            .clip(RoundedCornerShape(50))
            .background(Accent)
            .clickable { onClick() }
            .padding(horizontal = 28.dp, vertical = 14.dp)
    ) {
        Text(text, color = Color(0xFF14181E), fontSize = 15.sp, fontWeight = FontWeight.Medium)
    }
}

private fun vibrate(ctx: Context) {
    val v = if (Build.VERSION.SDK_INT >= 31) {
        (ctx.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager)?.defaultVibrator
    } else {
        ctx.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
    } ?: return
    runCatching { v.vibrate(VibrationEffect.createOneShot(28, VibrationEffect.DEFAULT_AMPLITUDE)) }
}
