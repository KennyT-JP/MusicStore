/// 登録したときに保存する表示言語の決め方（仕様書 2 章）
///
/// アプリの表示言語は `users.locale` を見て決まる（lib/app.dart）。
/// 登録の瞬間にどの値を書くかの規則をここに置き、
/// 実際の書き込み（auth_repository.dart）はこれを呼ぶ。
///
/// **規則をここへ切り出したのは、テストが本物を見るため。**
/// 以前は回帰テストがテストファイル内の写しを検証しており、
/// 本番の実装が変わっても緑のままだった（監査 第4回）。
library;

/// 表示言語の決定。
class SignupLocalePolicy {
  const SignupLocalePolicy._();

  /// このアプリが表示に対応している言語。
  static const Set<String> supported = {'ja', 'en'};

  /// 保存する表示言語を決める。
  ///
  /// いま画面に出ている言語をそのまま残す。扱わない言語（中国語・
  /// 韓国語など）は**英語に倒す**。日本語に倒すと、読めない言語で
  /// 固定されてしまう（監査 第3回）。
  static String localeFor(String languageCode) =>
      supported.contains(languageCode) ? languageCode : 'en';
}
