/// 同時編集の検出（仕様書 6.3）
///
/// 編集画面を開いた時点の更新日時を保持しておき、保存時に
/// 「開いてから他の人が更新していないか」を確認する。
/// 更新されていた場合は保存を中止して警告を出す（楽観的ロック）。
///
/// 編集中のロックは行わない。ブラウザを閉じられたときにロックが残るため。
///
/// この判定は Firestore のトランザクション内でも行い、画面上のチェックだけに
/// 頼らない。ここはその規則を通信なしで検証できる形に切り出したもの。
library;

/// 保存可否の判定結果。
enum SaveDecision {
  /// 保存してよい。
  proceed,

  /// 他の人が更新済み。保存を中止して再読み込みを促す。
  conflict,
}

/// 同時編集の検出。
class ConcurrentEditGuard {
  const ConcurrentEditGuard._();

  /// 保存してよいか判定する。
  ///
  /// [openedWith] は編集画面を開いたときに読み取った `updatedAt`。
  /// [currentOnServer] は保存直前にサーバー上で読み取った `updatedAt`。
  ///
  /// 両者が一致すれば、開いてから誰も更新していない。
  static SaveDecision check({
    required DateTime? openedWith,
    required DateTime? currentOnServer,
  }) {
    if (openedWith == null || currentOnServer == null) {
      // どちらかが取れない場合は、上書き事故を避けるため衝突扱いにする。
      return SaveDecision.conflict;
    }
    return openedWith.isAtSameMomentAs(currentOnServer)
        ? SaveDecision.proceed
        : SaveDecision.conflict;
  }
}
