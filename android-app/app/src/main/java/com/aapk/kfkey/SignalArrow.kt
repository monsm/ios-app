package com.aapk.kfkey

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.provider.Settings
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.clipRect
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow

/**
 * 靠近指示 —— 外形照 iOS「查找 / FindMy · AirTag 精确查找」那支箭头做, 只借外形, 不借它没有的能力。
 *
 * 诚实边界 (写死在注释里, 否则就是谎报能力):
 * 这把 ZK 锁是普通 BLE, 没有超宽频 (UWB), 也没有到达角 (AoA/AoD), 手机在物理上算不出锁的绝对方位。
 * FindMy 那支能直指 AirTag 的箭头靠的正是 UWB 测向, 抄不了。所以这支箭头由两件真实数据拼成:
 *   1) 旋转 = 手机自己的姿态方位 (TYPE_ROTATION_VECTOR 融合, 不需位置权限), 且**永远夹在前方 ±30°**;
 *   2) 指向 = 本次靠近里"信号最强那一刻手机朝向的方位" —— 靠**转动手机找最强信号** (BLE 能做到的最接近"指向")。
 * 箭头的**填充** = 当前信号 (真 RSSI, 与解锁判据同一份数): 空心底色 → 随信号从下往上灌满绿色,
 * 满绿 = 达武装线 = 可自动开锁。没有外圈 (用户 2026-10-18 明确: 箭头外不要圈圈)。
 *
 * 数值口径做成纯函数 (signalFill / relativeBearing / peakUpdate / distanceMeters): tools/kotlinshadow.js
 * 直接抠这份算术对拍, 免得"看起来对的箭头"与"真的会开的判据"各算各的。
 */

/** 信号填充 0..1: -farDbm..armDbm 线性; rssi>=arm 满; 未读到=0。 */
fun signalFill(rssi: Int?, armDbm: Int = AutoOpenKit.BASE, farDbm: Int = -95): Float {
    if (rssi == null) return 0f
    val lo = farDbm.toFloat()
    val hi = armDbm.toFloat()
    if (hi <= lo) return 0f
    return ((rssi - lo) / (hi - lo)).coerceIn(0f, 1f)
}

/** 目标方位相对当前朝向的差角, 归一到 -180..180。peak=null → 0 (由微扫表示"还不知道")。 */
fun relativeBearing(azimuthDeg: Float, peakDeg: Float?): Float {
    val p = peakDeg ?: return 0f
    var d = (p - azimuthDeg) % 360f
    if (d > 180f) d -= 360f
    if (d < -180f) d += 360f
    return d
}

/** 峰值方位更新 (纯函数): 只在明显更强 (差>1dB) 时改写 —— 广播有抖动, 跟着抖箭头会乱跳。 */
fun peakUpdate(bestRssi: Int?, bestPeak: Float?, rssi: Int, azimuthDeg: Float): Triple<Int?, Float?, Boolean> {
    if (bestRssi == null || rssi > bestRssi + 1) return Triple(rssi, azimuthDeg, true)
    return Triple(bestRssi, bestPeak, false)
}

/**
 * 由 RSSI 反推的**粗略**距离 (米): 对数路径损耗模型, 1 米基准 -59dBm, 指数 n=2.5。
 * 这是估计值不是测距 (BLE RSSI 抖动 ±6dB ⇒ 距离误差很大), 只用来给个"远近"的体感, 不谎称精确。
 * 读不到信号返回 -1 (调用方显示"测距中")。
 */
fun distanceMeters(rssi: Int?, at1m: Float = -59f, n: Float = 2.5f): Float {
    if (rssi == null) return -1f
    val d = Math.pow(10.0, ((at1m - rssi).toDouble()) / (10.0 * n)).toFloat()
    return d.coerceIn(0.1f, 12f)
}

/** 前方/左前方/右前方 (纯函数): 以夹到 ±30° 的相对方位判, 0 附近 = 前方。 */
fun directionLabel(bearingClamped: Float, dead: Float = 18f): String =
    if (bearingClamped < -dead) "左前方" else if (bearingClamped > dead) "右前方" else "前方"

/** 手机姿态: [yaw, pitch, roll] (度)。TYPE_ROTATION_VECTOR 取姿态不需位置权限 (本 App 没申请它)。 */
object HeadingSense {
    fun attitude(ctx: Context): Flow<FloatArray> = callbackFlow {
        val sm = ctx.getSystemService(Context.SENSOR_SERVICE) as? SensorManager
        val sensor = sm?.getDefaultSensor(Sensor.TYPE_ROTATION_VECTOR)
        if (sm == null || sensor == null) { close(); return@callbackFlow }
        val R = FloatArray(9)            // getRotationMatrixFromVector 的输出 (3×3)
        val out = FloatArray(3)          // getOrientation 的输出 (yaw/pitch/roll)
        val listener = object : SensorEventListener {
            override fun onSensorChanged(e: SensorEvent) {
                if (e.sensor.type != Sensor.TYPE_ROTATION_VECTOR) return
                // 必须先把旋转矢量转成 3×3 矩阵再取姿态角。直接把手上的四元数数组喂给
                // getOrientation 会当场 ArrayIndexOutOfBoundsException (它要的是 9 个元素),
                // 而这条路只在真机上走得到 —— 编译器与 CI 都看不见这种错。
                SensorManager.getRotationMatrixFromVector(R, e.values)
                SensorManager.getOrientation(R, out)
                var yaw = Math.toDegrees(out[0].toDouble()).toFloat(); if (yaw < 0f) yaw += 360f
                val pitch = Math.toDegrees(out[1].toDouble()).toFloat()
                val roll = Math.toDegrees(out[2].toDouble()).toFloat()
                trySend(floatArrayOf(yaw, pitch, roll))
            }
            override fun onAccuracyChanged(s: Sensor, a: Int) = Unit
        }
        sm.registerListener(listener, sensor, SensorManager.SENSOR_DELAY_GAME)
        awaitClose { sm.unregisterListener(listener) }
    }
}

/**
 * FindMy/AirTag 式靠近箭头。
 * @param armed 已达武装线 —— 由调用方传入 (与自动开锁判据同一个值), 不在这重算
 * @param busy 开锁在途: 淡化箭头, 免得"正在开"看起来像"还在找"
 * 无外圈: 只有那支空心箭头, 随信号从下往上灌满绿色。
 */
@Composable
fun SignalArrow(
    azimuthDeg: Float,
    peakDeg: Float?,
    rssi: Int?,
    armed: Boolean,
    busy: Boolean,
    pitchDeg: Float = 0f,
    rollDeg: Float = 0f,
    sizeDp: Int = 260,
    modifier: Modifier = Modifier,
) {
    val ctx = LocalContext.current
    val reduceMotion = remember(ctx) {
        runCatching {
            Settings.Global.getFloat(ctx.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f
        }.getOrDefault(false)
    }
    val fill = signalFill(rssi)
    // 方向永远夹在前方 ±30°: 用户口径 —— 箭头基本指前, 只在 ±30° 内随陀螺仪摆动, 不疯转。
    val raw = relativeBearing(azimuthDeg, peakDeg)
    val bearing = raw.coerceIn(-30f, 30f)
    val sweep = if (reduceMotion || peakDeg != null || busy) 0f else
        rememberInfiniteTransition(label = "sweep").animateFloat(
            -8f, 8f, infiniteRepeatable(tween(1500, easing = LinearEasing), RepeatMode.Reverse), label = "sweep",
        ).value
    val line = if (armed) Ok else Accent
    val desc = when {
        rssi == null -> "正在寻找门锁的信号"
        armed -> "信号已满, 可以开锁"
        else -> "信号 " + rssi + " dBm, 还差一点, 转动手机找更强的方向"
    }
    Box(
        modifier = modifier
            .graphicsLayer {
                // 3D 视差: 手机俯仰/横滚让卡片轻微前后倾 (cameraDistance 提供透视), 箭头本身按 ±30° 指向前方。
                rotationZ = bearing + sweep
                rotationX = (pitchDeg * 0.22f).coerceIn(-12f, 12f)
                rotationY = (rollDeg * 0.22f).coerceIn(-12f, 12f)
                cameraDistance = 40f * this.density   // 大一点 = 透视更柔, 箭头只轻微 3D 倾, 不疯摆
                alpha = if (busy) 0.55f else 1f
            }
            .size(sizeDp.dp)
            .semantics { contentDescription = desc },
        contentAlignment = Alignment.Center
    ) {
        Canvas(Modifier.size(sizeDp.dp)) {
            val cx = size.width / 2f
            val cy = size.height / 2f
            val len = size.minDimension * 0.62f
            drawAirTagArrow(cx, cy, len, fill, armed, line)
        }
    }
}

/**
 * 空心箭头 (无外圈): 白色描边轮廓 + 内部从下往上灌的绿色填充。
 * 满绿 = 达武装线。DrawScope 本身就是 Density, 所以 dp.toPx() 直接用。
 */
private fun DrawScope.drawAirTagArrow(cx: Float, cy: Float, len: Float, fill: Float, armed: Boolean, accent: Color) {
    val halfShaft = len * 0.11f
    val barb = len * 0.30f
    val headY = cy - len * 0.06f
    val tipY = cy - len * 0.46f
    val baseY = cy + len * 0.46f
    val arrow = Path().apply {
        moveTo(cx, tipY)
        lineTo(cx + barb, headY)
        lineTo(cx + halfShaft, headY)
        lineTo(cx + halfShaft, baseY)
        lineTo(cx - halfShaft, baseY)
        lineTo(cx - halfShaft, headY)
        lineTo(cx - barb, headY)
        close()
    }
    // 1) 内部填充: 深绿, 从底往上按 fill 灌 (clipRect 只画 fill 高度的那截)
    if (fill > 0.001f) {
        val fillTop = baseY - (baseY - tipY) * fill
        clipRect(left = cx - barb - 4f, top = fillTop, right = cx + barb + 4f, bottom = baseY) {
            drawPath(arrow, color = Color(0xFF0B6B33))
        }
    }
    // 2) 轮廓描边: 白色 (达武装线时更亮 + 外发光), 空心感就来自这里
    val outline = if (armed) Color.White else Color.White.copy(alpha = 0.82f)
    if (armed) {
        drawPath(arrow, color = Ok.copy(alpha = 0.28f), style = Stroke(width = len * 0.14f, cap = StrokeCap.Round, join = StrokeJoin.Round))
    }
    drawPath(arrow, color = outline, style = Stroke(width = len * 0.05f, cap = StrokeCap.Round, join = StrokeJoin.Round))
    // 3) 箭头上方的小圆点 (AirTag 精确查找那个"目标点")
    val dotY = tipY - len * 0.16f
    drawCircle(color = Color.White.copy(alpha = 0.25f), radius = len * 0.10f, center = Offset(cx, dotY))
    drawCircle(color = Color.White.copy(alpha = 0.92f), radius = len * 0.055f, center = Offset(cx, dotY))
}
