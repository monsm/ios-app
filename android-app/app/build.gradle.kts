plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

android {
    namespace = "com.aapk.kfkey"
    // 与 GitHub ubuntu 镜像自带的平台对齐, 免得 CI 现下载
    compileSdk = 35

    defaultConfig {
        applicationId = "com.aapk.kfkey"
        // 用户口径: 最低 Android 13
        minSdk = 33
        targetSdk = 34   // 刻意停在 34: 35 会强制 edge-to-edge, 而本界面没有做 inset 适配
        versionCode = 1
        versionName = "1.0"
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
