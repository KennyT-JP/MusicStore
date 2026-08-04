/// コメントの入れ子ツリーのテスト（仕様書 9 / 13.3）
///
/// 「返信は無制限の入れ子」を、フラットな保存から正しく組み直せるかを検証する。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:music_list_app/domain/comment_tree.dart';

/// テスト用のコメント。
class _Comment extends CommentNodeInput {
  const _Comment({
    required super.id,
    required super.parentId,
    required super.path,
    required super.createdAt,
  });
}

void main() {
  final base = DateTime.utc(2026, 8, 4, 12);

  _Comment comment(
    String id, {
    String? parent,
    List<String> path = const [],
    int minutes = 0,
  }) => _Comment(
    id: id,
    parentId: parent,
    path: path,
    createdAt: base.add(Duration(minutes: minutes)),
  );

  List<String> idsOf(List<CommentNode<_Comment>> roots) =>
      CommentTree.flatten(roots).map((n) => n.id).toList();

  group('ツリーの組み立て', () {
    test('ルートコメントだけなら並列に並ぶ', () {
      final roots = CommentTree.build([
        comment('a', minutes: 0),
        comment('b', minutes: 1),
      ]);
      expect(roots.length, 2);
      expect(idsOf(roots), ['a', 'b']);
    });

    test('返信が親の下にぶら下がる', () {
      final roots = CommentTree.build([
        comment('a', minutes: 0),
        comment('a-1', parent: 'a', path: ['a'], minutes: 1),
      ]);
      expect(roots.length, 1);
      expect(roots.first.children.map((n) => n.id), ['a-1']);
    });

    test('何段でもぶら下げられる（無制限の入れ子）', () {
      // 9 章の「返信への返信…と、何段でもぶら下げられる」を確認する。
      final comments = <_Comment>[comment('c0', minutes: 0)];
      final path = <String>[];
      for (var depth = 1; depth <= 20; depth++) {
        path.add('c${depth - 1}');
        comments.add(
          comment(
            'c$depth',
            parent: 'c${depth - 1}',
            path: List.of(path),
            minutes: depth,
          ),
        );
      }

      final roots = CommentTree.build(comments);
      expect(roots.length, 1);

      final flattened = CommentTree.flatten(roots);
      expect(flattened.length, 21);
      expect(flattened.last.id, 'c20');
      expect(flattened.last.depth, 20);
    });

    test('スレッド順（親の直下に子が続く）で平坦化される', () {
      final roots = CommentTree.build([
        comment('a', minutes: 0),
        comment('b', minutes: 10),
        comment('a-1', parent: 'a', path: ['a'], minutes: 1),
        comment('a-1-1', parent: 'a-1', path: ['a', 'a-1'], minutes: 2),
        comment('a-2', parent: 'a', path: ['a'], minutes: 3),
      ]);
      expect(idsOf(roots), ['a', 'a-1', 'a-1-1', 'a-2', 'b']);
    });
  });

  group('並び順', () {
    test('同じ親のコメントは投稿日時の古い順', () {
      final roots = CommentTree.build([
        comment('late', parent: 'root', path: ['root'], minutes: 5),
        comment('root', minutes: 0),
        comment('early', parent: 'root', path: ['root'], minutes: 1),
      ]);
      expect(roots.first.children.map((n) => n.id), ['early', 'late']);
    });

    test('投稿日時が同じなら ID 順で安定する', () {
      // 並びが実行のたびに変わらないようにする。
      final roots = CommentTree.build([
        comment('z', minutes: 0),
        comment('a', minutes: 0),
        comment('m', minutes: 0),
      ]);
      expect(idsOf(roots), ['a', 'm', 'z']);
    });
  });

  group('壊れたデータへの耐性', () {
    test('親が見つからないコメントは捨てずにルート扱いにする', () {
      // ツリーから漏れて画面に出なくなるほうが問題だと判断した。
      final roots = CommentTree.build([
        comment('a', minutes: 0),
        comment('orphan', parent: 'missing', path: ['missing'], minutes: 1),
      ]);
      expect(idsOf(roots), containsAll(['a', 'orphan']));
      expect(idsOf(roots).length, 2);
    });

    test('循環参照があっても無限再帰しない', () {
      final roots = CommentTree.build([
        comment('a', parent: 'b', path: ['b'], minutes: 0),
        comment('b', parent: 'a', path: ['a'], minutes: 1),
      ]);
      // どちらもルートに到達できないので、ツリーは空になる。
      // 少なくとも処理が終わることを確認する。
      expect(roots, isEmpty);
    });

    test('空の入力は空のツリーになる', () {
      expect(CommentTree.build(<_Comment>[]), isEmpty);
    });
  });

  group('返信の path 計算（13.3）', () {
    test('ルートコメントの path は空', () {
      expect(CommentTree.pathForReply(null), isEmpty);
    });

    test('返信の path は「親の path＋親の ID」', () {
      final parent = comment('a-1', parent: 'a', path: ['a']);
      expect(CommentTree.pathForReply(parent), ['a', 'a-1']);
    });

    test('深い階層でも積み上がる', () {
      final parent = comment(
        'c3',
        parent: 'c2',
        path: ['c0', 'c1', 'c2'],
      );
      expect(CommentTree.pathForReply(parent), ['c0', 'c1', 'c2', 'c3']);
    });
  });
}
