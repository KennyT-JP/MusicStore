/// 端末に落とす・消す・同期する（docs/DOWNLOAD-DESIGN.md 4 章）
///
/// **書く順序をこのクラスの中だけで完結させる**（10 節の 1）。
/// 4.1（落とす）と 4.4（同期）の順序が画面に散ると、
/// `index.json` と実ファイルの食い違い（孤児）が必ず起きる。
/// **画面からファイルを触らないこと。**
///
/// | 何を守るか | どこで |
/// | --- | --- |
/// | 目録を書くのは**最後** | [downloadItem] の手順 7 |
/// | 差し替えは**新しいのを落とし切ってから古いのを消す** | [syncWithServer] |
/// | 目録は**tmp + rename** | `DownloadFileSystem.writeAsStringAtomically` |
/// | 起動時の掃除 | [cleanUp] |
///
/// **判定は 1 つも書かない。** 対象かどうかは `download_target.dart`、
/// 回線は `download_network.dart`、同期は `download_sync.dart`、
/// 猶予は `offline_access.dart` にあり、ここはそれらを**呼ぶだけ**にする。
library;

import 'package:firebase_core/firebase_core.dart' show FirebaseException;

import '../../domain/download_index.dart';
import '../../domain/download_network.dart';
import '../../domain/download_sync.dart';
import '../../domain/download_target.dart';
import '../downloads/backup_exclusion.dart';
import '../downloads/download_access_api.dart';
import '../downloads/download_file_system.dart';
import '../downloads/download_index_codec.dart';
import '../downloads/download_network_status.dart';
import '../downloads/download_paths.dart';
import '../models/list_item.dart';

/// 落とせないファイル（3.3・論点 5）。
///
/// 音源と画像だけが対象で、PDF・zip は対象外。白リストに無い拡張子も
/// 対象外——**落として再生できないものを端末に残さない。**
class DownloadNotSupportedException implements Exception {
  const DownloadNotSupportedException();

  @override
  String toString() => 'DownloadNotSupportedException';
}

/// いまの回線では始められない（4.6・論点 11b）。
///
/// **画面には「Wi-Fi で接続してください」と出す。**
/// 「モバイルデータを使いません」とは書かない（4.6）。
class DownloadBlockedByNetworkException implements Exception {
  const DownloadBlockedByNetworkException();

  @override
  String toString() => 'DownloadBlockedByNetworkException';
}

/// 利用者が中止した（6.3・論点 20）。
///
/// **失敗ではない。** 通信の失敗と区別するために専用の型にしてある
/// （`item_repository.dart` の `UploadCanceledException` と同じ考え）。
class DownloadCanceledException implements Exception {
  const DownloadCanceledException();

  @override
  String toString() => 'DownloadCanceledException';
}

/// `storage.rules` の `canRead()` に落ちた（4.1 の「途中で失敗したとき」）。
///
/// **メンバーでなくなっている可能性が高い**ので、[DownloadRepository] は
/// これを投げる前に権限確認（4.2）を走らせている。
class DownloadPermissionDeniedException implements Exception {
  const DownloadPermissionDeniedException();

  @override
  String toString() => 'DownloadPermissionDeniedException';
}

/// 同期のためにサーバーから読んだ、その曲のいまの姿（4.4）。
///
/// **`previousFiles` は持たない。** サーバー専用の項目で Dart モデルにも
/// 無く、いまの `file` を見れば足りる。
class ServerItemSnapshot {
  const ServerItemSnapshot({
    required this.listId,
    required this.itemId,
    required this.status,
    this.listName = '',
    this.item,
  });

  /// ドキュメントが**無い**ときに使う（4.4 の「消えた」）。
  const ServerItemSnapshot.missing({
    required String listId,
    required String itemId,
  }) : this(listId: listId, itemId: itemId, status: null);

  final String listId;
  final String itemId;

  /// `'active'` / `'deleted'`、**ドキュメントが無ければ null**。
  final String? status;

  /// 差し替え後に目録へ書き直す名前（3.5）。
  final String listName;

  /// サーバー側のいまの項目。`replace` のときにここから落とし直す。
  final ListItem? item;
}

/// 同期の結果（4.4）。
///
/// **画面に何が起きたかを出すために返す。** 黙って消えると、利用者は
/// 「アプリが勝手に消した」と受け取る（4.4 の `remove` のとき）。
class DownloadSyncReport {
  const DownloadSyncReport({
    required this.index,
    required this.removed,
    required this.replaced,
    required this.failed,
  });

  final DownloadIndex index;

  /// 元が削除されたので端末からも消したもの（論点 11）。
  final List<DownloadedItem> removed;

  /// 差し替えられたので落とし直したもの（論点 11）。
  final List<DownloadedItem> replaced;

  /// 落とし直しに失敗したもの。**古いほうを残してある**（4.4）。
  final List<DownloadedItem> failed;

  bool get isEmpty => removed.isEmpty && replaced.isEmpty && failed.isEmpty;
}

/// 端末のダウンロードの読み書き（4 章）。
class DownloadRepository {
  /// **依存は private なフィールドに持つ。** 画面から
  /// `repository.files` のように触れると、順序の規則
  /// （10 節の 1「書く順序を 1 か所に閉じ込める」）がすぐ崩れる。
  ///
  /// private なフィールドは名前付き引数の初期化仮引数
  /// （`required this._files`）にできない——Dart は `_` で始まる
  /// 名前付き引数を許さない——ので、初期化子で書き写している。
  /// `prefer_initializing_formals` の指摘はその Dart の制限によるもので、
  /// 直せない。**フィールドを公開して直すのは、上の理由で本末転倒。**
  // ignore_for_file: prefer_initializing_formals
  DownloadRepository({
    required DownloadFileSystem files,
    required DownloadAccessApi access,
    required NetworkStatus network,
    BackupExclusion backup = const BackupExclusion(),
  }) : _files = files,
       _access = access,
       _network = network,
       _backup = backup;

  final DownloadFileSystem _files;
  final DownloadAccessApi _access;
  final NetworkStatus _network;
  final BackupExclusion _backup;

  // -------------------------------------------------------------------
  // 目録
  // -------------------------------------------------------------------

  /// 起動時に 1 回。保存先を用意し、バックアップから外し、目録を読む。
  ///
  /// **バックアップ除外は毎回かける**（3.2）。ディレクトリを作り直すと
  /// 印が消えるので、冪等に設定し直す。
  Future<DownloadIndex> load() async {
    final root = await _files.ensureRoot();
    await _backup.exclude(root);
    return _readOrEmpty();
  }

  /// いま印が付いているか（3.2 の「確かめる手段」）。
  ///
  /// **付けたつもりで付いていないのが最悪**なので読み取る口を用意する。
  /// iOS 以外では null（「要らない」を「付いていない」と混ぜない）。
  Future<bool?> isExcludedFromBackup() async =>
      _backup.isExcluded(await _files.ensureRoot());

  /// 通信条件の設定を変える（4.6・論点 11b）。
  Future<DownloadIndex> setAllowMobileData(bool value) async {
    final index = await _readOrEmpty();
    final updated = DownloadIndex(
      version: index.version,
      lastVerifiedAt: index.lastVerifiedAt,
      allowMobileData: value,
      items: index.items,
    );
    await _writeIndex(updated);
    return updated;
  }

  /// いまダウンロードを始めてよい回線か（4.6）。
  ///
  /// **判定は `DownloadNetworkPolicy.allows` に任せる。**
  Future<bool> allowsDownloadNow() async {
    final index = await _readOrEmpty();
    return DownloadNetworkPolicy.allows(
      isWifi: await _network.isWifi(),
      allowMobileData: index.allowMobileData,
    );
  }

  // -------------------------------------------------------------------
  // 4.7 起動時の掃除
  // -------------------------------------------------------------------

  /// 起動時の掃除（4.7）。**権限確認より先に、1 回だけ走らせる。**
  ///
  /// | 掃除するもの | なぜ |
  /// | --- | --- |
  /// | `.part` / `.tmp` | 前回が途中で終わった。再開はできない（4.1）ので捨てる |
  /// | 目録に載っていないディレクトリ・ファイル | 目録を書く前に落ちた、または差し替えの途中で落ちた（**孤児**） |
  /// | 目録に載っているが実体が無い項目 | 逆向きの食い違い。目録から落とす |
  ///
  /// **これが無いと、孤児が永久に容量を食い続ける。** 利用者からは
  /// 「設定の使用量が実際より小さい」「アプリのストレージだけが増え続ける」
  /// という形で出る（10 節の 1）。
  Future<DownloadIndex> cleanUp() async {
    await _files.ensureRoot();

    // 途中のものは、目録が読めるかどうかに関わらず捨ててよい。
    for (final path in await _files.listFiles()) {
      if (path.endsWith(DownloadPaths.partSuffix) ||
          path.endsWith(DownloadPaths.tempSuffix)) {
        await _files.deleteFile(path);
      }
    }

    final index = await _tryRead();
    if (index == null) {
      // **目録が読めないときは、これ以上消さない。** 空とみなして掃除すると、
      // 壊れた 1 行のために端末の音源が全部消える。tmp + rename にしてある
      // 以上ここへ来ることはほぼ無いが、来たときの既定は「残すほう」。
      return const DownloadIndex();
    }

    // 目録に載っているのに実体が無い項目を落とす。
    final kept = <DownloadedItem>[];
    for (final item in index.items) {
      if (await _files.exists(item.localAudio)) kept.add(item);
    }

    // 目録に無いディレクトリを消す（孤児）。
    final live = kept
        .map(
          (i) =>
              DownloadPaths.itemDirectory(listId: i.listId, itemId: i.itemId),
        )
        .toSet();
    for (final directory in await _files.listItemDirectories()) {
      if (!live.contains(directory)) await _files.deleteDirectory(directory);
    }

    // 生きているディレクトリの中の、目録が指していないファイルを消す。
    // **差し替えの途中で落ちたときの古いほうがここで消える**（4.4 の手順 4）。
    final referenced = <String>{DownloadPaths.indexFileName};
    for (final item in kept) {
      referenced.add(item.localAudio);
      final image = item.localImage;
      if (image != null) referenced.add(image);
      referenced.add(
        DownloadPaths.commentsFile(listId: item.listId, itemId: item.itemId),
      );
    }
    for (final path in await _files.listFiles()) {
      if (!referenced.contains(path)) await _files.deleteFile(path);
    }

    if (kept.length == index.items.length) return index;

    final updated = DownloadIndex(
      version: index.version,
      lastVerifiedAt: index.lastVerifiedAt,
      allowMobileData: index.allowMobileData,
      items: kept,
    );
    await _writeIndex(updated);
    return updated;
  }

  // -------------------------------------------------------------------
  // 4.1 ダウンロード
  // -------------------------------------------------------------------

  /// 曲を 1 つ落とす（4.1）。
  ///
  /// 手順は**この順序でなければならない**（4.1）。
  ///
  /// ```
  /// 1. 対象かどうか（download_target.dart）
  /// 2. 通信条件（download_network.dart）
  /// 3. .part へ writeToFile()
  /// 4. コメントを comments.json へ
  /// 5. .part を外す
  /// 6. index.json に 1 件足す   ← 最後
  /// ```
  ///
  /// **目録に書くのは最後。** 先に書くと、途中で失敗したときに
  /// 「持っていることになっているが実体が無い曲」が一覧に並ぶ。
  ///
  /// [comments] は呼ぶ側が解決して渡す（3.5 の `authorName` は解決済みで
  /// 持つ）。**このクラスは Firestore を読まない。**
  Future<DownloadIndex> downloadItem({
    required String listId,
    required String listName,
    required ListItem item,
    List<OfflineComment> comments = const [],
    DownloadProgress? onProgress,
    void Function(DownloadHandle handle)? onStarted,
  }) async {
    final file = item.file;
    if (file == null) throw const DownloadNotSupportedException();

    // **判定を書かない。** 3.3 の白リストは `playback.dart` にあり、
    // ここに別の集合を書くと「再生ボタンは出るのに落とせない曲」ができる。
    final kind = downloadTargetKind(
      contentType: file.contentType,
      fileName: file.fileName,
    );
    if (kind != DownloadTargetKind.audio) {
      throw const DownloadNotSupportedException();
    }

    final index = await _readOrEmpty();

    if (!DownloadNetworkPolicy.allows(
      isWifi: await _network.isWifi(),
      allowMobileData: index.allowMobileData,
    )) {
      throw const DownloadBlockedByNetworkException();
    }

    final relative = DownloadPaths.audioFile(
      listId: listId,
      itemId: item.id,
      storagePath: file.storagePath,
      fileName: file.fileName,
    );

    await _fetch(
      storagePath: file.storagePath,
      relativePath: relative,
      onProgress: onProgress,
      onStarted: onStarted,
    );

    final syncedAt = DateTime.now();
    await _files.writeAsStringAtomically(
      DownloadPaths.commentsFile(listId: listId, itemId: item.id),
      DownloadIndexCodec.encodeComments(
        itemId: item.id,
        syncedAt: syncedAt,
        comments: comments,
      ),
    );

    final downloaded = DownloadedItem(
      listId: listId,
      listName: listName,
      itemId: item.id,
      seq: item.seq,
      date: item.itemDate,
      storagePath: file.storagePath,
      fileName: file.fileName,
      contentType: file.contentType,
      sizeBytes: file.sizeBytes,
      localAudio: relative,
      // **端末上の実測を持つ**（3.5・6.4）。サーバー側の sizeBytes を
      // 使うと、落とし損ねたぶんが「端末内の使用量」に出ない。
      localBytes: await _files.lengthOf(relative),
      downloadedAt: syncedAt,
      title: item.title,
      artist: item.artist,
      commentsSyncedAt: syncedAt,
    );

    // 同じ曲を落とし直したときは、古い実体を消してから入れ替える。
    final previous = index.items
        .where((i) => i.itemId == item.id && i.listId == listId)
        .toList();
    for (final old in previous) {
      if (old.localAudio != relative) await _files.deleteFile(old.localAudio);
    }

    final updated = DownloadIndex(
      version: index.version,
      lastVerifiedAt: index.lastVerifiedAt,
      allowMobileData: index.allowMobileData,
      items: [
        ...index.items.where(
          (i) => !(i.itemId == item.id && i.listId == listId),
        ),
        downloaded,
      ],
    );
    await _writeIndex(updated);
    return updated;
  }

  /// 端末から 1 曲消す（論点 6 の手動削除）。
  Future<DownloadIndex> removeItem({
    required String listId,
    required String itemId,
  }) async {
    final index = await _readOrEmpty();
    await _files.deleteDirectory(
      DownloadPaths.itemDirectory(listId: listId, itemId: itemId),
    );
    final updated = DownloadIndex(
      version: index.version,
      lastVerifiedAt: index.lastVerifiedAt,
      allowMobileData: index.allowMobileData,
      items: index.items
          .where((i) => !(i.itemId == itemId && i.listId == listId))
          .toList(),
    );
    await _writeIndex(updated);
    return updated;
  }

  /// 端末のぶんを丸ごと消す（6.4 の「すべて削除」）。
  ///
  /// **画面には「曲とリストは消えません」を必ず添えること**（2.1）。
  /// 消えるのは端末に置いた写しだけで、資産（リスト・アップロードした
  /// ファイル）は 1 つも消えない。
  Future<DownloadIndex> removeAll() async {
    final index = await _readOrEmpty();
    await _files.deleteRoot();
    final cleared = DownloadIndex(
      version: index.version,
      lastVerifiedAt: index.lastVerifiedAt,
      allowMobileData: index.allowMobileData,
    );
    await _writeIndex(cleared);
    return cleared;
  }

  // -------------------------------------------------------------------
  // 4.2 / 4.5 権限確認
  // -------------------------------------------------------------------

  /// 起動ごとに 1 回、サーバーへ権限を問い合わせる（4.2）。
  ///
  /// ```
  /// 呼び出しが失敗した      → 何もしない。オフラインとして扱う
  ///                           （30 日の時計は動かさない）
  /// premiumActive: false    → downloads/ を丸ごと削除（論点 12 / 4.5）
  /// lists[X] == 'notMember' → X のぶんだけ削除（論点 13）
  /// ```
  ///
  /// **「メンバーであること」と「プレミアム」は別々に失われる**ので
  /// 両方を見る（4.2）。そして**結果が違う**——プレミアム失効は全部削除、
  /// 脱退・除外はそのリストだけ削除。
  ///
  /// **失敗を例外にして上へ流さない。** 圏外で 1 回失敗しただけで
  /// 全曲が消える事故を、呼ぶ側の書き方に委ねない（10 節の危険 4）。
  Future<DownloadIndex> verifyAccess() async {
    final index = await _readOrEmpty();
    final listIds = index.items.map((i) => i.listId).toSet().toList();

    final DownloadAccessResult result;
    try {
      result = await _access.verify(listIds);
    } on DownloadAccessUnavailableException {
      return index;
    }

    if (!result.premiumActive) {
      // **丸ごと消す**（4.5）。リストごとに残す判断はしない。
      await _files.deleteRoot();
      final cleared = DownloadIndex(
        version: index.version,
        lastVerifiedAt: result.verifiedAt,
        allowMobileData: index.allowMobileData,
      );
      await _writeIndex(cleared);
      return cleared;
    }

    // **答えが返っていないリストは消さない**（`lostAccessTo` の既定）。
    final lost = listIds.where(result.lostAccessTo).toSet();
    for (final listId in lost) {
      await _files.deleteDirectory(listId);
    }

    final updated = DownloadIndex(
      version: index.version,
      // **サーバーの時刻を入れる**（4.2）。端末の時計で埋めると、
      // 時計を進めるだけで確認を偽装できる。
      lastVerifiedAt: result.verifiedAt,
      allowMobileData: index.allowMobileData,
      items: index.items.where((i) => !lost.contains(i.listId)).toList(),
    );
    await _writeIndex(updated);
    return updated;
  }

  // -------------------------------------------------------------------
  // 4.4 同期（元の削除・差し替え）
  // -------------------------------------------------------------------

  /// 元が削除・差し替えされていないか突き合わせる（4.4・論点 11）。
  ///
  /// **判定は `DownloadSyncPolicy.decide` に任せる。** ここがするのは
  /// 「消す」「落とし直す」だけで、何を見て決めるかは持たない。
  ///
  /// [listIds] は**今回サーバーを見たリスト**。ここに含まれないリストの
  /// 曲には触らない——「今回見ていない」と「ドキュメントが無い」を
  /// 混ぜると、リスト A だけ同期したときに B が丸ごと消える。
  ///
  /// `replace` の順序は 4.4 のとおり。**古いのを先に消さない。**
  ///
  /// ```
  /// 1. 新しい storagePath を .part へ落とす
  /// 2. .part を外す
  /// 3. index.json を書き換える（tmp + rename）
  /// 4. 古い audio-<旧> を消す
  /// ```
  Future<DownloadSyncReport> syncWithServer({
    required Set<String> listIds,
    required Iterable<ServerItemSnapshot> serverItems,
  }) async {
    var index = await _readOrEmpty();
    final byKey = {
      for (final snapshot in serverItems)
        '${snapshot.listId}/${snapshot.itemId}': snapshot,
    };

    final removed = <DownloadedItem>[];
    final replaced = <DownloadedItem>[];
    final failed = <DownloadedItem>[];

    for (final local in [...index.items]) {
      if (!listIds.contains(local.listId)) continue;

      final snapshot = byKey['${local.listId}/${local.itemId}'];
      final serverFile = snapshot?.item?.file;

      final action = DownloadSyncPolicy.decide(
        serverStatus: snapshot?.status,
        serverStoragePath: serverFile?.storagePath,
        localStoragePath: local.storagePath,
      );

      switch (action) {
        case SyncAction.keep:
          break;

        case SyncAction.remove:
          await _files.deleteDirectory(
            DownloadPaths.itemDirectory(
              listId: local.listId,
              itemId: local.itemId,
            ),
          );
          index = _without(index, local);
          await _writeIndex(index);
          removed.add(local);

        case SyncAction.replace:
          final fresh = await _replace(local, snapshot!);
          if (fresh == null) {
            failed.add(local);
            break;
          }
          index = _replacing(index, local, fresh);
          // 3. 目録を書き換えてから……
          await _writeIndex(index);
          // 4. ……古いほうを消す。逆にすると、途中で落ちたときに
          //    聴けるものが 1 つも無くなる。
          await _files.deleteFile(local.localAudio);
          replaced.add(fresh);
      }
    }

    return DownloadSyncReport(
      index: index,
      removed: removed,
      replaced: replaced,
      failed: failed,
    );
  }

  // -------------------------------------------------------------------
  // 4.3 再生に渡すもの
  // -------------------------------------------------------------------

  /// 端末に実体がある音源の絶対パス。無ければ null（4.3）。
  ///
  /// **実体を確かめてから返す。** `index.json` にあっても、利用者が
  /// OS の設定から消していることがある。`PlaybackPolicy.resolve` に
  /// 渡す `localPath` は「目録にあり、**実体もある**」ときだけ。
  Future<String?> localAudioPath(String itemId) async {
    final index = await _readOrEmpty();
    final match = index.items.where((i) => i.itemId == itemId).toList();
    if (match.isEmpty) return null;
    final item = match.first;
    if (!await _files.exists(item.localAudio)) return null;
    return _files.absolutePathOf(item.localAudio);
  }

  /// オフラインで読むコメント（論点 8）。
  ///
  /// **読むだけ。** オフラインでの投稿はしない（9 節）——送った順と
  /// 表示される順が食い違い、返信の親子関係が壊れる。
  Future<List<OfflineComment>> offlineComments({
    required String listId,
    required String itemId,
  }) async {
    final raw = await _files.readAsString(
      DownloadPaths.commentsFile(listId: listId, itemId: itemId),
    );
    if (raw == null) return const [];
    return DownloadIndexCodec.decodeComments(raw);
  }

  // -------------------------------------------------------------------
  // 内部
  // -------------------------------------------------------------------

  /// 落とし直して、新しい目録の 1 件を返す。失敗したら null（古いのは残る）。
  Future<DownloadedItem?> _replace(
    DownloadedItem local,
    ServerItemSnapshot snapshot,
  ) async {
    final item = snapshot.item;
    final file = item?.file;
    if (item == null || file == null) return null;

    final relative = DownloadPaths.audioFile(
      listId: local.listId,
      itemId: local.itemId,
      storagePath: file.storagePath,
      fileName: file.fileName,
    );

    try {
      await _fetch(storagePath: file.storagePath, relativePath: relative);
    } on Object {
      return null;
    }

    return DownloadedItem(
      listId: local.listId,
      listName: snapshot.listName.isEmpty ? local.listName : snapshot.listName,
      itemId: local.itemId,
      seq: item.seq,
      date: item.itemDate,
      storagePath: file.storagePath,
      fileName: file.fileName,
      contentType: file.contentType,
      sizeBytes: file.sizeBytes,
      localAudio: relative,
      localImage: local.localImage,
      localBytes: await _files.lengthOf(relative),
      downloadedAt: DateTime.now(),
      title: item.title,
      artist: item.artist,
      commentsSyncedAt: local.commentsSyncedAt,
    );
  }

  /// `.part` へ落として、済んだら名前を外す（4.1 の手順 3 と 5）。
  ///
  /// **失敗したら `.part` を消し、目録には触らない**（4.1 の表）。
  Future<void> _fetch({
    required String storagePath,
    required String relativePath,
    DownloadProgress? onProgress,
    void Function(DownloadHandle handle)? onStarted,
  }) async {
    final part = DownloadPaths.partOf(relativePath);
    // 前回の残りがあれば捨てる。**再開はできない**（4.1 の B の代償）ので、
    // 途中から続けようとしない。**「再開」と書かないこと。**
    await _files.deleteFile(part);

    try {
      await _files.download(
        storagePath: storagePath,
        relativePath: part,
        onProgress: onProgress,
        onStarted: onStarted,
      );
    } on FirebaseException catch (e) {
      await _files.deleteFile(part);
      if (e.code == 'canceled') throw const DownloadCanceledException();
      if (e.code == 'unauthorized' || e.code == 'permission-denied') {
        // **その場で権限確認を走らせる**（4.1 の表）。
        // メンバーでなくなっていた可能性が高い。
        await verifyAccess();
        throw const DownloadPermissionDeniedException();
      }
      rethrow;
    } on Object {
      await _files.deleteFile(part);
      rethrow;
    }

    await _files.rename(part, relativePath);
  }

  DownloadIndex _without(DownloadIndex index, DownloadedItem item) =>
      DownloadIndex(
        version: index.version,
        lastVerifiedAt: index.lastVerifiedAt,
        allowMobileData: index.allowMobileData,
        items: index.items
            .where((i) => !(i.itemId == item.itemId && i.listId == item.listId))
            .toList(),
      );

  DownloadIndex _replacing(
    DownloadIndex index,
    DownloadedItem from,
    DownloadedItem to,
  ) => DownloadIndex(
    version: index.version,
    lastVerifiedAt: index.lastVerifiedAt,
    allowMobileData: index.allowMobileData,
    items: index.items
        .map((i) => i.itemId == from.itemId && i.listId == from.listId ? to : i)
        .toList(),
  );

  Future<DownloadIndex> _readOrEmpty() async =>
      await _tryRead() ?? const DownloadIndex();

  /// 目録を読む。**読めなければ null**（無いときは空の目録）。
  Future<DownloadIndex?> _tryRead() async {
    await _files.ensureRoot();
    final raw = await _files.readAsString(DownloadPaths.indexFileName);
    if (raw == null) return const DownloadIndex();
    return DownloadIndexCodec.tryDecode(raw);
  }

  /// **必ず tmp + rename**（3.4）。途中で電源が落ちても、
  /// 古い目録か新しい目録のどちらかが残り、壊れた目録は残らない。
  Future<void> _writeIndex(DownloadIndex index) =>
      _files.writeAsStringAtomically(
        DownloadPaths.indexFileName,
        DownloadIndexCodec.encode(index),
      );
}
