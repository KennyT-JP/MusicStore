/**
 * サーバー側ドメインロジックのテスト（仕様書 4.1 / 4.5 / 7.3）
 *
 * **Dart 側（test/domain/permissions_test.dart, quota_test.dart）と
 * 同じ内容を検証する。** 同じ規則を 2 つの言語で持っているため、
 * 片方だけ直して食い違うことを防ぐ。
 */
import { describe, expect, test } from 'vitest';

import {
  canStepDownAsSiteAdmin,
  canWrite,
  effectiveRole,
  hasAtLeast,
  isAssignableRole,
  isListAdmin,
  isMember,
  parseRole,
  type ListAccess,
} from '../src/domain/roles';
import {
  levelToNotify,
  quotaLevel,
  ratio,
  shouldResetNotice,
  shouldResetWarning,
} from '../src/domain/quota';
import { normalizeListName, parseItemStoragePath } from '../src/domain/paths';

const readOnly: ListAccess = { isSiteAdmin: false, role: 'readOnly' };
const superUser: ListAccess = { isSiteAdmin: false, role: 'superUser' };
const listAdmin: ListAccess = { isSiteAdmin: false, role: 'listAdmin' };
const siteAdmin: ListAccess = { isSiteAdmin: true, role: null };
const outsider: ListAccess = { isSiteAdmin: false, role: null };

describe('役割の階層（4.1）', () => {
  test('上位は下位を包含する', () => {
    expect(hasAtLeast(listAdmin, 'superUser')).toBe(true);
    expect(hasAtLeast(listAdmin, 'readOnly')).toBe(true);
    expect(hasAtLeast(superUser, 'readOnly')).toBe(true);
  });

  test('下位は上位を包含しない', () => {
    expect(hasAtLeast(readOnly, 'superUser')).toBe(false);
    expect(hasAtLeast(superUser, 'listAdmin')).toBe(false);
  });

  test('サイト管理者は全リストでリスト管理者と同等（4.2）', () => {
    expect(effectiveRole(siteAdmin)).toBe('listAdmin');
    expect(isListAdmin(siteAdmin)).toBe(true);
    expect(isMember(siteAdmin)).toBe(true);
  });

  test('未参加者は何も持たない', () => {
    expect(effectiveRole(outsider)).toBeNull();
    expect(isMember(outsider)).toBe(false);
    expect(canWrite(outsider)).toBe(false);
  });

  test('未知の役割文字列は復元しない', () => {
    // 不明な役割を強い権限として扱うと権限昇格になるため。
    expect(parseRole('owner')).toBeNull();
    expect(parseRole('')).toBeNull();
    expect(parseRole(undefined)).toBeNull();
    expect(parseRole('superUser')).toBe('superUser');
  });
});

describe('付与してよい役割（3.3 / 5.2）', () => {
  test('招待・承認で付与できるのは Super User と Read Only のみ', () => {
    expect(isAssignableRole('superUser')).toBe(true);
    expect(isAssignableRole('readOnly')).toBe(true);
  });

  test('リスト管理者やサイト管理者は付与できない', () => {
    expect(isAssignableRole('listAdmin')).toBe(false);
    expect(isAssignableRole('siteAdmin')).toBe(false);
    expect(isAssignableRole(null)).toBe(false);
  });
});

describe('項目の書き込み（4.2）', () => {
  test('Super User 以上は書ける', () => {
    expect(canWrite(superUser)).toBe(true);
    expect(canWrite(listAdmin)).toBe(true);
    expect(canWrite(siteAdmin)).toBe(true);
  });

  test('Read Only は書けない', () => {
    expect(canWrite(readOnly)).toBe(false);
  });
});

describe('サイト管理者が 0 人になることの防止（4.5）', () => {
  test('最後の 1 人は降格・退会できない', () => {
    expect(canStepDownAsSiteAdmin(true, 1)).toBe(false);
  });

  test('2 人以上いれば降格・退会できる', () => {
    expect(canStepDownAsSiteAdmin(true, 2)).toBe(true);
  });

  test('サイト管理者でない人は制限を受けない', () => {
    expect(canStepDownAsSiteAdmin(false, 1)).toBe(true);
  });
});

describe('容量の通知境界（7.3）', () => {
  const status = (used: number, quota = 1000) => ({
    usedBytes: used,
    quotaBytes: quota,
  });

  test('80% ちょうどはまだ Notice ではない', () => {
    expect(quotaLevel(status(800))).toBe('normal');
  });

  test('80% を超えたら Notice', () => {
    expect(quotaLevel(status(801))).toBe('notice');
    expect(quotaLevel(status(899))).toBe('notice');
  });

  test('90% ちょうどはまだ警告ではない', () => {
    expect(quotaLevel(status(900))).toBe('notice');
  });

  test('90% を超えたら警告', () => {
    expect(quotaLevel(status(901))).toBe('warning');
    expect(quotaLevel(status(1000))).toBe('warning');
  });

  test('上限が 0 のリストは満杯として扱う', () => {
    expect(ratio(status(0, 0))).toBe(1);
    expect(quotaLevel(status(0, 0))).toBe('warning');
  });

  test('送信済みなら再送しない', () => {
    expect(levelToNotify(status(850), false, false)).toBe('notice');
    expect(levelToNotify(status(850), true, false)).toBeNull();
  });

  test('Notice 送信済みでも 90% を超えたら警告を送る', () => {
    expect(levelToNotify(status(950), true, false)).toBe('warning');
    expect(levelToNotify(status(950), true, true)).toBeNull();
  });

  test('しきい値を下回ったらフラグを戻す', () => {
    expect(shouldResetNotice(status(800), true)).toBe(true);
    expect(shouldResetNotice(status(850), true)).toBe(false);
    expect(shouldResetWarning(status(900), true)).toBe(true);
    expect(shouldResetNotice(status(100), false)).toBe(false);
  });
});

describe('Storage パスの解析（13.7）', () => {
  test('項目のファイルを解析できる', () => {
    expect(parseItemStoragePath('lists/L1/items/I1/take01.mp3')).toEqual({
      listId: 'L1',
      itemId: 'I1',
      fileName: 'take01.mp3',
    });
  });

  test('ファイル名にスラッシュがあっても壊れない', () => {
    expect(parseItemStoragePath('lists/L1/items/I1/a/b.mp3')?.fileName).toBe(
      'a/b.mp3'
    );
  });

  test('形が違うパスには反応しない', () => {
    // 無関係なファイルで容量集計が動かないようにする。
    expect(parseItemStoragePath('other/L1/items/I1/x.mp3')).toBeNull();
    expect(parseItemStoragePath('lists/L1/x/I1/y.mp3')).toBeNull();
    expect(parseItemStoragePath('lists/L1/items/I1/')).toBeNull();
    expect(parseItemStoragePath('lists/L1/items')).toBeNull();
    expect(parseItemStoragePath('')).toBeNull();
  });
});

describe('リスト名の正規化（5.1）', () => {
  test('前後の空白と大文字小文字を吸収する', () => {
    expect(normalizeListName('  Practice  ')).toBe('practice');
    expect(normalizeListName('PRACTICE')).toBe('practice');
  });

  test('Dart 側の normalizeListName と同じ結果になること', () => {
    // lib/data/firestore_paths.dart の normalizeListName と揃える。
    expect(normalizeListName('練習音源')).toBe('練習音源');
  });
});
