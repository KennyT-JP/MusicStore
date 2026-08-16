/// リスト一括ダウンロードの見積もり（docs/DOWNLOAD-DESIGN.md 6.3・論点 20）
///
/// **曲数にも容量にも上限を置かない。** 代わりに、始める前に
/// **見積もりを出して確認を取る**（論点 20）。
///
/// > 上限を置かない代わりが、見積もり・進捗・中断の 3 つ。どれか 1 つでも
/// > 欠けると、「押したら何が起きるか分からないボタン」になる。
/// > **上限が無いことと、無警告で始めることは違う。**
///
/// ここに置くのは見積もりだけ。進捗と中断はダウンロードを回す側の仕事。
library;

import 'download_target.dart';

/// 見積もりの対象になる 1 件（6.3）。
class BulkDownloadCandidate {
  const BulkDownloadCandidate({
    required this.itemId,
    required this.contentType,
    required this.fileName,
    required this.sizeBytes,
  });

  final String itemId;

  /// 対象かどうかの判定に使う（3.3・論点 5）。
  final String contentType;
  final String fileName;

  /// サーバー側の大きさ。**まだ落としていないので、これしか無い。**
  final int sizeBytes;
}

/// 一括ダウンロードを始める前に出す見積もり（6.3）。
///
/// 画面には「**12 曲中 8 曲は保存済み。残り 4 曲・約 160 MB**」と出す。
/// **曲数と合計サイズを必ず両方出すこと**（論点 20）。
class BulkDownloadEstimate {
  const BulkDownloadEstimate({
    required this.targetCount,
    required this.alreadyDownloadedCount,
    required this.remainingCount,
    required this.remainingBytes,
  });

  /// 対象になる曲数（「12 曲中」の 12）。
  ///
  /// **対象外のファイル（PDF・zip・白リストに無い拡張子）は数えない**（3.3）。
  final int targetCount;

  /// すでに端末に持っている曲数（「8 曲は保存済み」）。
  final int alreadyDownloadedCount;

  /// これから落とす曲数（「残り 4 曲」）。
  final int remainingCount;

  /// これから落とす合計サイズ（「約 160 MB」）。
  final int remainingBytes;

  /// 落とすものが 1 つも無いか。**確認を出す必要すらない。**
  bool get isEmpty => remainingCount == 0;
}

/// 一括ダウンロードの見積もり（6.3）。
class BulkDownloadPolicy {
  const BulkDownloadPolicy._();

  /// 始める前の見積もりを出す。
  ///
  /// **すでに落としてあるぶんは数にもサイズにも入れない**（6.3）。
  /// 入れると、「残り 4 曲」と言いながら 12 曲ぶんの大きさを出すことになる。
  ///
  /// [downloadedItemIds] は `index.json` が持っている `itemId` の集合。
  /// 削除済みの項目を落とすかどうかは、**呼ぶ側で絞ってから渡すこと**——
  /// ここでは項目の状態を見ない（見るなら 4.4 の `DownloadSyncPolicy` と
  /// 判定が 2 つになる）。
  static BulkDownloadEstimate estimate({
    required Iterable<BulkDownloadCandidate> candidates,
    required Set<String> downloadedItemIds,
  }) {
    var targetCount = 0;
    var alreadyDownloadedCount = 0;
    var remainingCount = 0;
    var remainingBytes = 0;

    for (final candidate in candidates) {
      final kind = downloadTargetKind(
        contentType: candidate.contentType,
        fileName: candidate.fileName,
      );
      if (kind == DownloadTargetKind.unsupported) continue;

      targetCount++;
      if (downloadedItemIds.contains(candidate.itemId)) {
        alreadyDownloadedCount++;
        continue;
      }
      remainingCount++;
      remainingBytes += candidate.sizeBytes;
    }

    return BulkDownloadEstimate(
      targetCount: targetCount,
      alreadyDownloadedCount: alreadyDownloadedCount,
      remainingCount: remainingCount,
      remainingBytes: remainingBytes,
    );
  }
}
