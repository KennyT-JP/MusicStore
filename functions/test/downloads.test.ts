/**
 * オフライン用ダウンロードの権限判定（docs/DOWNLOAD-DESIGN.md 5.1 / 8.2）
 *
 * **この判定の結果は「端末のファイル削除」である**（10 節の危険 4）。
 * 間違えると、利用者が落とした音源が消える。だから境界と、
 * **「例外にしていないこと」そのもの**を、通信なしで固定する。
 *
 * 境界の流儀は既存に揃えている——**ちょうどの値は含まない**
 * （domain/premium.ts の `isPremiumActive`／domain/quota.ts の
 * 「80% を超えたら」と同じ）。
 *
 * 実際に Firestore と Auth を動かす確認は functions/test/integration.mjs
 * にある（未ログイン・メール未確認の符号、閲覧者、サイト管理者）。
 */
import { readFileSync } from 'node:fs';
import { describe, expect, test } from 'vitest';

import {
  evaluateDownloadAccess,
  parseDownloadListIds,
} from '../src/domain/downloads';

/** 2026-08-16 12:00:00 UTC。読みやすさのために固定する。 */
const NOW = Date.UTC(2026, 7, 16, 12, 0, 0);
const DAY = 86400000;

/** メンバーである人が 1 リストだけ持っている、いちばん普通の形。 */
const member = [{ listId: 'listA', isMember: true }];

const verdict = (
  premiumUntilMs: number | null,
  memberships = member,
  nowMs = NOW,
  isSiteAdmin = false
) => evaluateDownloadAccess({ premiumUntilMs, nowMs, isSiteAdmin, memberships });

describe('ダウンロードの権限（5.1）', () => {
  test('メンバーかつプレミアムなら許可（論点 9・12）', () => {
    expect(verdict(NOW + 30 * DAY)).toEqual({
      premiumActive: true,
      verifiedAt: NOW,
      lists: { listA: 'member' },
    });
  });

  test('Read Only でも許可される（役割の段階を見ていない／論点 9）', () => {
    // 判定が受け取るのは「members が有るか」だけで、役割は入り口にすら
    // 現れない。**readOnly を弾く道が無いこと**を、ここで固定しておく。
    expect(verdict(NOW + 1).lists).toEqual({ listA: 'member' });
  });

  test('メンバーでなければ不許可（閲覧者・脱退・除外／論点 9・13）', () => {
    // 閲覧者は viewers/{uid} にしか居ないので、members は無い。
    expect(verdict(NOW + 30 * DAY, [{ listId: 'listA', isMember: false }]))
      .toEqual({
        premiumActive: true,
        verifiedAt: NOW,
        lists: { listA: 'notMember' },
      });
  });

  test('リストごとに別々に決まる（2.3）', () => {
    // A から抜けても B は残る（論点 13）。片方だけ消せる形になっていること。
    expect(
      verdict(NOW + DAY, [
        { listId: 'listA', isMember: false },
        { listId: 'listB', isMember: true },
      ]).lists
    ).toEqual({ listA: 'notMember', listB: 'member' });
  });

  test('1 曲も持っていない人にも premiumActive を返す', () => {
    expect(verdict(NOW + DAY, [])).toEqual({
      premiumActive: true,
      verifiedAt: NOW,
      lists: {},
    });
  });

  test('verifiedAt は渡された時刻そのもの（サーバーの時刻／4.2）', () => {
    expect(verdict(null, [], 1234567).verifiedAt).toBe(1234567);
  });
});

/**
 * **プレミアム失効は「不許可」であって「失敗」ではない**（5.1 / 危険 4）
 *
 * 例外にすると、圏外・タイムアウト・コールドスタートの失敗と
 * 区別が付かない。**電波の悪い場所で 1 回失敗しただけで全曲が消える。**
 */
describe('プレミアム失効は正常応答で返す（危険 4）', () => {
  test('切れていても throw しない', () => {
    expect(() => verdict(NOW - DAY)).not.toThrow();
  });

  test('切れていたら premiumActive: false が正常に返る（論点 12）', () => {
    expect(verdict(NOW - DAY)).toEqual({
      premiumActive: false,
      verifiedAt: NOW,
      lists: { listA: 'member' },
    });
  });

  test('切れていても、メンバーであることは member のまま返る', () => {
    // **「プレミアムが切れた」と「リストから外れた」は別の答えである。**
    // まとめて notMember にすると、端末は「脱退した」と読んで
    // 復帰したあとの再ダウンロードの案内を出せなくなる。
    expect(verdict(NOW - DAY).lists).toEqual({ listA: 'member' });
  });

  test('premium を持たない人も、例外ではなく false（PREMIUM-DESIGN 7）', () => {
    expect(verdict(null)).toEqual({
      premiumActive: false,
      verifiedAt: NOW,
      lists: { listA: 'member' },
    });
  });
});

/**
 * サイト管理者は実効プレミアム（仕様書 4.1・旧・論点 18 を上書き）
 *
 * 「上位の役割は下位の権限をすべて包含する」に揃え、サイト管理者は
 * プレミアム機能をすべて持つ。`premiumActive` に `isSiteAdmin` を OR する。
 * **ただし混ぜるのは「プレミアムか」だけ**——「メンバーか」は別軸のまま。
 */
describe('サイト管理者は実効プレミアム（仕様書 4.1）', () => {
  test('プレミアムを持たなくても premiumActive: true', () => {
    expect(verdict(null, member, NOW, true).premiumActive).toBe(true);
  });

  test('期限が切れていても premiumActive: true', () => {
    expect(verdict(NOW - DAY, member, NOW, true).premiumActive).toBe(true);
  });

  test('サイト管理者はメンバーでなくても member（全リスト／仕様書 4.2）', () => {
    // サイト管理者は「全リストの項目を扱える」（4.2）ので、members に
    // 居なくても member を返す。クライアントの Permissions.canDownload が
    // `role != null || isSiteAdmin` を許すのと揃う。
    expect(
      verdict(null, [{ listId: 'listA', isMember: false }], NOW, true)
    ).toEqual({
      premiumActive: true,
      verifiedAt: NOW,
      lists: { listA: 'member' },
    });
  });
});

/**
 * 期限の境界（8.2）
 *
 * **`isPremiumActive` を使い回している**（domain/premium.ts）。
 * ここで `until > now` を書き直さない。書き直すと、境界が
 * ファイルごとに違うことになる。
 */
describe('期限の境界（8.2）', () => {
  test('ちょうど期限の瞬間は、もう有効ではない', () => {
    expect(verdict(NOW).premiumActive).toBe(false);
  });

  test('1 ミリ秒でも先なら有効', () => {
    expect(verdict(NOW + 1).premiumActive).toBe(true);
  });

  test('1 秒前・1 秒後', () => {
    expect(verdict(NOW - 1000).premiumActive).toBe(false);
    expect(verdict(NOW + 1000).premiumActive).toBe(true);
  });
});

/**
 * `listIds` の検証（5.1 の表）
 *
 * **ここだけは例外にしてよい。** 呼び出しの形が壊れているのであって、
 * 「権限が無い」という答えではない。
 */
describe('listIds の検証（5.1）', () => {
  const ids = (count: number) =>
    Array.from({ length: count }, (_, i) => `list${i}`);

  test('普通の一覧はそのまま通る', () => {
    expect(parseDownloadListIds(['a', 'b'])).toEqual({ listIds: ['a', 'b'] });
  });

  test('空の一覧も通る（1 曲も持っていない端末）', () => {
    expect(parseDownloadListIds([])).toEqual({ listIds: [] });
  });

  test('50 件ちょうどは通り、51 件は断る（境界／8.2）', () => {
    expect(parseDownloadListIds(ids(50))).toEqual({ listIds: ids(50) });
    expect(parseDownloadListIds(ids(51))).toEqual({ rejection: 'tooManyLists' });
  });

  test('配列でなければ missingField', () => {
    for (const value of [undefined, null, 'listA', 42, { listA: true }]) {
      expect(parseDownloadListIds(value), String(value)).toEqual({
        rejection: 'missingField',
      });
    }
  });

  test('要素が文字列でなければ missingField', () => {
    expect(parseDownloadListIds(['a', 1])).toEqual({ rejection: 'missingField' });
    expect(parseDownloadListIds(['a', null])).toEqual({
      rejection: 'missingField',
    });
  });

  test('ドキュメント ID として不正なものを断る', () => {
    // **`a/items/b` を通すと、lists/{listId}/members/{uid} が別の場所を
    // 指す。** 呼び出し側はその存在だけを返すので、他人のドキュメントが
    // 有るかどうかを 1 件ずつ試せる入口になる。
    for (const bad of ['', 'a/items/b', '.', '..', '__name__', 'x'.repeat(201)]) {
      expect(parseDownloadListIds([bad]), JSON.stringify(bad)).toEqual({
        rejection: 'missingField',
      });
    }
  });

  test('重複は 1 件にまとめる', () => {
    expect(parseDownloadListIds(['a', 'a', 'b'])).toEqual({
      listIds: ['a', 'b'],
    });
  });

  test('重複で水増しした 51 件は通らない（まとめる前に数える）', () => {
    const padded = Array.from({ length: 51 }, () => 'listA');
    expect(parseDownloadListIds(padded)).toEqual({ rejection: 'tooManyLists' });
  });
});

/**
 * 静的な見張り（8.4 と同じ考え方）
 *
 * **上の判定テストだけでは、実装が例外へ戻ったことを検出できない。**
 * `evaluateDownloadAccess` は throw しないままでも、呼び出し可能関数の側で
 * `if (!premiumActive) throw fail(...)` と書き足せてしまう。それをすると
 * 端末は「呼び出しが失敗した」としか読めなくなり、**電波の悪い場所で
 * 1 回失敗しただけで全曲が消える**（10 節の危険 4）。
 *
 * だから本文そのものを読んで見張る。**コメントは落としてから見る**——
 * このリポジトリの注記は禁じ手の名前をそのまま書くため（no_dead_code.test.ts
 * が同じ穴を塞いでいる）。
 */
describe('例外にしていないことの見張り（危険 4・8）', () => {
  /** コメントを除いた本文（no_dead_code.test.ts と同じ落とし方）。 */
  const bodyOf = (relative: string) =>
    readFileSync(new URL(relative, import.meta.url), 'utf8')
      .replace(/\/\*[\s\S]*?\*\//g, '')
      .replace(/\/\/[^\n]*/g, '');

  const callable = bodyOf('../src/callable/downloads.ts');
  const domain = bodyOf('../src/domain/downloads.ts');

  test('見張りが空振りしていない（本文を読めている）', () => {
    // 落とし過ぎ・パスの間違いで中身が空になると、以下がすべて素通りする。
    expect(callable).toContain('verifyDownloadAccess');
    expect(domain).toContain('evaluateDownloadAccess');
  });

  test('premiumRequired を投げていない（危険 4）', () => {
    // ここが赤くなったら、直す前に 5.1「なぜ premiumRequired を投げないか」を
    // 読むこと。プレミアムでないことは**正常な答え**である。
    expect(callable).not.toContain('premiumRequired');
    expect(domain).not.toContain('premiumRequired');
  });

  test('投げる符号は、入力の検証の 2 つだけ', () => {
    // `fail(...)` の第 2 引数を数え上げる。権限や状態を表す符号が
    // 増えていたら、それは正常応答で返すべきものである。
    const codes = [...callable.matchAll(/fail\(\s*'[^']*'\s*,\s*'(\w+)'/g)].map(
      (m) => m[1]
    );
    expect(codes.length, 'fail( を 1 つも読み取れていない').toBeGreaterThan(0);
    expect([...new Set(codes)].sort()).toEqual(['missingField', 'tooManyLists']);
    expect(domain).not.toContain('fail(');
  });

  test('プレミアムの状態で throw する道が無い', () => {
    // `throw` は入力の検証の 1 か所だけ。増えていたら、何を投げるように
    // なったのかを確かめること。
    expect([...callable.matchAll(/\bthrow\b/g)]).toHaveLength(1);
    expect([...domain.matchAll(/\bthrow\b/g)]).toHaveLength(0);
  });

  test('サイト管理者は実効プレミアムとして扱う（仕様書 4.1・旧・論点 18 を上書き）', () => {
    // 「上位の役割は下位の権限をすべて包含する」に揃え、サイト管理者は
    // プレミアム機能をすべて持つ方針へ上書きした（2026-08-22）。
    // 呼び出し側は access.ts の isSiteAdminRequest を使い、ドメインは
    // isSiteAdmin を受け取って premiumActive に OR する。
    expect(callable).toContain('isSiteAdminRequest');
    expect(domain).toContain('isSiteAdmin');

    // **混ぜるのは「プレミアムか」だけ。** 「メンバーか」の判定には
    // 役割の階層を持ち込まない（notMember は notMember のまま）。
    // ここが崩れると、メンバーでないサイト管理者が member 扱いになり、
    // クライアントと食い違って端末のファイルが消える。
    for (const source of [callable, domain]) {
      expect(source).not.toContain('hasAtLeast');
      expect(source).not.toContain('effectiveRole');
    }
  });

  test('期限の判定は isPremiumActive を使い回している（5.1 の表）', () => {
    // `until > now` をここで書き直すと、境界がファイルごとに違うことになる。
    expect(domain).toContain('isPremiumActive');
    expect(callable).not.toContain('isPremiumActive');
  });

  test('役割（role）を読んでいない（論点 9）', () => {
    // members ドキュメントの**存在だけ**で決める。`parseRole` を
    // 持ち込むと、readOnly を弾く道ができてしまう。
    expect(callable).not.toContain('parseRole');
    expect(callable).toContain('.exists');
  });
});
