/**
 * 手動指定クーポンコードの最小強度の検証（監査 第5回・群B・S1）
 *
 * **純関数だけを見る。** 保存やロックは callable/coupons.ts の責務で、
 * ここでは validateManualCouponCode が「8 文字かつ英数字混在」を正しく
 * 判定するかだけを確かめる。エミュレータは要らない。
 */
import { describe, expect, test } from 'vitest';

import {
  MANUAL_CODE_MIN_LENGTH,
  validateManualCouponCode,
} from '../src/domain/coupon';

describe('validateManualCouponCode', () => {
  test('最小長は 8', () => {
    expect(MANUAL_CODE_MIN_LENGTH).toBe(8);
  });

  test('7 文字は短すぎる（英数字混在でも不可）', () => {
    expect(validateManualCouponCode('ABC1234')).toEqual({
      ok: false,
      reason: 'tooShort',
    });
  });

  test('空白を詰めた実長で測る（末尾の空白で 8 文字に見せかけても不可）', () => {
    // 'ABC1234' は正規化後 7 文字。
    expect(validateManualCouponCode('ABC1234   ')).toEqual({
      ok: false,
      reason: 'tooShort',
    });
  });

  test('8 文字でも数字が無ければ不可', () => {
    expect(validateManualCouponCode('ABCDEFGH')).toEqual({
      ok: false,
      reason: 'needsLetterAndDigit',
    });
  });

  test('8 文字でも英字が無ければ不可', () => {
    expect(validateManualCouponCode('12345678')).toEqual({
      ok: false,
      reason: 'needsLetterAndDigit',
    });
  });

  test('長さが足りないほうを先に返す（数字も英字も無い短い列）', () => {
    // 記号だけ・短い → まず長さで弾く。
    expect(validateManualCouponCode('----')).toEqual({
      ok: false,
      reason: 'tooShort',
    });
  });

  test('8 文字の英数字混在は通る', () => {
    expect(validateManualCouponCode('ABCD1234')).toEqual({ ok: true });
  });

  test('英字 7・数字 1 の 8 文字は通る（各 1 文字で足りる）', () => {
    expect(validateManualCouponCode('ABCDEFG1')).toEqual({ ok: true });
  });

  test('小文字は正規化されて通る（normalizeCouponCode と整合）', () => {
    expect(validateManualCouponCode('abcd1234')).toEqual({ ok: true });
  });

  test('前後の空白は詰めてから判定する', () => {
    expect(validateManualCouponCode('  ABCD1234  ')).toEqual({ ok: true });
  });

  test('長い英数字混在も通る', () => {
    expect(validateManualCouponCode('PREMIUM2026GIFT')).toEqual({ ok: true });
  });
});
