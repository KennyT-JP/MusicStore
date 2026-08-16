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
    // START: FlutterFire Configuration
    // **google-services.json を置くだけでは読まれない。** このプラグインが
    // 変種ごとに JSON を探して、`R.string.default_web_client_id` などの
    // リソースへ展開する。**Google ログインが serverClientId をそこから
    // 読む**ので、適用を外すと「ビルドは通るのにログインだけ失敗する」。
    // 版は android/settings.gradle.kts の pluginManagement 側で固定。
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// **AGP / Kotlin / Gradle の版は android/settings.gradle.kts で固定してある。**
// **AGP を 9 に上げると release ビルドが作れなくなる**（file_picker と
// audio_session の要求が正面から衝突する）。理由は settings.gradle.kts の
// plugins ブロックの上に書いた。上げる前に必ず読むこと。

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

    // **本番と検証を「別のアプリ」として作る（2026-08-16。設計 5-2）。**
    //
    // **なぜ分けたか。** Google ログインは「パッケージ名＋署名鍵の SHA-1」の
    // 組み合わせで OAuth クライアントを作る。この組み合わせは **Firebase
    // プロジェクトをまたいで一意**でなければならず、本番が先に押さえると
    // 同じパッケージ名・同じ鍵のままでは検証プロジェクト側に作れなくなる
    // （Firebase が `Oauth client already exists in a different project`
    //   と返す。Session Concierge が実際に踏んでいる）。
    // **あとから分けるには applicationId を変えるしかないが、公開後の
    // applicationId は変更できない。** だから公開前のいま分ける。
    //
    // **副次的な利点のほうが大きい。** 識別子が変わるので、**本番と検証を
    // 同じ端末へ並べて入れられる**。分けないと入れ替えになり、片方を試す
    // たびにもう片方が消える。
    //
    // **`namespace` は変えない。** あちらは Kotlin / R クラスの置き場で、
    // 変えるとソースの参照が全部ずれる。変えるのは `applicationId` だけ。
    //
    // **`google-services.json` は変種ごとに要る**（下の `com.google.gms.
    // google-services` プラグインが読む）。置き場所は:
    //
    //   prod → android/app/google-services.json          （既定の置き場所）
    //   dev  → android/app/src/dev/google-services.json  （フレーバー別）
    //
    // **prod のぶんが「既定の置き場所」なのは、`flutterfire configure` の
    // 出力先がそこだから**（`scripts/configure-firebase.mjs` は出力先を
    // 指定しない）。ただしこの置き場所は**どの変種からも読める代替**でも
    // あるので、**`src/dev/` のファイルを消すと dev ビルドが黙って本番の
    // 設定で組み上がる**（エラーは出ない。実行して初めて本番に繋がる）。
    // **test/domain/android_platform_test.dart が両方の実在と、中の
    // `package_name` がフレーバーの applicationId と一致することを見張る。**
    //
    // **iOS には dev フレーバーを作らない**（設計 3-4）。Android は
    // `applicationIdSuffix` だけで済むが、iOS は Xcode の configuration と
    // scheme を増やす必要がある。検証は Web と Android の dev で行う。
    flavorDimensions += "env"
    productFlavors {
        create("prod") {
            dimension = "env"
            // 既定。applicationId は defaultConfig のまま（公開後は変更不可）。
        }
        create("dev") {
            dimension = "env"
            // jp.sessionconcierge.trackcabinet.dev
            // **android/app/src/dev/google-services.json に登録済みの
            // パッケージ名と一致していること。** 食い違うと Google ログインが
            // 「その端末のアプリは知らない」で失敗する。
            applicationIdSuffix = ".dev"
            // 手本（Session Concierge）はここで resValue の app_name を
            // 差し替えて端末のアプリ一覧で見分けられるようにしているが、
            // 音源創庫の AndroidManifest.xml は android:label に文字列を
            // 直接書いているため、いま置いても効かない。**表示名を分ける
            // なら、まず manifest を @string/app_name に変えること。**
        }
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
