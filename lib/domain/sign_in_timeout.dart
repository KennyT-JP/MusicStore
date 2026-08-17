/// Web のログインポップアップに上限をつける（監査 第5回・AP-12）
///
/// **`signInWithPopup` は、利用者がポップアップを放置すると解決しない。**
/// 待ち手（画面）はその間ずっと `_busy` のままで、画面全体が固まって
/// 復帰できない。ここで待ち時間に上限を設け、超えたら例外にして
/// **待ち手を解放する**。
///
/// **切り出したのはテストのため。** `Future.timeout` は時計に依存するので、
/// 本番の経路に直接書くと機械的に確かめられない。純粋な関数にして
/// `fakeAsync` で上限の前後を固定する（test/domain/sign_in_timeout_test.dart）。
library;

import 'dart:async';

/// ポップアップを待つ上限。
///
/// **Web のポップアップ専用。** email/password や、ネイティブの
/// `google_sign_in` 経路には付けない（それぞれ別の入口で完結する）。
const Duration kWebSignInTimeout = Duration(seconds: 90);

/// [op] を [timeout] の上限つきで待つ。
///
/// 時間内に終われば結果をそのまま返す。上限を過ぎたら
/// [SignInTimeoutException] を投げる。**[op] 自体は止められない**
/// （ポップアップの Future は解決しないまま残る）——目的は結果を
/// 打ち切ることではなく、**待っている画面を解放すること**。
Future<T> withSignInTimeout<T>(
  Future<T> Function() op, {
  Duration timeout = kWebSignInTimeout,
}) {
  return op().timeout(
    timeout,
    onTimeout: () => throw const SignInTimeoutException(),
  );
}

/// ログインのポップアップが、上限（[kWebSignInTimeout]）までに
/// 終わらなかったとき。
///
/// **利用者向けの文言は画面側の汎用メッセージに任せる**
/// （sign_in_screen.dart の `_run` が `catch` で受け、`errorGeneric`＝
/// 「しばらくしてからもう一度お試しください」に落とす）。ここが持つのは、
/// 「詳細」に出す技術的な手がかりだけ。
class SignInTimeoutException implements Exception {
  const SignInTimeoutException();

  @override
  String toString() =>
      'SignInTimeoutException: ログインの待ち時間が上限を超えました';
}
