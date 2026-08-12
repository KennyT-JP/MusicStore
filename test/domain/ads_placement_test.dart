/// 広告をどこに置くか（仕様書 12.5）
///
/// **AdSense の審査の 2 大指摘は、たいてい同じ事実から出る**——
/// 「広告のあるページに読めるテキストが無く、テキストのあるページに広告が
/// 無い」（共有ドキュメント `ナレッジベース.md` S-7、別プロジェクトで実際に
/// 2 指摘を受けた記録）。
///
/// このアプリは CanvasKit で画面を canvas に描くため、**アプリの画面には
/// HTML の文字が 1 つも残らない。** Googlebot は JS を実行するが、
/// 実行しても文字は増えない（`アンチパターン集.md` AP-43）。
/// だから配置はこう決めた。
///
/// | ページ | 広告 | 理由 |
/// | --- | --- | --- |
/// | アプリの画面（web/index.html） | **置かない** | 読めるテキストが無い |
/// | マニュアルの章ページ | 置く | 読み物。1 ページ 1,600 字以上 |
/// | 目次・プライバシーポリシー | 置かない | 薄い／法務のページ |
///
/// **この配置は、コメントではなくここで見張る。** 広告のスクリプトは
/// 1 行なので、戻すのも一瞬で、戻したことに誰も気づかない。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 広告のスクリプトの印。**client の指定まで見る**（別のアカウントで
/// 出していないこと）。
const _publisherId = 'pub-3984824596223175';
const _adScript = 'adsbygoogle.js?client=ca-$_publisherId';

/// 1 ページの本文の下限。`scripts/build-manual.mjs` の MIN_CHARS と揃える。
const _minChars = 1600;

const _languages = ['ja', 'en'];

/// 広告を出す読み物ページ（生成物）。`scripts/build-manual.mjs` の PAGES。
const _readingPages = ['start', 'lists', 'items', 'sharing', 'members', 'manage'];

/// 広告を出さないページ。
const _quietPages = ['index', 'privacy'];

String _read(String path) => File(path).readAsStringSync();

/// **コメントを外してから数える。** 外さないと、この配置を説明した
/// コメント（「広告は置かない。入れるなら pagead2… を許可」）が
/// 「広告がある」と判定される。逆向きの見張りでも、文字列の一致は
/// コメントの中で当たる（共有ドキュメント `アンチパターン集.md` AP-54)。
///
/// コメントアウトされた広告のコードは読み込まれないので、
/// 外して数えるのが正しい。
String _code(String html) => html.replaceAll(RegExp(r'<!--[\s\S]*?-->'), '');

/// タグを外した文章。**`<style>` の中身は本文ではない**ので落とす。
/// これを忘れると CSS の文字数で下限を満たしてしまい、
/// 「薄いページを作らない」という見張りが意味を失う。
String _plain(String html) => html
    .replaceAll(RegExp(r'<style>[\s\S]*?</style>'), '')
    .replaceAll(RegExp(r'<script[\s\S]*?</script>'), '')
    .replaceAll(RegExp(r'<!--[\s\S]*?-->'), '')
    .replaceAll(RegExp(r'<[^>]*>'), '')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

void main() {
  group('アプリの画面には広告を置かない', () {
    test('web/index.html に広告のコードが無い', () {
      final html = _code(_read('web/index.html'));

      expect(
        html,
        isNot(contains('adsbygoogle')),
        reason:
            'アプリの画面に広告のコードがあります。**canvas 描画なので'
            '読めるテキストが 0 で、「コンテンツを含まない画面における広告」'
            'の指摘に直結します**（ナレッジベース S-7）。',
      );
      expect(html, isNot(contains('pagead2.googlesyndication.com')));
    });

    test('広告枠の場所取りも残っていない', () {
      // 枠だけ残すと、**出ない広告のために画面の一部が埋まる。**
      final html = _code(_read('web/index.html'));
      expect(html, isNot(contains('id="ad-top"')));
      expect(html, isNot(contains('ad-placeholder')));
      expect(html, isNot(contains('setTopAdVisible')));
    });

    test('アプリの描画先は残す', () {
      // **広告枠を外しても #flutter-host は要る。** 読み込み中の表示を
      // この中に絶対配置しており、実機の狭い幅を作る確認手順
      // （docs/SETUP.md「ブラウザで実機を見る」）もこの要素を縮める。
      final html = _read('web/index.html');
      expect(html, contains('id="flutter-host"'));
      expect(_read('web/flutter_bootstrap.js'), contains('hostElement'));
    });
  });

  group('読み物のページに広告を置く', () {
    for (final lang in _languages) {
      for (final page in _readingPages) {
        test('$lang/$page: 広告があり、本文が $_minChars 字以上', () {
          final html = _read('web/help/$lang/$page.html');

          expect(
            html,
            contains(_adScript),
            reason: 'web/help/$lang/$page.html に広告のコードがありません',
          );

          final length = _plain(html).length;
          expect(
            length,
            greaterThanOrEqualTo(_minChars),
            reason:
                'web/help/$lang/$page.html の本文が $length 字です。'
                '**薄いページに広告を置くと「有用性の低いコンテンツ」の'
                '指摘に戻ります。** scripts/build-manual.mjs の PAGES で'
                '束ね方を見直してください。',
          );
        });
      }
    }

    test('広告のあるページから、プライバシーポリシーへ行ける', () {
      // **広告を出すページには、Cookie について書いた文書への導線が要る**
      // （ナレッジベース S-7）。
      for (final lang in _languages) {
        for (final page in _readingPages) {
          expect(
            _read('web/help/$lang/$page.html'),
            contains('privacy.html'),
            reason: 'web/help/$lang/$page.html にプライバシーポリシーへの導線がありません',
          );
        }
      }
    });

    test('プライバシーポリシーが、第三者配信の広告と Cookie に触れている', () {
      // 文書があるだけでは足りない。**広告 Cookie の説明が必要。**
      expect(_plain(_read('web/help/ja/privacy.html')), contains('Cookie'));
      expect(_plain(_read('web/help/ja/privacy.html')), contains('AdSense'));
      expect(_plain(_read('web/help/en/privacy.html')), contains('cookies'));
      expect(_plain(_read('web/help/en/privacy.html')), contains('AdSense'));
    });

    test('運営者と連絡先が、日英どちらにも同じ値で入っている', () {
      // **運営者の分からないポリシーは、無いのと同じ扱いになる。**
      // 値は scripts/build-manual.mjs の OPERATOR が正本で、原本には
      // 差し込み用の目印しか書かない。ここでは
      // 「差し込まれたか」と「日英で同じか」を見る。
      const name = "F's Factory";
      const contact = 'support@session-concierge.jp';

      for (final lang in _languages) {
        final page = _read('web/help/$lang/privacy.html');
        expect(page, contains(name), reason: '$lang のポリシーに運営者名がありません');
        expect(page, contains(contact), reason: '$lang のポリシーに連絡先がありません');
        expect(
          RegExp(r'%[A-Z_]+%').hasMatch(page),
          isFalse,
          reason: '$lang のポリシーに差し込めなかった目印が残っています',
        );
      }
    });
  });

  group('広告を置かないページ', () {
    for (final lang in _languages) {
      for (final page in _quietPages) {
        test('$lang/$page: 広告が無い', () {
          // 目次は薄く、プライバシーポリシーは読ませる文書。
          // **どちらも広告を置く場所ではない。**
          expect(_read('web/help/$lang/$page.html'), isNot(contains('adsbygoogle')));
        });
      }
    }
  });

  group('所有者の証明と、隠していないこと', () {
    test('ads.txt が同じパブリッシャー ID を書いている', () {
      // **片方だけでは審査に通らない。**
      final adsTxt = _read('web/ads.txt');
      expect(adsTxt, contains(_publisherId));
      expect(adsTxt, contains('DIRECT'));
    });

    test('robots.txt でアプリの画面を隠していない', () {
      // **隠して誤魔化すのは違反**（ナレッジベース S-7）。広告が
      // 「中身の無い画面」に出ている事実は変わらず、サイトの大部分が
      // 検索から消えるだけ。いまは robots.txt を置いていない。
      final robots = File('web/robots.txt');
      if (!robots.existsSync()) return;
      expect(
        robots.readAsStringSync(),
        isNot(contains('Disallow: /')),
        reason: 'アプリの画面を Disallow で隠してはいけません',
      );
    });
  });
}
