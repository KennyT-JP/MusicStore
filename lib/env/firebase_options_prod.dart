/// 本番環境の Firebase 接続設定
///
/// **このファイルは `flutterfire configure` が生成・上書きします。**
/// 手で編集しないでください。
///
/// ```sh
/// flutterfire configure \
///   --project=music-storage-d79b2 \
///   --out=lib/env/firebase_options_prod.dart \
///   --platforms=web,android,ios
/// ```
///
/// 詳しくは firebase_options_staging.dart の冒頭を参照してください。
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
