/// アプリ内バナー広告（AdMob）の見張り（docs/PREMIUM-DESIGN.md の広告）
///
/// **守りたいのは4つ。**
/// 1. **ネイティブ側（Manifest / Info.plist）と Dart 側の ID がずれない**
///    ——片方だけ直すと、Android は起動時に落ちるか広告が出ず、iOS は起動直後に
///    落ちる。どちらも「直したつもり」で気づけない。
/// 2. **本番の ID が Google のテスト用へ逆戻りしない**——動作確認のために
///    テスト用へ戻し、そのまま出す事故を止める。
/// 3. **出す条件がずれない**——Web・非対応プラットフォーム・プレミアム・
///    読み込み中には出さない。Android / iOS の非プレミアムにだけ出す。
/// 4. **広告要求が必ず非パーソナライズ**——UMP 同意フォームも ATT も実装
///    しないので、追跡の同意を取る手段が無い。要求を作る場所を1か所に固定し、
///    件数で見張る。
///
/// **Web の AdSense（`web/help/` の広告・`web/ads.txt`）とは別物。** あちらの
/// 見張りは `ads_placement_test.dart`。ここで見るのは `web/app-ads.txt`
/// （アプリ内広告の在庫証明）まで。
///
/// **抽出は必ずコメントを取り除いてから行う**（AP-54「写しを検証してしまう
/// 抜け道」）。コメントに本物と同じ形の記述があると、見張りがコメントのほうを
/// 検証してしまい、本物を壊しても緑になる。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:music_list_app/config/ads.dart';
import 'package:music_list_app/providers/app_providers.dart'
    show isPremiumOrAdminProvider;
import 'package:music_list_app/ui/widgets/ad_banner_box.dart';
import 'package:music_list_app/ui/widgets/ad_banner_slot.dart';

// ---------------------------------------------------------------------------
// 見張りの土台（受け取るのは**生のソース**。コメントの除去は中で行う）
// ---------------------------------------------------------------------------

String _readRaw(String path) => File(path).readAsStringSync();

/// XML / plist からコメント（`<!-- ... -->`）を取り除く。
String _stripXmlComments(String src) =>
    src.replaceAll(RegExp(r'<!--.*?-->', dotAll: true), ' ');

/// Dart / Kotlin ソースからコメント（`//`・`///`・`/* */`）を取り除く。
///
/// この見張りが読む lib のソースには、コメントに `google_mobile_ads` や
/// `AdRequest` の語がある（説明文）。取り除かないと、実装を消してもコメントの
/// 語で緑のままになる。
String _stripCodeComments(String src) => src
    .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), ' ')
    .replaceAll(RegExp(r'//[^\n]*'), '');

/// [pattern] に一致する箇所を**ちょうど1件**取り出す。0件でも2件以上でも落とす。
RegExpMatch _only(String src, RegExp pattern, String what) {
  final ms = pattern.allMatches(src).toList();
  if (ms.length != 1) {
    fail('$what が ${ms.length} 件（1件であるべき）: $pattern');
  }
  return ms.single;
}

/// AndroidManifest の `<meta-data android:name="…" android:value="…"/>` の値。
///
/// **属性の並び順は問わない**（`android:value` が先でも拾う）。
String _manifestMetaData(String xmlSource, String name) {
  final xml = _stripXmlComments(xmlSource);
  final tag = _only(
    xml,
    RegExp('<meta-data\\b[^>]*android:name\\s*=\\s*"$name"[^>]*/>', dotAll: true),
    'Manifest の meta-data $name',
  ).group(0)!;
  return _only(
    tag,
    RegExp(r'android:value\s*=\s*"([^"]*)"'),
    '$name の android:value',
  ).group(1)!;
}

/// plist の `<key>名前</key>` に続く `<string>…</string>`（ちょうど1件）。
String _plistValue(String plistSource, String key) => _only(
  _stripXmlComments(plistSource),
  RegExp('<key>$key</key>\\s*<string>([^<]*)</string>'),
  'Info.plist の $key',
).group(1)!;

/// `lib/` 以下の Dart ソース（コメントを取り除いた形）を、パスつきで全部返す。
Map<String, String> _libSources() {
  final out = <String, String>{};
  for (final f in Directory('lib').listSync(recursive: true)) {
    if (f is File && f.path.endsWith('.dart')) {
      final path = f.path.replaceAll(r'\', '/');
      out[path] = _stripCodeComments(f.readAsStringSync());
    }
  }
  return out;
}

/// glob（firebase.json の `ignore` / `rewrites.source`）を正規表現へ。
///
/// **`**/` は「0個以上のディレクトリ」**。単純に `.*` へ置き換えると
/// `ads.txt`・`app-ads.txt` にまで当たり、「配信から外されている」という
/// 嘘の赤が出る。`*` は区切りをまたがない。
RegExp _globToRegExp(String glob) {
  final sb = StringBuffer('^');
  for (var i = 0; i < glob.length; i++) {
    final c = glob[i];
    if (c == '*') {
      if (i + 1 < glob.length && glob[i + 1] == '*') {
        i++;
        if (i + 1 < glob.length && glob[i + 1] == '/') {
          sb.write('(?:[^/]*/)*'); // `**/` = 0個以上のディレクトリ
          i++;
        } else {
          sb.write('.*'); // 末尾の `**` = 何でも
        }
      } else {
        sb.write('[^/]*');
      }
    } else if (c == '?') {
      sb.write('[^/]');
    } else {
      sb.write(RegExp.escape(c));
    }
  }
  sb.write(r'$');
  return RegExp(sb.toString());
}

// ---------------------------------------------------------------------------

void main() {
  final manifest = _readRaw('android/app/src/main/AndroidManifest.xml');
  final infoPlist = _readRaw('ios/Runner/Info.plist');

  // -------------------------------------------------------------------------
  group('見張りの土台（コメントの中の偽物を拾わない・AP-54）', () {
    test('Manifest: コメントに書いた古い ID を拾わない', () {
      const decoy = '''
<application>
  <!-- 旧: <meta-data android:name="com.google.android.gms.ads.APPLICATION_ID"
       android:value="ca-app-pub-0000000000000000~0000000000"/> -->
  <meta-data
      android:name="com.google.android.gms.ads.APPLICATION_ID"
      android:value="ca-app-pub-1111111111111111~1111111111" />
</application>
''';
      expect(
        _manifestMetaData(decoy, 'com.google.android.gms.ads.APPLICATION_ID'),
        'ca-app-pub-1111111111111111~1111111111',
        reason: 'コメント側の 0000… を拾ってはいけない',
      );
    });

    test('Info.plist: コメントに書いた古い ID を拾わない', () {
      const decoy = '''
<dict>
  <!-- 旧: <key>GADApplicationIdentifier</key><string>ca-app-pub-0~0</string> -->
  <key>GADApplicationIdentifier</key>
  <string>ca-app-pub-1~1</string>
</dict>
''';
      expect(
        _plistValue(decoy, 'GADApplicationIdentifier'),
        'ca-app-pub-1~1',
        reason: 'コメント側の ca-app-pub-0~0 を拾ってはいけない',
      );
    });

    test('本物のファイルからコメントが実際に消えている', () {
      for (final raw in [manifest, infoPlist]) {
        expect(raw, contains('<!--'), reason: '前提が違う（コメントが無い）');
        final stripped = _stripXmlComments(raw);
        expect(stripped, isNot(contains('<!--')));
        expect(stripped.length, lessThan(raw.length));
      }
    });
  });

  // -------------------------------------------------------------------------
  group('ネイティブ側と Dart 側のアプリ ID（片方だけ直す事故を止める）', () {
    test('AndroidManifest の APPLICATION_ID が ads.dart と一致する', () {
      expect(
        _manifestMetaData(manifest, 'com.google.android.gms.ads.APPLICATION_ID'),
        kAndroidAdMobAppId,
        reason: 'AndroidManifest と lib/config/ads.dart のアプリ ID がずれている。'
            '**片方だけ直すと、起動時に SDK が落ちるか広告が出ない**'
            '（どちらもエラーが画面に出ない）',
      );
    });

    test('Info.plist の GADApplicationIdentifier が ads.dart と一致する', () {
      expect(
        _plistValue(infoPlist, 'GADApplicationIdentifier'),
        kIosAdMobAppId,
        reason: 'Info.plist と lib/config/ads.dart の iOS アプリ ID がずれている。'
            '**この宣言が食い違うと iOS は起動直後に落ちる**',
      );
    });

    test('Info.plist に GADApplicationIdentifier がある（無いと iOS が落ちる）', () {
      // 「一致する」だけだと、**両方消したとき**に `_only` が 0 件で落ちる形に
      // なる。落ちる理由を「そもそも無い」と切り分けられるよう、存在も別に見る。
      expect(
        _stripXmlComments(infoPlist),
        contains('GADApplicationIdentifier'),
      );
    });

    test('アプリ ID は本物（Google のテスト用ではない）', () {
      // アプリ ID は配布する側なので、テスト用のままにしない。
      // （切り替えるのは広告ユニット ID だけ。）
      expect(isGoogleSampleAdId(kAndroidAdMobAppId), isFalse);
      expect(isGoogleSampleAdId(kIosAdMobAppId), isFalse);
    });

    test('広告の読み込みに要る INTERNET 権限が main マニフェストにある', () {
      // release ビルドでは Flutter のツールが自動で足さない。無いと AdMob が
      // 広告を取りに行けない。
      expect(
        _stripXmlComments(manifest),
        contains('android.permission.INTERNET'),
        reason: 'AndroidManifest.xml に INTERNET 権限がありません',
      );
    });
  });

  // -------------------------------------------------------------------------
  group('出す条件（Android・iOS の非プレミアムだけ）', () {
    test('Android の非プレミアムには出す', () {
      expect(
        shouldShowBanner(platform: AdPlatform.android, isPremium: false),
        isTrue,
      );
    });

    test('iOS の非プレミアムには出す', () {
      expect(
        shouldShowBanner(platform: AdPlatform.ios, isPremium: false),
        isTrue,
      );
    });

    for (final p in [AdPlatform.android, AdPlatform.ios]) {
      test('${p.name} でもプレミアムには出さない（特典）', () {
        expect(shouldShowBanner(platform: p, isPremium: true), isFalse);
      });
    }

    for (final p in [AdPlatform.web, AdPlatform.other]) {
      test('${p.name} には出さない', () {
        expect(shouldShowBanner(platform: p, isPremium: false), isFalse);
      });
    }
  });

  // -------------------------------------------------------------------------
  group('本番と検証・デバッグでユニット ID を出し分ける', () {
    test('本番環境は本番の広告ユニット（Android / iOS）', () {
      expect(
        bannerAdUnitId(platform: AdPlatform.android, production: true),
        kAndroidBannerAdUnitId,
      );
      expect(
        bannerAdUnitId(platform: AdPlatform.ios, production: true),
        kIosBannerAdUnitId,
      );
    });

    test('本番以外（検証・デバッグ）は Google のテスト用（Android / iOS）', () {
      expect(
        bannerAdUnitId(platform: AdPlatform.android, production: false),
        kTestAndroidBannerAdUnitId,
      );
      expect(
        bannerAdUnitId(platform: AdPlatform.ios, production: false),
        kTestIosBannerAdUnitId,
      );
    });

    test('本番の広告ユニットは Google のテスト用ではない（逆戻りの検出）', () {
      expect(isGoogleSampleAdId(kAndroidBannerAdUnitId), isFalse);
      expect(isGoogleSampleAdId(kIosBannerAdUnitId), isFalse);
      // 逆向きの取り違え（テスト用のつもりが本番）も止める。
      expect(isGoogleSampleAdId(kTestAndroidBannerAdUnitId), isTrue);
      expect(isGoogleSampleAdId(kTestIosBannerAdUnitId), isTrue);
    });

    test('広告非対応のプラットフォームでユニット ID を求めたら落ちる', () {
      // 呼び出し側の間違い（Web で読み込もうとする等）を静かに通さない。
      expect(
        () => bannerAdUnitId(platform: AdPlatform.web, production: true),
        throwsStateError,
      );
      expect(
        () => bannerAdUnitId(platform: AdPlatform.other, production: true),
        throwsStateError,
      );
    });
  });

  // -------------------------------------------------------------------------
  group('非パーソナライズの徹底（要求を作る場所は1か所だけ）', () {
    final sources = _libSources();

    test('google_mobile_ads を import しているのは1ファイルだけ', () {
      final importers = {
        for (final e in sources.entries)
          if (e.value.contains('package:google_mobile_ads/')) e.key,
      };
      expect(
        importers,
        {'lib/ui/widgets/ad_banner_box_mobile.dart'},
        reason: '**Web では google_mobile_ads を読み込めない**'
            '（dart:io を使うのでコンパイルが通らない）。'
            '入口は条件つき import の先だけに保つこと',
      );
    });

    test('AdRequest を作っているのは 1 か所だけ', () {
      final sites = <String, int>{};
      for (final e in sources.entries) {
        final n = RegExp(r'\bAdRequest\(').allMatches(e.value).length;
        if (n > 0) sites[e.key] = n;
      }
      expect(
        sites,
        {'lib/ui/widgets/ad_banner_box_mobile.dart': 1},
        reason: '広告要求が複数の場所で作られている。**片方だけ '
            'nonPersonalizedAds を付け忘れると、そこだけ追跡広告になる。**'
            'ATT を実装していないので、追跡の同意は取れない',
      );
    });

    test('その 1 か所が非パーソナライズを指定している', () {
      final src = sources['lib/ui/widgets/ad_banner_box_mobile.dart']!;
      // `\b` を付けないと `buildAdRequest()` にも当たる。
      final call = _only(
        src,
        RegExp(r'\bAdRequest\([^)]*\)'),
        'AdRequest の生成',
      ).group(0)!;
      expect(
        call.replaceAll(' ', ''),
        contains('nonPersonalizedAds:true'),
        reason: '広告要求が非パーソナライズになっていない',
      );
    });
  });

  // -------------------------------------------------------------------------
  group('設置箇所（全主要画面共通の外枠に1か所だけ）', () {
    final sources = _libSources();

    test('AdBannerSlot を置いているのは app_router.dart の1か所だけ', () {
      // **AppShell は provider に触らない外枠のまま保つ**ため、広告の実体は
      // ProviderScope 配下の app_router.dart（ShellRoute）から `bottomBanner`
      // として1度だけ注入する。個別画面には置かない。
      final users = {
        for (final e in sources.entries)
          if (e.key != 'lib/ui/widgets/ad_banner_slot.dart' &&
              e.value.contains('AdBannerSlot('))
            e.key,
      };
      expect(
        users,
        {'lib/ui/app_router.dart'},
        reason: '広告の設置箇所が増減している。**全主要画面共通の外枠を組む '
            'app_router.dart の ShellRoute に1か所だけ**注入する',
      );
    });

    test('app_router.dart に置いてあるのはちょうど1つ', () {
      final src = sources['lib/ui/app_router.dart']!;
      expect(
        RegExp(r'AdBannerSlot\(').allMatches(src),
        hasLength(1),
        reason: '外枠は全画面で共有しているので、置くのは1か所でよい',
      );
    });

    test('AppShell が注入されたバナーを bottomBanner として受け取り描く', () {
      // **注入の配線が外れていないこと。** AppShell 側でパラメータを受けて
      // 下部に描いていなければ、app_router で渡しても画面には出ない。
      final src = sources['lib/ui/shell/app_shell.dart']!;
      expect(src, contains('this.bottomBanner'),
          reason: 'AppShell が bottomBanner を受け取っていない');
      expect(
        RegExp(r'\bbottomBanner\b').allMatches(src).length,
        greaterThanOrEqualTo(2),
        reason: 'AppShell が受け取った bottomBanner を描いていない'
            '（受け口だけで下部に置いていない）',
      );
    });
  });

  // -------------------------------------------------------------------------
  group('app-ads.txt（アプリ内広告の在庫証明）', () {
    final appAds = File('web/app-ads.txt');
    final ads = File('web/ads.txt');

    test('web/ に置いてある（リポジトリ直下ではない）', () {
      expect(
        appAds.existsSync(),
        isTrue,
        reason: 'web/app-ads.txt が無い。**web/ の中だけが build/web へ運ばれて'
            '配信される**',
      );
    });

    test('ads.txt と発行者が一致する（片方だけ直す事故を止める）', () {
      String pub(File f) =>
          RegExp(r'pub-\d+').firstMatch(f.readAsStringSync())!.group(0)!;
      expect(
        pub(appAds),
        pub(ads),
        reason: 'app-ads.txt と ads.txt の publisher ID が違う',
      );
    });

    test('中身が ads.txt と同じ1行（DIRECT と認証 ID まで）', () {
      expect(appAds.readAsStringSync().trim(), ads.readAsStringSync().trim());
    });

    test('配信される（catch-all rewrite に飲まれない・ads.txt と同じ扱い）', () {
      // Firebase Hosting は静的ファイルを rewrite より先に返すので、build/web に
      // 実ファイルが在れば `**` → /index.html に落ちない。見るべきは
      // 「web/ に在る」＋「hosting.public が build/web」＋「ignore に当たらない」で、
      // **ads.txt とまったく同じ扱いになっていること**。
      final json =
          jsonDecode(File('firebase.json').readAsStringSync())
              as Map<String, dynamic>;
      final hosting = json['hosting'] as Map<String, dynamic>;
      expect(hosting['public'], 'build/web');

      for (final pattern in (hosting['ignore'] as List).cast<String>()) {
        final re = _globToRegExp(pattern);
        for (final path in ['ads.txt', 'app-ads.txt']) {
          expect(
            re.hasMatch(path),
            isFalse,
            reason: 'firebase.json の ignore "$pattern" が $path を配信から外している',
          );
        }
      }

      // **rewrite の当たり方が ads.txt と同じであること。** 静的ファイルは
      // rewrite より先に返るので `**` に当たること自体は問題ない。危ないのは
      // 「片方にだけ効く rewrite」なので、2つの当たり方が同じかで見る。
      for (final r in (hosting['rewrites'] as List).cast<Map>()) {
        final re = _globToRegExp(r['source'] as String);
        expect(
          re.hasMatch('/app-ads.txt'),
          re.hasMatch('/ads.txt'),
          reason: 'firebase.json の rewrite "${r['source']}" が ads.txt と '
              'app-ads.txt を違う扱いにしている',
        );
      }
    });
  });

  // -------------------------------------------------------------------------
  group('画面経由（実際に描いて確かめる）', () {
    // **実 SDK は widget test で動かせない**（プラットフォームチャンネルを使う）。
    // ここで確かめるのは**枠を出すかどうかの判定**——[AdBannerSlot] が
    // プラットフォームとプレミアムに応じて [AdBannerBox] を出す／畳むこと。

    /// [AdBannerSlot] を1枚だけ描く。判定は**実効プレミアム**
    /// `isPremiumOrAdminProvider`（`AsyncValue<bool>`）を差し替える。
    /// サイト管理者かどうかの合成（プレミアム or サイト管理者）は上流の
    /// プロバイダの責務なので、ここでは合成後の実効値を直接渡す。
    Future<void> pump(
      WidgetTester tester, {
      required AdPlatform platform,
      required AsyncValue<bool> premium,
    }) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [isPremiumOrAdminProvider.overrideWithValue(premium)],
          child: MaterialApp(
            home: Scaffold(body: AdBannerSlot(platform: platform)),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('Android の非プレミアムには広告枠が出る', (tester) async {
      await pump(
        tester,
        platform: AdPlatform.android,
        premium: const AsyncData(false),
      );
      expect(
        find.byType(AdBannerBox),
        findsOneWidget,
        reason: 'ここが出ないと、下の「出ない」各件は前提が壊れていても通ってしまう',
      );
    });

    testWidgets('iOS の非プレミアムにも広告枠が出る', (tester) async {
      await pump(
        tester,
        platform: AdPlatform.ios,
        premium: const AsyncData(false),
      );
      expect(find.byType(AdBannerBox), findsOneWidget);
    });

    testWidgets('プレミアムには出ない', (tester) async {
      await pump(
        tester,
        platform: AdPlatform.android,
        premium: const AsyncData(true),
      );
      expect(find.byType(AdBannerBox), findsNothing);
    });

    testWidgets('サイト管理者（実効プレミアム）には出ない（仕様書 4.1）', (tester) async {
      // サイト管理者はプレミアム機能をすべて持つ＝広告も出さない。
      // 上流で `プレミアム or サイト管理者` を合成した実効値（true）が届く。
      await pump(
        tester,
        platform: AdPlatform.android,
        premium: const AsyncData(true),
      );
      expect(find.byType(AdBannerBox), findsNothing);
    });

    testWidgets('読み込み中は出ない（「まだ分からない」を混ぜない）', (tester) async {
      await pump(
        tester,
        platform: AdPlatform.android,
        premium: const AsyncLoading(),
      );
      expect(find.byType(AdBannerBox), findsNothing);
    });

    testWidgets('Web には出ない', (tester) async {
      await pump(
        tester,
        platform: AdPlatform.web,
        premium: const AsyncData(false),
      );
      expect(find.byType(AdBannerBox), findsNothing);
    });

    testWidgets('非対応プラットフォームには出ない', (tester) async {
      await pump(
        tester,
        platform: AdPlatform.other,
        premium: const AsyncData(false),
      );
      expect(find.byType(AdBannerBox), findsNothing);
    });
  });

  // -------------------------------------------------------------------------
  group('現在のプラットフォーム判定', () {
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    test('kIsWeb でないときは defaultTargetPlatform に従う', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(currentAdPlatform, AdPlatform.android);
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(currentAdPlatform, AdPlatform.ios);
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      expect(currentAdPlatform, AdPlatform.other);
    });
  });
}
