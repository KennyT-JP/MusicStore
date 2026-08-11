/// 使い方へのリンクが、実際に存在する節を指しているか（仕様書 14.2）
///
/// **画面のヘルプは、マニュアルの節へ直接飛ぶ。** 節の名前を変えたり
/// 消したりすると、押しても何も起きない（ページの先頭が出るだけ）ため、
/// **押した人には壊れたことが分からない。**
///
/// そこで、**公開しているマニュアルそのものを読んで**突き合わせる。
/// 対応表を書き写すと、片方だけ直したときに気づけない
/// （docs/AUDIT-CHECKLIST.md「注意書きを、仕組みと数えない」）。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_list_app/domain/help_links.dart';

/// 公開しているマニュアル（配信先の `/help/{言語}/`）。
const _manuals = {
  'ja': 'web/help/ja/index.html',
  'en': 'web/help/en/index.html',
};

/// `<h2 id="...">` の id を集める。
Set<String> _anchorsIn(String html) => RegExp(r'''id\s*=\s*["']([^"']+)["']''')
    .allMatches(html)
    .map((m) => m.group(1)!)
    .toSet();

void main() {
  group('マニュアルの節', () {
    for (final entry in _manuals.entries) {
      test('${entry.key}: すべての飛び先が存在する', () {
        final file = File(entry.value);
        expect(
          file.existsSync(),
          isTrue,
          reason: '${entry.value} が無い。画面のヘルプが全部リンク切れになる。',
        );

        final anchors = _anchorsIn(file.readAsStringSync());
        final missing = HelpTopic.values
            .map((t) => t.anchor)
            .where((a) => !anchors.contains(a))
            .toList();

        expect(
          missing,
          isEmpty,
          reason:
              '${entry.value} に、画面から飛ぶ節がありません: $missing\n'
              'マニュアル側で見出しを消した／名前を変えたときは、'
              'lib/domain/help_links.dart も直してください。',
        );
      });
    }

    test('日英で節の顔ぶれが同じ', () {
      // 片方にしか無い節があると、言語を切り替えたときだけ
      // リンク切れになる。**気づきにくい形**なので機械で見る。
      final ja = _anchorsIn(File(_manuals['ja']!).readAsStringSync());
      final en = _anchorsIn(File(_manuals['en']!).readAsStringSync());
      final topics = HelpTopic.values.map((t) => t.anchor).toSet();

      expect(ja.intersection(topics), en.intersection(topics));
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
      expect(helpUrlFor(HelpTopic.home, 'ja'), '/help/ja/#home');
      expect(helpUrlFor(HelpTopic.home, 'en'), '/help/en/#home');
    });

    test('用意していない言語は英語に倒す', () {
      // 2 言語しか無い。落ちるより、読める方を出す。
      expect(helpUrlFor(HelpTopic.home, 'fr'), '/help/en/#home');
    });
  });
}
