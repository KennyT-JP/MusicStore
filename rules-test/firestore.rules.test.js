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
import {
  collection,
  collectionGroup,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  query,
  setDoc,
  updateDoc,
  where,
} from 'firebase/firestore';

import {
  COMMENT_ID,
  ITEM_ID,
  LIST_ID,
  UID,
  asAnonymous,
  asSiteAdmin,
  asUnverified,
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

describe('リストの列挙（5.3）', () => {
  test('一般ユーザーは全リストを列挙できない', async () => {
    // 列挙できると未参加者が全リスト名を知れてしまい、
    // 「全リストの一覧を公開する画面は作らない」に反する。
    const outsider = db(asUser(env, UID.outsider));
    await assertFails(getDocs(collection(outsider, 'lists')));
  });

  test('メンバーでも全リストは列挙できない', async () => {
    const listAdmin = db(asUser(env, UID.listAdmin));
    await assertFails(getDocs(collection(listAdmin, 'lists')));
  });

  test('サイト管理者だけが全リストを列挙できる（11.1）', async () => {
    const siteAdmin = db(asSiteAdmin(env));
    await assertSucceeds(getDocs(collection(siteAdmin, 'lists')));
  });

  test('ID を知っていれば取得できる（共有 URL の経路）', async () => {
    const outsider = db(asUser(env, UID.outsider));
    await assertSucceeds(getDoc(doc(outsider, `lists/${LIST_ID}`)));
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

  // **回帰テスト（監査 第2回）。**
  //
  // 通知の宛先を集めるためのサイト管理者 uid 一覧と、定期削除の走査位置を
  // サーバー側で持つことにした。siteConfig/global は利用者も読めるため、
  // これらは読めない場所（siteConfig/internal）へ分けている。
  test('内部用のサイト設定はサイト管理者でも読めない', async () => {
    const siteAdmin = db(asSiteAdmin(env));
    await assertFails(getDoc(doc(siteAdmin, 'siteConfig/internal')));
  });

  test('内部用のサイト設定は誰も書けない', async () => {
    const siteAdmin = db(asSiteAdmin(env));
    await assertFails(
      setDoc(doc(siteAdmin, 'siteConfig/internal'), { siteAdminUids: ['x'] }),
    );
  });

  test('一般の利用者も内部用のサイト設定は読めない', async () => {
    const member = db(asUser(env, UID.readOnly));
    await assertFails(getDoc(doc(member, 'siteConfig/internal')));
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


// ---------------------------------------------------------------------------
// 2026-08-06 のゼロベース監査で見つけた穴。再発させないための回帰テスト。
// ---------------------------------------------------------------------------

describe('監査 S2：users を列挙できない', () => {
  test('一般利用者は users を一覧できない（全会員のメール収集を防ぐ）', async () => {
    const superUser = db(asUser(env, UID.superUser));
    await assertFails(getDocs(collection(superUser, 'users')));
  });

  test('ID を指定した取得は許す（表示名の解決に要る）', async () => {
    const superUser = db(asUser(env, UID.superUser));
    await assertSucceeds(getDoc(doc(superUser, `users/${UID.listAdmin}`)));
  });

  test('サイト管理者は一覧できる（11.1）', async () => {
    const siteAdmin = db(asSiteAdmin(env));
    await assertSucceeds(getDocs(collection(siteAdmin, 'users')));
  });
});

describe('監査 S3：メール確認が済むまで何もできない（3.1）', () => {
  test('未確認では他人のユーザー情報を読めない', async () => {
    const unverified = db(asUnverified(env, UID.superUser));
    await assertFails(getDoc(doc(unverified, `users/${UID.listAdmin}`)));
  });

  test('未確認ではリストを読めない', async () => {
    const unverified = db(asUnverified(env, UID.superUser));
    await assertFails(getDoc(doc(unverified, `lists/${LIST_ID}`)));
  });

  test('未確認では項目を追加できない', async () => {
    const unverified = db(asUnverified(env, UID.superUser));
    await assertFails(
      setDoc(doc(unverified, `lists/${LIST_ID}/items/new-item`), {
        seq: 99,
        createdBy: UID.superUser,
        status: 'active',
      }),
    );
  });

  test('未確認でも自分のユーザードキュメントは作れる（登録直後のため）', async () => {
    const unverified = db(asUnverified(env, 'u-brand-new'));
    await assertSucceeds(
      setDoc(doc(unverified, 'users/u-brand-new'), { displayName: '新規' }),
    );
  });

  // **回帰テスト（監査 第2回）。**
  //
  // 「作れる」だけを確かめていて、「読める」を一度も試していなかった。
  // 登録処理は「読んで、無ければ作る」順で動くため、読みが拒否されると
  // その先の確認メール送信に到達しない。メールが届かないまま
  // 「エラーが発生しました」とだけ出る状態が配信されていた。
  //
  // 作れるのに読めない、という食い違いを二度と作らないために、
  // 両方を並べて確かめる。
  test('未確認でも自分のユーザードキュメントは読める（登録処理は書く前に読む）', async () => {
    const unverified = db(asUnverified(env, 'u-brand-new'));
    await assertSucceeds(getDoc(doc(unverified, 'users/u-brand-new')));
  });

  test('未確認では他人のユーザードキュメントは読めない', async () => {
    const unverified = db(asUnverified(env, 'u-brand-new'));
    await assertFails(getDoc(doc(unverified, `users/${UID.listAdmin}`)));
  });

  test('未確認では他人のユーザードキュメントを作れない', async () => {
    const unverified = db(asUnverified(env, 'u-brand-new'));
    await assertFails(
      setDoc(doc(unverified, 'users/u-someone-else'), { displayName: '偽' }),
    );
  });
});

describe('監査 S1：項目に他リストのファイルパスを書けない', () => {
  test('自分のリスト配下のパスなら保存できる', async () => {
    const superUser = db(asUser(env, UID.superUser));
    await assertSucceeds(
      setDoc(doc(superUser, `lists/${LIST_ID}/items/ok-item`), {
        seq: 50,
        createdBy: UID.superUser,
        status: 'active',
        file: { storagePath: `lists/${LIST_ID}/items/ok-item/song.mp3` },
      }),
    );
  });

  test('他リストのパスは拒否する（定期削除に消させないため）', async () => {
    const superUser = db(asUser(env, UID.superUser));
    await assertFails(
      setDoc(doc(superUser, `lists/${LIST_ID}/items/evil-item`), {
        seq: 51,
        createdBy: UID.superUser,
        status: 'active',
        file: { storagePath: 'lists/list-2/items/victim/precious.mp3' },
      }),
    );
  });

  test('別の項目のパスも拒否する', async () => {
    const superUser = db(asUser(env, UID.superUser));
    await assertFails(
      setDoc(doc(superUser, `lists/${LIST_ID}/items/evil-item-2`), {
        seq: 52,
        createdBy: UID.superUser,
        status: 'active',
        file: { storagePath: `lists/${LIST_ID}/items/other-item/x.mp3` },
      }),
    );
  });

  test('previousFiles はクライアントから書けない（Functions のみ）', async () => {
    const superUser = db(asUser(env, UID.superUser));
    await assertFails(
      setDoc(doc(superUser, `lists/${LIST_ID}/items/evil-item-3`), {
        seq: 53,
        createdBy: UID.superUser,
        status: 'active',
        previousFiles: [{ storagePath: 'lists/list-2/items/victim/old.mp3' }],
      }),
    );
  });

  test('status に任意の文字列を入れられない', async () => {
    const superUser = db(asUser(env, UID.superUser));
    await assertFails(
      setDoc(doc(superUser, `lists/${LIST_ID}/items/evil-item-4`), {
        seq: 54,
        createdBy: UID.superUser,
        status: 'purged',
      }),
    );
  });
});


// ---------------------------------------------------------------------------
// ホームの参加リスト一覧（仕様書 14.2）
//
// **回帰テスト。** 以前は collectionGroup を documentId() で引いており、
// 「値は完全なドキュメントパスでなければならない」という制約に触れて
// 常に失敗していた。そのためリストを作ってもホームに出なかった。
// メンバーが持つ uid 項目で引く。
// ---------------------------------------------------------------------------

describe('自分の参加リストを引く', () => {
  test('メンバーは自分の members を collectionGroup で引ける', async () => {
    const c = db(asUser(env, UID.superUser));
    await assertSucceeds(
      getDocs(
        query(
          collectionGroup(c, 'members'),
          where('uid', '==', UID.superUser),
        ),
      ),
    );
  });

  test('サイト管理者も自分の members を引ける（兼任できる）', async () => {
    const c = db(asSiteAdmin(env));
    await assertSucceeds(
      getDocs(
        query(
          collectionGroup(c, 'members'),
          where('uid', '==', UID.siteAdmin),
        ),
      ),
    );
  });

  test('自分の参加申請も引ける', async () => {
    const c = db(asUser(env, UID.outsider));
    await assertSucceeds(
      getDocs(
        query(
          collectionGroup(c, 'joinRequests'),
          where('uid', '==', UID.outsider),
        ),
      ),
    );
  });
});


// ---------------------------------------------------------------------------
// 項目の追加（仕様書 6.2）
//
// **回帰テスト。** 連番の採番はクライアント側のトランザクションで行うのに、
// meta/stats の書き込みを全面禁止していたため、項目の追加が一度も
// 成功しなかった。コメントには「連番はトランザクション」と書いてあった。
// ---------------------------------------------------------------------------

describe('連番の採番（6.2）', () => {
  test('Super User は nextSeq を 1 進められる', async () => {
    const c = db(asUser(env, UID.superUser));
    await assertSucceeds(
      updateDoc(doc(c, `lists/${LIST_ID}/meta/stats`), { nextSeq: 3 }),
    );
  });

  test('Read Only は進められない', async () => {
    const c = db(asUser(env, UID.readOnly));
    await assertFails(
      updateDoc(doc(c, `lists/${LIST_ID}/meta/stats`), { nextSeq: 3 }),
    );
  });

  test('2 以上飛ばせない（欠番を作れない）', async () => {
    const c = db(asUser(env, UID.superUser));
    await assertFails(
      updateDoc(doc(c, `lists/${LIST_ID}/meta/stats`), { nextSeq: 4 }),
    );
  });

  test('戻せない（振り直せない）', async () => {
    const c = db(asUser(env, UID.superUser));
    await assertFails(
      updateDoc(doc(c, `lists/${LIST_ID}/meta/stats`), { nextSeq: 1 }),
    );
  });

  test('使用容量は書き換えられない（Functions のみ）', async () => {
    const c = db(asUser(env, UID.superUser));
    await assertFails(
      updateDoc(doc(c, `lists/${LIST_ID}/meta/stats`), { usedBytes: 0 }),
    );
  });

  test('nextSeq と一緒に容量も書くことはできない', async () => {
    const c = db(asUser(env, UID.superUser));
    await assertFails(
      updateDoc(doc(c, `lists/${LIST_ID}/meta/stats`), {
        nextSeq: 3,
        usedBytes: 0,
      }),
    );
  });

  test('日本語のファイル名でも項目を追加できる（13.7）', async () => {
    const c = db(asUser(env, UID.superUser));
    await assertSucceeds(
      setDoc(doc(c, `lists/${LIST_ID}/items/jp-name`), {
        seq: 10,
        createdBy: UID.superUser,
        status: 'active',
        kind: 'file',
        file: {
          storagePath: `lists/${LIST_ID}/items/jp-name/顔写真3.png`,
          fileName: '顔写真3.png',
          sizeBytes: 924672,
          contentType: 'image/png',
        },
      }),
    );
  });
});
