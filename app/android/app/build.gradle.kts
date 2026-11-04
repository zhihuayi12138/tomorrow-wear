plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.mingchuan.mingtian_chuanshenme"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.mingchuan.mingtian_chuanshenme"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

// 试过把 flutter_onnxruntime 锁死的 onnxruntime-android(1.28.0) 换成
// 体积小得多的 onnxruntime-mobile(1.18.0)：arm64 的 .so 能从 27 MB 降到 3.6 MB。
// **结论是换不了**，两条都试过：
//   1. 直接用 .onnx → `ONNX format model is not supported in this build`
//      （mobile 版只认预编译的 .ort 格式）；
//   2. 转成 .ort 再喂 → `Could not find an implementation for MaxPool(11)`
//      （mobile 版砍掉了 opset 11 的 MaxPool 内核，而 u2netp 就是 opset 11）。
// 所以还是用完整版，靠 `--split-per-abi` 分架构出包来控制体积：
// 通用包 160 MB，只给 arm64 的那份是 71 MB，2020 年后的手机都是 arm64。

flutter {
    source = "../.."
}
