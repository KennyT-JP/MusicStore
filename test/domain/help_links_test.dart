/// 使い方へのリンクが、実際に存在する節を指しているか（仕様書 14.2）
///
/// **画面のヘルプは、マニュアルの節へ直接飛ぶ。** 節の名前を変えたり
/// 消したりすると、押しても何も起きない（ページの先頭が出るだけ）ため、
/// **押した人には壊れたことが分からない。**
///
/// そこで、**公開しているマニュアルそのものを読んで**突き合わせる。
/// 対応表を書き写すと、片方だけ直したときに気づけない
/// （docs/AUDIT-CHECKLIST.md「注意書きを、仕組みと数えない」）。
///
/// **2026-08-13 から、マニュアルは章ごとのページに分かれている。**
/// 原本は `docs/manual/{言語}.html`、配信するのは
/// `scripts/build-manual.mjs` が生成した `web/help/{言語}/*.html`。
/// そのため、ここで見るものが 1 つ増えた。
///
///   1. 飛び先の節が、**その節を載せたページに**実在するか
///   2. **原本の各章の文章が、生成物に入っているか**
///      （原本を直して生成し忘れると、配信されるのは古い文章のまま）
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_list_app/domain/help_links.dart';

const _languages = ['ja', 'en'];

String _generated(String lang, String page) =>
    File('web/help/$lang/$page.html').readAsStringSync();

String _source(String lang) => File('docs/manual/$lang.html').readAsStringSync();

/// `<h2 id="...">` の id を集める。
Set<String> _anchorsIn(String html) => RegExp(r'''<h2 id\s*=\s*["']([^"']+)["']''')
    .allMatches(html)
    .map((m) => m.group(1)!)
    .toSet();

/// タグを外した文章。**`<style>` の中身は数えない**（CSS は本文ではない）。
String _plain(String html) => html
    .replaceAll(RegExp(r'<style>[\s\S]*?</style>'), '')
    .replaceAll(RegExp(r'<[^>]*>'), '')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

void main() {
  group('マニュアルの節', () {
    for (final lang in _languages) {
      test('$lang: すべての飛び先が、そのページに実在する', () {
        for (final topic in HelpTopic.values) {
          final file = File('web/help/$lang/${topic.page}.html');
          expect(
            file.existsSync(),
            isTrue,
            reason:
                'web/help/$lang/${topic.page}.html が無い。'
                '${topic.name} のヘルプが 404 になる。\n'
                'node scripts/build-manual.mjs を実行してください。',
          );

          expect(
            _anchorsIn(file.readAsStringSync()),
            contains(topic.anchor),
            reason:
                'web/help/$lang/${topic.page}.html に節「${topic.anchor}」がありません。\n'
                'scripts/build-manual.mjs の PAGES と '
                'lib/domain/help_links.dart の page が食い違っています。',
          );
        }
      });
    }

    test('日英で節の顔ぶれが同じ', () {
      // 片方にしか無い節があると、言語を切り替えたときだけ
      // リンク切れになる。**気づきにくい形**なので機械で見る。
      final ja = _anchorsIn(_source('ja'));
      final en = _anchorsIn(_source('en'));
      final topics = HelpTopic.values.map((t) => t.anchor).toSet();

      expect(ja.intersection(topics), en.intersection(topics));
    });

    test('節とページの対応が、日英で同じ', () {
      // **束ね方を言語ごとに変えてはいけない。** 変えると、対応表は
      // 1 つなのに行き先が 2 通りになり、片方だけ壊れる。
      for (final topic in HelpTopic.values) {
        final pages = _languages
            .where((lang) => _anchorsIn(_generated(lang, topic.page)).contains(topic.anchor))
            .toList();
        expect(pages, _languages, reason: '${topic.anchor} の載っているページが日英で違う');
      }
    });
  });

  group('原本と生成物', () {
    // **生成し忘れを落とす。** 原本を直しても、生成物は自動では変わらない。
    // 比較は HTML 全文ではなく**文章**で行う（生成側は枠組み・目次・
    // リンクの書き換えを意図的に変えるため、全文比較では常に落ちる）。
    for (final lang in _languages) {
      test('$lang: 原本の全章が、生成物に入っている', () {
        // 章は行頭の `<h2 id="...">` で始まる。id の無い h2（目次）は
        // 下の `id == null` で落ちる。
        final chapters = _source(lang).split(RegExp(r'(?=^<h2 id=")', multiLine: true));

        for (final chapter in chapters) {
          final id = RegExp(r'^<h2 id="([^"]+)"').firstMatch(chapter)?.group(1);
          if (id == null) continue;

          final topic = HelpTopic.values.firstWhere(
            (t) => t.anchor == id,
            orElse: () => throw StateError(
              '原本の章「$id」に対応する HelpTopic がありません。'
              'lib/domain/help_links.dart に足してください。',
            ),
          );

          // **章の文章を、まるごと突き合わせる。** 書き出しだけを見ると、
          // 段落の途中を直して生成し忘れたときに素通りする。
          //
          // 生成側が変えるのはリンクの行き先（href）と枠組みだけなので、
          // **タグを外した文章は原本とまったく同じになる。**
          // 原本の最後の章には旧 footer が続くので、そこで切る。
          final footer = chapter.indexOf('\n<footer>');
          final text = _plain(footer < 0 ? chapter : chapter.substring(0, footer));

          expect(
            _plain(_generated(lang, topic.page)),
            contains(text),
            reason:
                '原本 docs/manual/$lang.html の章「$id」が、'
                'web/help/$lang/${topic.page}.html に入っていません。\n'
                '原本を直したら node scripts/build-manual.mjs を実行してください。',
          );
        }
      });
    }

    test('原本は配信されない', () {
      // **1 枚ページと分割ページの両方を配信すると、同じ文章が 2 か所に出る。**
      // 重複コンテンツは、広告審査でも検索でも不利になる。
      expect(
        File('web/help/ja/index.html').readAsStringSync(),
        isNot(contains('<h2 id="getting-started">')),
        reason: 'web/help/ja/index.html が 1 枚ページのままです（目次だけにする）',
      );
      expect(Directory('docs/manual').existsSync(), isTrue);
    });
  });

  group('画面と節の対応', () {
    test('主な画面が、それぞれ違う節へ飛ぶ', () {
      // 全部が同じ節へ飛ぶなら、画面ごとに分けている意味が無い。
      final routes = [
        '/',
        '/notifications',
        '/settings',
        '/my-requests',
        '/request-list',
        '/lists/abc',
        '/lists/abc/items/1',
        '/lists/abc/add',
        '/lists/abc/members',
        '/lists/abc/join-requests',
        '/lists/abc/settings',
        '/s/xyz',
        '/admin/users',
        '/sign-in',
        '/reset-password',
        '/sign-up',
      ];
      final topics = routes.map(helpTopicForRoute).toSet();

      // パスワード再設定はログインと同じ節（探す場所が同じため）。
      // それ以外は 1 画面 1 節。
      expect(topics.length, routes.length - 1);
    });

    test('リストの下の画面を、リスト本体と取り違えない', () {
      // **長いパスから先に見ないと、全部「リストの中身」になる。**
      expect(helpTopicForRoute('/lists/abc'), HelpTopic.list);
      expect(helpTopicForRoute('/lists/abc/members'), HelpTopic.members);
      expect(helpTopicForRoute('/lists/abc/settings'), HelpTopic.listSettings);
      expect(helpTopicForRoute('/lists/abc/items/1'), HelpTopic.item);
      expect(helpTopicForRoute('/lists/abc/items/1/edit'), HelpTopic.itemForm);
    });

    test('知らない画面でも、先頭へは行ける', () {
      expect(helpTopicForRoute('/nowhere'), HelpTopic.gettingStarted);
    });
  });

  group('開く言語', () {
    test('表示言語に従う', () {
      expect(helpUrlFor(HelpTopic.home, 'ja'), '/help/ja/lists.html#home');
      expect(helpUrlFor(HelpTopic.home, 'en'), '/help/en/lists.html#home');
    });

    test('用意していない言語は英語に倒す', () {
      // 2 言語しか無い。落ちるより、読める方を出す。
      expect(helpUrlFor(HelpTopic.home, 'fr'), '/help/en/lists.html#home');
    });
  });
}
