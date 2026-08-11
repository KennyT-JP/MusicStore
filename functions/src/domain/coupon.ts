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
