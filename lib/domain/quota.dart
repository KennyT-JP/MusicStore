/// 容量上限の判定（仕様書 7.2 / 7.3 / 7.5）
///
/// 12.6 で「自動テストを書く対象（必須）」に挙げた領域。
/// 通知の境界（80% / 90%）とアップロードのブロック判定をここに集約する。
library;

/// 容量上限の初期値：1GB（7.2）。
const int kDefaultQuotaBytes = 1073741824;

/// Notice を出すしきい値（7.3）。
const double kQuotaNoticeThreshold = 0.80;

/// 警告を出すしきい値（7.3）。
const double kQuotaWarningThreshold = 0.90;

/// 容量に関する通知のレベル。
enum QuotaLevel {
  /// しきい値未満。通知しない。
  normal,

  /// 80% 超（7.3）。
  notice,

  /// 90% 超（7.3）。
  warning,
}

/// リストの容量の状態。
class QuotaStatus {
  const QuotaStatus({required this.usedBytes, required this.quotaBytes});

  final int usedBytes;
  final int quotaBytes;

  /// 使用率（0.0〜）。上限が 0 以下なら 1.0（＝満杯扱い）とする。
  ///
  /// 上限 0 のリストにアップロードを通してしまわないための保守的な既定値。
  double get ratio {
    if (quotaBytes <= 0) return 1.0;
    return usedBytes / quotaBytes;
  }

  /// 残り容量。超過している場合は 0。
  int get remainingBytes {
    final remaining = quotaBytes - usedBytes;
    return remaining > 0 ? remaining : 0;
  }

  /// 上限に達している、または超えているか。
  bool get isOverQuota => usedBytes >= quotaBytes;

  /// 通知レベル（7.3）。
  ///
  /// 「80% を超えたら」「90% を超えたら」なので、ちょうど 80%・90% は
  /// まだ超えていないものとして扱う。
  QuotaLevel get level {
    final r = ratio;
    if (r > kQuotaWarningThreshold) return QuotaLevel.warning;
    if (r > kQuotaNoticeThreshold) return QuotaLevel.notice;
    return QuotaLevel.normal;
  }
}

/// アップロード可否の判定結果。
class UploadDecision {
  const UploadDecision._(this.allowed, this.reason);

  const UploadDecision.allow() : this._(true, null);
  const UploadDecision.block(UploadBlockReason reason) : this._(false, reason);

  final bool allowed;
  final UploadBlockReason? reason;
}

/// アップロードをブロックする理由。
enum UploadBlockReason {
  /// すでに上限に達している（7.3）。
  alreadyOverQuota,

  /// このファイルを加えると上限を超える（7.5）。
  wouldExceedQuota,

  /// サイズが不正（0 以下）。
  invalidSize,
}

/// 容量に関する判定。
class QuotaPolicy {
  const QuotaPolicy._();

  /// アップロードを開始してよいか（7.5）。
  ///
  /// 無駄な通信と課金を避けるため、**アップロードを始める前**に呼ぶ。
  static UploadDecision canStartUpload({
    required QuotaStatus status,
    required int fileSizeBytes,
  }) {
    if (fileSizeBytes <= 0) {
      return const UploadDecision.block(UploadBlockReason.invalidSize);
    }
    if (status.isOverQuota) {
      return const UploadDecision.block(UploadBlockReason.alreadyOverQuota);
    }
    if (status.usedBytes + fileSizeBytes > status.quotaBytes) {
      return const UploadDecision.block(UploadBlockReason.wouldExceedQuota);
    }
    return const UploadDecision.allow();
  }

  // 通知境界（80% / 90%）を「誰に・いつ送るか」の判定は、ここには置かない。
  //
  // **サーバー側 functions/src/domain/quota.ts が正。** 通知はファイルの
  // 加算を検知した Functions が送るので、クライアントに規則の写しを持つと
  // テストは緑なのに本番では別のコードが動く状態になる（share_link.dart が
  // 既にやった「サーバーが正」方式に合わせる／監査 第4回）。
  // ここに残すのは、画面が使う表示レベル（QuotaStatus.level）と
  // アップロード前のブロック判定だけ。
}
