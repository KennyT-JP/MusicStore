/// コメントの入れ子ツリー組み立て（仕様書 9 / 13.3）
///
/// Firestore にはコメントをフラットに並べ、親 ID とルートからのパスを
/// 持たせている。項目のコメントは 1 回のクエリで全件取得し、
/// ここでツリーに組み直す。
library;

/// ツリー組み立ての入力となる、1 件のコメント。
class CommentNodeInput {
  const CommentNodeInput({
    required this.id,
    required this.parentId,
    required this.path,
    required this.createdAt,
  });

  final String id;

  /// 返信先のコメント ID。ルートコメントは null。
  final String? parentId;

  /// ルートから親までの ID を順に並べた配列。ルートコメントは空。
  final List<String> path;

  final DateTime createdAt;

  /// 階層の深さ。ルートは 0。
  int get depth => path.length;
}

/// 組み立て後のツリーの 1 ノード。
class CommentNode<T extends CommentNodeInput> {
  CommentNode({required this.value, required this.children});

  final T value;
  final List<CommentNode<T>> children;

  String get id => value.id;
  int get depth => value.depth;
}

/// コメントのツリー組み立て。
class CommentTree {
  const CommentTree._();

  /// フラットなコメント列を、ルートから始まるツリーに組み直す。
  ///
  /// - 同じ親を持つコメントどうしは **投稿日時の昇順**（古い順）で並べる。
  ///   日時が同一の場合は ID 順にして、並びが実行のたびに変わらないようにする。
  /// - 親が見つからないコメント（親が物理削除された等）は**捨てずにルート扱い**
  ///   にする。ツリーから漏れて画面に出なくなるほうが問題だと判断した。
  ///   なお 9 章の方針では、返信のある親はソフト削除して残すため、
  ///   通常このケースは発生しない。
  static List<CommentNode<T>> build<T extends CommentNodeInput>(
    Iterable<T> comments,
  ) {
    final all = comments.toList();
    final byId = <String, T>{for (final c in all) c.id: c};

    final childrenByParent = <String?, List<T>>{};
    for (final c in all) {
      // 親が存在しない場合はルート扱いにする。
      final parentId = (c.parentId != null && byId.containsKey(c.parentId))
          ? c.parentId
          : null;
      childrenByParent.putIfAbsent(parentId, () => <T>[]).add(c);
    }

    for (final list in childrenByParent.values) {
      list.sort(_compare);
    }

    List<CommentNode<T>> buildLevel(String? parentId, Set<String> visiting) {
      final children = childrenByParent[parentId] ?? const [];
      final nodes = <CommentNode<T>>[];
      for (final child in children) {
        // 循環参照の保険。データが壊れていても無限再帰させない。
        if (visiting.contains(child.id)) continue;
        nodes.add(
          CommentNode<T>(
            value: child,
            children: buildLevel(child.id, {...visiting, child.id}),
          ),
        );
      }
      return nodes;
    }

    return buildLevel(null, <String>{});
  }

  /// ツリーを、画面に上から順に描くための平坦な並びに変換する。
  ///
  /// 親の直下にその子が続くスレッド順になる。
  static List<CommentNode<T>> flatten<T extends CommentNodeInput>(
    List<CommentNode<T>> roots,
  ) {
    final result = <CommentNode<T>>[];
    void visit(CommentNode<T> node) {
      result.add(node);
      for (final child in node.children) {
        visit(child);
      }
    }

    for (final root in roots) {
      visit(root);
    }
    return result;
  }

  /// 新しく返信を作るときの `path` を求める（13.3）。
  ///
  /// ルートコメントなら空。返信なら「親のパス＋親の ID」。
  static List<String> pathForReply(CommentNodeInput? parent) {
    if (parent == null) return const [];
    return [...parent.path, parent.id];
  }

  static int _compare(CommentNodeInput a, CommentNodeInput b) {
    final byTime = a.createdAt.compareTo(b.createdAt);
    if (byTime != 0) return byTime;
    return a.id.compareTo(b.id);
  }
}
