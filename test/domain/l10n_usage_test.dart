/// 文言の定義と、実際に使われている数（仕様書 2 章）
///
/// **回帰テスト。** 第 1 回の監査で、文言の定義数（123）を
/// 「画面に出る文字列の総数」と読んだ結果、**定義を通らない約 88 箇所が
/// 全量リストから丸ごと落ちた**（AUDIT-CHECKLIST 観点 3）。
///
/// 逆向きの穴もある。**定義したのに誰も使っていない文言**は、
/// 数だけ増えて何も守らない。第 3 回の監査で 6 件見つかった。
/// どれも別の文言に置き換わったあとの取り残しだった。
///
/// - `changeRole` → `changeRoleTo` に置き換わっていた
/// - `columnTitle` / `columnArtist` → 一覧の列には出していない
/// - `conflictTitle` → 本文（`conflictBody`）だけを出している
/// - `inviteRevokedDone` → `inviteRevoked` を使っている
/// - `joinRequestTitle` → 参加申請の画面は別の題を使っている
///
/// **取り残しは「英語版だけ古い」形で残りやすい。** 使われていない
/// ことに気づけないと、翻訳の点検もそこで止まる。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/repo_files.dart';

Set<String> _keysOf(String path) {
  final map = jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
  return map.keys.where((k) => !k.startsWith('@')).toSet();
}

/// 本番と、それを確かめるテストのすべての文字。
String _allSource() {
  final buffer = StringBuffer();
  for (final dir in ['lib', 'test']) {
    for (final entry in filesUnder(dir)) {
      // 生成物は「使っている」に数えない。定義を写しただけのため。
      //
      // **除外し損ねると、この確認は常に通る。** 生成物にはすべての
      // 文言が定義として並んでいるので、どれも「使われている」ことに
      // なってしまう。Windows では区切りが違って除外できていなかった
      // （2026-08-07）。`filesUnder` が `/` にそろえて返す。
      if (entry.path.contains('/l10n/')) continue;
      buffer.write(entry.file.readAsStringSync());
    }
  }
  return buffer.toString();
}

void main() {
  group('文言', () {
    test('日本語と英語で、定義が一対一になっている', () {
      final ja = _keysOf('lib/l10n/app_ja.arb');
      final en = _keysOf('lib/l10n/app_en.arb');

      expect(ja.difference(en), isEmpty, reason: '英語版に無い文言');
      expect(en.difference(ja), isEmpty, reason: '日本語版に無い文言');
    });

    test('定義したのに使われていない文言が無い', () {
      final source = _allSource();
      // **「l10n を通した参照」だけを数える。**
      //
      // 以前は `\bキー名\b` で探していたため、`join` は `.join(`、
      // `members` は Firestore のコレクション名という**無関係な識別子に
      // 食われて、消しても緑のまま**だった（監査 第4回・実験で実証）。
      // 文言として使うには `l10n.キー名` か `AppL10n.of(context).キー名`
      // の形を必ず通るので、その前置きがある参照だけを有効とする。
      final unused = _keysOf('lib/l10n/app_ja.arb')
          .where(
            (key) => !RegExp(
              '(?:\\bl10n|AppL10n\\.of\\([^)]*\\))\\.$key\\b',
            ).hasMatch(source),
          )
          .toList()
        ..sort();

      expect(
        unused,
        isEmpty,
        reason:
            '使われていない文言は、数だけ増えて何も守りません。\n'
            '画面から呼ぶか、定義を消してください: $unused',
      );
    });
  });
}
