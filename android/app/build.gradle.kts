import java.util.Properties

// **署名鍵は、リポジトリに入れずに読み込む（2026-08-15）。**
//
// `android/key.properties` があればそれを使い、無ければデバッグ用の鍵で
// 署名する（`flutter run --release` が動くようにするため）。
// **鍵とパスワードは依頼者しか作れない**ので、ここでは受け口だけ用意する。
//
// 作り方（配布する段になってから）:
//
//   keytool -genkey -v -keystore upload-keystore.jks -storetype JKS //     -keyalg RSA -keysize 2048 -validity 10000 -alias upload
//
//   android/key.properties に次を書く（**コミットしない**）:
//     storeFile=<upload-keystore.jks への絶対パス>
//     storePassword=...
//     keyPassword=...
//     keyAlias=upload
//
// **鍵を失くすと、同じアプリとして更新できなくなる。** 手元だけでなく
// 安全な場所へ控えを取ること（Play アプリ署名を使う場合も、
// アップロード鍵は必要）。
val keystoreProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.musiclist.music_list_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.musiclist.music_list_app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            // key.properties が無いときは何も設定しない（下で debug に倒す）。
            val storePath = keystoreProperties.getProperty("storeFile")
            if (storePath != null) {
                storeFile = file(storePath)
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // **鍵があれば本番用、無ければデバッグ用。**
            // 無い状態でも `flutter run --release` は動かせるようにしておく。
            // ただし**デバッグ鍵で署名したものはストアへ出せない。**
            signingConfig = if (keystoreProperties.getProperty("storeFile") != null) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
