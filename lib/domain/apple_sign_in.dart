/// Sign in with Apple の規則（docs/MOBILE-APP-DESIGN.md 5-6）
///
/// **ここに置いたのは 2 つ。どちらも間違えても実行時に気づけない。**
///
/// | 規則 | 間違えるとどうなるか |
/// | --- | --- |
/// | ボタンを出す条件 | 画面が `Platform.isIOS` を各所で書くと、**`flutter build web` が `dart:io` を解決できずに落ちる** |
/// | nonce の渡し分け | Apple と Firebase を取り違えると `invalid-credential`。**実機で試すまで分からない** |
///
/// **規則をここへ切り出したのは、テストが本物を見るため。**
/// 以前は回帰テストがテストファイル内の写しを検証しており、本番の実装が
/// 変わっても緑のままだった（監査 第4回）。`lib/domain/signup_locale.dart`
/// と同じ形にしてある。
library;

import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show TargetPlatform;

/// 「Apple でサインイン」を出してよいか。
class AppleSignInPolicy {
  const AppleSignInPolicy._();

  /// 出してよいのは **iOS のときだけ**。
  ///
  /// 審査ガイドライン 4.8 が求めているのは iOS アプリの話で、Web と
  /// Android で同じことをするには Apple 側に Services ID と戻り先 URL の
  /// 登録（ドメイン検証つき）が別途要る。
  ///
  /// **判定をこの 1 箇所に閉じてある。画面は `isAvailable` を見るだけにする。**
  /// 各画面が `Platform.isIOS` を書くと、`dart:io` が共通コードへ漏れて
  /// **`flutter build web` が落ちる**（docs/MOBILE-APP-DESIGN.md 5-5）。
  /// `defaultTargetPlatform` は Web でも iOS を返す（Safari／iPhone）ので、
  /// **`isWeb` を先に外すこと。** 外し忘れると Web に出て、押しても
  /// 何も起きないボタンになる。
  static bool isAvailable({
    required bool isWeb,
    required TargetPlatform platform,
  }) => !isWeb && platform == TargetPlatform.iOS;
}

/// Apple に渡す nonce（docs/MOBILE-APP-DESIGN.md 5-6）。
///
/// **横取りされた ID トークンを弾くための仕組みなので、省略できない。**
class AppleNonce {
  const AppleNonce._();

  /// nonce に使ってよい文字。Apple は URL に載る形を求める。
  static const String alphabet =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._';

  /// 生の nonce を作る。**これを Firebase に渡す。**
  ///
  /// `Random.secure()` を使う。`Random()` は種が推測でき、
  /// **推測できる nonce は nonce として機能しない。**
  static String random([int length = 32]) {
    final rand = Random.secure();
    return List.generate(
      length,
      (_) => alphabet[rand.nextInt(alphabet.length)],
    ).join();
  }

  /// 生の nonce を SHA-256 にする。**これを Apple に渡す。**
  ///
  /// **逆にすると Firebase の検証が失敗して `invalid-credential` になる。**
  /// Apple は受け取ったハッシュを ID トークンに載せて返し、Firebase は
  /// 生の値を自分でハッシュして突き合わせる。だから Apple 側にだけ
  /// ハッシュを渡す。
  static String hashed(String rawNonce) =>
      sha256.convert(utf8.encode(rawNonce)).toString();
}
