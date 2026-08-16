/// オフライン用ダウンロードの操作（docs/DOWNLOAD-DESIGN.md 4 / 6 章）
///
/// 画面はここを見てボタンを出し分け、ここへ操作を頼む。
/// **ファイルの読み書きは `DownloadRepository` の中だけ**で、
/// 順序の規則もそちらにある（10 節の 1「画面から呼ばない」）。
///
/// **判定はすべて `lib/domain/` を呼ぶ。**
///
/// | 判定 | どこ |
/// | --- | --- |
/// | 落とせるか | `Permissions.canDownload`（5.2） |
/// | オフラインで聴けるか・残り日数・帯 | `OfflineAccessPolicy`（4.2 / 6.1） |
/// | 一括の見積もり | `BulkDownloadPolicy.estimate`（6.3） |
library;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/downloads/download_access_api.dart';
import '../data/downloads/download_file_system.dart';
import '../data/downloads/download_file_system_factory.dart';
import '../data/downloads/download_network_status.dart';
import '../data/models/list_item.dart';
import '../data/repositories/download_repository.dart';
import '../domain/download_estimate.dart';
import '../domain/download_index.dart';
import '../domain/offline_access.dart';
import '../domain/permissions.dart';
import 'app_providers.dart';

// ---------------------------------------------------------------------------
// 組み立て
// ---------------------------------------------------------------------------

/// 端末のファイルを触る口。**Web では何もできない実装が入る**（論点 2）。
final downloadFileSystemProvider = Provider<DownloadFileSystem>(
  // **Firebase は `ref.read` で遅らせる**（下の downloadAccessApiProvider と同じ理由）。
  (ref) => createDownloadFileSystem(() => ref.read(firebaseStorageProvider)),
);

/// 回線の様子。テストでは差し替える。
final networkStatusProvider = Provider<NetworkStatus>(
  (ref) => ConnectivityNetworkStatus(),
);

/// `verifyDownloadAccess` の呼び出し口（5.1）。
///
/// **Firebase は `ref.read` で遅らせる。** ここで `watch` すると、
/// 目録を読むだけの用（ダウンロード済み画面・設定の使用量）でも
/// Firebase の初期化が要ることになり、**オフラインで開く画面が
/// 真っ白になる**（6.1「この画面は Firestore を一切読まないこと」）。
final downloadAccessApiProvider = Provider<DownloadAccessApi>(
  (ref) => DownloadAccessApi(() => ref.read(firebaseFunctionsProvider)),
);

final downloadRepositoryProvider = Provider<DownloadRepository>(
  (ref) => DownloadRepository(
    files: ref.watch(downloadFileSystemProvider),
    access: ref.watch(downloadAccessApiProvider),
    network: ref.watch(networkStatusProvider),
  ),
);

// ---------------------------------------------------------------------------
// 目録
// ---------------------------------------------------------------------------

/// 端末に何を持っているか（3.5）。
///
/// **アプリ全体で 1 つ。** 目録は 1 つのファイルなので、複数の持ち主が
/// できると書き込みが競合する。
final downloadsProvider =
    AsyncNotifierProvider<DownloadsController, DownloadIndex>(
      DownloadsController.new,
    );

class DownloadsController extends AsyncNotifier<DownloadIndex> {
  DownloadRepository get _repository => ref.read(downloadRepositoryProvider);

  /// 起動時にここを通る。**掃除（4.7）が権限確認（4.2）より先。**
  ///
  /// 権限確認は [startup] で行う。ここでやらないのは、**目録を読むだけの
  /// 用（設定画面の使用量表示など）で毎回サーバーを呼びたくない**ため。
  @override
  Future<DownloadIndex> build() async {
    final repository = ref.watch(downloadRepositoryProvider);
    try {
      await repository.load();
      return await repository.cleanUp();
    } on DownloadStorageUnavailableException {
      // **Web には保存先が無い**（論点 2）。空の目録として振る舞い、
      // 再生は `PlaybackPolicy.resolve` が `remote` に倒す。
      return const DownloadIndex();
    } on MissingPluginException {
      // 端末側の実装が無い（Dart VM でのテストなど）。同上。
      return const DownloadIndex();
    }
  }

  /// アプリ起動時の一連（4.7 → 4.2）。
  ///
  /// **順序が要点。** 掃除を先にしないと、`.part` の残骸や孤児が
  /// 権限確認のあとまで残る。
  ///
  /// **権限確認が失敗しても何も起きない**（5.1）。圏外で 1 回失敗した
  /// だけで全曲が消える、という事故を起こさないため。
  Future<void> startup() async {
    state = await AsyncValue.guard(() async {
      await _repository.cleanUp();
      final index = await _repository.verifyAccess();
      await ref.read(isOnlineProvider.notifier).refresh();
      return index;
    });
  }

  /// 曲を 1 つ落とす（4.1）。
  Future<void> downloadItem({
    required String listId,
    required String listName,
    required ListItem item,
    List<OfflineComment> comments = const [],
    DownloadProgress? onProgress,
    void Function(DownloadHandle handle)? onStarted,
  }) async {
    // **失敗を握りつぶさない。** 画面が「Wi-Fi で接続してください」などを
    // 出し分けられるよう、例外はそのまま上げる。
    final index = await _repository.downloadItem(
      listId: listId,
      listName: listName,
      item: item,
      comments: comments,
      onProgress: onProgress,
      // **中断の手を画面へ渡す**（6.3・論点 20）。押したら、いま落として
      // いる曲の `.part` だけ捨て、済んだぶんは残る。
      onStarted: onStarted,
    );
    state = AsyncData(index);
  }

  /// 端末から 1 曲消す（論点 6）。
  Future<void> removeItem({
    required String listId,
    required String itemId,
  }) async {
    state = AsyncData(
      await _repository.removeItem(listId: listId, itemId: itemId),
    );
  }

  /// 端末のぶんを丸ごと消す（6.4）。
  ///
  /// **画面には「曲とリストは消えません」を必ず添えること**（2.1）。
  Future<void> removeAll() async {
    state = AsyncData(await _repository.removeAll());
  }

  /// モバイル通信でも落とすか（4.6・論点 11b）。
  Future<void> setAllowMobileData(bool value) async {
    state = AsyncData(await _repository.setAllowMobileData(value));
  }

  /// いま始めてよい回線か（4.6）。
  Future<bool> canStartDownloadNow() => _repository.allowsDownloadNow();

  /// 元の削除・差し替えを反映する（4.4）。
  ///
  /// 何が起きたかは戻り値で返す——**黙って消すと「アプリが勝手に消した」
  /// と受け取られる**ので、画面が知らせること。
  Future<DownloadSyncReport> sync({
    required Set<String> listIds,
    required Iterable<ServerItemSnapshot> serverItems,
  }) async {
    final report = await _repository.syncWithServer(
      listIds: listIds,
      serverItems: serverItems,
    );
    state = AsyncData(report.index);
    return report;
  }

  /// 端末にある音源の絶対パス（4.3）。無ければ null。
  ///
  /// **目録に無ければ、保存先を開きに行かない。** 再生のたびに
  /// ファイルシステムを触ると、**落としていない曲を鳴らすまでの間に
  /// 待ちが 1 つ増える。** ブラウザや OS は「利用者が触った直後」でないと
  /// 音を鳴らさないことがあり、その待ちが命取りになる
  /// （`PlaybackController._urls` を持っているのと同じ理由）。
  ///
  /// **保存先が使えないときも null。** Web とテストがここを通る。
  Future<String?> localAudioPath(String itemId) async {
    final index = state.value;
    if (index == null) return null;
    if (!index.items.any((item) => item.itemId == itemId)) return null;

    try {
      return await _repository.localAudioPath(itemId);
    } on DownloadStorageUnavailableException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// オフラインで読むコメント（論点 8）。**読むだけ。**
  Future<List<OfflineComment>> offlineComments({
    required String listId,
    required String itemId,
  }) => _repository.offlineComments(listId: listId, itemId: itemId);

  /// バックアップ除外が実際に付いているか（3.2）。
  ///
  /// **設定画面の開発者向け表示か、起動時のログに出すこと。**
  /// 付けたつもりで付いていないのが最悪なので、確かめる手段を残す。
  Future<bool?> backupExclusionState() => _repository.isExcludedFromBackup();

  /// 一括ダウンロードの見積もり（6.3・論点 20）。
  ///
  /// **上限を置かない代わりが、見積もり・進捗・中断の 3 つ。**
  /// 押す前に「12 曲中 8 曲は保存済み。残り 4 曲・約 160 MB」を出す。
  ///
  /// **削除済みの項目はここで外す。** `BulkDownloadPolicy` は項目の状態を
  /// 見ない決まりで（見ると 4.4 の判定と 2 つになる）、絞るのは呼ぶ側の仕事。
  BulkDownloadEstimate estimateBulk(Iterable<ListItem> items) {
    final index = state.value ?? const DownloadIndex();
    return BulkDownloadPolicy.estimate(
      candidates: items
          .where((item) => !item.isDeleted)
          .where((item) => item.file != null)
          .map(
            (item) => BulkDownloadCandidate(
              itemId: item.id,
              contentType: item.file!.contentType,
              fileName: item.file!.fileName,
              sizeBytes: item.file!.sizeBytes,
            ),
          ),
      downloadedItemIds: index.items.map((i) => i.itemId).toSet(),
    );
  }
}

// ---------------------------------------------------------------------------
// 回線
// ---------------------------------------------------------------------------

/// いま回線に繋がっているか（4.3 の `isOnline`）。
///
/// **既定は「繋がっている」。** 分からないことを「圏外」と断定すると、
/// 判定の仕組みが無い環境で**再生が全部止まる**。ここで安全側とは
/// 「いまできていることを壊さないほう」である
/// （落としてある曲は、この値に関わらず `local` で鳴る）。
final isOnlineProvider = NotifierProvider<OnlineController, bool>(
  OnlineController.new,
);

class OnlineController extends Notifier<bool> {
  @override
  bool build() => true;

  /// 回線を見に行って更新する。起動時（[DownloadsController.startup]）に呼ぶ。
  Future<void> refresh() async {
    state = await ref.read(networkStatusProvider).isOnline();
  }
}

// ---------------------------------------------------------------------------
// 判定（domain を呼ぶだけ）
// ---------------------------------------------------------------------------

/// そのリストの曲を落とせるか（5.2・論点 9・12・18）。
///
/// **`AsyncValue` のまま返す**（`app_providers.dart` の `isPremiumProvider`
/// と同じ理由）。届く前に false を確定させると、プレミアムの人に一瞬
/// 「ダウンロードできません」が見える。**読み込み中はどちらも出さないこと**
/// （6.5）。
final canDownloadProvider = Provider.family<AsyncValue<bool>, String>((
  ref,
  listId,
) {
  final access = ref.watch(listAccessProvider(listId));
  return ref
      .watch(isPremiumProvider)
      .whenData(
        (isPremium) => Permissions.canDownload(access, isPremium: isPremium),
      );
});

/// 閲覧者にはボタンそのものを出さない（6.5）。
///
/// **プレミアムを契約しても使えない**ので、押せるものを見せると
/// 「契約したのに使えない」になる。サイト管理者でメンバーでない人も同じ
/// （論点 18）——判定は `role != null` の 1 つだけ。
final showsDownloadButtonProvider = Provider.family<bool, String>(
  (ref, listId) => ref.watch(listAccessProvider(listId)).role != null,
);

/// ダウンロード済み画面の上に出す帯（6.1・論点 21）。
final offlineNoticeBandProvider = Provider<OfflineNoticeBand>((ref) {
  return OfflineAccessPolicy.band(
    lastVerifiedAt: ref.watch(downloadsProvider).value?.lastVerifiedAt,
    now: DateTime.now(),
  );
});

/// 帯に出す残り日数（6.1）。**切り捨て。短めに出すのが安全側。**
final offlineRemainingDaysProvider = Provider<int>((ref) {
  return OfflineAccessPolicy.remainingDays(
    lastVerifiedAt: ref.watch(downloadsProvider).value?.lastVerifiedAt,
    now: DateTime.now(),
  );
});

/// いまオフライン再生してよいか（4.2・論点 13b）。
///
/// **猶予を過ぎてもファイルは消さない。** オンラインで確認が取れれば
/// 即座に復活する。
final isPlayableOfflineProvider = Provider<bool>((ref) {
  return OfflineAccessPolicy.isPlayableOffline(
    lastVerifiedAt: ref.watch(downloadsProvider).value?.lastVerifiedAt,
    now: DateTime.now(),
  );
});
