/**
 * プレミアムの期限の判定（docs/PREMIUM-DESIGN.md 3.1 / 6-1）
 *
 * **状態は `until` だけで表す。** 「プレミアムかどうか」の真偽値を別に持つと、
 * 期限が切れた瞬間に 2 つが食い違う（AUDIT-CHECKLIST「同じ規則を 2 か所に
 * 持つな」）。`users/{uid}.premium` が無い人は「プレミアムでない」と読む。
 *
 * Firebase に依存しない純粋な関数だけを置く（domain/paths.ts と同じ方針）。
 * 通信なしでテストできるようにするため。
 */

/**
 * その時刻でプレミアムが有効か。
 *
 * **ちょうど期限の瞬間は含まない。** 容量のしきい値（domain/quota.ts）が
 * 「80% を超えたら」と決めているのと同じ流儀に揃えている。境界の扱いが
 * ファイルごとに違うと、どちらが正しいかを読む側が毎回調べ直すことになる。
 *
 * 数値でない値・NaN は「持っていない」として扱う。読み取り時に既定へ倒す
 * （`isWithdrawn` と同じ扱い方／PREMIUM-DESIGN 7）。
 */
export function isPremiumActive(
  untilMs: number | null | undefined,
  nowMs: number
): boolean {
  if (typeof untilMs !== 'number' || !Number.isFinite(untilMs)) return false;
  return untilMs > nowMs;
}

/**
 * 月数を足したあとの期限（D2 / D4）。
 *
 * **2 枚目のクーポンは上書きではなく延長する。** いまの期限が未来なら
 * そこから、過ぎていれば今から数える。上書きにすると、期限を延ばすつもりで
 * 入れた 2 枚目が**残っている期間を捨てる**ことになる。
 *
 * 月数は負でもよい（管理画面から縮める／`extendPremium`）。
 *
 * **日付は UTC で計算する。** サーバーの時間帯に依らず同じ結果にするため。
 * 月末は繰り上がらないように丸める（1/31 に 1 か月足すと 2/28 or 2/29）。
 * 繰り上げると「1 か月足したのに翌々月になる」ことが起きる。
 */
export function extendedPremiumUntil(params: {
  /** いまの期限。持っていなければ null。 */
  currentUntilMs: number | null | undefined;
  months: number;
  nowMs: number;
}): number {
  const { currentUntilMs, months, nowMs } = params;
  const base = isPremiumActive(currentUntilMs, nowMs)
    ? (currentUntilMs as number)
    : nowMs;
  return addMonths(base, months);
}

function addMonths(fromMs: number, months: number): number {
  const from = new Date(fromMs);
  const day = from.getUTCDate();

  // 1 日に固定してから月を動かす。31 日のまま動かすと、日数の足りない月へ
  // 繰り上がってしまう（Date の仕様）。
  const moved = new Date(
    Date.UTC(
      from.getUTCFullYear(),
      from.getUTCMonth() + months,
      1,
      from.getUTCHours(),
      from.getUTCMinutes(),
      from.getUTCSeconds(),
      from.getUTCMilliseconds()
    )
  );

  // 移動先の月の末日。0 日は「前の月の末日」を意味する。
  const lastDay = new Date(
    Date.UTC(moved.getUTCFullYear(), moved.getUTCMonth() + 1, 0)
  ).getUTCDate();

  moved.setUTCDate(Math.min(day, lastDay));
  return moved.getTime();
}
