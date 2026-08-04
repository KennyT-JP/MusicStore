/// エントリポイント
///
/// 接続先の Firebase プロジェクトは、ビルド時の `--dart-define=APP_ENV` で
/// 切り替える（仕様書 12.2）。指定がないときは検証環境に倒す。
///
/// ```sh
/// flutter run -d chrome                            # 検証環境
/// flutter run -d chrome --dart-define=APP_ENV=prod # 本番環境
/// ```
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'env/firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase の接続設定が未記入のままなら、起動時にはっきり分かる形で止める。
  // 設定を忘れたまま動かして、原因の分かりにくい失敗を追うことを避ける。
  DefaultFirebaseOptions.assertConfigured();

  // TODO(setup): flutterfire configure 後に Firebase を初期化する。
  //   await Firebase.initializeApp(options: DefaultFirebaseOptions.current);

  runApp(const ProviderScope(child: MusicListApp()));
}
