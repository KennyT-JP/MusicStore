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

/// `//` コメント行を取り除く。
///
/// **コメントに書いただけのキー名は「使用あり」と数えない。**
/// `no_dead_code_test.dart` の `_stripComments` と同じ考え方だが、
/// private な関数は library（＝ファイル）をまたいで共有できないため、
/// ここに複製している。
///
/// **監査 第6回 B1: この判定を支える helper 自身に単体テストが無く、
/// 将来退行しても誰も気づけない状態だった。** 実際、この切り出し
/// 以前は `_allSource()` がコメントを一切除去していなかったため、
/// `lib/providers/app_providers.dart` のドキュメントコメント中に書いた
/// `l10n.withdrawnUser` という**文字列**だけでも「使用あり」の根拠に
/// 数えられてしまう状態だった（このキーは実際には画面側からも呼ばれて
/// いるため、これまで実害としては表面化していなかった）。
String _stripLineComments(String source) => source
    .replaceAll('\r\n', '\n')
    .split('\n')
    .map((line) => line.replaceFirst(RegExp(r'(?<!:)//.*$'), ''))
    .join('\n');

/// 文言キー [key] が、コメント除去済みの [source] の中で
/// 「l10n 経由の呼び出し」として使われているとみなせるか。
///
/// `l10n.キー名` か `AppL10n.of(context).キー名` の形を通ったものだけを
/// 「使われている」と数える。見出し語だけの一致（`\bキー名\b`）だと、
/// 無関係な識別子に食われて消しても緑のままだった
/// （監査 第4回・実験で実証。例: `join` が `List.join(...)` に、
/// `members` が Firestore のコレクション名に食われる）。
bool _isKeyUsed(String source, String key) =>
    RegExp('(?:\\bl10n|AppL10n\\.of\\([^)]*\\))\\.$key\\b').hasMatch(source);

/// 本番と、それを確かめるテストのすべての文字（コメント除去済み）。
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
  return _stripLineComments(buffer.toString());
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
          .where((key) => !_isKeyUsed(source, key))
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

  group('_stripLineComments（コメント除去 helper 自身の検査／監査 第6回 B1）', () {
    test('コメントだけに書いたキー名は、除去後は見つからない', () {
      const source = '// l10n.oldKey はもう使っていない\nfinal x = l10n.newKey;';
      final stripped = _stripLineComments(source);
      expect(stripped.contains('l10n.oldKey'), isFalse);
      expect(stripped.contains('l10n.newKey'), isTrue);
    });

    test('CRLF 混じりでもコメントを落とせる', () {
      const source =
          'final x = l10n.newKey;\r\n// l10n.oldKey は説明の中だけ\r\n';
      final stripped = _stripLineComments(source);
      expect(stripped.contains('l10n.newKey'), isTrue);
      expect(stripped.contains('l10n.oldKey'), isFalse);
    });

    test('URL の // はコメントとして落とさない（直前が `:`）', () {
      const source = "final url = 'https://example.com/l10n.notAKey';";
      expect(_stripLineComments(source).contains('l10n.notAKey'), isTrue);
    });
  });

  group('_isKeyUsed（文言キー判定 helper 自身の検査／監査 第6回 B1）', () {
    test('`l10n.キー名` の形は使用ありと判定する', () {
      expect(_isKeyUsed('final t = l10n.someKey;', 'someKey'), isTrue);
    });

    test('`AppL10n.of(context).キー名` の形は使用ありと判定する', () {
      expect(_isKeyUsed('AppL10n.of(context).someKey', 'someKey'), isTrue);
      // 引数名は `context` に限らない（`ctx` など）。
      expect(_isKeyUsed('AppL10n.of(ctx).someKey', 'someKey'), isTrue);
    });

    test('l10n. / AppL10n.of(...). の前置きが無い一致は使用ありとしない', () {
      // 監査 第4回で実証: `join` が `List.join(...)` に、
      // `members` が Firestore のコレクション名に食われて、
      // 消しても緑のままだった。
      expect(_isKeyUsed('final s = list.join(",");', 'join'), isFalse);
      expect(
        _isKeyUsed("firestore.collection('members')", 'members'),
        isFalse,
      );
    });

    test('単語境界を越えた部分一致は使用ありとしない', () {
      // `someKeyExtra` という別の識別子の中に `someKey` が部分文字列と
      // して含まれていても、`someKey` というキーの使用とは数えない。
      expect(_isKeyUsed('l10n.someKeyExtra', 'someKey'), isFalse);
    });
  });
}
