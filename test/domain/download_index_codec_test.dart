/// 目録の JSON 変換（docs/DOWNLOAD-DESIGN.md 3.5）
///
/// **形が 2 か所にならないことを、ここで固定する。** 項目の一覧は
/// `lib/domain/download_index.dart` にしか無く、`DownloadIndexCodec` は
/// その型を組み立てて返すだけ。往復して失われる項目があれば、
/// **どこかに 2 つ目の形ができている**ということなので、ここが落ちる。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:music_list_app/data/downloads/download_index_codec.dart';
import 'package:music_list_app/domain/download_index.dart';
import 'package:music_list_app/domain/local_date.dart';

DownloadedItem _item({
  String itemId = 'item-1',
  String listId = 'list-1',
  String storagePath = 'lists/list-1/items/item-1/1755200000000-take3.wav',
  String localAudio = 'list-1/item-1/audio-1755200000000.wav',
}) => DownloadedItem(
  listId: listId,
  listName: 'バンド練習 2026',
  itemId: itemId,
  seq: 42,
  date: LocalDate.tryParse('2026-08-01')!,
  storagePath: storagePath,
  fileName: 'take3.wav',
  contentType: 'audio/wav',
  sizeBytes: 41234567,
  localAudio: localAudio,
  localBytes: 41234500,
  downloadedAt: DateTime.fromMillisecondsSinceEpoch(1755290000000),
  title: '通し 3 回目',
  artist: 'みんな',
  commentsSyncedAt: DateTime.fromMillisecondsSinceEpoch(1755290001000),
);

void main() {
  group('index.json', () {
    test('往復しても 1 項目も落ちない（形が 2 か所にならないための保険）', () {
      final index = DownloadIndex(
        lastVerifiedAt: DateTime.fromMillisecondsSinceEpoch(1755300000000),
        allowMobileData: true,
        items: [_item()],
      );

      final back = DownloadIndexCodec.tryDecode(
        DownloadIndexCodec.encode(index),
      );

      expect(back, isNotNull);
      expect(back!.version, kDownloadIndexVersion);
      expect(back.lastVerifiedAt, index.lastVerifiedAt);
      expect(back.allowMobileData, isTrue);
      expect(back.items, hasLength(1));

      final item = back.items.single;
      final source = index.items.single;
      expect(item.listId, source.listId);
      expect(item.listName, source.listName);
      expect(item.itemId, source.itemId);
      expect(item.seq, source.seq);
      expect(item.date, source.date);
      expect(item.title, source.title);
      expect(item.artist, source.artist);
      expect(item.storagePath, source.storagePath);
      expect(item.fileName, source.fileName);
      expect(item.contentType, source.contentType);
      expect(item.sizeBytes, source.sizeBytes);
      expect(item.localAudio, source.localAudio);
      expect(item.localImage, source.localImage);
      expect(item.localBytes, source.localBytes);
      expect(item.downloadedAt, source.downloadedAt);
      expect(item.commentsSyncedAt, source.commentsSyncedAt);
    });

    test('3.5 が挙げた項目名で書く', () {
      // **名前を勝手に変えない。** 3.5 の例と食い違うと、次に読む人が
      // 仕様と実物のどちらが正しいかを調べ直すことになる。
      final map = DownloadIndexCodec.toMap(DownloadIndex(items: [_item()]));
      expect(
        map.keys,
        containsAll(<String>[
          'version',
          'lastVerifiedAt',
          'allowMobileData',
          'items',
        ]),
      );
      final item = (map['items'] as List).single as Map<String, dynamic>;
      expect(
        item.keys,
        containsAll(<String>[
          'listId',
          'listName',
          'itemId',
          'seq',
          'date',
          'title',
          'artist',
          'storagePath',
          'fileName',
          'contentType',
          'sizeBytes',
          'localAudio',
          'localImage',
          'localBytes',
          'downloadedAt',
          'commentsSyncedAt',
        ]),
      );
    });

    test('使用量はサーバー側ではなく端末の実測を足す（6.4）', () {
      final index = DownloadIndex(
        items: [
          _item(itemId: 'a', localAudio: 'list-1/a/audio-1.wav'),
          _item(itemId: 'b', localAudio: 'list-1/b/audio-2.wav'),
        ],
      );
      // localBytes（41234500）× 2。sizeBytes（41234567）ではない。
      expect(index.localBytesTotal, 82469000);
    });

    test('壊れていたら null（空の目録に倒さない）', () {
      // **空にすると、4.7 の掃除が全部を孤児として消す。**
      expect(DownloadIndexCodec.tryDecode('{'), isNull);
      expect(DownloadIndexCodec.tryDecode('[]'), isNull);
      expect(DownloadIndexCodec.tryDecode('{"items": 3}'), isNull);
    });

    test('1 件でも読めなければ、目録ごと読めなかったことにする', () {
      // 黙って飛ばすと、その曲のファイルが孤児になって次の掃除で消える。
      const source =
          '{"version":1,"items":[{"listId":"l","itemId":"i",'
          '"storagePath":"p","localAudio":"a","date":"2026-08-01"}]}';
      // downloadedAt が無い＝読めない。
      expect(DownloadIndexCodec.tryDecode(source), isNull);
    });

    test('中身が空でも、目録として読める', () {
      final index = DownloadIndexCodec.tryDecode(
        DownloadIndexCodec.encode(const DownloadIndex()),
      );
      expect(index, isNotNull);
      expect(index!.items, isEmpty);
      expect(index.lastVerifiedAt, isNull);
      // **既定は Wi-Fi のみ**（論点 11b）。
      expect(index.allowMobileData, isFalse);
    });
  });

  group('comments.json', () {
    test('path / parentId をそのまま持つので、comment_tree にそのまま渡せる', () {
      // **別の組み立て方を作らないための保険**（3.5）。`path` が落ちると、
      // オフラインでは返信の親子関係を組み直せない。
      final comments = [
        OfflineComment(
          id: 'c1',
          parentId: null,
          path: const [],
          createdAt: DateTime.fromMillisecondsSinceEpoch(1755280000000),
          body: '親',
          authorName: '山田',
          status: 'active',
        ),
        OfflineComment(
          id: 'c2',
          parentId: 'c1',
          path: const ['c1'],
          createdAt: DateTime.fromMillisecondsSinceEpoch(1755280001000),
          body: '返信',
          authorName: '鈴木',
          status: 'deleted',
        ),
      ];

      final back = DownloadIndexCodec.decodeComments(
        DownloadIndexCodec.encodeComments(
          itemId: 'item-1',
          syncedAt: DateTime.fromMillisecondsSinceEpoch(1755290000000),
          comments: comments,
        ),
      );

      expect(back, hasLength(2));
      expect(back[1].id, 'c2');
      expect(back[1].parentId, 'c1');
      expect(back[1].path, ['c1']);
      expect(back[1].depth, 1);
      expect(back[1].createdAt, comments[1].createdAt);
      // **削除済みも持つ**（ツリーの親になるため）。
      expect(back[1].status, 'deleted');
      // **authorName は解決済みで持つ**（3.5）。オフラインでは
      // `users/{uid}` を引けない。
      expect(back[1].authorName, '鈴木');
    });

    test('読めない中身でも空で返す（音源は聴けるため）', () {
      expect(DownloadIndexCodec.decodeComments('{'), isEmpty);
      expect(DownloadIndexCodec.decodeComments('{"comments":{}}'), isEmpty);
    });
  });
}
