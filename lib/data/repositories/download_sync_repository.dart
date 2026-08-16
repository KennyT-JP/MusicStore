/// ダウンロード同期のために**サーバーから取ってくる**
/// （docs/DOWNLOAD-DESIGN.md 3.5 / 4.4）
///
/// `DownloadRepository` は端末のファイルだけを触り、**Firestore を
/// 読まない**（`download_repository.dart` の冒頭）。読む係がここで、
/// 渡すのは [ServerItemSnapshot]——`DownloadRepository.syncWithServer` の
/// 材料——だけである。
///
/// **判定は 1 つも書かない。** 何を消し何を落とし直すかは
/// `domain/download_sync.dart` にあり、ここがするのは
/// **問い合わせと詰め替えだけ**。
///
/// **コメントの `authorName` の解決（3.5）はここに無い。**
/// `ui/downloads/download_jobs.dart` の `offlineCommentsLoaderProvider` が
/// すでに行っており、画面と同じ `DisplayNameResolver.resolveInList` を
/// 通している。**退会・除外の判定を 2 か所に持たないため、こちらには
/// 書かない**（2 つあると、画面では「退会したユーザー」なのに端末の
/// 写しには本名が残る、という食い違いが出る）。
///
/// ## サーバーへの問い合わせは 2 本ある（片方では足りない）
///
/// 4.4 は「`updatedAt` がそれより新しい項目だけを読む」と書いている。
/// **それだけでは、消えたことが分からない。**
///
/// | 元で起きたこと | `updatedAt` のクエリに出るか |
/// | --- | --- |
/// | 直された・差し替えられた | 出る |
/// | 削除された（ソフト削除／`status: 'deleted'`） | **出る**（`updatedAt` も動く） |
/// | **ドキュメントごと消えた** | **出ない** |
///
/// 最後の行は理屈の上の話ではない。アカウント削除
/// （`functions/src/callable/user_admin.ts` の `deleteSiteUser`）は、
/// その人が登録した曲を `doc.ref.delete()` で**物理削除**する。
/// 消えたドキュメントは「更新されたドキュメント」として上がってこない。
///
/// そして `DownloadRepository.syncWithServer` は、**渡されなかった項目を
/// 「消えた」と読む**（`SyncAction.remove`）。つまり
/// **持っている 1 曲ごとに、必ず 1 つ答えを返さなければならない。**
/// 返さなければ、変わっていないだけの曲まで端末から消える。
///
/// そこで、`updatedAt` のクエリで上がってこなかったぶんだけ、
/// **ID を並べて存在を確かめる**（`ItemRepository.fetchItemsByIds`）。
/// 見つかればそのままの姿を、見つからなければ
/// [ServerItemSnapshot.missing] を返す。
///
/// ### 読む量（正直に書いておく）
///
/// 2 本目があるので、**読む量は「端末が持っている曲数」が下限**になる。
/// 4.4 が避けたかった「リストの全件を読む」よりは少ないが、
/// **1 本目のぶんだけ多く読むことがある**——落としていない曲が
/// たくさん直されていると、そのぶんも返ってくる。
///
/// **それでも 1 本目を残しているのは、変わったものを 1 往復で
/// 受け取れるからで、消すかどうかの判断には 2 本目が要る。**
/// 読む量を詰めたくなったら、2 本目を集計クエリ（`count()`）にして
/// 「数が合えば全部ある」と省く手があるが、**省いた側は
/// 「変わっていない」と言い切ることになる**ので、そこまでやる前に
/// 端末が持つ曲数を実測すること（このアプリはリスト 3 件の規模）。
///
/// ## 索引は要らない（10 節の危険 7）
///
/// - `where('updatedAt', isGreaterThan: …)` は**単一フィールドの範囲**で、
///   コレクション範囲の単一フィールド索引は Firestore が自動で作る。
///   **`firestore.indexes.json` に書くと逆に配信が止まる**
///   （400 `this index is not necessary`／同ファイルの冒頭の注記）
/// - ID による絞り込みはキーの索引で足りる
///
/// **`orderBy` や 2 つ目の絞り込みを足した瞬間に合成索引が要る。**
/// エミュレータは索引を強制しないので、**統合テストは緑のまま
/// 本番だけが落ちる**。この形は
/// `test/domain/download_sync_query_test.dart` が見張っている。
library;

import '../../domain/download_index.dart';
import '../models/list_item.dart';
import 'download_repository.dart';
import 'item_repository.dart';
import 'list_repository.dart';

/// 同期に要るものをサーバーから集める（4.4 / 3.5）。
class DownloadSyncRepository {
  DownloadSyncRepository(this._items, this._lists);

  final ItemRepository _items;
  final ListRepository _lists;

  /// 端末の時計のずれを見込む幅。
  ///
  /// **問い合わせの起点は端末の時計から作る。** 「そのリストを最後に
  /// 同期した時刻」は `index.json` に無い（`DownloadIndex` は
  /// `lastVerifiedAt` しか持たない）ので、**そのリストで最も古い
  /// [DownloadedItem.downloadedAt]** を起点にする。落としたあとの変更は
  /// すべてそれより新しいので、取りこぼさない。
  ///
  /// ただし `downloadedAt` は端末の時計、`updatedAt` はサーバーの時計で
  /// 打たれている。**端末が進んでいると、その差のあいだに起きた変更を
  /// 永久に見落とす**（起点は落とした時刻で固定されるため、次の同期でも
  /// 拾えない）。そこで 1 日ぶん手前へ倒す。
  ///
  /// **広げすぎても損はしない。** 余分に返るのは
  /// 「落とす直前に直された項目」だけで、結果は同じ `keep` になる。
  static const Duration _clockSkewAllowance = Duration(days: 1);

  /// そのリストについて、**端末が持っている 1 曲ごとの**いまのサーバー側の姿
  /// （4.4）。
  ///
  /// 戻り値は `DownloadRepository.syncWithServer` の `serverItems` に
  /// そのまま渡す。**持っていない曲のぶんは返さない**——同期が見るのは
  /// 端末にあるものだけで、返しても捨てられる。
  ///
  /// **失敗は投げる。** 圏外や権限の失敗を「消えた」と混ぜないため、
  /// 呼ぶ側は**このリストを `listIds` に入れないこと**で対処する
  /// （`DownloadsController.syncFromServer`）。
  Future<List<ServerItemSnapshot>> fetchServerItems({
    required String listId,
    required Iterable<DownloadedItem> localItems,
  }) async {
    final held = localItems.where((i) => i.listId == listId).toList();
    if (held.isEmpty) return const [];

    // 差し替え後に目録へ書き直す名前（3.5）。リストが消えていれば空にして
    // おき、`DownloadRepository` 側で端末の値を残す。
    final listName = (await _lists.fetchList(listId))?.name ?? '';

    final byId = <String, ListItem>{
      for (final item in await _items.fetchItemsUpdatedAfter(
        listId,
        _syncedThrough(held),
      ))
        item.id: item,
    };

    // **上がってこなかったぶんの存在を確かめる。** 変わっていないのか、
    // ドキュメントごと消えたのかは、ここでしか分からない。
    final unaccounted = held
        .map((i) => i.itemId)
        .where((id) => !byId.containsKey(id))
        .toList();
    for (final item in await _items.fetchItemsByIds(listId, unaccounted)) {
      byId[item.id] = item;
    }

    final snapshots = <ServerItemSnapshot>[];
    for (final local in held) {
      final item = byId[local.itemId];
      if (item == null) {
        // 見つからなかった＝ドキュメントが無い（4.4 の「消えた」）。
        snapshots.add(
          ServerItemSnapshot.missing(listId: listId, itemId: local.itemId),
        );
        continue;
      }
      snapshots.add(
        ServerItemSnapshot(
          listId: listId,
          itemId: local.itemId,
          // **`'active'` / `'deleted'` をそのまま渡す。** ここで
          // 「削除されているか」を判断しない（判定は `DownloadSyncPolicy`）。
          status: item.status.wireName,
          listName: listName,
          item: item,
        ),
      );
    }
    return snapshots;
  }

  /// `updatedAt` のクエリの起点（[_clockSkewAllowance] の注記）。
  DateTime _syncedThrough(List<DownloadedItem> held) {
    var earliest = held.first.downloadedAt;
    for (final item in held) {
      if (item.downloadedAt.isBefore(earliest)) earliest = item.downloadedAt;
    }
    return earliest.subtract(_clockSkewAllowance);
  }
}
