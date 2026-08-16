import java.util.Properties
import java.io.FileInputStream

// **署名鍵は、リポジトリに入れずに読み込む（2026-08-15）。**
//
// `android/key.properties` があればそれを使う。鍵の無い環境（CI・他の PC）でも
// debug ビルド（`flutter run` など）は普通に動く必要があるので、ファイルの
// 有無で分岐する。ただし **release だけは鍵が無ければ作らせない**（下の判定）。
// **鍵とパスワードは依頼者しか作れない**ので、ここでは受け口だけ用意する。
//
// 作り方（配布する段になってから）:
//
//   keytool -genkey -v -keystore upload-keystore.jks -storetype JKS \
//     -keyalg RSA -keysize 2048 -validity 10000 -alias upload
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
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    FileInputStream(keystorePropertiesFile).use { keystoreProperties.load(it) }
}

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// **鍵が無いまま release ビルドを通さない（2026-08-16）。**
//
// 以前は鍵が無いとデバッグ署名に落としていたが、そのせいで key.properties の
// 無い環境の `assembleRelease` が**エラーも警告も出さずにデバッグ鍵で署名された
// 成果物を出していた**。Play は debug 署名を弾くが、APK を直接配る経路では
// それが本番として流通しうる。ここで明示的に止める。
//
// **判定を buildTypes の中に書いてはいけない。** buildTypes ブロックは debug
// ビルドでも設定段階で必ず評価されるので、そこで throw すると鍵を持たない
// 開発機で `flutter run`（debug）まで落ちる。実行しようとしているタスク名を
// 見て、release を作ろうとしたときだけ止める。
// （`gradlew build` のようにタスク名へ Release が出ない呼び方をした場合は
//   ここを素通りするが、その先で AGP が「storeFile が無い」と落ちる。
//   いずれにせよデバッグ鍵の成果物は出ない。）
//
// 出来上がったものは `keytool -printcert -jarfile <AAB/APK>` で確かめる。
// **`CN=Android Debug` と出たら失敗。**
val wantsReleaseBuild =
    gradle.startParameter.taskNames.any { it.contains("Release") }
if (wantsReleaseBuild && !keystorePropertiesFile.exists()) {
    throw GradleException(
        "release ビルドに必要な android/key.properties が見つかりません。\n" +
        "鍵もパスワードもリポジトリには入れていないため、この環境には自動では\n" +
        "用意されません。配布用の鍵と key.properties の作り方は、このファイルの\n" +
        "冒頭のコメントと docs/MOBILE-APP-DESIGN.md の 5-10 を参照してください。\n" +
        "（動作確認だけなら flutter run / assembleDebug を使ってください。\n" +
        "  以前はここでデバッグ署名に落としていましたが、デバッグ鍵の成果物が\n" +
        "  本番として配られる事故を避けるため、失敗させる方に変えました。）")
}

android {
    // **namespace は変えない。** ここは Kotlin / R クラスの置き場で、
    // 変えるとソースの参照が全部ずれる（MainActivity.kt の場所もここに従う）。
    // ストアと端末が見るアプリの同一性は下の applicationId が決める。
    namespace = "com.musiclist.music_list_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // **Play ストアでのアプリ識別子。公開後は変更不可**
        // （docs/MOBILE-APP-DESIGN.md 3-3）。連絡先ドメイン
        // session-concierge.jp 由来。applicationId はハイフンを使えないため
        // 詰めた形にしてある。iOS の Bundle ID も同じ文字列。
        //
        // **namespace とは別の値であること**（同 3-4）。Google ログインは
        // 「パッケージ名＋署名鍵の SHA-1」で OAuth クライアントを作り、その
        // 組み合わせは Firebase プロジェクトをまたいで一意でなければならない。
        applicationId = "jp.sessionconcierge.trackcabinet"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            // key.properties が無ければ何も設定しない。release を作ろうと
            // した場合はファイル冒頭の判定で既に止まっているので、ここへ
            // 来るのは debug ビルド＝この設定が使われない場合だけ。
            if (keystorePropertiesFile.exists()) {
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // **release は配布用の署名しか使わない。** 鍵の無い環境で
            // デバッグ署名に落とす分岐は廃止した（理由はファイル冒頭）。
            // 鍵が無い状態でここが実際に使われることは無い（冒頭で停止する）。
            signingConfig = signingConfigs.getByName("release")
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
