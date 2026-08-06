/// リスト名の正規化（仕様書 5.1 / 13.3）
///
/// **回帰テスト。** この関数はクライアント（Dart）とサーバー（TypeScript）の
/// 両方にあり、同じ結果になることが前提になっている。
/// ところが Dart 側だけスラッシュの置き換えを忘れており、`a/b` という名前で
/// ドキュメント参照が壊れる状態だった（監査 第2回）。
///
/// しかも「揃っていること」を確かめるはずのサーバー側のテストが、
/// **スラッシュを含まない入力しか渡していなかった**。両者が一致する唯一の
/// 領域だけを確かめており、食い違いをそのまま隠していた。
///
/// ここの表は `functions/test/domain.test.ts` の同名のテストと**同じ内容**。
/// 片方を変えたらもう片方も直すこと。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:music_list_app/data/firestore_paths.dart';

void main() {
  group('リスト名の正規化', () {
    test('前後の空白と大文字小文字を吸収する', () {
      expect(normalizeListName('  Practice  '), 'practice');
      expect(normalizeListName('PRACTICE'), 'practice');
    });

    test('サーバー側と同じ結果になる', () {
      // functions/test/domain.test.ts の同名テストと同じ表。
      const cases = {
        '練習音源': '練習音源',
        '  Practice  ': 'practice',
        'PRACTICE': 'practice',
        // ここが抜けていた。スラッシュはパスの区切りになるため潰す。
        'a/b': 'a_b',
        'A/B/C': 'a_b_c',
        '  Foo / Bar  ': 'foo _ bar',
        '/leading': '_leading',
        'trailing/': 'trailing_',
      };
      cases.forEach((input, expected) {
        expect(normalizeListName(input), expected, reason: '入力: $input');
      });
    });

    test('正規化した名前はドキュメント ID として使える（区切りを含まない）', () {
      // Firestore のドキュメント ID にスラッシュが入ると、そこで階層が
      // 切れてしまう。`listNames/a/b` は `listNames/a` の下になり、
      // 奇数セグメントの不正な参照になる。
      for (final name in ['a/b', 'A/B/C', '/leading', 'trailing/']) {
        expect(normalizeListName(name).contains('/'), isFalse);
      }
    });
  });
}
