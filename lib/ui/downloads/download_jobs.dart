/// 進行中のダウンロード（docs/DOWNLOAD-DESIGN.md 6.2 / 6.3）
///
/// **ここは画面の状態だけを持つ。** ファイルの読み書きも、書く順序も
/// `DownloadRepository` の中だけにある（10 節の 1「画面から呼ばない」）。
/// ここがするのは 3 つ——**どこまで進んだかを覚える・中止の手を持つ・
/// 済んだら忘れる。**
///
/// **上限を置かない代わりが、見積もり・進捗・中断の 3 つ**（論点 20）。
/// 見積もりは `BulkDownloadPolicy.estimate`（domain）にあり、
/// 残りの 2 つがここにある。
library;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/downloads/download_file_system.dart';
import '../../data/models/list_item.dart';
import '../../data/repositories/download_repository.dart';
import '../../domain/display_name.dart';
import '../../domain/download_index.dart';
import '../../domain/download_target.dart';
import '../../providers/app_providers.dart';
import '../../providers/download_provider.dart';

/// 1 曲の結果。**「中止」を「失敗」と混ぜない**（4.1 の表）。
enum DownloadOutcome {
  done,

  /// 利用者が中止した。**知らせない。** 押したとおりに止まっただけ。
  canceled,

  /// Wi-Fi でなく、モバイル通信も許していない（4.6・論点 11b）。
  blockedByNetwork,

  /// 音源として落とせないファイル（3.3・論点 5）。
  notSupported,

  /// `storage.rules` に落ちた。メンバーでなくなっている可能性が高い（4.1）。
  permissionDenied,

  /// 保存先が無い。**Web に導線が残っている**という作りの誤り（6.5）。
  unavailable,

  failed,
}

/// 1 曲ぶんの進み具合（4.1 の手順 3）。
///
/// **「%」だけでなく「12.3 MB / 41.2 MB」も出すこと。**
/// 曲は大きく、% だけだと止まって見える。
class ItemDownloadJob {
  const ItemDownloadJob({this.transferred = 0, this.total = 0});

  final int transferred;
  final int total;

  /// 0.0〜1.0。まだ全体の大きさが分からなければ null（不定の輪を出す）。
  double? get ratio {
    if (total <= 0) return null;
    return (transferred / total).clamp(0.0, 1.0);
  }
}

/// リスト一括の進み具合（6.3）。
///
/// 進捗は 2 段——「12 曲中 5 曲目」と「その曲の中の進捗」。
class BulkDownloadJob {
  const BulkDownloadJob({
    required this.listId,
    required this.total,
    required this.completed,
    required this.failed,
    this.currentItemId,
  });

  final String listId;

  /// これから落とす曲数（すでに持っているぶんは入っていない）。
  final int total;

  final int completed;
  final int failed;
  final String? currentItemId;

  /// 「5 / 12 曲目」の 5。
  int get position =>
      completed + failed + 1 > total ? total : completed + failed + 1;
}

/// 一括の結末（6.3）。
class BulkDownloadResult {
  const BulkDownloadResult({
    required this.completed,
    required this.failed,
    required this.canceled,
  });

  final int completed;
  final int failed;

  /// 途中で止めた。**済んだぶんは残っている**（4.1）。
  final bool canceled;
}

/// いま何を落としているか。
class DownloadJobs {
  const DownloadJobs({this.items = const {}, this.bulk});

  /// `itemId` → 進み具合。
  final Map<String, ItemDownloadJob> items;

  final BulkDownloadJob? bulk;

  bool isDownloading(String itemId) => items.containsKey(itemId);
}

/// コメントを解決して端末に持てる形にする（論点 8・3.5）。
///
/// **差し替えられるようにしてある**（`downloadUrlResolverProvider` と同じ理由）。
/// ボタンの出し分けを確かめるだけのテストに Firestore を要らせない。
typedef OfflineCommentsLoader =
    Future<List<OfflineComment>> Function({
      required String listId,
      required String itemId,
      required String withdrawnLabel,
    });

/// 既定の読み込み（Firestore から読んで、表示名を解決して埋める）。
///
/// **`authorName` は解決済みで持つ**（3.5）。表示名は `users/{uid}` にあり、
/// オフラインでは引けない。名前が変わっても端末側は古いまま出るが、
/// **「名前が古い」と「名前が出ない」なら前者のほうがまし。**
///
/// ## 画面用のプロバイダを通さない（2026-08-16 に実際に踏んだ）
///
/// `itemCommentsProvider` / `userDirectoryProvider` / `listMembersProvider` は
/// **autoDispose** である（`app_providers.dart` の「リストや項目ごとに
/// 作られるプロバイダは autoDispose にすること」／監査 S7）。
/// `ref.read(….future)` は**購読を作らない**ので、その曲のコメントを
/// 誰も見ていないと、**値が届く前に破棄される。**
///
/// ```
/// Bad state: The provider StreamProvider<List<ItemComment>>… was disposed
/// during loading state, yet no value could be emitted.
/// ```
///
/// **そして下の catch がそれを握りつぶし、コメント 0 件のまま保存される。**
/// 項目詳細から落としたときだけ動く（その画面が購読しているため）ので、
/// **一覧からの単曲と一括だけが静かに壊れる**という形になっていた。
///
/// **リポジトリを直に呼ぶ。** `itemRepositoryProvider` /
/// `listRepositoryProvider` は autoDispose ではなく、購読の有無に左右されない。
/// **一度きりの読み取りなので `.first` で足りる**——ここは画面ではないので、
/// 更新を追い続ける必要がない。
final offlineCommentsLoaderProvider = Provider<OfflineCommentsLoader>((ref) {
  return ({
    required String listId,
    required String itemId,
    required String withdrawnLabel,
  }) async {
    final comments = await ref
        .read(itemRepositoryProvider)
        .watchComments(listId, itemId)
        .first;
    if (comments.isEmpty) return const [];

    final users = await ref
        .read(listRepositoryProvider)
        .fetchUsers(comments.map((c) => c.createdBy));
    final members = await ref
        .read(listRepositoryProvider)
        .watchMembers(listId)
        .first;
    final memberUids = members.map((m) => m.uid).toSet();

    return [
      for (final comment in comments)
        OfflineComment(
          id: comment.id,
          parentId: comment.parentId,
          path: comment.path,
          createdAt: comment.createdAt,
          body: comment.body,
          authorName: DisplayNameResolver.resolveInList(
            uid: comment.createdBy,
            user: users[comment.createdBy] == null
                ? null
                : UserNameSource(
                    displayName: users[comment.createdBy]!.displayName,
                    isWithdrawn: users[comment.createdBy]!.isWithdrawn,
                  ),
            currentMemberUids: memberUids,
            withdrawnLabel: withdrawnLabel,
          ).text,
          status: comment.isDeleted ? 'deleted' : 'active',
        ),
    ];
  };
});

final downloadJobsProvider =
    NotifierProvider<DownloadJobsController, DownloadJobs>(
      DownloadJobsController.new,
    );

class DownloadJobsController extends Notifier<DownloadJobs> {
  /// 中止の手。**状態には入れない**——描き直しのたびに配るものではない。
  final _handles = <String, DownloadHandle>{};

  /// 一括を止めてほしいと言われたか（6.3）。
  bool _bulkCanceled = false;

  @override
  DownloadJobs build() => const DownloadJobs();

  /// 曲を 1 つ落とす（4.1・6.2）。
  ///
  /// **例外を上へ流さない。** 画面は結果を見て文言を選ぶ。
  /// どれも「押した人に何が起きたかを伝える」ための区別で、
  /// **失敗と中止を混ぜない**（4.1）。
  Future<DownloadOutcome> downloadItem({
    required String listId,
    required String listName,
    required ListItem item,
    required String withdrawnLabel,
  }) async {
    if (state.isDownloading(item.id)) return DownloadOutcome.canceled;
    _setJob(item.id, const ItemDownloadJob());

    try {
      // **コメントが取れなくても音源は落とす**（論点 8）。
      // 読み物が 1 つ欠けるだけで、聴けなくなるわけではない。
      var comments = const <OfflineComment>[];
      try {
        comments = await ref.read(offlineCommentsLoaderProvider)(
          listId: listId,
          itemId: item.id,
          withdrawnLabel: withdrawnLabel,
        );
      } catch (_) {
        comments = const [];
      }

      await ref
          .read(downloadsProvider.notifier)
          .downloadItem(
            listId: listId,
            listName: listName,
            item: item,
            comments: comments,
            onProgress: (transferred, total) => _setJob(
              item.id,
              ItemDownloadJob(transferred: transferred, total: total),
            ),
            onStarted: (handle) => _handles[item.id] = handle,
          );
      return DownloadOutcome.done;
    } on DownloadCanceledException {
      return DownloadOutcome.canceled;
    } on DownloadBlockedByNetworkException {
      return DownloadOutcome.blockedByNetwork;
    } on DownloadNotSupportedException {
      return DownloadOutcome.notSupported;
    } on DownloadPermissionDeniedException {
      return DownloadOutcome.permissionDenied;
    } on DownloadStorageUnavailableException {
      return DownloadOutcome.unavailable;
    } on MissingPluginException {
      return DownloadOutcome.unavailable;
    } catch (_) {
      return DownloadOutcome.failed;
    } finally {
      _handles.remove(item.id);
      _clearJob(item.id);
    }
  }

  /// いま落としている 1 曲を止める（6.2）。
  ///
  /// **`.part` だけが捨てられ、済んだぶんは残る**（4.1）。
  Future<void> cancelItem(String itemId) async {
    final handle = _handles.remove(itemId);
    await handle?.cancel();
  }

  /// リスト一括（6.3・論点 4）。**曲ごとの繰り返し。並列にしない。**
  ///
  /// - **同時に 1 つずつ。** 並列にすると端末の回線を占有し、途中で止めた
  ///   ときにどこまで済んだのか分からなくなる
  /// - **1 曲失敗しても止めない。** 続けて、最後に「3 曲落とせませんでした」
  ///   と出す。1 曲の失敗で 50 曲が止まるのは割に合わない
  /// - **いつでも中断できる**（論点 20）
  ///
  /// [items] は画面が持っている一覧をそのまま渡してよい。
  /// **すでに落としてあるぶんと対象外のファイルはここで外す**（6.3）。
  Future<BulkDownloadResult> downloadList({
    required String listId,
    required String listName,
    required Iterable<ListItem> items,
    required String withdrawnLabel,
  }) async {
    // **`.value` で読まない。** まだ目録が届いていないと空集合へ静かに倒れ、
    // **すでに持っている曲をもう一度落とす**（test/domain/async_provider_read_test.dart）。
    final index = await ref.read(downloadsProvider.future);
    final downloaded = index.items.map((i) => i.itemId).toSet();

    final targets = items
        .where((item) => !item.isDeleted)
        .where((item) => item.file != null)
        .where(
          (item) =>
              downloadTargetKind(
                contentType: item.file!.contentType,
                fileName: item.file!.fileName,
              ) ==
              DownloadTargetKind.audio,
        )
        .where((item) => !downloaded.contains(item.id))
        .toList();

    _bulkCanceled = false;
    var completed = 0;
    var failed = 0;

    for (final item in targets) {
      if (_bulkCanceled) break;
      state = DownloadJobs(
        items: state.items,
        bulk: BulkDownloadJob(
          listId: listId,
          total: targets.length,
          completed: completed,
          failed: failed,
          currentItemId: item.id,
        ),
      );

      final outcome = await downloadItem(
        listId: listId,
        listName: listName,
        item: item,
        withdrawnLabel: withdrawnLabel,
      );

      switch (outcome) {
        case DownloadOutcome.done:
          completed++;
        case DownloadOutcome.canceled:
          // **中止は失敗に数えない。** 押したとおりに止まっただけ。
          _bulkCanceled = true;
        case DownloadOutcome.blockedByNetwork:
        case DownloadOutcome.unavailable:
          // **続けても同じ結果にしかならない。** 1 曲ずつ 50 回
          // 同じことを確かめない。
          failed++;
          _bulkCanceled = true;
        case DownloadOutcome.notSupported:
        case DownloadOutcome.permissionDenied:
        case DownloadOutcome.failed:
          failed++;
      }
    }

    final canceled = _bulkCanceled;
    _bulkCanceled = false;
    state = DownloadJobs(items: state.items);
    return BulkDownloadResult(
      completed: completed,
      failed: failed,
      canceled: canceled,
    );
  }

  /// 一括を止める（6.3・論点 20）。
  ///
  /// **いま落としている曲の `.part` だけ捨て、済んだぶんは残す**（4.1）。
  Future<void> cancelBulk() async {
    _bulkCanceled = true;
    final current = state.bulk?.currentItemId;
    if (current != null) await cancelItem(current);
  }

  void _setJob(String itemId, ItemDownloadJob job) {
    state = DownloadJobs(
      items: {...state.items, itemId: job},
      bulk: state.bulk,
    );
  }

  void _clearJob(String itemId) {
    final next = {...state.items}..remove(itemId);
    state = DownloadJobs(items: next, bulk: state.bulk);
  }
}
