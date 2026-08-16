/// エントリポイント
///
/// 接続先はビルド時の `--dart-define` で切り替える（仕様書 12.2）。
///
/// ```sh
/// # ローカルのエミュレータ（Firebase プロジェクト不要）
/// firebase emulators:start --project demo-musiclist
/// flutter run -d chrome --dart-define=USE_EMULATOR=true
///
/// # 検証環境（既定）
/// flutter run -d chrome
///
/// # 本番環境
/// flutter run -d chrome --dart-define=APP_ENV=prod
/// ```
library;

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'env/firebase_emulators.dart';
import 'env/firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 接続設定が未記入のままクラウドに繋ごうとしたら、原因が分かる形で止める。
  // 設定を忘れたまま動かして、追いにくい失敗を追うことを避ける。
  DefaultFirebaseOptions.assertConfigured();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.current);

  // 最初の読み書きより前にエミュレータへ向ける。
  if (useFirebaseEmulators) {
    await connectToFirebaseEmulators();
  }

  // 開いた URL を、最初の描画より前に控える（app.dart の説明を参照）。
  // Web のパスは `#/s/xxx` のようにフラグメントに入っている。
  //
  // **ネイティブ（iOS / Android）では、ここから起動 URL は取れない。**
  // `Uri.base` は実行時のカレントディレクトリを指す `file:` 形式で、
  // fragment は必ず空になる（落ちはしないが、常に `/` と同じ）。
  // 起動時のディープリンクは App Links / Universal Links で受け取る口を
  // 別途用意する（仕様書 5-8-2）。ここでは既定の `/` に倒しておく。
  final fragment = kIsWeb ? Uri.base.fragment : '';
  final launchLocation = fragment.startsWith('/') ? fragment : '/';

  runApp(
    ProviderScope(
      overrides: [launchLocationProvider.overrideWithValue(launchLocation)],
      child: const MusicListApp(),
    ),
  );
}
