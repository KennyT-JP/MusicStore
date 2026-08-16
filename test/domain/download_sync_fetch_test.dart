/// 同期のためにサーバーから取ってくる（docs/DOWNLOAD-DESIGN.md 4.4）
///
/// **守るのは「1 曲ごとに必ず 1 つ答えを返す」こと。**
/// `DownloadRepository.syncWithServer` は、渡されなかった項目を
/// **「消えた」と読む**（`SyncAction.remove`）。取ってくる側が 1 件でも
/// 落とすと、**変わっていないだけの曲が端末から消える。**
///
/// | 元で起きたこと | 期待 |
/// | --- | --- |
/// | 何も起きていない | `keep`（**ここが抜けると全部消える**） |
/// | 直された（`storagePath` は同じ） | `keep` |
/// | 差し替えられた | `replace` |
/// | 削除された（ソフト削除） | `remove` |
/// | **ドキュメントごと消えた** | `remove` |
/// | URL 項目に変わった | `remove` |
///
/// **ソフト削除の行を `status` で絞ると落とせなくなる。**
/// 同期は「消えたものを端末からも消す」ために使うので、
/// `status == 'active'` で絞った瞬間に、削除された曲が端末に永遠に残る。
///
/// 判定そのもの（`DownloadSyncPolicy.decide`）は
/// `download_sync_test.dart` にある。ここで確かめるのは
/// **その判定に渡る材料が正しく揃うか**なので、材料を作ったあと
/// 実際に `decide` へ通して結果まで見る。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:music_list_app/data/models/list_item.dart';
import 'package:music_list_app/data/models/music_list.dart';
import 'package:music_list_app/data/repositories/download_repository.dart';
import 'package:music_list_app/data/repositories/download_sync_repository.dart';
import 'package:music_list_app/data/repositories/item_repository.dart';
import 'package:music_list_app/data/repositories/list_repository.dart';
import 'package:music_list_app/domain/download_index.dart';
import 'package:music_list_app/domain/download_sync.dart';
import 'package:music_list_app/domain/local_date.dart';
import 'package:music_list_app/providers/download_provider.dart';

class _FakeItemRepository extends Mock implements ItemRepository {}

class _FakeListRepository extends Mock implements ListRepository {}

class _FakeDownloadRepository extends Mock implements DownloadRepository {}

class _FakeSyncRepository extends Mock implements DownloadSyncRepository {}

// ---------------------------------------------------------------------------
// 道具
// ---------------------------------------------------------------------------

const _listId = 'list-1';

/// 端末が持っている 1 曲。
DownloadedItem _local({
  String itemId = 'i1',
  String listId = _listId,
  String storagePath = 'lists/list-1/items/i1/1000-take.wav',
  DateTime? downloadedAt,
}) => DownloadedItem(
  listId: listId,
  listName: 'バンド練習 2026',
  itemId: itemId,
  seq: 1,
  date: LocalDate.tryParse('2026-08-01')!,
  storagePath: storagePath,
  fileName: 'take.wav',
  contentType: 'audio/wav',
  sizeBytes: 8,
  localAudio: '$listId/$itemId/audio-1000.wav',
  localBytes: 8,
  downloadedAt:
      downloadedAt ?? DateTime.fromMillisecondsSinceEpoch(1755290000000),
);

/// サーバー側の 1 曲。[storagePath] が null なら URL 項目（ファイル無し）。
ListItem _server({
  String id = 'i1',
  String? storagePath = 'lists/list-1/items/i1/1000-take.wav',
  ContentStatus status = ContentStatus.active,
}) => ListItem(
  id: id,
  seq: 1,
  itemDate: LocalDate.tryParse('2026-08-01')!,
  kind: storagePath == null ? ItemKind.url : ItemKind.file,
  file: storagePath == null
      ? null
      : ItemFile(
          storagePath: storagePath,
          fileName: 'take.wav',
          sizeBytes: 8,
          contentType: 'audio/wav',
        ),
  url: storagePath == null ? 'https://example.com/x' : null,
  createdBy: 'u1',
  registrantDisplayName: '',
  status: status,
);

/// 取ってきた材料を、実際の判定に通す（4.4）。
SyncAction _actionFor(ServerItemSnapshot snapshot, DownloadedItem local) =>
    DownloadSyncPolicy.decide(
      serverStatus: snapshot.status,
      serverStoragePath: snapshot.item?.file?.storagePath,
      localStoragePath: local.storagePath,
    );

void main() {
  setUpAll(() {
    registerFallbackValue(DateTime.fromMillisecondsSinceEpoch(0));
    registerFallbackValue(<String>[]);
    registerFallbackValue(<String>{});
    registerFallbackValue(<ServerItemSnapshot>[]);
  });

  late _FakeItemRepository items;
  late _FakeListRepository lists;
  late DownloadSyncRepository repository;

  setUp(() {
    items = _FakeItemRepository();
    lists = _FakeListRepository();
    repository = DownloadSyncRepository(items, lists);

    when(() => lists.fetchList(any())).thenAnswer(
      (_) async => const MusicList(
        id: _listId,
        name: 'バンド練習 2026',
        createdBy: 'u1',
        adminCount: 1,
        memberCount: 2,
      ),
    );
    // 既定は「変わっていない」「消えていない」。各テストで上書きする。
    when(
      () => items.fetchItemsUpdatedAfter(any(), any()),
    ).thenAnswer((_) async => const <ListItem>[]);
    when(
      () => items.fetchItemsByIds(any(), any()),
    ).thenAnswer((_) async => const <ListItem>[]);
  });

  Future<List<ServerItemSnapshot>> fetch(List<DownloadedItem> local) =>
      repository.fetchServerItems(listId: _listId, localItems: local);

  // -------------------------------------------------------------------------
  // 何が返るか
  // -------------------------------------------------------------------------

  group('端末が持っている 1 曲ごとに 1 つ返る（4.4）', () {
    test('変わっていなければ keep（**ここが抜けると全部消える**）', () async {
      final local = _local();
      // 更新のクエリには上がってこない。存在の確認では見つかる。
      when(
        () => items.fetchItemsByIds(any(), any()),
      ).thenAnswer((_) async => [_server()]);

      final snapshots = await fetch([local]);

      expect(snapshots, hasLength(1));
      expect(
        _actionFor(snapshots.single, local),
        SyncAction.keep,
        reason:
            '更新のクエリに上がってこない＝変わっていない、である。'
            '答えを返さないと syncWithServer が「消えた」と読み、'
            '端末から消える。',
      );
    });

    test('直されただけ（storagePath が同じ）なら keep', () async {
      final local = _local();
      when(
        () => items.fetchItemsUpdatedAfter(any(), any()),
      ).thenAnswer((_) async => [_server()]);

      final snapshots = await fetch([local]);

      expect(snapshots.single.status, 'active');
      expect(_actionFor(snapshots.single, local), SyncAction.keep);
    });

    test('差し替えられていれば replace（論点 11）', () async {
      final local = _local();
      when(() => items.fetchItemsUpdatedAfter(any(), any())).thenAnswer(
        (_) async => [
          _server(storagePath: 'lists/list-1/items/i1/2000-take.wav'),
        ],
      );

      final snapshots = await fetch([local]);

      expect(_actionFor(snapshots.single, local), SyncAction.replace);
      expect(
        snapshots.single.item?.file?.storagePath,
        'lists/list-1/items/i1/2000-take.wav',
        reason: '落とし直す先が要る。項目そのものを渡すこと。',
      );
      expect(
        snapshots.single.listName,
        'バンド練習 2026',
        reason: '差し替え後に目録へ書き直す名前（3.5）',
      );
    });

    test('ソフト削除は deleted のまま渡る（status で絞らない）', () async {
      final local = _local();
      when(() => items.fetchItemsUpdatedAfter(any(), any())).thenAnswer(
        (_) async => [_server(status: ContentStatus.deleted)],
      );

      final snapshots = await fetch([local]);

      expect(
        snapshots.single.status,
        'deleted',
        reason:
            "status == 'active' で絞ると、削除された項目がクエリから消え、"
            '端末には永遠に残る（4.4）。',
      );
      expect(_actionFor(snapshots.single, local), SyncAction.remove);
    });

    test('ドキュメントごと消えていれば remove', () async {
      final local = _local();
      // どちらのクエリにも出てこない＝もう無い。
      final snapshots = await fetch([local]);

      expect(snapshots, hasLength(1));
      expect(
        snapshots.single.status,
        isNull,
        reason: 'ドキュメントが無いことは status: null で表す（4.4）',
      );
      expect(snapshots.single.item, isNull);
      expect(_actionFor(snapshots.single, local), SyncAction.remove);
    });

    test('URL 項目に変わっていれば remove', () async {
      final local = _local();
      when(
        () => items.fetchItemsUpdatedAfter(any(), any()),
      ).thenAnswer((_) async => [_server(storagePath: null)]);

      final snapshots = await fetch([local]);

      expect(_actionFor(snapshots.single, local), SyncAction.remove);
    });
  });

  // -------------------------------------------------------------------------
  // どう取ってくるか
  // -------------------------------------------------------------------------

  group('問い合わせ方（4.4）', () {
    test('更新のクエリに出なかったぶんだけ、存在を確かめる', () async {
      final changed = _local(itemId: 'i1');
      final quiet = _local(
        itemId: 'i2',
        storagePath: 'lists/list-1/items/i2/1000-take.wav',
      );
      when(
        () => items.fetchItemsUpdatedAfter(any(), any()),
      ).thenAnswer((_) async => [_server(id: 'i1')]);
      when(() => items.fetchItemsByIds(any(), any())).thenAnswer(
        (_) async => [
          _server(id: 'i2', storagePath: 'lists/list-1/items/i2/1000-take.wav'),
        ],
      );

      final snapshots = await fetch([changed, quiet]);

      final asked =
          verify(
                () => items.fetchItemsByIds(_listId, captureAny()),
              ).captured.single
              as Iterable<String>;
      expect(
        asked.toList(),
        ['i2'],
        reason:
            'すでに姿が分かっているものを読み直さない。'
            '**上がってこなかったぶんだけ**を確かめる。',
      );
      expect(snapshots.map((s) => s.itemId), ['i1', 'i2']);
    });

    test('起点は、そのリストで最も古い downloadedAt から余裕を引いた時刻', () async {
      final old = DateTime.fromMillisecondsSinceEpoch(1000000000000);
      final recent = DateTime.fromMillisecondsSinceEpoch(1755290000000);

      await fetch([
        _local(itemId: 'i1', downloadedAt: recent),
        _local(
          itemId: 'i2',
          storagePath: 'lists/list-1/items/i2/1000-take.wav',
          downloadedAt: old,
        ),
      ]);

      final since =
          verify(
                () => items.fetchItemsUpdatedAfter(_listId, captureAny()),
              ).captured.single
              as DateTime;

      expect(
        since.isBefore(old),
        isTrue,
        reason:
            '新しいほうを起点にすると、古い曲に起きた変更を取りこぼす。'
            'そして端末の時計とサーバーの時計はずれるので、'
            '最も古い downloadedAt よりさらに手前へ倒す。',
      );
      expect(
        old.difference(since),
        const Duration(days: 1),
        reason: '倒す幅（端末の時計のずれの見込み）',
      );
    });

    test('ほかのリストの曲は混ぜない', () async {
      final mine = _local(itemId: 'i1');
      final other = _local(
        itemId: 'i9',
        listId: 'list-2',
        storagePath: 'lists/list-2/items/i9/1000-take.wav',
      );

      final snapshots = await fetch([mine, other]);

      expect(snapshots.map((s) => s.itemId), ['i1']);
      final asked =
          verify(
                () => items.fetchItemsByIds(_listId, captureAny()),
              ).captured.single
              as Iterable<String>;
      expect(asked.toList(), ['i1']);
    });

    test('そのリストの曲を 1 つも持っていなければ、何も問い合わせない', () async {
      final snapshots = await fetch([_local(itemId: 'i9', listId: 'list-2')]);

      expect(snapshots, isEmpty);
      verifyNever(() => items.fetchItemsUpdatedAfter(any(), any()));
      verifyNever(() => items.fetchItemsByIds(any(), any()));
      verifyNever(() => lists.fetchList(any()));
    });

    test('リストが消えていても、端末の名前を消さない', () async {
      when(() => lists.fetchList(any())).thenAnswer((_) async => null);
      when(
        () => items.fetchItemsUpdatedAfter(any(), any()),
      ).thenAnswer((_) async => [_server()]);

      final snapshots = await fetch([_local()]);

      expect(
        snapshots.single.listName,
        '',
        reason:
            '空にしておけば DownloadRepository が端末の値を残す。'
            '当てずっぽうの名前を書き込まない。',
      );
    });
  });

  // -------------------------------------------------------------------------
  // 読めなかったリストの扱い（10 節の危険 4 と同じ形）
  // -------------------------------------------------------------------------

  group('DownloadsController.syncFromServer', () {
    late _FakeDownloadRepository downloads;
    late _FakeSyncRepository server;
    late ProviderContainer container;

    final held = [
      _local(itemId: 'i1', listId: 'a'),
      _local(itemId: 'i2', listId: 'b'),
    ];

    setUp(() {
      downloads = _FakeDownloadRepository();
      server = _FakeSyncRepository();

      final index = DownloadIndex(items: held);
      when(() => downloads.load()).thenAnswer((_) async => index);
      when(() => downloads.cleanUp()).thenAnswer((_) async => index);
      when(
        () => downloads.syncWithServer(
          listIds: any(named: 'listIds'),
          serverItems: any(named: 'serverItems'),
        ),
      ).thenAnswer(
        (_) async => DownloadSyncReport(
          index: index,
          removed: const [],
          replaced: const [],
          failed: const [],
        ),
      );

      container = ProviderContainer.test(
        overrides: [
          downloadRepositoryProvider.overrideWithValue(downloads),
          downloadSyncRepositoryProvider.overrideWithValue(server),
        ],
      );
    });

    test('読めなかったリストは listIds に入れない（消さない）', () async {
      when(
        () => server.fetchServerItems(
          listId: 'a',
          localItems: any(named: 'localItems'),
        ),
      ).thenAnswer(
        (_) async => [
          ServerItemSnapshot.missing(listId: 'a', itemId: 'i1'),
        ],
      );
      // b は圏外・権限などで読めなかった。
      when(
        () => server.fetchServerItems(
          listId: 'b',
          localItems: any(named: 'localItems'),
        ),
      ).thenThrow(StateError('offline'));

      await container.read(downloadsProvider.future);
      await container.read(downloadsProvider.notifier).syncFromServer();

      final captured = verify(
        () => downloads.syncWithServer(
          listIds: captureAny(named: 'listIds'),
          serverItems: captureAny(named: 'serverItems'),
        ),
      ).captured;

      expect(
        captured.first,
        {'a'},
        reason:
            '読めなかったリストを渡すと、そのリストの曲は材料が無いまま'
            '「消えた」と判定される。電波が悪いだけで端末から消えてしまう。',
      );
      expect((captured.last as Iterable<ServerItemSnapshot>), hasLength(1));
    });

    test('1 曲も持っていなければサーバーを見に行かない', () async {
      when(
        () => downloads.load(),
      ).thenAnswer((_) async => const DownloadIndex());
      when(
        () => downloads.cleanUp(),
      ).thenAnswer((_) async => const DownloadIndex());

      await container.read(downloadsProvider.future);
      final report = await container
          .read(downloadsProvider.notifier)
          .syncFromServer();

      expect(report.isEmpty, isTrue);
      verifyNever(
        () => server.fetchServerItems(
          listId: any(named: 'listId'),
          localItems: any(named: 'localItems'),
        ),
      );
      verifyNever(
        () => downloads.syncWithServer(
          listIds: any(named: 'listIds'),
          serverItems: any(named: 'serverItems'),
        ),
      );
    });
  });
}
