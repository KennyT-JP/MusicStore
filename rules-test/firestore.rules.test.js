/**
 * Firestore セキュリティルールのテスト（仕様書 13.5）
 *
 * 12.6 で「クライアントを信用しない最後の防波堤」として
 * 自動テスト必須にした領域。
 */
import { afterAll, beforeAll, beforeEach, describe, expect, test } from 'vitest';
import {
  assertFails,
  assertSucceeds,
} from '@firebase/rules-unit-testing';
import { doc, getDoc, setDoc, updateDoc, deleteDoc } from 'firebase/firestore';

import {
  COMMENT_ID,
  ITEM_ID,
  LIST_ID,
  UID,
  asAnonymous,
  asSiteAdmin,
  asUser,
  createTestEnv,
  seed,
} from './helpers.js';

let env;

beforeAll(async () => {
  env = await createTestEnv();
});

afterAll(async () => {
  await env?.cleanup();
});

beforeEach(async () => {
  await seed(env);
});

const db = (ctx) => ctx.firestore();

describe('未ログイン（3.1.1）', () => {
  test('リスト名すら読めない', async () => {
    const anon = db(asAnonymous(env));
    await assertFails(getDoc(doc(anon, `lists/${LIST_ID}`)));
  });

  test('項目も読めない', async () => {
    const anon = db(asAnonymous(env));
    await assertFails(getDoc(doc(anon, `lists/${LIST_ID}/items/${ITEM_ID}`)));
  });

  test('招待も読めない', async () => {
    const anon = db(asAnonymous(env));
    await assertFails(getDoc(doc(anon, 'invites/secret-invite-id')));
  });
});

describe('未参加者から見たリスト（5.3）', () => {
  test('リスト名など最低限の情報は読める', async () => {
    const outsider = db(asUser(env, UID.outsider));
    await assertSucceeds(getDoc(doc(outsider, `lists/${LIST_ID}`)));
  });

  test('中身（項目）は読めない', async () => {
    const outsider = db(asUser(env, UID.outsider));
    await assertFails(
      getDoc(doc(outsider, `lists/${LIST_ID}/items/${ITEM_ID}`)),
    );
  });

  test('コメントも読めない', async () => {
    const outsider = db(asUser(env, UID.outsider));
    await assertFails(
      getDoc(
        doc(outsider, `lists/${LIST_ID}/items/${ITEM_ID}/comments/${COMMENT_ID}`),
      ),
    );
  });

  test('容量などの内部情報は読めない', async () => {
    // lists/{listId} を公開しても meta/stats は隠れる（13.2 の 2 段構成）。
    const outsider = db(asUser(env, UID.outsider));
    await assertFails(getDoc(doc(outsider, `lists/${LIST_ID}/meta/stats`)));
  });

  test('項目を追加できない', async () => {
    const outsider = db(asUser(env, UID.outsider));
    await assertFails(
      setDoc(doc(outsider, `lists/${LIST_ID}/items/new-item`), {
        seq: 2,
        createdBy: UID.outsider,
        status: 'active',
      }),
    );
  });
});

describe('Read Only（4.2 / 9）', () => {
  test('項目を読める', async () => {
    const readOnly = db(asUser(env, UID.readOnly));
    await assertSucceeds(
      getDoc(doc(readOnly, `lists/${LIST_ID}/items/${ITEM_ID}`)),
    );
  });

  test('容量は読める（メンバーなので）', async () => {
    const readOnly = db(asUser(env, UID.readOnly));
    await assertSucceeds(getDoc(doc(readOnly, `lists/${LIST_ID}/meta/stats`)));
  });

  test('項目を追加できない', async () => {
    const readOnly = db(asUser(env, UID.readOnly));
    await assertFails(
      setDoc(doc(readOnly, `lists/${LIST_ID}/items/new-item`), {
        seq: 2,
        createdBy: UID.readOnly,
        status: 'active',
      }),
    );
  });

  test('コメントを書けない', async () => {
    const readOnly = db(asUser(env, UID.readOnly));
    await assertFails(
      setDoc(
        doc(readOnly, `lists/${LIST_ID}/items/${ITEM_ID}/comments/new`),
        { body: 'コメント', createdBy: UID.readOnly, status: 'active' },
      ),
    );
  });

  test('自分から抜けられる（5.4）', async () => {
    const readOnly = db(asUser(env, UID.readOnly));
    await assertSucceeds(
      deleteDoc(doc(readOnly, `lists/${LIST_ID}/members/${UID.readOnly}`)),
    );
  });

  test('他人を除外できない', async () => {
    const readOnly = db(asUser(env, UID.readOnly));
    await assertFails(
      deleteDoc(doc(readOnly, `lists/${LIST_ID}/members/${UID.superUser}`)),
    );
  });
});

describe('Super User（4.2 / 6.3）', () => {
  test('項目を追加できる', async () => {
    const superUser = db(asUser(env, UID.superUser));
    await assertSucceeds(
      setDoc(doc(superUser, `lists/${LIST_ID}/items/new-item`), {
        seq: 2,
        date: '2026-08-04',
        kind: 'url',
        url: 'https://example.com/x',
        createdBy: UID.superUser,
        status: 'active',
      }),
    );
  });

  test('登録者を他人になりすまして追加できない', async () => {
    const superUser = db(asUser(env, UID.superUser));
    await assertFails(
      setDoc(doc(superUser, `lists/${LIST_ID}/items/new-item`), {
        seq: 2,
        createdBy: UID.listAdmin,
        status: 'active',
      }),
    );
  });

  test('自分の項目は編集できる', async () => {
    const superUser = db(asUser(env, UID.superUser));
    await assertSucceeds(
      updateDoc(doc(superUser, `lists/${LIST_ID}/items/${ITEM_ID}`), {
        title: '曲名を付けた',
      }),
    );
  });

  test('連番は変更できない（6.2：振り直しなし）', async () => {
    const superUser = db(asUser(env, UID.superUser));
    await assertFails(
      updateDoc(doc(superUser, `lists/${LIST_ID}/items/${ITEM_ID}`), {
        seq: 99,
      }),
    );
  });

  test('登録者を書き換えられない', async () => {
    const superUser = db(asUser(env, UID.superUser));
    await assertFails(
      updateDoc(doc(superUser, `lists/${LIST_ID}/items/${ITEM_ID}`), {
        createdBy: UID.readOnly,
      }),
    );
  });

  test('項目を物理削除できない（6.2：ソフト削除）', async () => {
    const superUser = db(asUser(env, UID.superUser));
    await assertFails(
      deleteDoc(doc(superUser, `lists/${LIST_ID}/items/${ITEM_ID}`)),
    );
  });

  test('メンバーを除外できない', async () => {
    const superUser = db(asUser(env, UID.superUser));
    await assertFails(
      deleteDoc(doc(superUser, `lists/${LIST_ID}/members/${UID.readOnly}`)),
    );
  });

  test('容量を書き換えられない（13.3）', async () => {
    // 上限判定をすり抜けるための改ざんを防ぐ。
    const superUser = db(asUser(env, UID.superUser));
    await assertFails(
      updateDoc(doc(superUser, `lists/${LIST_ID}/meta/stats`), {
        usedBytes: 0,
      }),
    );
  });

  test('連番カウンタを直接書き換えられない', async () => {
    const superUser = db(asUser(env, UID.superUser));
    await assertFails(
      updateDoc(doc(superUser, `lists/${LIST_ID}/meta/stats`), {
        nextSeq: 1,
      }),
    );
  });
});

describe('他人の項目（6.3）', () => {
  test('Super User は他人の項目を編集できない', async () => {
    // ITEM_ID は superUser が作成したものなので、
    // listAdmin ではない別の Super User を作って確認する。
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(
        doc(ctx.firestore(), `lists/${LIST_ID}/members/u-other-super`),
        { role: 'superUser', via: 'request' },
      );
    });
    const other = db(asUser(env, 'u-other-super'));
    await assertFails(
      updateDoc(doc(other, `lists/${LIST_ID}/items/${ITEM_ID}`), {
        title: '勝手に変更',
      }),
    );
  });

  test('リスト管理者は他人の項目を編集できる', async () => {
    const listAdmin = db(asUser(env, UID.listAdmin));
    await assertSucceeds(
      updateDoc(doc(listAdmin, `lists/${LIST_ID}/items/${ITEM_ID}`), {
        title: '管理者が修正',
      }),
    );
  });

  test('リスト管理者は他人のコメントを編集できる（9）', async () => {
    const listAdmin = db(asUser(env, UID.listAdmin));
    await assertSucceeds(
      updateDoc(
        doc(
          listAdmin,
          `lists/${LIST_ID}/items/${ITEM_ID}/comments/${COMMENT_ID}`,
        ),
        { status: 'deleted' },
      ),
    );
  });
});

describe('リスト管理者（5.4 / 5.5）', () => {
  test('メンバーの役割を変更できる', async () => {
    const listAdmin = db(asUser(env, UID.listAdmin));
    await assertSucceeds(
      updateDoc(doc(listAdmin, `lists/${LIST_ID}/members/${UID.readOnly}`), {
        role: 'superUser',
      }),
    );
  });

  test('メンバーを除外できる', async () => {
    const listAdmin = db(asUser(env, UID.listAdmin));
    await assertSucceeds(
      deleteDoc(doc(listAdmin, `lists/${LIST_ID}/members/${UID.readOnly}`)),
    );
  });

  test('リストを削除できる', async () => {
    const listAdmin = db(asUser(env, UID.listAdmin));
    await assertSucceeds(deleteDoc(doc(listAdmin, `lists/${LIST_ID}`)));
  });

  test('集計フィールドは書き換えられない', async () => {
    const listAdmin = db(asUser(env, UID.listAdmin));
    await assertFails(
      updateDoc(doc(listAdmin, `lists/${LIST_ID}`), { memberCount: 999 }),
    );
  });

  test('メンバーを直接追加できない（承認・招待は Functions 経由）', async () => {
    const listAdmin = db(asUser(env, UID.listAdmin));
    await assertFails(
      setDoc(doc(listAdmin, `lists/${LIST_ID}/members/${UID.outsider}`), {
        role: 'superUser',
        via: 'request',
      }),
    );
  });

  test('他のリストは操作できない', async () => {
    const listAdmin = db(asUser(env, UID.listAdmin));
    await assertFails(deleteDoc(doc(listAdmin, `lists/list-2`)));
  });
});

describe('サイト管理者（4.2 / 13.5）', () => {
  test('メンバー登録がなくても中身を読める', async () => {
    const siteAdmin = db(asSiteAdmin(env));
    await assertSucceeds(
      getDoc(doc(siteAdmin, `lists/${LIST_ID}/items/${ITEM_ID}`)),
    );
  });

  test('どのリストの項目も編集できる', async () => {
    const siteAdmin = db(asSiteAdmin(env));
    await assertSucceeds(
      updateDoc(doc(siteAdmin, `lists/${LIST_ID}/items/${ITEM_ID}`), {
        title: 'サイト管理者が修正',
      }),
    );
  });

  test('どのリストも削除できる（5.5）', async () => {
    const siteAdmin = db(asSiteAdmin(env));
    await assertSucceeds(deleteDoc(doc(siteAdmin, `lists/list-2`)));
  });

  test('サイト設定を変更できる', async () => {
    const siteAdmin = db(asSiteAdmin(env));
    await assertSucceeds(
      updateDoc(doc(siteAdmin, 'siteConfig/global'), {
        inviteExpiryHours: 48,
      }),
    );
  });

  test('siteAdminCount は書き換えられない（4.5）', async () => {
    // 最後の 1 人の判定を迂回されないようにする。
    const siteAdmin = db(asSiteAdmin(env));
    await assertFails(
      updateDoc(doc(siteAdmin, 'siteConfig/global'), { siteAdminCount: 5 }),
    );
  });

  test('サイト管理者でなければサイト設定を変更できない', async () => {
    const listAdmin = db(asUser(env, UID.listAdmin));
    await assertFails(
      updateDoc(doc(listAdmin, 'siteConfig/global'), {
        inviteExpiryHours: 48,
      }),
    );
  });

  test('容量も直接は書き換えられない（Functions のみ）', async () => {
    const siteAdmin = db(asSiteAdmin(env));
    await assertFails(
      updateDoc(doc(siteAdmin, `lists/${LIST_ID}/meta/stats`), {
        usedBytes: 0,
      }),
    );
  });
});

describe('参加申請（5.2 / 5.2.1）', () => {
  test('本人は申請できる', async () => {
    const outsider = db(asUser(env, UID.outsider));
    await assertSucceeds(
      setDoc(doc(outsider, `lists/${LIST_ID}/joinRequests/${UID.outsider}`), {
        status: 'pending',
      }),
    );
  });

  test('他人の名前で申請できない', async () => {
    const outsider = db(asUser(env, UID.outsider));
    await assertFails(
      setDoc(doc(outsider, `lists/${LIST_ID}/joinRequests/other-uid`), {
        status: 'pending',
      }),
    );
  });

  test('申請時に役割を指定できない（5.2）', async () => {
    const outsider = db(asUser(env, UID.outsider));
    await assertFails(
      setDoc(doc(outsider, `lists/${LIST_ID}/joinRequests/${UID.outsider}`), {
        status: 'pending',
        assignedRole: 'listAdmin',
      }),
    );
  });

  test('自分で承認できない', async () => {
    const outsider = db(asUser(env, UID.outsider));
    await assertFails(
      setDoc(doc(outsider, `lists/${LIST_ID}/joinRequests/${UID.outsider}`), {
        status: 'approved',
      }),
    );
  });

  test('却下後に再申請できる（5.2.1）', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(
        doc(
          ctx.firestore(),
          `lists/${LIST_ID}/joinRequests/${UID.outsider}`,
        ),
        { status: 'rejected', decidedBy: UID.listAdmin },
      );
    });
    const outsider = db(asUser(env, UID.outsider));
    await assertSucceeds(
      setDoc(doc(outsider, `lists/${LIST_ID}/joinRequests/${UID.outsider}`), {
        status: 'pending',
      }),
    );
  });

  test('リスト管理者は申請を読める', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(
        doc(
          ctx.firestore(),
          `lists/${LIST_ID}/joinRequests/${UID.outsider}`,
        ),
        { status: 'pending' },
      );
    });
    const listAdmin = db(asUser(env, UID.listAdmin));
    await assertSucceeds(
      getDoc(doc(listAdmin, `lists/${LIST_ID}/joinRequests/${UID.outsider}`)),
    );
  });
});

describe('リスト作成申請（5.1）', () => {
  test('誰でも申請できる', async () => {
    const outsider = db(asUser(env, UID.outsider));
    await assertSucceeds(
      setDoc(doc(outsider, 'listRequests/req-2'), {
        listName: 'あたらしいリスト',
        nameLower: 'あたらしいりすと',
        requestedBy: UID.outsider,
        status: 'pending',
      }),
    );
  });

  test('自分で承認済みにできない', async () => {
    const outsider = db(asUser(env, UID.outsider));
    await assertFails(
      setDoc(doc(outsider, 'listRequests/req-2'), {
        listName: 'あたらしいリスト',
        requestedBy: UID.outsider,
        status: 'approved',
      }),
    );
  });

  test('申請者本人は自分の申請を読める（5.2.1）', async () => {
    const outsider = db(asUser(env, UID.outsider));
    await assertSucceeds(getDoc(doc(outsider, 'listRequests/req-1')));
  });

  test('他人の申請は読めない', async () => {
    const superUser = db(asUser(env, UID.superUser));
    await assertFails(getDoc(doc(superUser, 'listRequests/req-1')));
  });

  test('サイト管理者は読める', async () => {
    const siteAdmin = db(asSiteAdmin(env));
    await assertSucceeds(getDoc(doc(siteAdmin, 'listRequests/req-1')));
  });

  test('承認・却下はクライアントからできない（Functions のみ）', async () => {
    const siteAdmin = db(asSiteAdmin(env));
    await assertFails(
      updateDoc(doc(siteAdmin, 'listRequests/req-1'), { status: 'approved' }),
    );
  });
});

describe('招待 URL（3.3 / 13.3）', () => {
  test('ID を知っていれば読める', async () => {
    const outsider = db(asUser(env, UID.outsider));
    await assertSucceeds(getDoc(doc(outsider, 'invites/secret-invite-id')));
  });

  test('発行はクライアントからできない', async () => {
    const listAdmin = db(asUser(env, UID.listAdmin));
    await assertFails(
      setDoc(doc(listAdmin, 'invites/forged'), {
        listId: LIST_ID,
        role: 'listAdmin',
        status: 'active',
      }),
    );
  });

  test('使用済みに書き換えられない（ワンタイム性は Functions が担保）', async () => {
    const outsider = db(asUser(env, UID.outsider));
    await assertFails(
      updateDoc(doc(outsider, 'invites/secret-invite-id'), { status: 'used' }),
    );
  });
});

describe('リスト名の重複チェック（5.1 / 13.3）', () => {
  test('ID 直接指定なら存在を確認できる', async () => {
    const outsider = db(asUser(env, UID.outsider));
    await assertSucceeds(getDoc(doc(outsider, 'listNames/テストリスト')));
  });

  test('クライアントからは書けない', async () => {
    const outsider = db(asUser(env, UID.outsider));
    await assertFails(
      setDoc(doc(outsider, 'listNames/よこどり'), { listId: 'x' }),
    );
  });
});

describe('ユーザー（3.4 / 3.5）', () => {
  test('表示名の解決のため、ログイン済みなら誰でも読める', async () => {
    const readOnly = db(asUser(env, UID.readOnly));
    await assertSucceeds(getDoc(doc(readOnly, `users/${UID.superUser}`)));
  });

  test('自分の表示名は変えられる', async () => {
    const superUser = db(asUser(env, UID.superUser));
    await assertSucceeds(
      updateDoc(doc(superUser, `users/${UID.superUser}`), {
        displayName: '新しい名前',
      }),
    );
  });

  test('他人の表示名は変えられない', async () => {
    const superUser = db(asUser(env, UID.superUser));
    await assertFails(
      updateDoc(doc(superUser, `users/${UID.readOnly}`), {
        displayName: 'いたずら',
      }),
    );
  });

  test('退会フラグは自分でも立てられない（Functions が処理する）', async () => {
    // 最後のサイト管理者の退会を止めるため、サーバー側で判定する（4.5）。
    const superUser = db(asUser(env, UID.superUser));
    await assertFails(
      updateDoc(doc(superUser, `users/${UID.superUser}`), {
        isWithdrawn: true,
      }),
    );
  });

  test('ユーザードキュメントは削除できない（3.5：投稿は残す）', async () => {
    const superUser = db(asUser(env, UID.superUser));
    await assertFails(deleteDoc(doc(superUser, `users/${UID.superUser}`)));
  });
});

describe('通知（10 / 13.3）', () => {
  beforeEach(async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(
        doc(ctx.firestore(), `users/${UID.superUser}/notifications/n1`),
        { type: 'itemAdded', listId: LIST_ID, isRead: false },
      );
    });
  });

  test('本人だけが読める', async () => {
    const superUser = db(asUser(env, UID.superUser));
    await assertSucceeds(
      getDoc(doc(superUser, `users/${UID.superUser}/notifications/n1`)),
    );

    const readOnly = db(asUser(env, UID.readOnly));
    await assertFails(
      getDoc(doc(readOnly, `users/${UID.superUser}/notifications/n1`)),
    );
  });

  test('既読にできる', async () => {
    const superUser = db(asUser(env, UID.superUser));
    await assertSucceeds(
      updateDoc(doc(superUser, `users/${UID.superUser}/notifications/n1`), {
        isRead: true,
      }),
    );
  });

  test('既読以外は書き換えられない', async () => {
    const superUser = db(asUser(env, UID.superUser));
    await assertFails(
      updateDoc(doc(superUser, `users/${UID.superUser}/notifications/n1`), {
        type: 'listRequested',
      }),
    );
  });

  test('自分で通知を作れない（Functions のみ）', async () => {
    const superUser = db(asUser(env, UID.superUser));
    await assertFails(
      setDoc(doc(superUser, `users/${UID.superUser}/notifications/n2`), {
        type: 'itemAdded',
        isRead: false,
      }),
    );
  });
});

describe('定義していないパス', () => {
  test('読み書きとも拒否する', async () => {
    const siteAdmin = db(asSiteAdmin(env));
    await assertFails(getDoc(doc(siteAdmin, 'secrets/anything')));
    await assertFails(setDoc(doc(siteAdmin, 'secrets/anything'), { a: 1 }));
  });
});
