/// Firebase の接続設定（仕様書 12.2）
///
/// **このファイルはプレースホルダーです。**
/// Firebase プロジェクトを作成したら、次の手順で実際の値に置き換えてください。
///
/// ```sh
/// dart pub global activate flutterfire_cli
///
/// # 検証環境
/// flutterfire configure \
///   --project=<検証用プロジェクト ID> \
///   --out=lib/env/firebase_options_staging.dart \
///   --platforms=web,android,ios
///
/// # 本番環境
/// flutterfire configure \
///   --project=<本番用プロジェクト ID> \
///   --out=lib/env/firebase_options_prod.dart \
///   --platforms=web,android,ios
/// ```
///
/// 生成された 2 つのファイルを import し、[DefaultFirebaseOptions.current] で
/// [AppEnvironment] に応じて振り分けます。
///
/// なお Firebase の Web 設定値（apiKey 等）は公開前提の識別子であり、
/// これ自体は秘密情報ではありません。アクセス制御はセキュリティルール
/// （firestore.rules / storage.rules）で行います（仕様書 13.5）。
library;

import 'package:firebase_core/firebase_core.dart';

import 'app_environment.dart';

/// 環境に応じた Firebase の接続設定。
class DefaultFirebaseOptions {
  const DefaultFirebaseOptions._();

  /// 現在の環境（[AppEnvironment.current]）の設定。
  static FirebaseOptions get current {
    switch (AppEnvironment.current) {
      case AppEnvironment.production:
        return _production;
      case AppEnvironment.staging:
        return _staging;
    }
  }

  /// 未設定を表すマーカー。
  ///
  /// この値のままアプリを起動すると [FirebaseNotConfiguredError] を投げ、
  /// 「設定を忘れたまま動かしてしまう」ことを防ぐ。
  static const String _placeholder = 'REPLACE_ME';

  static const FirebaseOptions _staging = FirebaseOptions(
    apiKey: _placeholder,
    appId: _placeholder,
    messagingSenderId: _placeholder,
    projectId: _placeholder,
    storageBucket: _placeholder,
  );

  static const FirebaseOptions _production = FirebaseOptions(
    apiKey: _placeholder,
    appId: _placeholder,
    messagingSenderId: _placeholder,
    projectId: _placeholder,
    storageBucket: _placeholder,
  );

  /// 設定が実際の値に置き換えられているか。
  static bool get isConfigured => current.apiKey != _placeholder;

  /// 未設定なら例外を投げる。
  static void assertConfigured() {
    if (!isConfigured) {
      throw FirebaseNotConfiguredError(AppEnvironment.current);
    }
  }
}

/// Firebase の接続設定が未記入のまま起動されたときのエラー。
class FirebaseNotConfiguredError extends Error {
  FirebaseNotConfiguredError(this.environment);

  final AppEnvironment environment;

  @override
  String toString() =>
      'Firebase の接続設定が未設定です（${environment.label}）。\n'
      'lib/env/firebase_options.dart の手順に従って flutterfire configure を'
      '実行し、生成された設定に差し替えてください。';
}
