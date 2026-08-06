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
  shouldRejectUpload,
  shouldResetNotice,
  shouldResetWarning,
} from '../src/domain/quota';
import {
  isPathOwnedByItem,
  normalizeListName,
  parseItemStoragePath,
  shouldDeleteOrphan,
} from '../src/domain/paths';
import { ERROR_CODES, fail } from '../src/errors';
import { evaluateInvite } from '../src/domain/invite';

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

  /// **回帰テスト（監査 第2回）。**
  ///
  /// 「Dart 側と同じ結果になること」というテストが、
  /// **スラッシュを含まない入力しか渡していなかった**。両者が一致する
  /// 唯一の領域だけを確かめており、食い違いをそのまま隠していた。
  /// Dart 側はスラッシュを置き換えておらず、`a/b` という名前で
  /// ドキュメント参照が壊れる状態だった。
  ///
  /// 揃っていることを確かめるテストは、**揃っていない可能性がある入力**を
  /// 通さなければ意味がない。
  test('Dart 側の normalizeListName と同じ結果になること', () => {
    // lib/data/firestore_paths.dart の normalizeListName と揃える。
    // 変えるときは必ず両方を直し、test/domain/list_name_test.dart も見ること。
    const cases: [string, string][] = [
      ['練習音源', '練習音源'],
      ['  Practice  ', 'practice'],
      ['PRACTICE', 'practice'],
      // ここが抜けていた。スラッシュはパスの区切りになるため潰す。
      ['a/b', 'a_b'],
      ['A/B/C', 'a_b_c'],
      ['  Foo / Bar  ', 'foo _ bar'],
      ['/leading', '_leading'],
      ['trailing/', 'trailing_'],
    ];
    for (const [input, expected] of cases) {
      expect(normalizeListName(input)).toBe(expected);
    }
  });
});

/**
 * ファイルの持ち主の検証（仕様書 13.7 / 監査 S1）
 *
 * **定期削除がファイルを消す前に必ず通す関数。** 項目の `file.storagePath`
 * はクライアントが書けるため、他人のリストのパスを書いておくと、
 * サーバーの権限でそのファイルを消させられる。
 *
 * 第 1 回監査で最も重大とされた欠陥に対する防御そのものが、
 * **テスト 0 件だった**（監査 第2回）。
 */
describe('ファイルの持ち主の検証（13.7 / S1）', () => {
  test('自分の項目のパスなら通る', () => {
    expect(isPathOwnedByItem('lists/L1/items/I1/take01.mp3', 'L1', 'I1')).toBe(
      true
    );
  });

  test('入れ子のファイル名でも通る', () => {
    expect(isPathOwnedByItem('lists/L1/items/I1/a/b.mp3', 'L1', 'I1')).toBe(
      true
    );
  });

  test('別のリストのパスは通さない', () => {
    expect(isPathOwnedByItem('lists/L2/items/I1/x.mp3', 'L1', 'I1')).toBe(false);
  });

  test('別の項目のパスは通さない', () => {
    expect(isPathOwnedByItem('lists/L1/items/I2/x.mp3', 'L1', 'I1')).toBe(false);
  });

  test('lists 配下でないパスは通さない', () => {
    expect(isPathOwnedByItem('other/L1/items/I1/x.mp3', 'L1', 'I1')).toBe(false);
    expect(isPathOwnedByItem('lists/L1/x/I1/y.mp3', 'L1', 'I1')).toBe(false);
  });

  test('ファイル名が無いパスは通さない', () => {
    expect(isPathOwnedByItem('lists/L1/items/I1/', 'L1', 'I1')).toBe(false);
    expect(isPathOwnedByItem('lists/L1/items/I1', 'L1', 'I1')).toBe(false);
  });

  test('文字列でない値・空文字は通さない', () => {
    expect(isPathOwnedByItem(null, 'L1', 'I1')).toBe(false);
    expect(isPathOwnedByItem(undefined, 'L1', 'I1')).toBe(false);
    expect(isPathOwnedByItem(123, 'L1', 'I1')).toBe(false);
    expect(isPathOwnedByItem({}, 'L1', 'I1')).toBe(false);
    expect(isPathOwnedByItem('', 'L1', 'I1')).toBe(false);
  });

  test('先頭に別のリストのパスを紛れ込ませても通さない', () => {
    // `lists/L1/items/I1/` で始まるように見せかけた別リストのパス。
    expect(
      isPathOwnedByItem('lists/L1x/items/I1/x.mp3', 'L1', 'I1')
    ).toBe(false);
    expect(
      isPathOwnedByItem('../lists/L1/items/I1/x.mp3', 'L1', 'I1')
    ).toBe(false);
  });
});

/**
 * 上限を超えたアップロードの扱い（仕様書 7.5 / 監査 S5・第2回）
 *
 * **回帰テスト。** 仕様は「すり抜けたぶんは削除せず受け入れる」と
 * 定めているのに、実装は超過を検知したファイルをすべて消していた。
 * しかもクライアントは「アップロード完了 → 項目作成」の順で動くため、
 * 削除と項目作成が競合し、**ファイルの無い項目**が残りえた。
 *
 * かといって一切消さないと、画面を経由しない呼び出しで上限を無視できる。
 * 「すり抜け」と「無視」を分ける。
 */
describe('上限を超えたアップロードの扱い（7.5 / S5）', () => {
  const quotaBytes = 1000;

  test('このファイルで初めて超えたなら残す（すり抜け）', () => {
    // 900 使っていて 200 のファイル → 1100。超えたが、来る前は 900。
    expect(
      shouldRejectUpload({ usedBytesAfter: 1100, sizeBytes: 200, quotaBytes })
    ).toBe(false);
  });

  test('ちょうど上限まで使っていた状態からの追加は取り消す', () => {
    // 1000 使っていて 50 のファイル → 1050。来る前がすでに上限。
    expect(
      shouldRejectUpload({ usedBytesAfter: 1050, sizeBytes: 50, quotaBytes })
    ).toBe(true);
  });

  test('すでに超えている状態からの追加は取り消す（上限の無視）', () => {
    expect(
      shouldRejectUpload({ usedBytesAfter: 2000, sizeBytes: 100, quotaBytes })
    ).toBe(true);
  });

  test('1 つのファイルが単独で上限を超えていても残す', () => {
    // 0 使用のところに 5000 のファイル。開始前チェックをすり抜けた形。
    expect(
      shouldRejectUpload({ usedBytesAfter: 5000, sizeBytes: 5000, quotaBytes })
    ).toBe(false);
  });

  test('上限が 0 なら常に取り消す（満杯扱い）', () => {
    expect(
      shouldRejectUpload({ usedBytesAfter: 1, sizeBytes: 1, quotaBytes: 0 })
    ).toBe(true);
  });
});

/**
 * エラーの符号（仕様書 2 章 / 監査 第2回）
 *
 * **回帰テスト。** サーバーが返す文をそのまま画面に出していたため、
 * 英語表示でも申請・承認・招待・退会・容量変更のエラーが日本語で出ていた。
 * 符号（details.code）を載せて、画面側で文言を引くようにした。
 *
 * 符号を増やしたときに、控えの文言と画面側の l10n を足し忘れないよう
 * ここで数と中身を固定する。画面側の対応表は
 * test/domain/function_error_test.dart にある。
 */
describe('エラーの符号（2 章）', () => {
  test('すべての符号に控えの文言がある', () => {
    for (const code of ERROR_CODES) {
      const error = fail('internal', code);
      expect(error.message, code).toBeTruthy();
      expect(error.message, code).not.toBe(code);
    }
  });

  test('符号は details に載る（画面が出し分けるため）', () => {
    const error = fail('not-found', 'listNotFound');
    expect(error.details).toMatchObject({ code: 'listNotFound' });
  });

  test('穴埋めの値も details に載る', () => {
    const error = fail('already-exists', 'listNameTaken', {
      listName: '練習音源',
    });
    expect(error.details).toMatchObject({
      code: 'listNameTaken',
      listName: '練習音源',
    });
  });

  test('符号が重複していない', () => {
    expect(new Set(ERROR_CODES).size).toBe(ERROR_CODES.length);
  });
});

/**
 * 行き場を失ったファイルの削除判断（仕様書 7.5 / 監査 第2回）
 *
 * **リポジトリでもっとも取り返しのつかない処理。**
 * 利用者の音源を Storage から永久に消す。にもかかわらず
 * `functions/src/scheduled/purge.ts` はテストが 1 件も無かった。
 * さらに `firebase.json` に pubsub エミュレータが無く、
 * **エミュレータでは一度も起動できない**状態だった。
 *
 * Storage を実際に消すところは動かせなくても、「消してよいか」の
 * 判断だけなら確かめられる。
 */
describe('孤児ファイルの削除判断（7.5）', () => {
  const cutoffMs = 1_000_000;
  const path = 'lists/L1/items/I1/take01.mp3';
  const old = cutoffMs - 1;
  const fresh = cutoffMs + 1;

  test('項目が無く、猶予期間も過ぎていれば消す', () => {
    expect(
      shouldDeleteOrphan({ path, createdAtMs: old, cutoffMs, item: null })
    ).toBe(true);
  });

  test('猶予期間内なら消さない（項目作成の直前かもしれない）', () => {
    expect(
      shouldDeleteOrphan({ path, createdAtMs: fresh, cutoffMs, item: null })
    ).toBe(false);
  });

  test('アップロード時刻が読めないものは消さない', () => {
    expect(
      shouldDeleteOrphan({ path, createdAtMs: NaN, cutoffMs, item: null })
    ).toBe(false);
  });

  test('項目が今このファイルを指しているなら消さない', () => {
    expect(
      shouldDeleteOrphan({
        path,
        createdAtMs: old,
        cutoffMs,
        item: { file: { storagePath: path } },
      })
    ).toBe(false);
  });

  test('項目が別のファイルを指しているなら消す（差し替え後の残骸）', () => {
    expect(
      shouldDeleteOrphan({
        path,
        createdAtMs: old,
        cutoffMs,
        item: { file: { storagePath: 'lists/L1/items/I1/new.mp3' } },
      })
    ).toBe(true);
  });

  test('差し替えの旧ファイルとして保持されていれば消さない', () => {
    expect(
      shouldDeleteOrphan({
        path,
        createdAtMs: old,
        cutoffMs,
        item: {
          file: { storagePath: 'lists/L1/items/I1/new.mp3' },
          previousFiles: [{ storagePath: path }],
        },
      })
    ).toBe(false);
  });

  test('項目のファイル置き場でないパスには触らない', () => {
    for (const other of [
      'other/L1/items/I1/x.mp3',
      'lists/L1/x/I1/y.mp3',
      'lists/L1/items/I1/',
      '',
    ]) {
      expect(
        shouldDeleteOrphan({
          path: other,
          createdAtMs: old,
          cutoffMs,
          item: null,
        }),
        other
      ).toBe(false);
    }
  });

  test('previousFiles が壊れていても消す判断は変わらない', () => {
    // 配列でない値・null 混じりでも例外を出さない。
    for (const previousFiles of [null, 'x', 42, [null], [{}]]) {
      expect(
        shouldDeleteOrphan({
          path,
          createdAtMs: old,
          cutoffMs,
          item: { file: null, previousFiles },
        })
      ).toBe(true);
    }
  });
});

/**
 * 招待の受諾可否（仕様書 3.3 / 監査 S11・第2回）
 *
 * **本番で動いている側をテストする。**
 * 以前は同じ規則が Flutter 側にもあり、そちらだけが 13 件のテストで
 * 守られていた。しかし本番コードからは一度も呼ばれておらず、実際に
 * 動いていたのは membership.ts のインライン実装で、無テストだった。
 */
describe('招待の受諾可否（3.3）', () => {
  const now = 1_000_000;
  const active = {
    exists: true,
    status: 'active',
    expiresAtMs: now + 1000,
    listId: 'L1',
  };

  test('有効な招待は受け入れる', () => {
    expect(
      evaluateInvite({ invite: active, isAlreadyMember: false, nowMs: now })
    ).toEqual({ listId: 'L1' });
  });

  test('存在しない招待', () => {
    expect(
      evaluateInvite({
        invite: { exists: false },
        isAlreadyMember: false,
        nowMs: now,
      })
    ).toEqual({ rejection: 'inviteNotFound' });
  });

  test('使用済みはワンタイム性で弾く', () => {
    expect(
      evaluateInvite({
        invite: { ...active, status: 'used' },
        isAlreadyMember: false,
        nowMs: now,
      })
    ).toEqual({ rejection: 'inviteAlreadyUsed' });
  });

  test('取り消し済み', () => {
    expect(
      evaluateInvite({
        invite: { ...active, status: 'revoked' },
        isAlreadyMember: false,
        nowMs: now,
      })
    ).toEqual({ rejection: 'inviteRevoked' });
  });

  test('期限切れ（ちょうどの時刻は切れている扱い）', () => {
    expect(
      evaluateInvite({
        invite: { ...active, expiresAtMs: now },
        isAlreadyMember: false,
        nowMs: now,
      })
    ).toEqual({ rejection: 'inviteExpired' });
  });

  test('期限が読めないものは通さない', () => {
    for (const expiresAtMs of [undefined, NaN]) {
      expect(
        evaluateInvite({
          invite: { ...active, expiresAtMs },
          isAlreadyMember: false,
          nowMs: now,
        })
      ).toEqual({ rejection: 'inviteExpired' });
    }
  });

  test('リスト ID が無い招待は「見つからない」扱い', () => {
    expect(
      evaluateInvite({
        invite: { ...active, listId: '' },
        isAlreadyMember: false,
        nowMs: now,
      })
    ).toEqual({ rejection: 'inviteNotFound' });
  });

  test('すでにメンバーなら受け入れない', () => {
    expect(
      evaluateInvite({ invite: active, isAlreadyMember: true, nowMs: now })
    ).toEqual({ rejection: 'alreadyMember' });
  });

  // **判定の順番にも意味がある。**
  test('取り消し済みなら、期限が切れていても「取り消し」と伝える', () => {
    expect(
      evaluateInvite({
        invite: { ...active, status: 'revoked', expiresAtMs: now - 1 },
        isAlreadyMember: false,
        nowMs: now,
      })
    ).toEqual({ rejection: 'inviteRevoked' });
  });

  test('期限切れなら、すでにメンバーでも「期限切れ」と伝える', () => {
    expect(
      evaluateInvite({
        invite: { ...active, expiresAtMs: now - 1 },
        isAlreadyMember: true,
        nowMs: now,
      })
    ).toEqual({ rejection: 'inviteExpired' });
  });
});
