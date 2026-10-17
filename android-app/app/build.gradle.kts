import java.time.Instant
import java.time.ZoneId
import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

// ============ 编译号 = 构建时刻 (东八区) ============
// 口径: 一次构建出一个号, 单调递增 ⇒ 每次 CI 产物都能**原地覆盖安装** (配合下面随仓库走的签名)。
//
// 为什么 versionCode 不能直接拿 yyyyMMddHHmm: 它是 **32 位 Int** (上界 2147483647),
// 而 202610171833 早就溢出 —— 那不是"看着别扭", 是装不上。所以:
//   versionCode = 距 2026-01-01 00:00 (东八区) 的秒数 (单调、同一秒内唯一; 按此基准,
//                 int32 触界时刻 = 2094-01-19 03:14, 下面那道闸会在那之前直接报错)
//   versionName = 1.0.<yyyyMMdd.HHmmss>  ← 与 iOS 的 CFBundleVersion **同一个串**
//
// 同一次 push 的 ipa 与 apk 必须共享同一个时刻: CI 顶部 stamp 作业算一次, 两个 job 经
// KF_BUILD_TS (epoch 秒) / KF_BUILD_STAMP 传进来。本地手编没有这两个变量时回落"构建当刻"。
val buildZone: ZoneId = ZoneId.of("Asia/Shanghai")
val buildBaseSec: Long = ZonedDateTime.of(2026, 1, 1, 0, 0, 0, 0, buildZone).toEpochSecond()

// ⚠ 写 project.providers 而不是裸 providers: 顶层函数会编成脚本类的成员方法, 那里看不见
//   脚本的隐式 Project 接收者; 顶层 val 虽然看得见, 但只有 CI 能验, 所以取与本文件
//   signingConfigs 里 project.findProperty 同一种绝对稳的写法 (少一处靠接收者推断的地方)。
//
// providers 而不是 System.getenv: 将来若开 configuration cache, 直接读环境变量不会让缓存失效
//   —— CI 换一次 push 仍复用旧编译号, 覆盖安装"看着成功"其实装的是上一版。登记成输入才安全。
val kfBuildTsRaw: String = project.providers.environmentVariable("KF_BUILD_TS").orNull.orEmpty()
val kfBuildEpochSec: Long = if (kfBuildTsRaw.isBlank()) {
    Instant.now().epochSecond   // 本地手编 (没有这个环境变量): 回落"构建当刻"
} else {
    kfBuildTsRaw.trim().toLongOrNull()
        ?: throw GradleException("KF_BUILD_TS 必须是整数 epoch 秒, 现在是: \"$kfBuildTsRaw\"")
}

// 只取一次时刻、只格式化一次: versionCode 与 versionName 共用 kfBuildEpochSec,
// println 与 versionName 共用 kfStampText。各取各的会跨秒 —— 包内两处版本号差一秒,
// 就变成"这次到底构建于何时"的悬案, 也正是核对步骤查无实据的那种坑。
val kfStampText: String = Instant.ofEpochSecond(kfBuildEpochSec).atZone(buildZone)
    .format(DateTimeFormatter.ofPattern("yyyyMMdd'.'HHmmss"))

// 配置期打印: CI 拿它核对"gradle 用的确实是 stamp 作业那一个时刻"。
// 少了这条, KF_BUILD_TS 万一没传进来 (env 写错名/stamp 作业改名), gradle 会**静默**回落到
// "构建当刻" —— 号照样单调、照样能装, 但 ipa 与 apk 的时刻不再相同, 而这正是这次要解决的问题。
println("KfBuildStamp versionCode=${kfBuildEpochSec - buildBaseSec} versionName=1.0.$kfStampText")

android {
    namespace = "com.aapk.kfkey"
    // 与 GitHub ubuntu 镜像自带的平台对齐, 免得 CI 现下载
    compileSdk = 35

    defaultConfig {
        applicationId = "com.aapk.kfkey"
        // 用户口径: 最低 Android 13
        minSdk = 33
        targetSdk = 34   // 刻意停在 34: 35 会强制 edge-to-edge, 而本界面没有做 inset 适配
        // versionCode = 距 2026-01-01 00:00 (东八区) 的秒数: 单调递增 ⇒ 新包总能覆盖旧包。
        // 界限在**截断之前**判: Long.toInt() 溢出是静默回绕, 先转再查等于没查。
        versionCode = run {
            val diff = kfBuildEpochSec - buildBaseSec
            if (diff <= 0L) throw GradleException("versionCode 非正数 ($diff) — 构建时刻早于 2026-01-01 基准?")
            if (diff > Int.MAX_VALUE - 1L) throw GradleException("versionCode 触到 int32 上界 ($diff) — 按 2026-01-01 基准应到 2094-01-19 才会碰这里, 说明时钟或基准错了")
            diff.toInt()
        }
        // versionName = 人读时刻, 与 iOS 的 CFBundleVersion 同一串 (yyyyMMdd.HHmmss, 东八区):
        // 两端产物文件名/包内版本号互相对得上, 出问题能确定"这台手机上装的是哪一次 push"。
        versionName = "1.0.$kfStampText"
    }

    signingConfigs {
        // 固定签名的仓库文件随仓库提交: CI 每次都是全新的 runner, 默认 debug.keystore 每台都不一样,
        // 于是"装一次就不让升级"。选一个随仓库走的签名, 之后每次构建都能原地覆盖安装。
        // ⚠ 这是自签的**安装用**密钥 (给 AltStore/直接安装用的), 不是 Google Play 上传密钥 ——
        //   真要上架 Play 得另建并自己保存。
        create("kf") {
            storeFile = file("keystore/kfkey.p12")
            storeType = "PKCS12"
            storePassword = (project.findProperty("KF_STORE_PW") as String?) ?: "kfkey2026"
            keyAlias = "kfkey"
            keyPassword = (project.findProperty("KF_KEY_PW") as String?) ?: "kfkey2026"
        }
    }

    buildTypes {
        debug {
            signingConfig = signingConfigs.getByName("kf")
        }
        release {
            signingConfig = signingConfigs.getByName("kf")
            // 这是个两人用的极简工具, 不混淆也能保持体积与崩溃栈可读
            isMinifyEnabled = false
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
    }
    buildFeatures {
        compose = true
    }
    packaging {
        resources.excludes += "/META-INF/{AL2.0,LGPL2.1}"
    }
}

dependencies {
    implementation(platform("androidx.compose:compose-bom:2024.10.01"))
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-graphics")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.activity:activity-compose:1.9.3")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.8.7")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0")
    // 扫码: zxing-android-embedded 自带扫码页, 不依赖 Google Play 服务 (国产机也能用)
    implementation("com.journeyapps:zxing-android-embedded:4.3.0")
    debugImplementation("androidx.compose.ui:ui-tooling")
}
