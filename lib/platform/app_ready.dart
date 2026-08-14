/// 「アプリの準備が整った」ことを、外側（HTML）へ伝える
///
/// `web/index.html` はロゴ入りの読み込み画面を出しており、
/// **`window.appReady()` が呼ばれるまで消しません**（2026-08-14）。
///
/// 以前は Flutter の最初の描画で消していましたが、そのとき出るのは
/// ログイン状態の復元を待つ画面で、**いちばん見せたいところで
/// 読み込み画面を自分から消していました**。
///
/// **Web 以外では何もしません。** テストは Dart VM で走るので、
/// ここを条件付きの取り込みにしておかないと `dart:js_interop` を
/// 解決できずに落ちます。
library;

export 'app_ready_stub.dart'
    if (dart.library.js_interop) 'app_ready_web.dart';
