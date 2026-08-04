/// 連番の採番（仕様書 6.2 / 13.3）
///
/// 12.6 で「自動テストを書く対象（必須）」に挙げた領域。
///
/// 実際の採番は Firestore のトランザクションで
/// `lists/{listId}/meta/stats.nextSeq` を読み、項目作成と同時に +1 する。
/// ここはその計算規則と不変条件を、通信なしで検証できる形に切り出したもの。
library;

/// 連番カウンタの状態。
class SequenceCounter {
  const SequenceCounter(this.nextSeq);

  /// リスト作成直後の初期値（13.3）。
  const SequenceCounter.initial() : nextSeq = 1;

  /// 次に採番する番号。
  final int nextSeq;

  /// 採番結果。
  SequenceAllocation allocate() {
    if (nextSeq < 1) {
      throw StateError('nextSeq must be 1 or greater, but was $nextSeq');
    }
    return SequenceAllocation(
      seq: nextSeq,
      updatedCounter: SequenceCounter(nextSeq + 1),
    );
  }
}

/// 1 回の採番の結果。
class SequenceAllocation {
  const SequenceAllocation({required this.seq, required this.updatedCounter});

  /// この項目に付ける連番。
  final int seq;

  /// 書き戻すカウンタ。
  final SequenceCounter updatedCounter;
}

/// 連番に関する規則。
class SequencePolicy {
  const SequencePolicy._();

  /// 項目の削除では連番を戻さない（6.2：振り直しなし・欠番を残す）。
  ///
  /// 削除は項目の `status` を `deleted` にするだけで、カウンタには触らない。
  /// この関数はその意図を明示するためのもの。
  static SequenceCounter onItemDeleted(SequenceCounter counter) => counter;

  /// アップロードが失敗・中断したときも連番を消費しない（7.5）。
  ///
  /// ファイルのアップロードが完全に終わってから項目を作成するため、
  /// 失敗した時点では採番自体が行われていない。
  static SequenceCounter onUploadAborted(SequenceCounter counter) => counter;
}
