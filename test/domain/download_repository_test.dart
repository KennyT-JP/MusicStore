/// 端末のファイルを実際に触る（docs/DOWNLOAD-DESIGN.md 8.3）
///
/// **`Directory.systemTemp` を使う。** 保存先の解決（`path_provider`）は
/// 端末が要るので、`IoDownloadFileSystem` に根を渡して差し替える。
/// **どこに置くかの判定そのものは `download_storage_test.dart` の
/// 静的な見張りが守る**——ここで確かめられるのは順序と後始末だけ。
///
/// 8.3 が挙げている 6 つを、この順で確かめる。
///
/// 1. 差し替えで古いものが残らないこと
/// 2. 差し替えの途中で落ちても、聴けるものが残ること
/// 3. `index.json` の原子性
/// 4. 孤児の掃除（4.7）
/// 5. プレミアム失効で `downloads/` が空になること（論点 12）
/// 6. リスト A から抜けたとき、A のぶんだけ消えて B が残ること（論点 13）
///
/// 加えて、**4.1 の「目録に書くのは最後」**を落として確かめる。
library;

import 'dart:convert';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart' show FirebaseException;
import 'package:flutter_test/flutter_test.dart';
import 'package:music_list_app/data/downloads/download_access_api.dart';
import 'package:music_list_app/data/downloads/download_file_system.dart';
import 'package:music_list_app/data/downloads/download_file_system_io.dart';
import 'package:music_list_app/data/downloads/download_network_status.dart';
import 'package:music_list_app/data/downloads/download_paths.dart';
import 'package:music_list_app/data/models/list_item.dart';
import 'package:music_list_app/data/repositories/download_repository.dart';
import 'package:music_list_app/domain/download_index.dart';
import 'package:music_list_app/domain/local_date.dart';

// ---------------------------------------------------------------------------
// 差し替え
// ---------------------------------------------------------------------------

/// Storage の代わり。**`download` だけを偽物にし、ほかは本物のまま。**
///
/// 本物の `IoDownloadFileSystem` に委ねるのが要点で、
/// tmp + rename も `.part` の後始末も、実装そのものを確かめている。
class _Files implements DownloadFileSystem {
  _Files(String root)
    : _io = IoDownloadFileSystem(() => throw StateError('Storage は使わない'), root);

  final IoDownloadFileSystem _io;

  /// サーバー側にあることにするファイル（`storagePath` → 中身）。
  final server = <String, String>{};

  /// この `storagePath` を取りに行ったら失敗させる。
  final failures = <String, Object>{};

  final requested = <String>[];

  @override
  Future<void> download({
    required String storagePath,
    required String relativePath,
    DownloadProgress? onProgress,
    void Function(DownloadHandle handle)? onStarted,
  }) async {
    requested.add(storagePath);

    final failure = failures[storagePath];
    if (failure != null) {
      // **途中まで書けてから切れた場合を作る。**
      //
      // 何も書かずに失敗させると、「`.part` を消す」処理があってもなくても
      // テストが通る（消す対象がそもそも無いため）。**見張れていない
      // 見張り**になるので、必ず途中まで書いてから失敗させる
      // （2026-08-16 に、実装を壊しても緑のままだったのを踏んだ）。
      final partial = server[storagePath];
      if (partial != null) {
        await _io.writeAsStringAtomically(
          relativePath,
          partial.substring(0, partial.length ~/ 2),
        );
      }
      throw failure;
    }

    final body = server[storagePath];
    if (body == null) {
      throw FirebaseException(
        plugin: 'firebase_storage',
        code: 'object-not-found',
      );
    }
    onProgress?.call(body.length, body.length);
    await _io.writeAsStringAtomically(relativePath, body);
  }

  @override
  Future<String> ensureRoot() => _io.ensureRoot();
  @override
  Future<String> absolutePathOf(String p) => _io.absolutePathOf(p);
  @override
  Future<bool> exists(String p) => _io.exists(p);
  @override
  Future<int> lengthOf(String p) => _io.lengthOf(p);
  @override
  Future<String?> readAsString(String p) => _io.readAsString(p);
  @override
  Future<void> writeAsStringAtomically(String p, String c) =>
      _io.writeAsStringAtomically(p, c);
  @override
  Future<void> rename(String a, String b) => _io.rename(a, b);
  @override
  Future<void> deleteFile(String p) => _io.deleteFile(p);
  @override
  Future<void> deleteDirectory(String p) => _io.deleteDirectory(p);
  @override
  Future<void> deleteRoot() => _io.deleteRoot();
  @override
  Future<List<String>> listFiles() => _io.listFiles();
  @override
  Future<List<String>> listItemDirectories() => _io.listItemDirectories();
}

/// `verifyDownloadAccess` の差し替え。
class _Access extends DownloadAccessApi {
  _Access() : super(_never);

  static Never _never() => throw StateError('Functions は使わない');

  bool premiumActive = true;
  DateTime verifiedAt = DateTime.fromMillisecondsSinceEpoch(1755300000000);
  Set<String> notMember = {};

  /// **呼び出しそのものを失敗させる**（圏外・タイムアウト）。
  bool unavailable = false;

  List<String> lastListIds = const [];

  @override
  Future<DownloadAccessResult> verify(List<String> listIds) async {
    lastListIds = listIds;
    if (unavailable) {
      throw const DownloadAccessUnavailableException('offline');
    }
    return DownloadAccessResult(
      premiumActive: premiumActive,
      verifiedAt: verifiedAt,
      members: {for (final id in listIds) id: !notMember.contains(id)},
    );
  }
}

class _Network implements NetworkStatus {
  bool wifi = true;
  bool online = true;

  @override
  Future<bool> isWifi() async => wifi;
  @override
  Future<bool> isOnline() async => online;
}

// ---------------------------------------------------------------------------
// 道具
// ---------------------------------------------------------------------------

ListItem _item({
  required String id,
  required String storagePath,
  String fileName = 'take.wav',
  String contentType = 'audio/wav',
  int seq = 1,
  int sizeBytes = 8,
}) => ListItem(
  id: id,
  seq: seq,
  itemDate: LocalDate.tryParse('2026-08-01')!,
  kind: ItemKind.file,
  file: ItemFile(
    storagePath: storagePath,
    fileName: fileName,
    sizeBytes: sizeBytes,
    contentType: contentType,
  ),
  createdBy: 'u1',
  registrantDisplayName: '山田',
  status: ContentStatus.active,
);

void main() {
  late Directory temp;
  late _Files files;
  late _Access access;
  late _Network network;
  late DownloadRepository repository;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('downloads-test');
    files = _Files('${temp.path.replaceAll(r'\', '/')}/downloads');
    access = _Access();
    network = _Network();
    repository = DownloadRepository(
      files: files,
      access: access,
      network: network,
    );
  });

  tearDown(() async {
    if (temp.existsSync()) await temp.delete(recursive: true);
  });

  /// 1 曲落とす。返るのはその時点の目録。
  Future<void> download(
    String listId,
    String itemId,
    String storagePath, {
    String body = 'audio!!!',
    String fileName = 'take.wav',
  }) async {
    files.server[storagePath] = body;
    await repository.downloadItem(
      listId: listId,
      listName: 'バンド練習 2026',
      item: _item(id: itemId, storagePath: storagePath, fileName: fileName),
    );
  }

  Future<List<String>> filesInRoot() => files.listFiles();

  group('4.1 落とす', () {
    test('目録に書くのは最後（失敗したら目録は増えず、.part も残らない）', () async {
      files.failures['lists/l/items/i/take.wav'] = const SocketException(
        '通信が切れた',
      );
      files.server['lists/l/items/i/take.wav'] = 'audio!!!';

      await expectLater(
        repository.downloadItem(
          listId: 'l',
          listName: 'バンド練習 2026',
          item: _item(id: 'i', storagePath: 'lists/l/items/i/take.wav'),
        ),
        throwsA(isA<SocketException>()),
      );

      final index = await repository.load();
      expect(index.items, isEmpty, reason: '失敗した曲を目録に書かないこと');
      expect(
        await filesInRoot(),
        isNot(contains(endsWith(DownloadPaths.partSuffix))),
        reason: '.part を消すこと（4.1 の表）',
      );
    });

    test('落とすと目録・実体・コメントが揃う', () async {
      await download('l', 'i', 'lists/l/items/i/take.wav');

      final index = await repository.load();
      final item = index.items.single;
      expect(item.itemId, 'i');
      expect(item.listId, 'l');
      // **端末上の実測**（3.5・6.4）。
      expect(item.localBytes, 'audio!!!'.length);
      expect(await files.exists(item.localAudio), isTrue);
      expect(
        await files.exists(
          DownloadPaths.commentsFile(listId: 'l', itemId: 'i'),
        ),
        isTrue,
      );
    });

    test('音源でないファイルは落とさない（論点 5・3.3 の白リスト）', () async {
      files.server['lists/l/items/i/score.pdf'] = 'pdf';
      await expectLater(
        repository.downloadItem(
          listId: 'l',
          listName: 'x',
          item: _item(
            id: 'i',
            storagePath: 'lists/l/items/i/score.pdf',
            fileName: 'score.pdf',
            contentType: 'application/pdf',
          ),
        ),
        throwsA(isA<DownloadNotSupportedException>()),
      );
      expect(files.requested, isEmpty, reason: '取りに行きすらしないこと');
    });

    test('Wi-Fi でなく、モバイル通信も許していなければ始めない（4.6）', () async {
      network.wifi = false;

      await expectLater(
        repository.downloadItem(
          listId: 'l',
          listName: 'x',
          item: _item(id: 'i', storagePath: 'lists/l/items/i/take.wav'),
        ),
        throwsA(isA<DownloadBlockedByNetworkException>()),
      );
      expect(await repository.allowsDownloadNow(), isFalse);

      // 設定で許すと始められる。
      await repository.setAllowMobileData(true);
      expect(await repository.allowsDownloadNow(), isTrue);
      await download('l', 'i', 'lists/l/items/i/take.wav');
      expect((await repository.load()).items, hasLength(1));
    });

    test('権限で落ちたら、その場で権限確認が走る（4.1 の表）', () async {
      files.failures['lists/l/items/i/take.wav'] = FirebaseException(
        plugin: 'firebase_storage',
        code: 'unauthorized',
      );

      await expectLater(
        repository.downloadItem(
          listId: 'l',
          listName: 'x',
          item: _item(id: 'i', storagePath: 'lists/l/items/i/take.wav'),
        ),
        throwsA(isA<DownloadPermissionDeniedException>()),
      );
      expect(
        access.lastListIds,
        isNotNull,
        reason: 'メンバーでなくなっている可能性が高いので確かめること',
      );
      expect((await repository.load()).lastVerifiedAt, access.verifiedAt);
    });
  });

  group('4.4 同期', () {
    test('差し替えると、古い実体が残らない（8.3）', () async {
      await download('l', 'i', 'lists/l/items/i/1000-take.wav');
      final before = (await repository.load()).items.single;
      expect(before.localAudio, endsWith('audio-1000.wav'));

      files.server['lists/l/items/i/2000-take.wav'] = 'new audio';
      final report = await repository.syncWithServer(
        listIds: {'l'},
        serverItems: [
          ServerItemSnapshot(
            listId: 'l',
            itemId: 'i',
            status: 'active',
            item: _item(id: 'i', storagePath: 'lists/l/items/i/2000-take.wav'),
          ),
        ],
      );

      expect(report.replaced, hasLength(1));
      final after = (await repository.load()).items.single;
      expect(after.localAudio, endsWith('audio-2000.wav'));
      expect(await files.exists(before.localAudio), isFalse);
      expect(await files.exists(after.localAudio), isTrue);
    });

    test('落とし直しに失敗したら、古いほうが残る（4.4 の順序）', () async {
      await download('l', 'i', 'lists/l/items/i/1000-take.wav');
      final before = (await repository.load()).items.single;

      // 新しいほうを server に置かない＝取りに行って失敗する。
      final report = await repository.syncWithServer(
        listIds: {'l'},
        serverItems: [
          ServerItemSnapshot(
            listId: 'l',
            itemId: 'i',
            status: 'active',
            item: _item(id: 'i', storagePath: 'lists/l/items/i/2000-take.wav'),
          ),
        ],
      );

      expect(report.failed, hasLength(1));
      expect(report.replaced, isEmpty);
      // **聴けるものが 1 つも無い状態にしない。**
      expect(await files.exists(before.localAudio), isTrue);
      expect(
        (await repository.load()).items.single.localAudio,
        before.localAudio,
      );
    });

    test('元が削除されていたら、端末からも消す（論点 11）', () async {
      await download('l', 'i', 'lists/l/items/i/take.wav');

      final report = await repository.syncWithServer(
        listIds: {'l'},
        serverItems: const [
          ServerItemSnapshot(listId: 'l', itemId: 'i', status: 'deleted'),
        ],
      );

      expect(report.removed, hasLength(1));
      expect((await repository.load()).items, isEmpty);
      expect(await files.listItemDirectories(), isEmpty);
    });

    test('ドキュメントが無くなっていたら消す', () async {
      await download('l', 'i', 'lists/l/items/i/take.wav');

      final report = await repository.syncWithServer(
        listIds: {'l'},
        serverItems: const [
          ServerItemSnapshot.missing(listId: 'l', itemId: 'i'),
        ],
      );

      expect(report.removed, hasLength(1));
      expect((await repository.load()).items, isEmpty);
    });

    test('今回見ていないリストには触らない', () async {
      // 「今回見ていない」と「ドキュメントが無い」を混ぜると、
      // リスト A だけ同期したときに B が丸ごと消える。
      await download('a', 'i', 'lists/a/items/i/take.wav');
      await download('b', 'j', 'lists/b/items/j/take.wav');

      final report = await repository.syncWithServer(
        listIds: {'a'},
        serverItems: const [
          ServerItemSnapshot.missing(listId: 'a', itemId: 'i'),
        ],
      );

      expect(report.removed.single.listId, 'a');
      expect((await repository.load()).items.single.listId, 'b');
    });
  });

  group('4.7 起動時の掃除', () {
    test('.part が残っていたら捨てる', () async {
      await download('l', 'i', 'lists/l/items/i/take.wav');
      await files.writeAsStringAtomically('l/i/audio-999.wav.part', 'とちゅう');

      await repository.cleanUp();

      expect(
        await filesInRoot(),
        isNot(contains(endsWith(DownloadPaths.partSuffix))),
      );
      // 済んでいるほうは残す。
      expect((await repository.load()).items, hasLength(1));
    });

    test('目録に載っていないディレクトリを消す（孤児）', () async {
      await download('l', 'i', 'lists/l/items/i/take.wav');
      await files.writeAsStringAtomically('l/orphan/audio-1.wav', 'ゴミ');
      expect(await files.listItemDirectories(), hasLength(2));

      await repository.cleanUp();

      expect(await files.listItemDirectories(), ['l/i']);
    });

    test('目録に載っているが実体が無い項目を落とす', () async {
      await download('l', 'i', 'lists/l/items/i/take.wav');
      final item = (await repository.load()).items.single;
      await files.deleteFile(item.localAudio);

      final index = await repository.cleanUp();

      expect(index.items, isEmpty);
      // 目録から落ちたので、ディレクトリごと孤児として消える。
      expect(await files.listItemDirectories(), isEmpty);
    });

    test('差し替えの途中で落ちても、次の掃除で目録に無いほうが消える（8.3）', () async {
      await download('l', 'i', 'lists/l/items/i/1000-take.wav');
      // 手順 2（.part を外す）の直後で止まった状態を作る。
      await files.writeAsStringAtomically('l/i/audio-2000.wav', 'new audio');

      // このとき両方ある＝聴けるものが必ず 1 つはある。
      expect(await files.exists('l/i/audio-1000.wav'), isTrue);
      expect(await files.exists('l/i/audio-2000.wav'), isTrue);

      await repository.cleanUp();

      // 目録が指しているのは古いほう（まだ書き換えていない）。
      expect(await files.exists('l/i/audio-1000.wav'), isTrue);
      expect(await files.exists('l/i/audio-2000.wav'), isFalse);
    });

    test('目録が読めないときは、それ以上消さない', () async {
      await download('l', 'i', 'lists/l/items/i/take.wav');
      final root = await files.ensureRoot();
      File('$root/${DownloadPaths.indexFileName}').writeAsStringSync('{');

      await repository.cleanUp();

      // **壊れた 1 行のために端末の音源を全部消さない。**
      expect(await files.listItemDirectories(), ['l/i']);
    });
  });

  group('3.4 目録の原子性', () {
    test('index.json.tmp を残しても、index.json は壊れていない', () async {
      await download('l', 'i', 'lists/l/items/i/take.wav');
      final root = await files.ensureRoot();
      File(
        '$root/${DownloadPaths.indexFileName}${DownloadPaths.tempSuffix}',
      ).writeAsStringSync('書きかけ');

      final index = await repository.load();
      expect(index.items, hasLength(1));
      expect(
        jsonDecode(
          File('$root/${DownloadPaths.indexFileName}').readAsStringSync(),
        ),
        isA<Map<String, dynamic>>(),
      );

      // 掃除が .tmp を捨てる。
      await repository.cleanUp();
      expect(
        await filesInRoot(),
        isNot(contains(endsWith(DownloadPaths.tempSuffix))),
      );
    });

    test('書き終えたあとに .tmp が残らない', () async {
      await download('l', 'i', 'lists/l/items/i/take.wav');
      expect(
        await filesInRoot(),
        isNot(contains(endsWith(DownloadPaths.tempSuffix))),
      );
    });
  });

  group('4.2 / 4.5 権限確認', () {
    test('プレミアムが切れたら downloads/ が空になる（論点 12）', () async {
      await download('a', 'i', 'lists/a/items/i/take.wav');
      await download('b', 'j', 'lists/b/items/j/take.wav');

      access.premiumActive = false;
      final index = await repository.verifyAccess();

      expect(index.items, isEmpty);
      expect(await files.listItemDirectories(), isEmpty);
      // 確認は取れているので、時計は進む。
      expect(index.lastVerifiedAt, access.verifiedAt);
    });

    test('リスト A から抜けたら、A のぶんだけ消えて B が残る（論点 13）', () async {
      await download('a', 'i', 'lists/a/items/i/take.wav');
      await download('b', 'j', 'lists/b/items/j/take.wav');

      access.notMember = {'a'};
      final index = await repository.verifyAccess();

      expect(index.items.map((i) => i.listId), ['b']);
      expect(await files.listItemDirectories(), ['b/j']);
    });

    test('呼び出しに失敗したら何もしない（30 日の時計も動かさない）', () async {
      await download('a', 'i', 'lists/a/items/i/take.wav');
      final before = await repository.load();

      access.unavailable = true;
      final index = await repository.verifyAccess();

      // **電波の悪い場所で 1 回失敗しただけで全曲が消える、を防ぐ。**
      expect(index.items, hasLength(1));
      expect(index.lastVerifiedAt, before.lastVerifiedAt);
      expect(await files.listItemDirectories(), ['a/i']);
    });

    test('答えの返っていないリストは消さない', () async {
      await download('a', 'i', 'lists/a/items/i/take.wav');
      // members に 'a' を入れない答えを返す。
      access.notMember = {};
      final index = await repository.verifyAccess();
      expect(index.items, hasLength(1));
    });
  });

  group('4.3 / 論点 8 再生とコメント', () {
    test('実体があるときだけ絶対パスを返す', () async {
      await download('l', 'i', 'lists/l/items/i/take.wav');
      final path = await repository.localAudioPath('i');
      expect(path, isNotNull);
      expect(File(path!).existsSync(), isTrue);

      await files.deleteFile((await repository.load()).items.single.localAudio);
      expect(await repository.localAudioPath('i'), isNull);
      expect(await repository.localAudioPath('知らない曲'), isNull);
    });

    test('コメントを読める（読むだけ）', () async {
      files.server['lists/l/items/i/take.wav'] = 'audio!!!';
      await repository.downloadItem(
        listId: 'l',
        listName: 'x',
        item: _item(id: 'i', storagePath: 'lists/l/items/i/take.wav'),
        comments: [OfflineCommentFixture.build()],
      );

      final comments = await repository.offlineComments(
        listId: 'l',
        itemId: 'i',
      );
      expect(comments, hasLength(1));
      expect(comments.single.authorName, '山田');
    });
  });

  group('論点 6 手動削除', () {
    test('1 曲だけ消せる', () async {
      await download('l', 'i', 'lists/l/items/i/take.wav');
      await download('l', 'j', 'lists/l/items/j/take.wav');

      await repository.removeItem(listId: 'l', itemId: 'i');

      expect((await repository.load()).items.map((e) => e.itemId), ['j']);
      expect(await files.listItemDirectories(), ['l/j']);
    });

    test('すべて消しても、通信条件の設定は残る', () async {
      await repository.setAllowMobileData(true);
      await download('l', 'i', 'lists/l/items/i/take.wav');

      final index = await repository.removeAll();

      expect(index.items, isEmpty);
      expect(index.allowMobileData, isTrue);
      expect(await files.listItemDirectories(), isEmpty);
    });
  });
}

/// テスト用のコメント 1 件。
class OfflineCommentFixture {
  const OfflineCommentFixture._();

  static OfflineComment build() => OfflineComment(
    id: 'c1',
    parentId: null,
    path: const [],
    createdAt: DateTime.fromMillisecondsSinceEpoch(1755280000000),
    body: 'よかった',
    authorName: '山田',
    status: 'active',
  );
}
