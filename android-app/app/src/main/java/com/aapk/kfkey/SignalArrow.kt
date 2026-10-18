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
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import kotlin.math.cos
import kotlin.math.sin
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow

/**
 * 靠近指示 —— 外形照 iOS「查找 / FindMy」那支箭头做, 只借外形, 不借它没有的能力。
 *
 * 诚实边界 (写死在注释里, 否则就是谎报能力):
 * 这把 ZK 锁是普通 BLE, 没有超宽频 (UWB), 也没有到达角 (AoA/AoD), 手机在物理上算不出锁的绝对方位。
 * FindMy 那支能直指 AirTag 的箭头靠的正是 UWB 测向, 抄不了。所以这支箭头由两件真实数据拼成:
 *   1) 旋转 = 手机自己的姿态方位 (TYPE_ROTATION_VECTOR 融合, 不需位置权限);
 *   2) 指向 = 本次靠近里"信号最强那一刻手机朝向的方位" —— 靠**转动手机找最强信号**,
 *      这是 BLE 能做到的最接近"指向"的东西 (FindMy 在无 UWB 的老设备上也这么退化)。
 * 环的填充 = 当前信号 (真 RSSI, 与解锁判据同一份数); 满弧 = 达武装线 = 可自动开锁 = 满绿。
 *
 * 数值口径做成纯函数 (signalFill / relativeBearing / peakUpdate): tools/kotlinshadow.js 直接抠这份算术对拍,
 * 免得"看起来对的箭头"与"真的会开的判据"各算各的 —— 本仓这类分歧最后都变成用户看到的假线索。
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

/** 手机朝向流 (度, 0..360, 磁北 0)。TYPE_ROTATION_VECTOR 取方位不需位置权限 (本 App 没申请它)。 */
object HeadingSense {
    fun azimuth(ctx: Context): Flow<Float> = callbackFlow {
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
                var deg = Math.toDegrees(out[0].toDouble()).toFloat()
                if (deg < 0f) deg += 360f
                trySend(deg)
            }
            override fun onAccuracyChanged(s: Sensor, a: Int) = Unit
        }
        sm.registerListener(listener, sensor, SensorManager.SENSOR_DELAY_UI)
        awaitClose { sm.unregisterListener(listener) }
    }
}

/**
 * @param armed 已达武装线 —— 由调用方传入 (与自动开锁判据同一个值), 不在这重算
 * @param busy 开锁在途: 淡化箭头并停微扫, 免得"正在开"看起来像"还在找"
 */
@Composable
fun SignalArrow(
    azimuthDeg: Float,
    peakDeg: Float?,
    rssi: Int?,
    armed: Boolean,
    busy: Boolean,
    modifier: Modifier = Modifier,
) {
    val ctx = LocalContext.current
    val reduceMotion = remember(ctx) {
        runCatching {
            Settings.Global.getFloat(ctx.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f
        }.getOrDefault(false)
    }
    val fill = signalFill(rssi)
    val bearing = relativeBearing(azimuthDeg, peakDeg)
    val sweep = if (reduceMotion || peakDeg != null || busy) 0f else
        rememberInfiniteTransition(label = "sweep").animateFloat(
            -14f, 14f, infiniteRepeatable(tween(1400, easing = LinearEasing), RepeatMode.Reverse), label = "sweep",
        ).value
    val line = if (armed) Ok else Accent
    val desc = when {
        rssi == null -> "正在寻找门锁的信号"
        armed -> "信号已满, 可以开锁"
        else -> "信号 " + rssi + " dBm, 还差一点, 转动手机找更强的方向"
    }
    Box(modifier = modifier.semantics { contentDescription = desc }, contentAlignment = Alignment.Center) {
        Canvas(Modifier.size(208.dp)) {
            val cx = size.width / 2f
            val cy = size.height / 2f
            val r = size.minDimension / 2f - 8.dp.toPx()
            drawCircle(
                color = Color.White.copy(alpha = 0.08f), radius = r, center = Offset(cx, cy),
                style = Stroke(width = 2.dp.toPx(), cap = StrokeCap.Round),
            )
            if (fill > 0.001f) {
                val ir = r - 3.dp.toPx()
                drawArc(
                    color = line.copy(alpha = if (armed) 1f else 0.85f),
                    startAngle = -90f, sweepAngle = 360f * fill, useCenter = false,
                    topLeft = Offset(cx - ir, cy - ir), size = Size(ir * 2f, ir * 2f),
                    style = Stroke(width = 4.dp.toPx(), cap = StrokeCap.Round),
                )
            }
            for (k in 0 until 12) {
                // 同齿轮那处: Offset 只吃 Float, toRadians 给的 Double 必须转回来
                val a = Math.toRadians((k * 30 - 90).toDouble()).toFloat()
                val inner = r - 6.dp.toPx()
                val outer = r - if (k % 3 == 0) 13.dp.toPx() else 10.dp.toPx()
                drawLine(
                    color = Color.White.copy(alpha = if (k % 3 == 0) 0.22f else 0.12f),
                    start = Offset(cx + cos(a) * inner, cy + sin(a) * inner),
                    end = Offset(cx + cos(a) * outer, cy + sin(a) * outer),
                    strokeWidth = 1.5f.dp.toPx(), cap = StrokeCap.Round,
                )
            }
            rotate(bearing + sweep, pivot = Offset(cx, cy)) {
                drawHollowTriangleWithGyro(
                    cx, cy, r - 22.dp.toPx(), 
                    line.copy(alpha = if (busy) 0.5f else 1f),
                    azimuthDeg  // Pass actual gyro yaw
                )
                
                // Outer circle ring background (FindMy style)
                drawCircle(
                    color = Accent.copy(alpha = 0.1f),
                    radius = r - 10.dp.toPx(),
                    center = Offset(cx, cy),
                    style = androidx.compose.ui.graphics.drawscope.Stroke(width = 2.dp.toPx())
                )
            }
            drawCircle(color = Ink.copy(alpha = 0.9f), radius = 3.dp.toPx(), center = Offset(cx, cy))
        }
        
        // Glow effect when signal > 70% (like AirTag strong signal)

        if (fill > 0.7f && peakDeg != null) {

            Canvas(modifier.size(208.dp)) {

                val glowRadius = (size.minDimension / 2f - 22.dp.toPx()) * 1.5f

                drawCircle(

                    color = line.copy(alpha = 0.15f),

                    radius = glowRadius,

                    center = Offset(size.width / 2f, size.height / 2f)

                )

            }

        }
    }
}
/** FindMy 式箭头: 细腰长身, 尖端朝上 (0°)。DrawScope 本身就是 Density, 所以 8.dp.toPx() 直接用。 */
private fun DrawScope.drawFindArrow(cx: Float, cy: Float, len: Float, color: Color) {
    val w = len * 0.16f
    val tip = cy - len / 2f
    val base = cy + len / 2f
    val p = Path().apply {
        moveTo(cx, tip)
        lineTo(cx + w, cy)
        lineTo(cx + w * 0.42f, cy)
        lineTo(cx + w * 0.42f, base)
        lineTo(cx - w * 0.42f, base)
        lineTo(cx - w * 0.42f, cy)
        lineTo(cx - w, cy)
        close()
    }
    drawPath(p, color)
}
/** Hollow triangle arrow with 3D gyro rotation + green stroke effect */
private fun DrawScope.drawHollowTriangleWithGyro(
    cx: Float, 
    cy: Float, 
    len: Float, 
    color: Color,
    gyroYaw: Float
) {
    val strokeWidth = 6.dp.toPx()
    val halfWidth = len * 0.12f
    
    // Create hollow triangle path (stroke only, no fill)
    val arrowPath = Path().apply {
        moveTo(cx, cy - len/2)      // Top tip
        lineTo(cx + halfWidth*0.3f, cy + len/4)  // Lower right inner point
        lineTo(cx + halfWidth, cy + len/2)       // Bottom right corner
        lineTo(cx, cy + len/3)           // Middle indent (V shape)
        lineTo(cx - halfWidth, cy + len/2)       // Bottom left corner
        lineTo(cx - halfWidth*0.3f, cy + len/4)  // Upper left inner point
        close()                          // Close for stroke but won't fill
    }
    
    // Rotate based on gyro yaw for 3D directional feel (±30° range)
    val adjustedAngle = ((gyroYaw % 360) - 180).coerceIn(-30f, 30f).toDouble()
    rotate(adjustedAngle.toFloat(), pivot = Offset(cx, cy)) {
        // Stroke only → hollow arrow (no fill)
        drawPath(
            arrowPath,
            color = color,
            style = androidx.compose.ui.graphics.drawscope.Stroke(width = strokeWidth)
        )
    }
    
    // Small center dot marker
    drawCircle(
        color = color,
        radius = 2.dp.toPx(),
        center = Offset(cx, cy)
    )
}
