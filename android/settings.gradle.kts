pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

// **AGP は 8 系のまま。9 に上げないこと（2026-08-16）。**
//
// **上げると Android の release ビルドが作れなくなる。** 理由は 1 行では
// 書けないので、次の人が「新しいほうがよかろう」で上げてしまわないよう
// 経緯ごと残す。**test/domain/android_platform_test.dart が 8 系であることを
// 見張っている**（この段落を読まずに上げても、テストが赤くなって止まる）。
//
// AGP 9 は Kotlin の適用方法を変え、`android.builtInKotlin` という
// **プロジェクト全体にひとつだけ**のスイッチで決まるようになった。
// ところが依存しているプラグインの要求が正面から衝突する:
//
//   - `file_picker` … AGP 9 では Kotlin プラグインを自分で適用しないため、
//     builtInKotlin を切っていると Kotlin ソースがコンパイルされない
//   - `audio_session` … 逆に「AGP 9 では（自前の Kotlin 適用は）不要」と
//     判断して、適用しようとすると拒否する
//
// **どちらに倒しても片方が壊れる。** スイッチは 1 つしかないので、
// 片方を直すもう片方が必ず落ちる。逃げ道は無い。
//
// そこで **Session Concierge と同じ、出荷実績のある組み合わせ**に揃えた。
// この 3 つは互いに噛み合っているので、**1 つだけ動かさないこと**:
//
//   - AGP                   8.11.1（この下の行）
//   - Kotlin                2.2.20（同じく下の行）
//   - Gradle wrapper        8.14  （android/gradle/wrapper/gradle-wrapper.properties）
//
// **上げ直すなら、まず `file_picker` と `audio_session` の両方が AGP 9 に
// 対応した版を出したことを確かめてから。** 手元で確かめる方法は
// `flutter build apk --release` を通しきること。**`flutter run`（debug）は
// 通ってしまう**ので、debug が動いたことを根拠にしないこと。
plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.11.1" apply false
    // START: FlutterFire Configuration
    id("com.google.gms.google-services") version("4.4.4") apply false
    // END: FlutterFire Configuration
    id("org.jetbrains.kotlin.android") version "2.2.20" apply false
}

include(":app")
