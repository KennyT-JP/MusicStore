/// 同期クエリの形と、索引の宣言（docs/DOWNLOAD-DESIGN.md 4.4・10 節の危険 7）
///
/// **索引が足りないことは、実行するまで分からない。そして
/// エミュレータは索引を強制しない。** 統合テストは緑のまま、
/// **本番だけが落ちる**——2026-08-10 に、ユーザー削除が本番で必ず
/// 失敗した件がこれだった（`firestore.indexes.json` の注記）。
///
/// ## いまの形なら索引は要らない（根拠）
///
/// | クエリ | 形 | 索引 |
/// | --- | --- | --- |
/// | `where('updatedAt', isGreaterThan: …)` | 単一フィールドの範囲・コレクション範囲 | **自動**（宣言しない） |
/// | `where(FieldPath.documentId, whereIn: …)` | キーによる絞り込み | **不要** |
///
/// **書いてはいけない、という向きにも注意。** このリポジトリの
/// `firestore.indexes.json` は冒頭で「単一フィールドの索引はここに
/// 書かない。書くと『このインデックスは不要』(400) で**配信が止まる**」と
/// 定めている。つまりこの件は「足りない」も「余計」も事故になる。
///
/// ## だからクエリの形のほうを固定する
///
/// **`orderBy` を 1 つ足すか、2 つ目の絞り込みを足した瞬間に、
/// 合成索引が要る。** そのときこのテストが落ちる。落ちたら
/// `firestore.indexes.json` に宣言を足し、下の期待も書き換えること。
/// **テストを消して通すのは、2026-08-10 と同じ事故をもう一度起こす道。**
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/repo_files.dart';

/// `//`・`///` のコメントを落とす（`download_storage_test.dart` と同じ手当て）。
///
/// **コメントに書いた名前は呼び出しではない。** ここは長い注記に
/// `orderBy` や `status` の話が出てくるので、落とさずに当てると
/// **説明文のせいで必ず落ちる。**
String _stripComments(String source) => source
    .replaceAll('\r\n', '\n')
    .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
    .split('\n')
    .map((line) => line.replaceFirst(RegExp(r'(?<!:)//.*$'), ''))
    .join('\n');

/// Firestore への絞り込みだけを数える。
///
/// **Dart の `Iterable.where` と混ぜない。** 素の `.where(` で数えると、
/// 空の ID を落とすだけの `.where((id) => id.isNotEmpty)` まで
/// 「クエリの絞り込み」に見えて、**索引が要るかどうかの判断が狂う。**
final _firestoreWhere = RegExp(r"\.where\(\s*(?:'|FieldPath)");

/// `lib/data/repositories/item_repository.dart` の、そのメソッドの中身だけ。
String _methodBody(String signature) {
  final source = _stripComments(
    filesUnder('lib/data/repositories')
        .firstWhere((e) => e.path.endsWith('item_repository.dart'))
        .file
        .readAsStringSync(),
  );

  final start = source.indexOf(signature);
  expect(
    start,
    isNot(-1),
    reason:
        '$signature が見つかりません。名前を変えたなら、'
        'このテストも一緒に直してください（黙って見張りが外れます）。',
  );

  // インデント 2 の閉じ括弧までが 1 メソッド。
  final end = source.indexOf('\n  }', start);
  expect(end, isNot(-1));
  return source.substring(start, end);
}

void main() {
  group('4.4 の同期クエリ（危険 7）', () {
    test('updatedAt の範囲だけで引いている', () {
      final body = _methodBody('Future<List<ListItem>> fetchItemsUpdatedAfter(');

      expect(
        body,
        contains("where('updatedAt', isGreaterThan:"),
        reason: '4.4 の「新しい項目だけを読む」はこの形',
      );
      expect(
        _firestoreWhere.allMatches(body).length,
        1,
        reason:
            '絞り込みが 2 つになると合成索引が要ります（危険 7）。\n'
            'firestore.indexes.json に宣言を足し、このテストも直してください。',
      );
      expect(
        body,
        isNot(contains('orderBy(')),
        reason:
            '範囲の項目以外で並べ替えると合成索引が要ります（危険 7）。\n'
            'エミュレータは索引を強制しないので、足りないことに'
            '統合テストでは気づけません。**本番だけが落ちます。**',
      );
    });

    test('status で絞っていない（削除された項目を拾うため）', () {
      final body = _methodBody('Future<List<ListItem>> fetchItemsUpdatedAfter(');

      expect(
        body,
        isNot(contains('status')),
        reason:
            '同期は「消えたものを端末からも消す」ために使います。\n'
            "status == 'active' で絞ると、削除された項目がクエリから消え、"
            '端末には落としたものが永遠に残ります（4.4・論点 11）。',
      );
    });

    test('存在の確認は、ドキュメント ID だけで引いている', () {
      final body = _methodBody('Future<List<ListItem>> fetchItemsByIds(');

      expect(body, contains('FieldPath.documentId'));
      expect(
        _firestoreWhere.allMatches(body).length,
        1,
        reason:
            'ドキュメント ID に別の絞り込みを重ねると、__name__ を含む'
            '合成索引が要ります（危険 7）。',
      );
      expect(body, isNot(contains('orderBy(')));
    });
  });

  group('firestore.indexes.json（危険 7）', () {
    late Map<String, dynamic> declared;

    setUpAll(() {
      declared =
          jsonDecode(File('firestore.indexes.json').readAsStringSync())
              as Map<String, dynamic>;
    });

    test('items の updatedAt を合成索引に書いていない', () {
      // **単一フィールドは書かないのが正しい。** 書くと配信が
      // 400 `this index is not necessary` で止まる
      // （firestore.indexes.json 冒頭の注記）。
      final offenders = (declared['indexes'] as List)
          .cast<Map<String, dynamic>>()
          .where((index) => index['collectionGroup'] == 'items')
          .where(
            (index) => (index['fields'] as List)
                .cast<Map<String, dynamic>>()
                .any((f) => f['fieldPath'] == 'updatedAt'),
          )
          .toList();

      expect(
        offenders,
        isEmpty,
        reason:
            'updatedAt は単一フィールドの範囲だけで引いており、'
            'コレクション範囲の単一フィールド索引は Firestore が'
            '自動で作ります。宣言すると配信が止まります。',
      );
    });

    test('items の updatedAt に fieldOverrides を置いていない', () {
      // **上書きを置くと、その項目の自動索引の設定を自分で持つことになる。**
      // 置いたうえで昇順を落とすと、4.4 のクエリが本番で失敗する。
      final offenders = (declared['fieldOverrides'] as List)
          .cast<Map<String, dynamic>>()
          .where(
            (o) =>
                o['collectionGroup'] == 'items' &&
                o['fieldPath'] == 'updatedAt',
          )
          .toList();

      expect(offenders, isEmpty);
    });

    test('既存の宣言を巻き添えにしていない', () {
      // 4.4 のために触る必要は無いファイルなので、いま要るものが
      // 残っていることだけ確かめる（消すと本番だけが落ちる）。
      final groups = (declared['indexes'] as List)
          .cast<Map<String, dynamic>>()
          .map((i) => i['collectionGroup'])
          .toList();
      expect(groups, containsAll(<String>['items', 'listRequests']));

      final overrides = (declared['fieldOverrides'] as List)
          .cast<Map<String, dynamic>>()
          .map((o) => '${o['collectionGroup']}.${o['fieldPath']}')
          .toList();
      expect(
        overrides,
        containsAll(<String>[
          'members.uid',
          'joinRequests.uid',
          'items.createdBy',
          'viewers.uid',
        ]),
      );
    });
  });
}
