/// 端末に持つ目録の形（docs/DOWNLOAD-DESIGN.md 3.4 / 3.5）
///
/// **ファイルは触らない。** 型と、そこから直接出てくる値だけを固定する。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:music_list_app/domain/comment_tree.dart';
import 'package:music_list_app/domain/download_index.dart';
import 'package:music_list_app/domain/local_date.dart';

DownloadedItem _item({
  required String itemId,
  required int sizeBytes,
  required int localBytes,
  String listId = 'list-1',
}) => DownloadedItem(
  listId: listId,
  listName: 'バンド練習 2026',
  itemId: itemId,
  seq: 42,
  date: const LocalDate(2026, 8, 1),
  storagePath: 'lists/$listId/items/$itemId/1755200000000-take3.wav',
  fileName: 'take3.wav',
  contentType: 'audio/wav',
  sizeBytes: sizeBytes,
  localAudio: '$listId/$itemId/audio-1755200000000.wav',
  localBytes: localBytes,
  downloadedAt: DateTime.utc(2026, 8, 16),
);

void main() {
  test('既定は「まだ何も確認できていない・Wi-Fi のみ・空」', () {
    const index = DownloadIndex();

    expect(index.version, kDownloadIndexVersion);
    // **一度も確認が取れていなければ null。** OfflineAccessPolicy が
    // これを受けて「再生できない」に倒す（安全側）。
    expect(index.lastVerifiedAt, isNull);
    // **既定は Wi-Fi のみ**（論点 11b）。
    expect(index.allowMobileData, isFalse);
    expect(index.items, isEmpty);
  });

  test('使用量は端末上の実測（localBytes）を合計する（6.4）', () {
    // **サーバー側の sizeBytes を使わないこと。** 落とし損ねたぶんが
    // 数字に出ず、設定画面の「端末内の使用量」が実際と食い違う。
    final index = DownloadIndex(
      items: [
        _item(itemId: 'i1', sizeBytes: 1000, localBytes: 900),
        _item(itemId: 'i2', sizeBytes: 2000, localBytes: 2000),
      ],
    );

    expect(index.localBytesTotal, 2900);
  });

  test('空の目録の使用量は 0', () {
    expect(const DownloadIndex().localBytesTotal, 0);
  });

  test('音源の置き場所は downloads からの相対パス（3.5）', () {
    // **絶対パスで持たないこと。** iOS はアプリを更新するとコンテナの
    // 絶対パスが変わることがあり、更新の翌日に全部「ファイルが無い」
    // ことになる。
    final item = _item(itemId: 'i1', sizeBytes: 10, localBytes: 10);

    expect(item.localAudio.startsWith('/'), isFalse);
    expect(item.localImage, isNull, reason: '画像は無いこともある（論点 5）');
  });

  group('オフラインのコメント（3.5 の comments.json）', () {
    // **path / depth / parentId をそのまま持つので、comment_tree.dart の
    // ツリー組み立てをオフラインでもそのまま使える。**
    // **別の組み立て方を作らないこと。**
    OfflineComment comment(
      String id, {
      String? parentId,
      List<String> path = const [],
    }) => OfflineComment(
      id: id,
      parentId: parentId,
      path: path,
      createdAt: DateTime.utc(2026, 8, 16),
      body: '本文 $id',
      authorName: '藤田',
      status: 'active',
    );

    test('comment_tree.dart のツリー組み立てにそのまま渡せる', () {
      final roots = CommentTree.build([
        comment('c1'),
        comment('c2', parentId: 'c1', path: const ['c1']),
      ]);

      expect(roots, hasLength(1));
      expect(roots.first.id, 'c1');
      expect(roots.first.children.first.id, 'c2');
      expect(roots.first.children.first.depth, 1);
    });

    test('表示名は解決済みで持つ（オフラインでは users を引けない）', () {
      // 名前が変わっても端末側は古いまま出るが、
      // **「名前が古い」と「名前が出ない」なら前者のほうがまし。**
      expect(comment('c1').authorName, '藤田');
    });
  });
}
