/// 検証（ステージング）環境の Firebase 接続設定
///
/// **このファイルは `flutterfire configure` が生成・上書きします。**
/// 手で編集しないでください。
///
/// ```sh
/// flutterfire configure \
///   --project=music-storage-dev \
///   --out=lib/env/firebase_options_staging.dart \
///   --platforms=web,android,ios
/// ```
///
/// いまは `REPLACE_ME` が入っています。この状態でクラウドに繋ごうとすると
/// [FirebaseNotConfiguredError] を投げて止まります（設定忘れに気づけるように）。
///
/// 生成前でもアプリがビルドできるよう、生成後と同じ形（`DefaultFirebaseOptions`
/// クラスの `currentPlatform`）で置いてあります。
///
/// なお Firebase の Web 設定値（apiKey 等）は公開前提の識別子であり、
/// それ自体は秘密情報ではありません。アクセス制御はセキュリティルールで
/// 行います（仕様書 13.5）。
library;

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;

/// 生成後のファイルと同じ形。
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform => const FirebaseOptions(
    apiKey: 'REPLACE_ME',
    appId: 'REPLACE_ME',
    messagingSenderId: 'REPLACE_ME',
    projectId: 'REPLACE_ME',
    storageBucket: 'REPLACE_ME',
  );
}
