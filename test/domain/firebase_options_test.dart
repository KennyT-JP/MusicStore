/// Firebase の接続設定が android / iOS を持っているか（設計 6 節の 13 番）
///
/// **`lib/env/firebase_options_*.dart` は `flutterfire configure` の生成物。**
/// 生成時に `--platforms` へ渡さなかったプラットフォームは、
/// **本体が消えるのではなく `UnsupportedError` を投げる分岐に置き換わる。**
///
/// ```dart
/// case TargetPlatform.android:
///   throw UnsupportedError(
///     'DefaultFirebaseOptions have not been configured for android - '
///     'you can reconfigure this by running the FlutterFire CLI again.',
///   );
/// ```
///
/// **これがいちばん悪い形で壊れる。**
///
/// | いつ | 何が起きるか |
/// | --- | --- |
/// | ビルド | **通る。** 型としては正しいコードなので警告も出ない |
/// | `flutter test` | **通る。** テストは web でもネイティブでもない |
/// | 実機で起動 | **`main()` の `Firebase.initializeApp` で即座に例外。** 起動画面のまま止まる |
///
/// 既定は `--platforms=web` だけ（`scripts/configure-firebase.mjs:35-38`）。
/// **何も考えずに生成し直すと、android / iOS が黙って落ちる側に戻る。**
///
/// **生成し直すときは必ず `--platforms` を付けること:**
///
/// ```sh
/// scripts\configure-firebase.cmd prod --platforms=web,android,ios
/// scripts\configure-firebase.cmd --platforms=web,android
/// ```
///
/// > **検証環境の android は `.dev` の applicationId で登録されている。**
/// > `flutterfire configure` は `build.gradle.kts` の `applicationId`
/// > （＝接尾辞の付かない本番の値）を既定で使うので、検証環境を生成し直す
/// > ときは `--android-package-name=jp.sessionconcierge.trackcabinet.dev`
/// > も渡すこと。渡さないと**検証プロジェクトに本番と同じパッケージ名の
/// > アプリが新しく作られる**（消すまで残る）。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _prodPath = 'lib/env/firebase_options_prod.dart';
const _stagingPath = 'lib/env/firebase_options_staging.dart';

/// Dart のコメントを取り除いて返す。
///
/// **生成物の冒頭には使い方の例が `///` で入っている。**
/// 取り除かずに探すと、その例文の中の語を拾う。
String _read(String path) {
  final file = File(path);
  expect(
    file.existsSync(),
    isTrue,
    reason:
        '$path がありません。\n'
        'scripts\\configure-firebase.cmd で生成してください（設計 5-3）',
  );
  return file
      .readAsStringSync()
      .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
      .replaceAll(RegExp(r'//[^\n]*'), '');
}

/// 設定の名前（`ios`）から `TargetPlatform` の綴り（`iOS`）へ。
String _caseLabel(String platform) => platform == 'ios' ? 'iOS' : platform;

/// `switch (defaultTargetPlatform)` の中の `case TargetPlatform.[platform]:`
/// から、次の `case` / `default` までの中身を返す。
///
/// **`case` ごとに切って読む。** ファイル全体を `contains` で見ると、
/// 別のプラットフォームの `UnsupportedError` を拾って、どのプラットフォームが
/// 壊れているのか分からなくなる（macOS / Windows / Linux の 3 つは
/// **投げるのが正しい**ので、必ず 1 件は残っている）。
String _caseBody(String source, String platform) {
  final start = source.indexOf('case TargetPlatform.$platform:');
  expect(
    start,
    isNot(-1),
    reason: 'case TargetPlatform.$platform: が見つかりません',
  );

  final rest = source.substring(start);
  final next = RegExp(
    r'\n\s*(case TargetPlatform\.|default:)',
  ).firstMatch(rest.substring(1));
  return next == null ? rest : rest.substring(0, next.start + 1);
}

/// [platform] の設定が使える形で入っていること。
///
/// **`case` のラベルと設定の名前は綴りが違う。**
/// `TargetPlatform.iOS` に対して `static const FirebaseOptions ios`。
/// 片方の綴りで両方を探すと、**見つからないのを「壊れている」と誤読する。**
void _expectConfigured(String path, String platform) {
  final source = _read(path);
  final body = _caseBody(source, _caseLabel(platform));

  expect(
    body,
    isNot(contains('UnsupportedError')),
    reason:
        '$path の $platform が UnsupportedError を投げます。\n'
        '**ビルドもテストも通り、実機で起動した瞬間だけ落ちます**（設計 6 節の 13 番）。\n'
        '\n'
        '生成し直すときに --platforms を付け忘れていませんか\n'
        '（既定は web だけ。scripts/configure-firebase.mjs:35-38）。\n'
        '\n'
        '  scripts\\configure-firebase.cmd prod --platforms=web,android,ios\n'
        '  scripts\\configure-firebase.cmd --platforms=web,android',
  );

  // **投げないことだけでは足りない。** 実体（`static const FirebaseOptions
  // android = ...`）まで在ることを確かめる。
  expect(
    body,
    contains('return $platform;'),
    reason: '$path の $platform が設定を返していません',
  );
  expect(
    source,
    contains('static const FirebaseOptions $platform = FirebaseOptions('),
    reason: '$path に $platform の FirebaseOptions がありません',
  );
}

/// [path] の [platform] の設定から `名前: '値'` を読む。
String? _optionValue(String path, String platform, String name) {
  final source = _read(path);
  final block = RegExp(
    'static const FirebaseOptions $platform = FirebaseOptions\\((.*?)\\);',
    dotAll: true,
  ).firstMatch(source);
  expect(block, isNotNull, reason: '$path に $platform の設定がありません');
  return RegExp("$name:\\s*'([^']+)'").firstMatch(block!.group(1)!)?.group(1);
}

void main() {
  group('本番（$_prodPath）', () {
    test('android と iOS が UnsupportedError を投げない', () {
      _expectConfigured(_prodPath, 'android');
      _expectConfigured(_prodPath, 'ios');
    });

    test('登録済みのアプリ ID を指している', () {
      // **プロジェクトを取り違えると、検証環境のデータに本番から書き込む。**
      // 値そのものを固定しておく（Firebase の設定値は公開前提の識別子で、
      // 秘密情報ではない。仕様書 13.5）。
      expect(
        _optionValue(_prodPath, 'android', 'appId'),
        '1:856522879081:android:0cdd0eedd4d9be1fbc32f8',
      );
      expect(
        _optionValue(_prodPath, 'ios', 'appId'),
        '1:856522879081:ios:5e83a2d98d5137e0bc32f8',
      );
      for (final platform in ['web', 'android', 'ios']) {
        expect(
          _optionValue(_prodPath, platform, 'projectId'),
          'music-storage-d79b2',
          reason: '本番の $platform が本番プロジェクトを指していません',
        );
      }
    });

    test('iOS の Bundle ID が決めた値である', () {
      expect(
        _optionValue(_prodPath, 'ios', 'iosBundleId'),
        'jp.sessionconcierge.trackcabinet',
      );
    });
  });

  group('検証（$_stagingPath）', () {
    test('android が UnsupportedError を投げない', () {
      _expectConfigured(_stagingPath, 'android');
    });

    test('登録済みのアプリ ID を指している', () {
      // **検証の android は `.dev` の applicationId で登録されている。**
      // ここが本番と同じ appId になっていたら、`--android-package-name` を
      // 付け忘れて生成し直した跡（本番と同じパッケージ名のアプリが
      // 検証プロジェクトに作られてしまう）。
      expect(
        _optionValue(_stagingPath, 'android', 'appId'),
        '1:928958401238:android:372674a05895e064b8d777',
      );
      for (final platform in ['web', 'android']) {
        expect(
          _optionValue(_stagingPath, platform, 'projectId'),
          'music-storage-dev',
          reason: '検証の $platform が検証プロジェクトを指していません',
        );
      }
    });

    test('iOS は持たない（設計 3-4）', () {
      // **「書いていないこと」の見張り。**
      //
      // **iOS には dev フレーバーを作らない。** Android は
      // `applicationIdSuffix` だけで分けられるが、iOS は Xcode の
      // configuration と scheme を増やす必要がある。Session Concierge は
      // 「iOS は本番のみ」と割り切り、確認は Web と Android の dev で
      // 行っている。音源創庫も同じにした。
      //
      // **ここが緑から赤に変わったら、それは事故ではなく方針変更。**
      // 検証プロジェクトに iOS アプリを登録し、Xcode 側の scheme も
      // 用意したなら、この test を消して上の android と同じ形にすること。
      final source = _read(_stagingPath);
      expect(
        source,
        isNot(contains('static const FirebaseOptions ios = FirebaseOptions(')),
        reason:
            '検証環境に iOS の設定が入っています。\n'
            'iOS に dev フレーバーは作らない方針です（設計 3-4）。\n'
            '方針を変えたなら、この見張りごと直してください',
      );
    });
  });
}
