/**
 * 引き換え失敗のレート制限の判定（監査 第5回・群B・S1）
 *
 * **時刻窓とカウントの純粋な判定だけを見る。** 保存（Firestore）や
 * トランザクションは callable/coupons.ts の責務。ここでは
 * isCouponRateLimited（ロック中か）と nextCouponFailureState
 * （1 回数えたあとの状態）の境界を確かめる。エミュレータは要らない。
 */
import { describe, expect, test } from 'vitest';

import {
  type CouponAttemptState,
  isCouponRateLimited,
  nextCouponFailureState,
} from '../src/domain/coupon';

const WINDOW = 60 * 60 * 1000; // 1 時間
const MAX = 10;
const NOW = 1_000_000_000_000;

function limited(state: CouponAttemptState, nowMs = NOW): boolean {
  return isCouponRateLimited(state, { nowMs, maxFailures: MAX, windowMs: WINDOW });
}

describe('isCouponRateLimited', () => {
  test('記録が無ければロックしない', () => {
    expect(limited({ windowStartMs: null, failCount: 0 })).toBe(false);
  });

  test('閾値未満はロックしない', () => {
    expect(limited({ windowStartMs: NOW, failCount: MAX - 1 })).toBe(false);
  });

  test('窓の中で閾値に達したらロックする', () => {
    expect(limited({ windowStartMs: NOW, failCount: MAX })).toBe(true);
  });

  test('閾値を超えてもロックのまま', () => {
    expect(limited({ windowStartMs: NOW, failCount: MAX + 5 })).toBe(true);
  });

  test('窓を過ぎていればロックしない（自然回復）', () => {
    // 開始から窓ちょうど＝もう窓の外。
    expect(
      limited({ windowStartMs: NOW - WINDOW, failCount: MAX + 100 })
    ).toBe(false);
  });

  test('窓の内側（境界の 1 ミリ秒手前）ではまだロック', () => {
    expect(
      limited({ windowStartMs: NOW - WINDOW + 1, failCount: MAX })
    ).toBe(true);
  });
});

describe('nextCouponFailureState', () => {
  test('記録が無ければ窓を今から始めて 1 から数える', () => {
    expect(
      nextCouponFailureState(
        { windowStartMs: null, failCount: 0 },
        { nowMs: NOW, windowMs: WINDOW }
      )
    ).toEqual({ windowStartMs: NOW, failCount: 1 });
  });

  test('窓の中なら開始時刻を保ったまま足す', () => {
    const start = NOW - 5 * 60 * 1000; // 5 分前
    expect(
      nextCouponFailureState(
        { windowStartMs: start, failCount: 3 },
        { nowMs: NOW, windowMs: WINDOW }
      )
    ).toEqual({ windowStartMs: start, failCount: 4 });
  });

  test('窓が切れていたら数え直す', () => {
    expect(
      nextCouponFailureState(
        { windowStartMs: NOW - WINDOW - 1, failCount: 9 },
        { nowMs: NOW, windowMs: WINDOW }
      )
    ).toEqual({ windowStartMs: NOW, failCount: 1 });
  });

  test('窓ちょうどの経過も「切れた」として数え直す（isCouponRateLimited と同じ境界）', () => {
    expect(
      nextCouponFailureState(
        { windowStartMs: NOW - WINDOW, failCount: 9 },
        { nowMs: NOW, windowMs: WINDOW }
      )
    ).toEqual({ windowStartMs: NOW, failCount: 1 });
  });
});

describe('窓の一巡（10 回失敗 → ロック → 回復）', () => {
  test('連続失敗で閾値に達し、窓を過ぎると解ける', () => {
    let state: CouponAttemptState = { windowStartMs: null, failCount: 0 };
    // 同じ時刻で MAX 回失敗する。
    for (let i = 0; i < MAX; i += 1) {
      state = nextCouponFailureState(state, { nowMs: NOW, windowMs: WINDOW });
    }
    expect(state).toEqual({ windowStartMs: NOW, failCount: MAX });
    expect(limited(state, NOW)).toBe(true);

    // 窓を過ぎればロックは解ける。
    expect(limited(state, NOW + WINDOW)).toBe(false);
  });
});
