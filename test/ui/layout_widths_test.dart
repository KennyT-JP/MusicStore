/// 画面の最大幅（仕様書 12.5・監査 第4回）
///
/// **広い画面で本文が横いっぱいに伸びると読みにくい**ので、画面ごとに
/// 上限を置いている。ところがその値は各画面に散らばった数字で、
/// **変えても誰も気づかない**（監査 第4回で「固定するテストが無い」と
/// 記録に回した項目。2026-08-15 に追加）。
///
/// ここでは**実際のソースを読む**。値を写して比べると、片方だけ直した
/// ときに気づけない（共有ドキュメント AP-54）。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 画面と、そこで使ってよい上限。
///
/// **狭い順に意味がある。**
///   420 … 入力だけの画面（ログイン・エラー表示）。1 列で読み切れる幅
///   480〜560 … 申請などの短い画面
///   640 … 曲の追加・編集。入力欄が多く、少し広くないと窮屈になる
const _expected = {
  'lib/ui/widgets/auth_scaffold.dart': 420,
  'lib/ui/widgets/async_view.dart': 420,
  'lib/ui/screens/share_link_screen.dart': 520,
  'lib/ui/screens/item_form_screen.dart': 640,
};

/// そのファイルに出てくる `maxWidth: N` を全部集める。
List<int> _widthsIn(String path) => RegExp(r'maxWidth:\s*(\d+)')
    .allMatches(File(path).readAsStringSync())
    .map((m) => int.parse(m.group(1)!))
    .toList();

void main() {
  group('画面の最大幅が変わっていないか', () {
    for (final entry in _expected.entries) {
      test('${entry.key} は ${entry.value}', () {
        expect(
          File(entry.key).existsSync(),
          isTrue,
          reason: '${entry.key} が無い。移動したならこの一覧も直すこと',
        );
        expect(
          _widthsIn(entry.key),
          contains(entry.value),
          reason:
              '${entry.key} の最大幅が変わっています。'
              '意図した変更なら、この一覧の数字も直してください',
        );
      });
    }

    test('極端に広い上限を置いていない', () {
      // **1000 を超えると、上限を置いた意味がほぼ無くなる**
      // （PC の画面いっぱいに 1 行が伸びる）。
      for (final path in _expected.keys) {
        for (final width in _widthsIn(path)) {
          expect(width, lessThanOrEqualTo(1000), reason: path);
        }
      }
    });
  });
}
