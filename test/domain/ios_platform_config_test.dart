/// iOS のプラットフォーム設定の見張り
///
/// **iOS のビルドは一度も走っていない**（docs/MOBILE-APP-DESIGN.md 冒頭）。
/// 手元に Xcode は無く、確かめる手段が CI しかない。
/// **手元で潰せる失敗を CI で踏むと、失敗ビルドを浪費する**（設計 5 節・8-1）
/// ので、Windows の `flutter test` で機械的に見張れるものはここで止める。
///
/// 見張るのは docs/MOBILE-APP-DESIGN.md 6 節の 4・5・6・7・8・9・14 番。
///
/// **「書いてあること」だけでなく「書いていないこと」も見張る。**
/// `UIBackgroundModes` と `aps-environment` は、**書くと壊れる**側の項目
/// （前者は審査で用途説明を求められ、後者は APNs 鍵が無いうちは署名が
/// 失敗する）。**足し忘れより、うっかり足すほうが起きやすい。**
///
/// **XML のコメントは取り除いてから見る。**
/// `Info.plist` と `Runner.entitlements` には「なぜ書かないか」を
/// コメントで残してある。素のまま文字列で探すと、**その説明文に名前が
/// 残っているせいで「書いてある」と誤判定する。**
/// `test/domain/firebase_launchers_test.dart:19-24` がまったく同じ形で
/// 一度空振りしている（docs/AUDIT-CHECKLIST.md 観点 4）。
///
/// **2026-08-16 に `GoogleService-Info.plist` を置いた**（設計 5-3）。
/// それまで `Info.plist` の Google ログイン 2 項目は仮の値で、値そのものは
/// 見張っていなかった。いまは実値なので、**`GoogleService-Info.plist` と
/// 一字一句一致すること**まで見る。片方だけ取り直すと、**ビルドは通り、
/// ログインも成功し、それでもアプリに戻らない。**
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_list_app/l10n/app_localizations.dart';

/// docs/MOBILE-APP-DESIGN.md 3-3（論点 16）で決めたアプリ ID。
///
/// **一度ストアに出すと変えられない。** Android の `applicationId` と
/// 同じ文字列に揃える（ストアが違うので衝突しない）。
const _bundleId = 'jp.sessionconcierge.trackcabinet';

/// Firebase SDK が要求する下限（設計 5-1）。**13.0 のままだと CI で落ちる。**
const _minimumDeploymentTarget = 15.0;

const _pbxprojPath = 'ios/Runner.xcodeproj/project.pbxproj';
const _infoPlistPath = 'ios/Runner/Info.plist';
const _entitlementsPath = 'ios/Runner/Runner.entitlements';

/// Firebase の iOS 設定（`flutterfire configure` / Firebase コンソールが配る）。
///
/// **本番のぶんだけ置く。** iOS には dev フレーバーを作らない（設計 3-4）。
const _googleServicePlistPath = 'ios/Runner/GoogleService-Info.plist';

/// このリポジトリが「未設定」を表すのに使う印。
///
/// `scripts/deploy.mjs` が Web の接続設定で同じ印を見張っている。
const _placeholder = 'REPLACE_ME';

/// `<!-- ... -->` を取り除く。
///
/// **これを通さないと、「書かない理由」を書いたコメントを
/// 「書いてある」と読んでしまう。**
String _stripXmlComments(String xml) =>
    xml.replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');

String _read(String path) {
  final file = File(path);
  expect(file.existsSync(), isTrue, reason: '$path が見つかりません');
  return file.readAsStringSync();
}

/// plist の `<key>[name]</key>` の直後にある `<array>` の中の文字列を返す。
List<String> _plistStringArray(String plist, String name) {
  final array = RegExp(
    '<key>${RegExp.escape(name)}</key>\\s*<array>(.*?)</array>',
    dotAll: true,
  ).firstMatch(plist);
  if (array == null) return const [];
  return RegExp(r'<string>(.*?)</string>', dotAll: true)
      .allMatches(array.group(1)!)
      .map((m) => m.group(1)!.trim())
      .toList();
}

/// plist の `<key>[name]</key>` の直後にある `<string>` の中身を返す。
String? _plistString(String plist, String name) => RegExp(
  '<key>${RegExp.escape(name)}</key>\\s*<string>(.*?)</string>',
  dotAll: true,
).firstMatch(plist)?.group(1)?.trim();

void main() {
  group('コメントの取り除き', () {
    // **この見張り自身が空振りしないことを確かめる。**
    // ここが壊れると、下の「書いていないこと」の見張りが全部
    // 素通りする（コメントの中の名前を拾って、逆に赤くなる）。
    test('コメントの中身は見えなくなる', () {
      expect(
        _stripXmlComments('<!-- <key>UIBackgroundModes</key> -->\n<key>A</key>'),
        contains('<key>A</key>'),
      );
      expect(
        _stripXmlComments('<!-- <key>UIBackgroundModes</key> -->'),
        isNot(contains('UIBackgroundModes')),
      );
    });
  });

  group('project.pbxproj', () {
    test('IPHONEOS_DEPLOYMENT_TARGET が全箇所で 15.0 以上（設計 5-1）', () {
      final source = _read(_pbxprojPath);
      final found = RegExp(r'IPHONEOS_DEPLOYMENT_TARGET = ([\d.]+);')
          .allMatches(source)
          .map((m) => m.group(1)!)
          .toList();

      // **数えてから中身を見る。** 0 件でも「全部 15.0 以上」は成り立つ。
      expect(
        found.length,
        greaterThanOrEqualTo(3),
        reason:
            'IPHONEOS_DEPLOYMENT_TARGET が $_pbxprojPath に '
            '${found.length} 箇所しかありません。\n'
            'テンプレートには 3 箇所（Debug / Release / Profile）あります。\n'
            '書き方が変わったなら、この見張りも直してください',
      );

      final tooOld = found
          .where((v) => (double.tryParse(v) ?? 0) < _minimumDeploymentTarget)
          .toList();
      expect(
        tooOld,
        isEmpty,
        reason:
            '$_minimumDeploymentTarget 未満の指定が残っています: $tooOld\n'
            '**1 箇所でも古いと、Firebase SDK の要求に届かず CI で落ちます**\n'
            '（設計 5-1。手元で潰せる失敗を CI で踏まないこと）',
      );
    });

    test('PRODUCT_BUNDLE_IDENTIFIER が決めた値（設計 3-3）', () {
      final source = _read(_pbxprojPath);
      final found = RegExp(r'PRODUCT_BUNDLE_IDENTIFIER = ([^;]+);')
          .allMatches(source)
          .map((m) => m.group(1)!.trim())
          .toList();

      expect(
        found.length,
        greaterThanOrEqualTo(6),
        reason:
            'PRODUCT_BUNDLE_IDENTIFIER が ${found.length} 箇所しかありません。\n'
            'Runner に 3 箇所・RunnerTests に 3 箇所あります',
      );

      // RunnerTests の派生形も、親に合わせる。
      const allowed = {_bundleId, '$_bundleId.RunnerTests'};
      final wrong = found.where((id) => !allowed.contains(id)).toSet();
      expect(
        wrong,
        isEmpty,
        reason:
            '決めた値と違う Bundle ID が残っています: $wrong\n'
            '正しくは $_bundleId（テスト用は $_bundleId.RunnerTests）です。\n'
            '**一度ストアに出すと変えられません**（設計 3-3）',
      );

      // Runner 本体（派生形でないほう）が実在すること。
      expect(found, contains(_bundleId));
    });

    test('Runner.entitlements が CODE_SIGN_ENTITLEMENTS から参照されている', () {
      final source = _read(_pbxprojPath);
      final references = RegExp(r'CODE_SIGN_ENTITLEMENTS = ([^;]+);')
          .allMatches(source)
          .map((m) => m.group(1)!.trim())
          .toList();

      expect(
        references.length,
        greaterThanOrEqualTo(3),
        reason:
            'CODE_SIGN_ENTITLEMENTS が ${references.length} 箇所しかありません。\n'
            '**Runner の Debug / Release / Profile の 3 つすべてに要ります。**\n'
            '**登録しないと Runner.entitlements は 1 行も効きません**',
      );

      for (final reference in references) {
        expect(
          reference,
          'Runner/Runner.entitlements',
          reason: '想定と違うファイルを指しています: $reference',
        );
        // ios/ からの相対で書かれている。実在も確かめる。
        expect(
          File('ios/$reference').existsSync(),
          isTrue,
          reason: 'ios/$reference が実在しません',
        );
      }
    });
  });

  group('Info.plist', () {
    test('CFBundleLocalizations があり、lib/l10n の言語と一致する', () {
      final plist = _stripXmlComments(_read(_infoPlistPath));
      final declared = _plistStringArray(plist, 'CFBundleLocalizations');

      expect(
        declared,
        isNotEmpty,
        reason:
            'CFBundleLocalizations がありません。\n'
            '**無いと、日本語の端末でも英語で起動します**（設計 5-7）。\n'
            'Flutter の supportedLocales は OS の判断に効きません',
      );

      // **同じことを決める場所が 2 つある**状態を放置しない（設計 6 節の 6 番）。
      final supported =
          AppL10n.supportedLocales.map((l) => l.languageCode).toSet();
      expect(
        declared.toSet(),
        supported,
        reason:
            'Info.plist の言語（$declared）と lib/l10n の言語（$supported）が\n'
            '食い違っています。**片方だけ足すと、その言語で起動しません**',
      );
    });

    test('ITSAppUsesNonExemptEncryption = false がある', () {
      final plist = _stripXmlComments(_read(_infoPlistPath));
      expect(
        RegExp(
          r'<key>ITSAppUsesNonExemptEncryption</key>\s*<false\s*/>',
        ).hasMatch(plist),
        isTrue,
        reason:
            'ITSAppUsesNonExemptEncryption = false がありません。\n'
            '**無いと、アップロードのたびに輸出コンプライアンスの質問が出ます**\n'
            '（設計 5-7・5-17）',
      );
    });

    test('Google ログインの戻り先（CFBundleURLTypes / GIDClientID）がある', () {
      final plist = _stripXmlComments(_read(_infoPlistPath));
      for (final key in ['CFBundleURLTypes', 'GIDClientID']) {
        expect(
          plist,
          contains('<key>$key</key>'),
          reason:
              '$key がありません。\n'
              '**無いと、認証は済むのにアプリへ戻れません**（設計 5-5 / 5-7）。\n'
              '利用者からは「固まった」ように見えます',
        );
      }
    });

    test('未設定の印が残っていない', () {
      // **仮の値のまま出すと、認証は済むのにアプリへ戻ってこない。**
      // ビルドも審査も通るので、**実機で試すまで誰も気づかない。**
      //
      // コメントを取り除いてから見る。「以前は仮の値だった」という説明を
      // 「まだ仮の値だ」と読まないため。
      final plist = _stripXmlComments(_read(_infoPlistPath));
      expect(
        plist,
        isNot(contains(_placeholder)),
        reason:
            'Info.plist に $_placeholder が残っています。\n'
            '$_googleServicePlistPath の REVERSED_CLIENT_ID と CLIENT_ID を\n'
            '実値として写してください（設計 5-3 / 5-7）',
      );
    });

    test('UIBackgroundModes を書いていない（逆向きの見張り）', () {
      final plist = _stripXmlComments(_read(_infoPlistPath));
      expect(
        plist,
        isNot(contains('<key>UIBackgroundModes</key>')),
        reason:
            'UIBackgroundModes が書かれています。\n'
            '**使わない背景動作を宣言すると、審査で用途の説明を求められます**。\n'
            'バックグラウンド再生も通知も今回やりません（設計 5-7・7 節）',
      );
    });

    test('使わない権限を書いていない（逆向きの見張り）', () {
      final plist = _stripXmlComments(_read(_infoPlistPath));
      expect(
        plist,
        isNot(contains('<key>NSCameraUsageDescription</key>')),
        reason:
            'NSCameraUsageDescription が書かれています。\n'
            'カメラは使いません。**使わない権限を書くと審査で用途を訊かれます**\n'
            '（設計 5-7。「念のため書いておく」がいちばん悪い選択）',
      );
    });
  });

  group('GoogleService-Info.plist（設計 5-3）', () {
    test('ファイルが置いてある', () {
      // **無いと iOS の Firebase が起動時に落ちる**（設計 6 節の 14 番）。
      // 5-3 で「設定ファイルはコミットする」と決めているので、
      // CI でもここが成立する。
      expect(
        File(_googleServicePlistPath).existsSync(),
        isTrue,
        reason:
            '$_googleServicePlistPath がありません。\n'
            'scripts\\configure-firebase.cmd prod --platforms=web,android,ios\n'
            'または Firebase コンソールから取得して置いてください（5-3）',
      );
    });

    test('Xcode のビルドに含まれている（Resources ビルドフェーズ）', () {
      // **置くだけでは製品に入らない。** project.pbxproj に登録しないと
      // Runner.app へコピーされず、**実機で「設定ファイルが無い」と落ちる。**
      //
      // **Windows では `flutterfire configure` が pbxproj を触らない**
      // （中で ruby と xcodeproj gem を呼ぶため macOS でしか動かない。
      //   flutterfire_cli 1.4.1 の config.dart が `Platform.isMacOS` で
      //   まるごと囲っている）。**だから手で登録した。消さないこと。**
      final pbxproj = _read(_pbxprojPath);

      expect(
        pbxproj,
        contains('/* GoogleService-Info.plist */'),
        reason:
            '$_pbxprojPath に GoogleService-Info.plist の登録がありません。\n'
            '**ファイルを置いただけでは Runner.app に入りません**',
      );

      // Runner の Resources フェーズの中身を実際に見る。
      // **ファイル参照だけだと Xcode のツリーに見えるだけで、
      //   コピーはされない。**
      final resources = RegExp(
        r'/\* Resources \*/ = \{\s*isa = PBXResourcesBuildPhase;(.*?)\};',
        dotAll: true,
      )
          .allMatches(pbxproj)
          .map((m) => m.group(1)!)
          .where((body) => body.contains('LaunchScreen.storyboard'))
          .toList();
      expect(
        resources,
        hasLength(1),
        reason:
            'Runner の Resources ビルドフェーズを特定できませんでした。\n'
            'pbxproj の構造が変わったなら、この見張りも直してください',
      );
      expect(
        resources.single,
        contains('GoogleService-Info.plist in Resources'),
        reason:
            'Runner の Resources ビルドフェーズに GoogleService-Info.plist が\n'
            'ありません。**ツリーに見えるだけでは製品に入りません**',
      );
    });

    test('Bundle ID が決めた値と一致する', () {
      final plist = _stripXmlComments(_read(_googleServicePlistPath));
      expect(
        _plistString(plist, 'BUNDLE_ID'),
        _bundleId,
        reason:
            'GoogleService-Info.plist の BUNDLE_ID が project.pbxproj の\n'
            'PRODUCT_BUNDLE_IDENTIFIER と違います。\n'
            '**別のアプリの設定を置いていませんか**',
      );
    });

    test('Info.plist の 2 つの値が GoogleService-Info.plist と一字一句同じ', () {
      // **同じことを決める場所が 2 つある**（設計 6 節の 6 番と同じ形）。
      // plist を取り直したのに Info.plist を直し忘れると、
      // **ビルドは通り、ログインも成功し、それでもアプリに戻らない。**
      // エラーは出ず、利用者からは「固まった」ように見える。
      final service = _stripXmlComments(_read(_googleServicePlistPath));
      final info = _stripXmlComments(_read(_infoPlistPath));

      final reversed = _plistString(service, 'REVERSED_CLIENT_ID');
      final clientId = _plistString(service, 'CLIENT_ID');
      expect(reversed, isNotNull, reason: 'REVERSED_CLIENT_ID がありません');
      expect(clientId, isNotNull, reason: 'CLIENT_ID がありません');

      expect(
        _plistStringArray(info, 'CFBundleURLSchemes'),
        contains(reversed),
        reason:
            'Info.plist の CFBundleURLSchemes に REVERSED_CLIENT_ID\n'
            '（$reversed）がありません。\n'
            '**認証は済むのにアプリへ戻れません**（設計 5-7）',
      );

      expect(
        _plistString(info, 'GIDClientID'),
        clientId,
        reason:
            'Info.plist の GIDClientID が CLIENT_ID（$clientId）と\n'
            '違います。**google_sign_in がここを読みます**（設計 5-7）',
      );
    });

  });

  group('Runner.entitlements', () {
    test('Sign in with Apple の宣言がある（設計 5-6）', () {
      final entitlements = _stripXmlComments(_read(_entitlementsPath));
      expect(
        entitlements,
        contains('<key>com.apple.developer.applesignin</key>'),
        reason:
            'com.apple.developer.applesignin がありません。\n'
            '**無いと、実装しても呼んだ瞬間に失敗します**（capability 無し扱い）。\n'
            '審査ガイドライン 4.8 で必要です',
      );
      expect(
        _plistStringArray(entitlements, 'com.apple.developer.applesignin'),
        contains('Default'),
      );
    });

    test('Associated Domains に本番と検証のホストが入っている（設計 5-8-2）', () {
      final entitlements = _stripXmlComments(_read(_entitlementsPath));
      final domains = _plistStringArray(
        entitlements,
        'com.apple.developer.associated-domains',
      );

      expect(
        domains,
        isNotEmpty,
        reason:
            'com.apple.developer.associated-domains がありません。\n'
            '**無いと、共有リンクを押しても Safari で開くだけです。**\n'
            '**エラーは出ません**（設計 5-8-2）',
      );
      expect(
        domains,
        containsAll(<String>[
          'applinks:music-storage-d79b2.web.app', // 本番（.firebaserc の prod）
          'applinks:music-storage-dev.web.app', // 検証（同 staging）
        ]),
        reason: '本番と検証の両方のホストが要ります。いまの値: $domains',
      );
    });

    test('aps-environment を書いていない（逆向きの見張り）', () {
      final entitlements = _stripXmlComments(_read(_entitlementsPath));
      expect(
        entitlements,
        isNot(contains('<key>aps-environment</key>')),
        reason:
            'aps-environment が書かれています。\n'
            '**APNs 鍵が無いうちに書くと署名が失敗します**\n'
            '（「プロビジョニングプロファイルに aps-environment が含まれて\n'
            'いない」でビルドが止まる）。通知は今回やりません（設計 5-6・7 節）',
      );
    });
  });
}
