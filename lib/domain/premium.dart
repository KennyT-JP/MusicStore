/// プレミアムの判定（docs/PREMIUM-DESIGN.md 3.1）
///
/// **状態は `users/{uid}.premium.until` だけで表す。** 「プレミアムかどうか」の
/// 真偽値を別に持つと、期限が切れたときに 2 つが食い違う。
///
/// **サーバーにも同じ判定がある**（`functions/src/domain/premium.ts`）。
/// 実際に作成を止めるのはサーバーで、ここにあるのは**画面の出し分け**のため
/// だけの写しである。判定の正本はサーバー側であり、ここを緩めても
/// リストは作れない。
library;

/// プレミアムの判定。
class PremiumPolicy {
  const PremiumPolicy._();

  /// [until] の時点までプレミアム。まだ来ていなければ有効。
  ///
  /// [until] が null（`premium` が無い）なら、プレミアムでない
  /// （設計 7 節「読み取り時に既定へ倒す」）。
  ///
  /// **ちょうど同時刻は「切れている」として扱う。** サーバーの
  /// `until > now` と同じ向きにそろえる。片方だけ `>=` にすると、
  /// 境界の 1 瞬だけ画面にボタンが出るのに押すと断られる。
  static bool isActive(DateTime? until, {DateTime? now}) {
    if (until == null) return false;
    return until.isAfter(now ?? DateTime.now());
  }

  /// 入力されたクーポンコードを、送る形にそろえる。
  ///
  /// 前後の空白と、貼り付けで紛れ込む改行・タブだけを落とす。
  /// メールや紙から写すと末尾に空白が付き、そのままでは
  /// 正しいコードなのに「見つかりません」と出る。
  ///
  /// **大文字小文字はここで変えない。** 照合はサーバーが `codeHash` で
  /// 行い、その手前で大文字に揃えている
  /// （`functions/src/domain/coupon.ts` の `normalizeCouponCode`）。
  /// **同じ規則を 2 か所に持たない**——片方だけ直したときに、
  /// 正しいコードが通らなくなる。ここは、送る前に必ず要る整形
  /// （見えない空白を落とす）だけを受け持つ。
  static String normalizeCouponCode(String raw) =>
      raw.replaceAll(RegExp(r'\s'), '');
}
