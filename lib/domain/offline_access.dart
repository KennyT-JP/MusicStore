/// オフライン再生の猶予（docs/DOWNLOAD-DESIGN.md 4.2 / 6.1・論点 13b / 21）
///
/// **通信も端末の音も要らない形にしてある。** `playback.dart` /
/// `permissions.dart` と同じ流儀で、判定だけをここに置いて回帰テストで固定する。
///
/// ## この判定は端末の時計に依存している（4.2 の注記）
///
/// 端末の日付を戻せば、猶予は伸びる。塞ぐには「時刻をサーバーからしか
/// 取らない」しかなく、**それはオフライン再生と両立しない。** オフラインで
/// 聴けることが要求である以上、ここは開く。
///
/// **これは「保証」ではなく「歯止め」である。** 意図せず圏外にいた人が
/// 急に聴けなくなるのを防ぐための猶予であって、悪意ある人を止める仕組みでは
/// ない。画面にも規約にもそう書くこと。**「時計を戻すと再生できる」ことは
/// 仕様であり、不具合ではない**（テストで固定してある）。
library;

/// オフラインで聴ける期間（論点 13b）。**30 日 = 2,592,000,000 ミリ秒。**
///
/// **`siteConfig.itemPurgeGraceDays` の既定 30 日とは別物**（10 節の 9）。
/// たまたま同じ値だが、混ぜて `siteConfig` から読むようにすると、
/// サイト管理者が削除の猶予を 15 日に変えた瞬間に、
/// オフラインで聴ける期間まで 15 日になる。
const Duration kOfflineGrace = Duration(days: 30);

/// 予告の帯を出し始める残り日数（6.1・論点 21）。**残り 7 日以下で出す。**
const int kOfflineNoticeDays = 7;

/// ダウンロード済み画面の上に出す帯（6.1）。3 段。
enum OfflineNoticeBand {
  /// 残り 8 日以上。**帯を出さない。**
  none,

  /// 残り 7 日以下で、まだ聴ける。「あと N 日でオフライン再生が止まります」。
  expiring,

  /// 猶予を過ぎて再生が止まっている。
  ///
  /// **ファイルは消していない**（論点 13b）。帯にもそう書く——
  /// 一度オンラインになれば、そのまま聴けるようになる。
  stopped,
}

/// オフライン再生の可否と残り日数（4.2 / 6.1）。
class OfflineAccessPolicy {
  const OfflineAccessPolicy._();

  /// オフラインで再生してよいか（論点 13b）。
  ///
  /// **ちょうど 30 日は「切れている」側に倒す。**
  /// `functions/src/domain/premium.ts` の `isPremiumActive` が
  /// `untilMs > nowMs`（ちょうどは含まない）としており、境界の扱いが
  /// ファイルごとに違うと、どちらが正しいかを読む側が毎回調べ直すことになる。
  ///
  /// **[lastVerifiedAt] が null なら不可。** ダウンロードは権限確認を
  /// 通ったあとにしか始まらないので実際には起きないはずだが、
  /// 既定は安全側に倒す（`ListRole.tryParse` が未知の値に役割を
  /// 与えないのと同じ考え）。
  static bool isPlayableOffline({
    required DateTime? lastVerifiedAt,
    required DateTime now,
    Duration grace = kOfflineGrace,
  }) {
    if (lastVerifiedAt == null) return false;
    return now.difference(lastVerifiedAt) < grace;
  }

  /// 残り日数。0 以下なら止まっている（6.1・論点 21）。
  ///
  /// **`inDays` は切り捨て。** 残り 7 日 12 時間なら「あと 7 日」と出る。
  /// **切り上げにしないこと**——「あと 8 日」と出したのに 7 日後に止まると、
  /// 1 日ぶん嘘をついたことになる。**短めに出すのが安全側。**
  static int remainingDays({
    required DateTime? lastVerifiedAt,
    required DateTime now,
    Duration grace = kOfflineGrace,
  }) {
    if (lastVerifiedAt == null) return 0;
    final left = grace - now.difference(lastVerifiedAt);
    return left.isNegative ? 0 : left.inDays;
  }

  /// 画面の上に出す帯（6.1）。
  ///
  /// **可否の判定（[isPlayableOffline]）を分岐の軸にする。**
  /// 残り日数が 0 でも、30 日ちょうどに達するまでは「あと 0 日」の予告で、
  /// 停止の帯ではない。日数だけで分けると、この 1 段がずれる。
  static OfflineNoticeBand band({
    required DateTime? lastVerifiedAt,
    required DateTime now,
    Duration grace = kOfflineGrace,
  }) {
    final playable = isPlayableOffline(
      lastVerifiedAt: lastVerifiedAt,
      now: now,
      grace: grace,
    );
    if (!playable) return OfflineNoticeBand.stopped;

    final left = remainingDays(
      lastVerifiedAt: lastVerifiedAt,
      now: now,
      grace: grace,
    );
    return left <= kOfflineNoticeDays
        ? OfflineNoticeBand.expiring
        : OfflineNoticeBand.none;
  }
}
