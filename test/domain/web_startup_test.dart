/// 最初の表示までの待ち時間に効く指定（web/index.html）
///
/// **回帰テスト。** サイトを開いてから画面が出るまで 5 秒ほどかかり、
/// その間まったくの白い画面だった（2026-08-07）。
///
/// Flutter Web は「index.html を読む → flutter_bootstrap.js →
/// main.dart.js → 描画に必要なものを取りに行く」と順に辿るため、
/// **何が要るか分かるまでに時間がかかる。** 先に分かっている分は
/// 先に取りに行かせ、待っている間は待っていると分かる表示を出す。
///
/// `web/index.html` は Flutter の雛形をそのまま使うことが多く、
/// SDK の更新やテンプレートの入れ替えで**黙って元に戻りやすい**。
/// ここで固定する。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _indexHtml() => File('web/index.html').readAsStringSync();

void main() {
  group('最初の表示までの待ち時間', () {
    test('読み込み中であることを、アプリを待たずに出す', () {
      final html = _indexHtml();

      // HTML と CSS だけで書いてあること。script の到着を待つと、
      // いちばん見せたい最初の数秒に間に合わない。
      expect(html, contains('id="loading"'));
      final loadingAt = html.indexOf('id="loading"');
      // 説明文にも同じ名前が出るので、読み込む指定そのものを探す。
      final bootstrapAt = html.indexOf('<script src="flutter_bootstrap.js"');
      expect(bootstrapAt, isNot(-1), reason: 'アプリの読み込み指定が見つかりません');
      expect(
        loadingAt,
        lessThan(bootstrapAt),
        reason: '読み込み中の表示は、アプリの読み込みより前に書くこと',
      );
    });

    test('最初の描画が済んだら消す', () {
      final html = _indexHtml();

      // このイベント名は Flutter の engine が発火する。
      // 変えると読み込み中の表示が消えなくなる。
      expect(html, contains('flutter-first-frame'));
      expect(html, contains("getElementById('loading')"));
    });

    test('どの画面でも要るものは、先に取りに行かせる', () {
      final html = _indexHtml();

      // main.dart.js は flutter_bootstrap.js を読み終えて初めて分かる。
      // 先に知らせておくと、その分だけ早く始められる。
      expect(html, contains('rel="preload"'));
      expect(html, contains('main.dart.js'));

      // 描画部（CanvasKit）は Google の配信網から取る。
      // 接続の確立だけでも往復が要るので、先に済ませておく。
      expect(html, contains('rel="preconnect"'));
      expect(html, contains('gstatic.com'));
    });

    test('雛形のままの文言が残っていない', () {
      final html = _indexHtml();

      // 雛形の値はブラウザのタブや共有時にそのまま出る。
      expect(html, isNot(contains('A new Flutter project')));
      expect(html, isNot(contains('<title>music_list_app</title>')));
    });
  });

  group('Firebase の SDK を先に取りに行かせる（2026-08-08）', () {
    /// firebase_core_web が実際に読み込む SDK の版。
    ///
    /// **写さずに、その場で読む**（docs/AUDIT-CHECKLIST.md 観点 4）。
    /// 版が上がると URL が変わり、先読みが空振りするだけでなく
    /// 「先読みしたのに使わなかった」という無駄な取得になる。
    String sdkVersion() {
      final config = jsonDecode(
        File('.dart_tool/package_config.json').readAsStringSync(),
      );
      final package = (config['packages'] as List).firstWhere(
        (p) => p['name'] == 'firebase_core_web',
      );
      // **末尾の `/` を補う。** 無いまま resolve すると最後の区切りが
      // 置き換わり、パッケージ名ごと消えた場所を読みに行く。
      final raw = package['rootUri'] as String;
      final root = Uri.parse(raw.endsWith('/') ? raw : '$raw/');
      final source = File.fromUri(
        root.resolve('lib/src/firebase_sdk_version.dart'),
      ).readAsStringSync();
      final match = RegExp(
        r"supportedFirebaseJsSdkVersion\s*=\s*'([^']+)'",
      ).firstMatch(source);
      expect(match, isNotNull, reason: 'firebase_core_web の版を読めません');
      return match!.group(1)!;
    }

    /// firebase_core が初期化のときに読み込むもの。
    ///
    /// **firestore だけ名前が違う。** `firebase-firestore.js` ではなく
    /// `firebase-firestore-pipelines.js` を読む（firebase_core_web の
    /// `_initializeCore`）。取り違えると、使わないものを先読みして
    /// 帯域を食うだけになる。
    const services = [
      'firebase-app',
      'firebase-auth',
      'firebase-firestore-pipelines',
      'firebase-functions',
      'firebase-storage',
    ];

    test('最初の描画に要る SDK を、すべて先読みする', () {
      // **`await Firebase.initializeApp()` が終わるまで runApp しない。**
      // つまりこの 5 本が揃うまで 1 フレームも描かれない（lib/main.dart）。
      // 先読みが無いと、エンジンを読み終えたあとに直列でぶら下がる。
      final html = _indexHtml();
      final version = sdkVersion();

      for (final service in services) {
        final url =
            'https://www.gstatic.com/firebasejs/$version/$service.js';
        expect(
          html,
          contains('<link rel="modulepreload" href="$url"'),
          reason: '$service を先読みしていません（版 $version）',
        );
      }
    });

    test('SDK は modulepreload で先読みする（種類を合わせる）', () {
      // **firebase_core は SDK を動的な `import()` で読み込む。**
      // 取りに行くのはモジュールなので、`as="script"`（クラシック
      // スクリプト）で先読みしても種類が合わず、**使われないまま
      // もう一度取りに行く**。速くするどころか転送量が倍になる。
      // 2026-08-09 に実際にやり、開発者ツールに警告が 5 件出た。
      final html = _indexHtml();
      expect(
        html,
        isNot(contains('firebasejs/${sdkVersion()}/firebase-app.js" as="script"')),
        reason: 'モジュールは as="script" では先読みできません',
      );
    });

    test('使わないものを先読みしない', () {
      // 先読みして使わないと、帯域を食ったうえに警告が出る。
      final html = _indexHtml();
      expect(
        html,
        isNot(contains('firebase-firestore.js')),
        reason: '読み込まれるのは firebase-firestore-pipelines.js のほうです',
      );
    });
  });

  group('広告枠とアプリの置き場所（2026-08-09）', () {
    String bootstrap() => File('web/flutter_bootstrap.js').readAsStringSync();

    test('広告枠はアプリの外に置く', () {
      // **CanvasKit は画面を canvas に描く。** 広告の要素をアプリの
      // 画面の中には差し込めないので、body を縦並びにして
      // 上に広告枠・下にアプリを置く。
      final html = _indexHtml();
      expect(html, contains('id="ad-top"'));
      expect(html, contains('id="flutter-host"'));

      // 順番が逆だと、広告が画面の下に出る。
      expect(
        html.indexOf('id="ad-top"'),
        lessThan(html.indexOf('id="flutter-host"')),
      );
    });

    test('アプリの描画先を指定している', () {
      // **これが無いと body 全面に描かれ、広告枠と重なる。**
      expect(bootstrap(), contains('hostElement'));
      expect(bootstrap(), contains('flutter-host'));
    });

    test('ビルドが差し替える印を消していない', () {
      // **この 2 つはビルド時に flutter.js 本体と設定へ置き換わる。**
      // 消すとアプリが起動しない。
      final source = bootstrap();
      expect(source, contains('{{flutter_js}}'));
      expect(source, contains('{{flutter_build_config}}'));

      // **印は 1 つずつだけ。** 説明のつもりで書いたものにも
      // 中身が差し込まれ、起動しなくなる（SessionConcierge で実際に起きた）。
      expect(RegExp(r'\{\{flutter_js\}\}').allMatches(source), hasLength(1));
      expect(
        RegExp(r'\{\{flutter_build_config\}\}').allMatches(source),
        hasLength(1),
      );
    });

    test('読み込み中の表示が広告枠に重ならない', () {
      // fixed のままだと、body が縦並びになった時点で枠の上に重なる。
      final html = _indexHtml();
      final loading = html.substring(html.indexOf('#loading {'));
      expect(loading, contains('position: absolute'));
    });

    test('広告の出し分けの入口がある', () {
      // プレミアムには出さない予定。アプリ側から切り替えられるようにする。
      expect(_indexHtml(), contains('window.setTopAdVisible'));
    });

    test('AdSense のコードと ads.txt が揃っている', () {
      // **片方だけでは審査に通らない。** ads.txt は所有者の証明で、
      // 同じパブリッシャー ID を書く。
      const publisherId = 'pub-3984824596223175';
      expect(_indexHtml(), contains('adsbygoogle.js?client=ca-$publisherId'));

      final adsTxt = File('web/ads.txt').readAsStringSync();
      expect(adsTxt, contains(publisherId));
      expect(adsTxt, contains('DIRECT'));
    });
  });

  group('ブランドの画像（2026-08-09）', () {
    // brand/README.md が置き場所まで指定している。
    // **書いてある場所に、実物があること。** 参照だけ直して置き忘れると、
    // タブのアイコンやホーム画面の見た目が黙って壊れる。
    /// index.html が指しているもの（タブのアイコン・共有画像・読み込み中のロゴ）。
    const fromHtml = [
      'brand/favicon.svg',
      'brand/png/favicon-16.png',
      'brand/png/favicon-32.png',
      'brand/png/apple-touch-icon.png',
      'brand/png/og-image.png',
      'brand/logo-horizontal-light.svg',
      'brand/logo-horizontal-dark.svg',
    ];

    /// manifest.json が指しているもの（ホーム画面・インストール時）。
    /// **こちらは index.html には出てこない。** 一緒に確かめようとして
    /// 落ちた（2026-08-09）。見る場所を取り違えると、テストの側が嘘になる。
    const fromManifest = [
      'brand/png/icon-192.png',
      'brand/png/icon-512.png',
      'brand/png/icon-maskable-192.png',
      'brand/png/icon-maskable-512.png',
    ];

    test('参照している画像が実在する', () {
      for (final href in [...fromHtml, ...fromManifest]) {
        expect(
          File('web/$href').existsSync(),
          isTrue,
          reason: 'web/$href がありません',
        );
      }
    });

    test('index.html から参照している', () {
      final html = _indexHtml();
      for (final href in fromHtml) {
        expect(html, contains(href), reason: '$href を参照していません');
      }
    });

    test('PWA の一覧（manifest）も同じ場所を指している', () {
      final manifest = jsonDecode(
        File('web/manifest.json').readAsStringSync(),
      );
      final icons = (manifest['icons'] as List)
          .map((e) => (e as Map)['src'] as String)
          .toList();

      expect(icons, contains('brand/png/icon-192.png'));
      expect(icons, contains('brand/png/icon-512.png'));
      // **maskable を落とさない。** 無いと Android のホーム画面で
      // 白い枠に収められ、余白だらけの見た目になる。
      expect(
        (manifest['icons'] as List).where((e) => (e as Map)['purpose'] == 'maskable'),
        hasLength(2),
      );

      for (final src in icons) {
        expect(File('web/$src').existsSync(), isTrue, reason: '$src がありません');
      }
    });

    test('共有したときの画像は絶対 URL で指す', () {
      // 相対のままだと、読み取る側が解決できずに画像が出ない。
      final html = _indexHtml();
      expect(
        html,
        contains('<meta property="og:image" content="https://'),
        reason: 'og:image は絶対 URL で書くこと',
      );
    });
  });

  group('日本語フォントを最初の描画の邪魔にしない（2026-08-08）', () {
    String pubspec() => File('pubspec.yaml').readAsStringSync();

    test('pubspec の fonts: で宣言しない', () {
      // **`fonts:` に書くと、エンジンが読み終えるまで最初の描画が
      // 始まらない。** 圧縮後で 1.2MB あり、「画面が出るまで 5 秒」の
      // 主因だった。assets: として積み、描画のあとに読み込む
      // （lib/providers/font_provider.dart）。
      final text = pubspec();
      expect(
        RegExp(r'^\s*fonts:', multiLine: true).hasMatch(text),
        isFalse,
        reason: 'フォントを fonts: で宣言すると、最初の描画が待たされます',
      );
      expect(text, contains('assets/fonts/NotoSansJP-400.ttf'));
    });

    test('太字は同梱しない', () {
      // 約 1.2MB（圧縮後）を減らせて、失うのは見た目だけ。
      // CanvasKit が w400 から擬似的な太字を作る。
      expect(pubspec(), isNot(contains('NotoSansJP-700')));
    });

    test('実行時に読み込む口がある', () {
      // 同梱をやめたわけではない。既定のままだと日本語のグリフを
      // Google Fonts から取りに行き、遮断された環境で文字が出なくなる。
      final source = File(
        'lib/providers/font_provider.dart',
      ).readAsStringSync();
      expect(source, contains('FontLoader'));
      expect(source, contains('assets/fonts/NotoSansJP-400.ttf'));
    });

    test('読み込めなくても画面は出す', () {
      // フォントが載らないだけで、端末のフォントで動き続けられる。
      // ここで落とすと、字が違うというだけで画面が出なくなる。
      final source = File(
        'lib/providers/font_provider.dart',
      ).readAsStringSync();
      expect(source, contains('catch'));
    });
  });
}
