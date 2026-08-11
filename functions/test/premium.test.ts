/**
 * プレミアムと人ごとの容量（docs/PREMIUM-DESIGN.md 2 / 3 / 6）
 *
 * **境界だけを、通信なしで固定する。** 課金が絡む判定は、間違えると
 * 利用者のお金に直結する（PREMIUM-DESIGN の冒頭）。実際に Firestore を
 * 動かす確認は functions/test/integration.mjs にあり、ここでは
 * 「どちら側に倒すか」を 1 件ずつ書き出す。
 *
 * 境界の流儀は既存に揃えている——**ちょうどの値は含まない**
 * （domain/quota.ts の「80% を超えたら」と同じ）。
 */
import { describe, expect, test } from 'vitest';

import { extendedPremiumUntil, isPremiumActive } from '../src/domain/premium';
import {
  USER_DEFAULT_QUOTA_BYTES,
  quotaLevel,
  resolveUserQuota,
} from '../src/domain/quota';
import {
  evaluateCouponRedemption,
  generateCouponCode,
  hashCouponCode,
  normalizeCouponCode,
} from '../src/domain/coupon';

/** 2026-08-11 12:00:00 UTC。読みやすさのために固定する。 */
const NOW = Date.UTC(2026, 7, 11, 12, 0, 0);
const GB = 1073741824;

describe('プレミアムの期限（3.1）', () => {
  test('期限ちょうどは、もう有効ではない', () => {
    expect(isPremiumActive(NOW, NOW)).toBe(false);
  });

  test('1 ミリ秒でも先なら有効', () => {
    expect(isPremiumActive(NOW + 1, NOW)).toBe(true);
  });

  test('1 秒前・1 秒後', () => {
    expect(isPremiumActive(NOW - 1000, NOW)).toBe(false);
    expect(isPremiumActive(NOW + 1000, NOW)).toBe(true);
  });

  test('premium を持たない人はプレミアムでない（7）', () => {
    // users/{uid}.premium が無い人は「持っていない」と読む。
    expect(isPremiumActive(undefined, NOW)).toBe(false);
    expect(isPremiumActive(null, NOW)).toBe(false);
    expect(isPremiumActive(Number.NaN, NOW)).toBe(false);
  });
});

describe('期限の延長（D4）', () => {
  test('持っていない人は今から数える', () => {
    expect(extendedPremiumUntil({ currentUntilMs: null, months: 1, nowMs: NOW }))
      .toBe(Date.UTC(2026, 8, 11, 12, 0, 0));
  });

  test('2 枚目は上書きではなく足す', () => {
    const first = extendedPremiumUntil({
      currentUntilMs: null,
      months: 1,
      nowMs: NOW,
    });
    const second = extendedPremiumUntil({
      currentUntilMs: first,
      months: 2,
      nowMs: NOW,
    });
    // 1 か月 + 2 か月 = 3 か月先。2 枚目の 2 か月で上書きされない。
    expect(second).toBe(Date.UTC(2026, 10, 11, 12, 0, 0));
  });

  test('期限が過ぎている人は、今から数え直す（残りは戻らない）', () => {
    const expired = Date.UTC(2026, 0, 1);
    expect(
      extendedPremiumUntil({ currentUntilMs: expired, months: 1, nowMs: NOW })
    ).toBe(Date.UTC(2026, 8, 11, 12, 0, 0));
  });

  test('負の月数で縮む（管理画面から戻す）', () => {
    const until = Date.UTC(2026, 10, 11, 12, 0, 0);
    expect(
      extendedPremiumUntil({ currentUntilMs: until, months: -2, nowMs: NOW })
    ).toBe(Date.UTC(2026, 8, 11, 12, 0, 0));
  });

  test('月末は繰り上がらない（1/31 + 1 か月は 2 月末）', () => {
    const jan31 = Date.UTC(2026, 0, 31, 9, 0, 0);
    expect(
      extendedPremiumUntil({
        currentUntilMs: jan31,
        months: 1,
        nowMs: Date.UTC(2026, 0, 1),
      })
    ).toBe(Date.UTC(2026, 1, 28, 9, 0, 0));
  });
});

/**
 * 人ごとの上限（「容量の数字」）
 *
 * **上限は 2 つの値でできている。** 土台（サイト管理者が決める。既定 2GB）と、
 * 実効値（自動拡張が上げる）。プレミアムだけが 90% を超えたときに 2GB ずつ
 * 増え、実効値 10GB で止まる。**しきい値は quotaLevel が持っている**ので、
 * ここでも 0.9 を書き直さない（監査 S15 の再発防止）。
 */
describe('人ごとの上限と自動拡張（容量の数字）', () => {
  const premium = (
    usedBytes: number,
    quotaBytes = 2 * GB,
    quotaBytesBase = 2 * GB
  ) =>
    resolveUserQuota({
      usedBytes,
      quotaBytes,
      quotaBytesBase,
      premiumActive: true,
    });
  const free = (
    usedBytes: number,
    quotaBytes = 2 * GB,
    quotaBytesBase = 2 * GB
  ) =>
    resolveUserQuota({
      usedBytes,
      quotaBytes,
      quotaBytesBase,
      premiumActive: false,
    });

  test('土台の既定は 2GB', () => {
    expect(USER_DEFAULT_QUOTA_BYTES).toBe(2147483648);
  });

  test('90% ちょうどでは拡張しない', () => {
    expect(premium(2 * GB * 0.9)).toBe(2 * GB);
    // 前提の確認：この使用量は quotaLevel でも warning ではない。
    expect(quotaLevel({ usedBytes: 2 * GB * 0.9, quotaBytes: 2 * GB })).toBe(
      'notice'
    );
  });

  test('90% を超えたら 2GB 足す', () => {
    expect(premium(2 * GB * 0.9 + 1)).toBe(4 * GB);
  });

  test('90% の直前では増えない', () => {
    expect(premium(2 * GB * 0.9 - 1)).toBe(2 * GB);
  });

  test('一度に何段でも上がる（2→4→6→8→10）', () => {
    // 4GB 使っている人は、2GB から一気に上がりきる。
    // 4GB は 4GB の 100%、6GB の 66%。→ 6GB で止まる。
    expect(premium(4 * GB)).toBe(6 * GB);
    expect(premium(8.5 * GB)).toBe(10 * GB);
  });

  test('10GB で止まる（それ以上は増えない）', () => {
    expect(premium(9.9 * GB, 10 * GB)).toBe(10 * GB);
    expect(premium(20 * GB, 10 * GB)).toBe(10 * GB);
  });

  test('プレミアムでない人は拡張されない', () => {
    expect(free(2 * GB * 0.9 + 1)).toBe(2 * GB);
    expect(free(10 * GB)).toBe(2 * GB);
  });

  test('切れたら土台に戻る（既存のファイルは消さない／D3）', () => {
    // 10GB まで拡張して 6GB 使っている人の期限が切れた場合。
    // 上限だけが土台へ戻り、使用量（6GB）はそのまま残る。
    expect(free(6 * GB, 10 * GB)).toBe(2 * GB);
  });

  test('切れた人でも、下げてある土台は上げ直さない', () => {
    // サイト管理者が事情があって下げた上限を、期限切れの処理で
    // 2GB へ「戻して」しまわないこと。
    expect(free(0, GB, GB)).toBe(GB);
  });

  test('上限が 0 でも、プレミアムなら土台まで持ち上がる', () => {
    // 実効値は土台を下回らない。
    expect(premium(0, 0)).toBe(2 * GB);
  });
});

/**
 * 移行の手当てが消えないこと（「既存の利用者への影響」）
 *
 * **回帰テスト。** 期限切れの戻し先を「既定の 2GB」と決め打ちにすると、
 * リストを 3 つ以上持つ無償の方へサイト管理から足した上限が、
 * **次にファイルが増減した瞬間に黙って消える。** 戻す先は土台にする。
 */
describe('土台（quotaBytesBase）と実効値（quotaBytes）', () => {
  const resolve = (
    usedBytes: number,
    quotaBytes: number,
    quotaBytesBase: number,
    premiumActive: boolean
  ) =>
    resolveUserQuota({ usedBytes, quotaBytes, quotaBytesBase, premiumActive });

  test('無償の人に土台 5GB を与えたら、増減しても 5GB のまま', () => {
    for (const used of [0, GB, 4.9 * GB, 5 * GB, 6 * GB]) {
      expect(resolve(used, 5 * GB, 5 * GB, false), `used=${used}`).toBe(5 * GB);
    }
  });

  test('土台を上げたら、その場で効く（実効値は土台を下回らない）', () => {
    // 実効値 2GB のまま土台だけ 5GB になった直後。
    expect(resolve(0, 2 * GB, 5 * GB, false)).toBe(5 * GB);
    expect(resolve(0, 2 * GB, 5 * GB, true)).toBe(5 * GB);
  });

  test('プレミアムで土台 5GB なら 5→7→9→10 で止まる', () => {
    // 5GB の 90% を超えたところ。
    expect(resolve(4.6 * GB, 5 * GB, 5 * GB, true)).toBe(7 * GB);
    // 7GB の 90% を超えたところ。
    expect(resolve(6.4 * GB, 7 * GB, 5 * GB, true)).toBe(9 * GB);
    // 9GB の 90% を超えたところ。**11GB にはならず 10GB で止まる。**
    expect(resolve(8.2 * GB, 9 * GB, 5 * GB, true)).toBe(10 * GB);
    // すでに 10GB。これ以上は増えない（アップロードが止まる）。
    expect(resolve(9.9 * GB, 10 * GB, 5 * GB, true)).toBe(10 * GB);
  });

  test('一段ずつでなく、一気に上がっても 10GB を超えない', () => {
    expect(resolve(9.5 * GB, 5 * GB, 5 * GB, true)).toBe(10 * GB);
  });

  test('切れたら土台の 5GB に戻る（2GB ではない）', () => {
    // 10GB まで拡張していた人の期限が切れても、手当ての 5GB は残る。
    expect(resolve(6 * GB, 10 * GB, 5 * GB, false)).toBe(5 * GB);
  });

  test('土台が 10GB を超えていても、その値が上限になる', () => {
    // 10GB はあくまで**自動拡張が届く先**。サイト管理者が決めた土台は
    // 縛らない（縛ると、決めた値が黙って下がる）。
    expect(resolve(0, 12 * GB, 12 * GB, true)).toBe(12 * GB);
    expect(resolve(11 * GB, 12 * GB, 12 * GB, false)).toBe(12 * GB);
  });
});

describe('クーポンのコード（D8）', () => {
  test('自動生成は 24 文字', () => {
    expect(generateCouponCode()).toHaveLength(24);
  });

  test('読み違えやすい文字を使わない', () => {
    for (let i = 0; i < 50; i += 1) {
      expect(generateCouponCode()).toMatch(/^[A-HJ-NP-Z2-9]{24}$/);
    }
  });

  test('毎回違う', () => {
    const codes = new Set(
      Array.from({ length: 50 }, () => generateCouponCode())
    );
    expect(codes.size).toBe(50);
  });

  test('大文字小文字と前後の空白を吸収する', () => {
    expect(normalizeCouponCode('  abcd-1  ')).toBe('ABCD-1');
    expect(hashCouponCode(' spring2026 ')).toBe(hashCouponCode('SPRING2026'));
  });

  test('違うコードは違うハッシュになる', () => {
    expect(hashCouponCode('AAAA')).not.toBe(hashCouponCode('AAAB'));
  });
});

/**
 * 引き換えの可否（9-1）
 *
 * **二重取りの防止そのものはトランザクションの仕事**（callable/coupons.ts）。
 * ここで固定するのは、その中で使う 4 つの条件の境界。
 */
describe('クーポンの引き換え可否（3.2）', () => {
  const usable = {
    disabled: false,
    expiresAtMs: null,
    usedCount: 0,
    maxUses: 1,
  };
  const verdict = (
    coupon: typeof usable | null,
    alreadyRedeemed = false,
    nowMs = NOW
  ) => evaluateCouponRedemption({ coupon, alreadyRedeemed, nowMs });

  test('使える', () => {
    expect(verdict(usable)).toEqual({ ok: true });
  });

  test('見つからない', () => {
    expect(verdict(null)).toEqual({ rejection: 'couponNotFound' });
  });

  test('停止されている', () => {
    expect(verdict({ ...usable, disabled: true })).toEqual({
      rejection: 'couponDisabled',
    });
  });

  test('期限ちょうどは、もう使えない', () => {
    expect(verdict({ ...usable, expiresAtMs: NOW })).toEqual({
      rejection: 'couponExpired',
    });
    expect(verdict({ ...usable, expiresAtMs: NOW + 1 })).toEqual({ ok: true });
    expect(verdict({ ...usable, expiresAtMs: NOW - 1 })).toEqual({
      rejection: 'couponExpired',
    });
  });

  test('人数の上限に達している', () => {
    expect(verdict({ ...usable, usedCount: 1, maxUses: 1 })).toEqual({
      rejection: 'couponUsedUp',
    });
    expect(verdict({ ...usable, usedCount: 1, maxUses: 2 })).toEqual({
      ok: true,
    });
  });

  test('同じ人は二度使えない（二重取りの防止）', () => {
    expect(verdict(usable, true)).toEqual({ rejection: 'couponAlreadyUsed' });
  });

  test('上限を使用済みより下げても、すでに使った人は「使用済み」と答える', () => {
    // D1 の補足。**それ以上使えなくなるだけ**で、使った人の記録には
    // 触らない。ここで couponUsedUp を返すと、画面には「他の人で
    // 埋まりました」と出て、自分が使った事実が伝わらない。
    expect(verdict({ ...usable, usedCount: 5, maxUses: 1 }, true)).toEqual({
      rejection: 'couponAlreadyUsed',
    });
  });
});
