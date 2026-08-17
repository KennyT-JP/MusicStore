/**
 * クーポンのコードと引き換え可否（docs/PREMIUM-DESIGN.md 3.2 / D8）
 *
 * Firebase に依存しない純粋な関数だけを置く（domain/paths.ts と同じ方針）。
 * **二重取りの防止そのものはここではできない**——「使用記録が無いこと」と
 * 「上限に達していないこと」を同時に確かめるのはトランザクションの仕事
 * （callable/coupons.ts）。ここが受け持つのは、その中で使う判断の中身だけ。
 */
import { createHash, randomBytes } from 'node:crypto';

/**
 * 自動生成に使う文字（D8）。
 *
 * **読み違えやすい文字を入れない。** `0/O`・`1/l/I` は、口頭や紙で
 * 渡したときに必ず取り違えられる。小文字も使わない（正規化で大文字へ
 * 揃えるため、混ぜても意味が無い）。
 */
const CODE_ALPHABET = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

/** 自動生成するコードの長さ（D8）。推測できない長さにする。 */
const CODE_LENGTH = 24;

/**
 * 引き換えコードを自動生成する（D8）。
 *
 * **`Math.random` を使わない。** 当たれば誰でもプレミアムになれる値なので、
 * 予測できない乱数（`node:crypto`）から作る。
 */
export function generateCouponCode(): string {
  // **剰余で丸めない。** 256 は文字数（31）で割り切れないため、
  // `byte % 31` にすると先頭の数文字だけ出やすくなる。5 ビットを取り出し、
  // 文字数からはみ出た値は捨てて引き直す（偏りを作らない）。
  const chars: string[] = [];
  while (chars.length < CODE_LENGTH) {
    for (const byte of randomBytes(CODE_LENGTH)) {
      const index = byte % 32;
      const char = CODE_ALPHABET[index];
      if (char === undefined) continue;
      chars.push(char);
      if (chars.length === CODE_LENGTH) break;
    }
  }
  return chars.join('');
}

/**
 * 入力されたコードを、照合できる形に揃える。
 *
 * **前後の空白と大文字小文字を吸収する**（リスト名の正規化と同じ考え方）。
 * 紙やメールで渡したコードは、小文字で打ち込まれたり、コピーで空白が
 * 付いたりする。そこで弾くと、正しいコードを持っている人が入れられない。
 */
export function normalizeCouponCode(code: string): string {
  return code.trim().toUpperCase();
}

/**
 * 照合用のハッシュ（3.2）。
 *
 * **探すときはこちらを使う。** コードそのもので引くと、クエリの条件に
 * 平文が載る。ログや索引に平文が残らないようにするための一手間。
 */
export function hashCouponCode(code: string): string {
  return createHash('sha256').update(normalizeCouponCode(code)).digest('hex');
}

/**
 * 手動指定コードの最小の長さ（監査 第5回・群B・S1）。
 *
 * **自動生成コード（24 文字）はこの制約の対象外。** 総当たりで当てられる
 * リスクがあるのは、管理者が短く付けた手動指定コードだけ。ここを 8 文字
 * かつ英数字混在に縛って、当てにくい最小の強度を担保する。
 */
export const MANUAL_CODE_MIN_LENGTH = 8;

/** 手動指定コードが弱いときの理由。 */
export type ManualCodeRejection = 'tooShort' | 'needsLetterAndDigit';

/**
 * 管理者が指定したクーポンコードが、最小の強度を満たすか（S1）。
 *
 * **`normalizeCouponCode` と同じ正規化を通してから測る。** 前後の空白を
 * 詰めたあとの「実際に照合される文字列」で長さと文字種を見ないと、
 * 末尾の空白で 8 文字に見せかけたコードを通してしまう。呼び出し側も
 * すでに正規化しているので、ここで重ねて掛けても結果は変わらない。
 *
 * 条件は 2 つ:
 *   - 最小 [MANUAL_CODE_MIN_LENGTH] 文字
 *   - 英字と数字の両方を含む
 */
export function validateManualCouponCode(
  code: string
): { ok: true } | { ok: false; reason: ManualCodeRejection } {
  const normalized = normalizeCouponCode(code);
  if (normalized.length < MANUAL_CODE_MIN_LENGTH) {
    return { ok: false, reason: 'tooShort' };
  }
  const hasLetter = /[A-Za-z]/.test(normalized);
  const hasDigit = /[0-9]/.test(normalized);
  if (!hasLetter || !hasDigit) {
    return { ok: false, reason: 'needsLetterAndDigit' };
  }
  return { ok: true };
}

/**
 * 引き換えの失敗回数（総当たり対策の窓／S1）。
 *
 * **判断だけをここに置く。** 実際の保存・ロックは callable/coupons.ts の
 * 責務だが、「窓が過ぎたか」「閾値に達したか」という境界の判定は純関数に
 * 切り出して単体テストする（evaluateCouponRedemption と同じ方針）。
 */
export interface CouponAttemptState {
  /** いま数えている時間窓の開始時刻（ミリ秒）。記録が無ければ null。 */
  windowStartMs: number | null;
  /** その窓の中で数えた失敗の回数。 */
  failCount: number;
}

/**
 * いま一時ロック中か（S1）。
 *
 * **窓が過ぎていれば数えない。** 失敗の記録は消さずに残すが、窓の外に
 * なった時点で「無かったもの」として扱う。これで概ね [windowMs] で
 * 自然に回復する（別途の後片付けが要らない）。
 */
export function isCouponRateLimited(
  state: CouponAttemptState,
  params: { nowMs: number; maxFailures: number; windowMs: number }
): boolean {
  const { nowMs, maxFailures, windowMs } = params;
  if (state.windowStartMs === null) return false;
  if (nowMs - state.windowStartMs >= windowMs) return false;
  return state.failCount >= maxFailures;
}

/**
 * 失敗を 1 つ数えたあとの状態（S1）。
 *
 * **窓が切れていたら数え直す。** 昔の失敗をいつまでも引きずらないため、
 * 窓の外なら開始時刻を今に置き換えて 1 から数える。窓の中なら足すだけ。
 */
export function nextCouponFailureState(
  state: CouponAttemptState,
  params: { nowMs: number; windowMs: number }
): CouponAttemptState {
  const { nowMs, windowMs } = params;
  if (state.windowStartMs === null || nowMs - state.windowStartMs >= windowMs) {
    return { windowStartMs: nowMs, failCount: 1 };
  }
  return { windowStartMs: state.windowStartMs, failCount: state.failCount + 1 };
}

/** 引き換えを断る理由。errors.ts の符号と同じ名前にしてある。 */
export type CouponRejection =
  | 'couponNotFound'
  | 'couponDisabled'
  | 'couponExpired'
  | 'couponUsedUp'
  | 'couponAlreadyUsed';

export interface CouponState {
  disabled: boolean;
  /** クーポン自体の有効期限。無期限なら null。 */
  expiresAtMs: number | null;
  usedCount: number;
  maxUses: number;
}

/**
 * このクーポンを、この人が今 使えるか（9-1）。
 *
 * **判断だけをここに置く。** 実際に断るか通すかはトランザクションの中で
 * 決まるが、条件が 4 つあるので、境界の確認をここに集めて単体テストする。
 *
 * - 期限は**ちょうどの瞬間を含まない**（isPremiumActive と同じ流儀）
 * - 上限は `usedCount < maxUses` で見る。**上限を使用済みより下げても、
 *   すでに使った人の記録には触らない**（D1 の補足）
 */
export function evaluateCouponRedemption(params: {
  /** 見つからなければ null。 */
  coupon: CouponState | null;
  /** この人の使用記録がすでにあるか。 */
  alreadyRedeemed: boolean;
  nowMs: number;
}): { rejection: CouponRejection } | { ok: true } {
  const { coupon, alreadyRedeemed, nowMs } = params;

  if (!coupon) return { rejection: 'couponNotFound' };
  if (coupon.disabled) return { rejection: 'couponDisabled' };
  if (coupon.expiresAtMs !== null && coupon.expiresAtMs <= nowMs) {
    return { rejection: 'couponExpired' };
  }

  // **「もう使った」を「上限に達した」より先に返す。** 逆にすると、
  // 自分が使ったクーポンなのに「他の人で埋まりました」と読める文が出る。
  if (alreadyRedeemed) return { rejection: 'couponAlreadyUsed' };
  if (!(coupon.usedCount < coupon.maxUses)) {
    return { rejection: 'couponUsedUp' };
  }

  return { ok: true };
}
