/// Firebase の接続設定（仕様書 12.2）
///
/// 接続先は 3 通りある。
///
/// | 起動方法 | 接続先 |
/// | --- | --- |
/// | `--dart-define=USE_EMULATOR=true` | ローカルのエミュレータ（設定不要） |
/// | 指定なし | 検証（ステージング）プロジェクト |
/// | `--dart-define=APP_ENV=prod` | 本番プロジェクト |
///
/// **検証・本番の設定はプレースホルダーのままです。**
/// Firebase プロジェクトを作成したら、次の手順で実際の値に置き換えてください。
///
/// ```sh
/// dart pub global activate flutterfire_cli
///
/// flutterfire configure \
///   --project=<検証用プロジェクト ID> \
///   --out=lib/env/firebase_options_staging.dart \
///   --platforms=web,android,ios
///
/// flutterfire configure \
///   --project=<本番用プロジェクト ID> \
///   --out=lib/env/firebase_options_prod.dart \
///   --platforms=web,android,ios
/// ```
///
/// 生成された 2 つのファイルを import し、[DefaultFirebaseOptions.current] から
/// 返すように書き換えます。詳しい手順は docs/SETUP.md を参照してください。
///
/// なお Firebase の Web 設定値（apiKey 等）は公開前提の識別子であり、
/// これ自体は秘密情報ではありません。アクセス制御はセキュリティルール
/// （firestore.rules / storage.rules）で行います（仕様書 13.5）。
library;

import 'package:firebase_core/firebase_core.dart';

import 'app_environment.dart';
import 'firebase_emulators.dart';

/// 環境に応じた Firebase の接続設定。
class DefaultFirebaseOptions {
  const DefaultFirebaseOptions._();

  /// 現在の接続先の設定。
  static FirebaseOptions get current {
    if (useFirebaseEmulators) return _emulator;
    switch (AppEnvironment.current) {
      case AppEnvironment.production:
        return _production;
      case AppEnvironment.staging:
        return _staging;
    }
  }

  /// 未設定を表すマーカー。
  ///
  /// この値のままクラウドに繋ごうとすると [FirebaseNotConfiguredError] を投げ、
  /// 「設定を忘れたまま動かしてしまう」ことを防ぐ。
  static const String _placeholder = 'REPLACE_ME';

  /// エミュレータ用のダミー設定。
  ///
  /// エミュレータは接続値を検証しないため、実在しない値でよい。
  /// プロジェクト ID を `demo-` で始めると、Firebase CLI が
  /// 「クラウドのサービスには一切アクセスしない」モードで動く。
  static const FirebaseOptions _emulator = FirebaseOptions(
    apiKey: 'demo-api-key',
    appId: '1:000000000000:web:0000000000000000000000',
    messagingSenderId: '000000000000',
    projectId: 'demo-musiclist',
    storageBucket: 'demo-musiclist.appspot.com',
  );

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
  ///
  /// エミュレータに接続する場合は設定が不要なので、何もしない。
  static void assertConfigured() {
    if (useFirebaseEmulators) return;
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
      '\n'
      '次のいずれかを行ってください。\n'
      '\n'
      '  1. ローカルのエミュレータで試す（設定不要）\n'
      '       firebase emulators:start --project demo-musiclist\n'
      '       flutter run -d chrome --dart-define=USE_EMULATOR=true\n'
      '\n'
      '  2. Firebase プロジェクトに接続する\n'
      '       docs/SETUP.md の手順に従って flutterfire configure を実行し、\n'
      '       lib/env/firebase_options.dart を差し替えてください。';
}
