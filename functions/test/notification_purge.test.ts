/**
 * 既読通知の保持判定（監査 第5回・群B）
 *
 * **境界だけを単体で確かめる。** 取り返しのつかない削除なので、
 * 「既読かつ保持日数を超えて古いものだけ消す・未読は残す」という判断を
 * エミュレータ無しで固定する（domain.test.ts の shouldDeleteOrphan と同じ考え方）。
 */
import { describe, expect, it, vi } from 'vitest';

// purge.ts の import 時に Firebase 実体へ触れさせないための差し替え。
// 検証するのは純関数 shouldPurgeNotification だけで、Firestore は要らない。
vi.mock('firebase-admin/firestore', () => ({
  getFirestore: () => {
    throw new Error('この経路に来てはいけない');
  },
  Timestamp: class {},
}));
vi.mock('firebase-admin/storage', () => ({
  getStorage: () => {
    throw new Error('この経路に来てはいけない');
  },
}));
vi.mock('firebase-functions/logger', () => ({
  info: () => undefined,
  warn: () => undefined,
  error: () => undefined,
}));
vi.mock('firebase-functions/v2/scheduler', () => ({
  onSchedule: () => () => undefined,
}));

const { shouldPurgeNotification } = await import('../src/scheduled/purge');

const DAY_MS = 24 * 60 * 60 * 1000;
// 判定は現在時刻との相対だけなので、基準はいつでもよい。
const now = Date.parse('2026-08-17T00:00:00Z');
const daysAgo = (days: number) => now - days * DAY_MS;

describe('shouldPurgeNotification（保持 90 日）', () => {
  it('既読で 91 日前なら消す', () => {
    expect(shouldPurgeNotification(true, daysAgo(91), now, 90)).toBe(true);
  });

  it('既読でも 90 日ちょうどは残す（「超えたら」なので）', () => {
    expect(shouldPurgeNotification(true, daysAgo(90), now, 90)).toBe(false);
  });

  it('既読でも 89 日前は残す', () => {
    expect(shouldPurgeNotification(true, daysAgo(89), now, 90)).toBe(false);
  });

  it('未読は 91 日前でも残す', () => {
    expect(shouldPurgeNotification(false, daysAgo(91), now, 90)).toBe(false);
  });

  it('未読はどれだけ古くても残す', () => {
    expect(shouldPurgeNotification(false, daysAgo(1000), now, 90)).toBe(false);
  });

  it('createdAt が数値でないものは判断できないので残す', () => {
    expect(shouldPurgeNotification(true, Number.NaN, now, 90)).toBe(false);
  });
});

describe('shouldPurgeNotification（保持日数は設定値）', () => {
  it('保持 30 日なら 31 日前の既読を消す', () => {
    expect(shouldPurgeNotification(true, daysAgo(31), now, 30)).toBe(true);
  });

  it('保持 30 日なら 29 日前の既読は残す', () => {
    expect(shouldPurgeNotification(true, daysAgo(29), now, 30)).toBe(false);
  });
});
