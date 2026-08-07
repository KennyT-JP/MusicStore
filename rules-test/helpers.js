/**
 * セキュリティルールのテスト用ヘルパー（仕様書 12.6 / 13.5）
 *
 * ルールは「クライアントを信用しない最後の防波堤」なので、
 * ルール単体で検証する。エミュレータ上で動くため、本番・検証プロジェクトには
 * 一切触れない。
 */
import { readFileSync } from 'node:fs';
import { initializeTestEnvironment } from '@firebase/rules-unit-testing';

export const LIST_ID = 'list-1';
export const OTHER_LIST_ID = 'list-2';
export const ITEM_ID = 'item-1';
export const COMMENT_ID = 'comment-1';

/** テストで使う uid。役割ごとに分けている。 */
export const UID = {
  siteAdmin: 'u-site-admin',
  listAdmin: 'u-list-admin',
  superUser: 'u-super-user',
  readOnly: 'u-read-only',
  outsider: 'u-outsider',
  // 共有リンクから「参加せずに見る」を選んだ人（仕様書 3.3）。
  viewer: 'u-viewer',
};

/** エミュレータを立ち上げ、ルールを読み込む。 */
export async function createTestEnv() {
  return initializeTestEnvironment({
    projectId: 'demo-musiclist',
    firestore: {
      rules: readFileSync('../firestore.rules', 'utf8'),
      host: '127.0.0.1',
      port: 8080,
    },
    storage: {
      rules: readFileSync('../storage.rules', 'utf8'),
      host: '127.0.0.1',
      port: 9199,
    },
  });
}

/**
 * サイト管理者としての認証コンテキスト。
 *
 * 判定は Auth のカスタムクレームで行う（仕様書 13.5）。
 */
export function asSiteAdmin(env) {
  return env.authenticatedContext(UID.siteAdmin, {
    siteAdmin: true,
    email_verified: true,
  });
}

/**
 * 通常の利用者。
 *
 * **メール確認済みとして扱う。** ルールが `email_verified` を見るため
 * （仕様書 3.1／監査 S3）、指定しないとすべて拒否される。
 */
export function asUser(env, uid) {
  return env.authenticatedContext(uid, { email_verified: true });
}

/** メール確認がまだ済んでいない利用者（3.1）。 */
export function asUnverified(env, uid) {
  return env.authenticatedContext(uid, { email_verified: false });
}

export function asAnonymous(env) {
  return env.unauthenticatedContext();
}

/**
 * ルールを迂回して、テストの前提となるデータを作る。
 *
 * メンバー登録や項目の作成は Cloud Functions が行うものも多く、
 * クライアントからは書けないため、ここで直接投入する。
 */
export async function seed(env) {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();

    await db.doc('siteConfig/global').set({
      defaultQuotaBytes: 1073741824,
      itemPurgeGraceDays: 30,
      orphanFileGraceHours: 24,
      siteAdminCount: 1,
    });

    await db.doc(`users/${UID.listAdmin}`).set({
      displayName: '管理者',
      isWithdrawn: false,
    });
    await db.doc(`users/${UID.superUser}`).set({
      displayName: '投稿者',
      isWithdrawn: false,
    });
    await db.doc(`users/${UID.readOnly}`).set({
      displayName: '閲覧者',
      isWithdrawn: false,
    });
    await db.doc(`users/${UID.outsider}`).set({
      displayName: '部外者',
      isWithdrawn: false,
    });
    await db.doc(`users/${UID.viewer}`).set({
      displayName: '見るだけの人',
      isWithdrawn: false,
    });

    // 公開してよい情報のみ（仕様書 13.2）
    await db.doc(`lists/${LIST_ID}`).set({
      name: 'テストリスト',
      nameLower: 'テストリスト',
      createdBy: UID.listAdmin,
      adminCount: 1,
      memberCount: 3,
    });
    await db.doc(`lists/${OTHER_LIST_ID}`).set({
      name: '別のリスト',
      nameLower: '別のリスト',
      createdBy: UID.outsider,
      adminCount: 1,
      memberCount: 1,
    });

    // 容量・連番などの内部情報（メンバーのみ）
    await db.doc(`lists/${LIST_ID}/meta/stats`).set({
      nextSeq: 2,
      usedBytes: 100,
      quotaBytes: 1073741824,
      notifiedNotice80: false,
      notifiedWarning90: false,
    });

    await db.doc(`lists/${LIST_ID}/members/${UID.listAdmin}`).set({
      uid: UID.listAdmin,
      role: 'listAdmin',
      via: 'founder',
    });
    await db.doc(`lists/${LIST_ID}/members/${UID.superUser}`).set({
      uid: UID.superUser,
      role: 'superUser',
      via: 'request',
    });
    await db.doc(`lists/${LIST_ID}/members/${UID.readOnly}`).set({
      uid: UID.readOnly,
      role: 'readOnly',
      via: 'invite',
    });

    // **参加せずに見るだけの人（仕様書 3.3）。**
    // メンバーではないので members には入れない。
    await db.doc(`lists/${LIST_ID}/viewers/${UID.viewer}`).set({
      uid: UID.viewer,
      viaLink: 'link-1',
    });

    await db.doc('shareLinks/link-1').set({
      listId: LIST_ID,
      role: 'readOnly',
      createdBy: UID.listAdmin,
      revoked: false,
    });

    await db.doc(`lists/${LIST_ID}/items/${ITEM_ID}`).set({
      seq: 1,
      date: '2026-08-04',
      kind: 'url',
      url: 'https://example.com/song',
      createdBy: UID.superUser,
      status: 'active',
    });

    await db
      .doc(`lists/${LIST_ID}/items/${ITEM_ID}/comments/${COMMENT_ID}`)
      .set({
        body: 'いいですね',
        parentId: null,
        path: [],
        depth: 0,
        createdBy: UID.superUser,
        status: 'active',
      });

    await db.doc('listNames/テストリスト').set({ listId: LIST_ID });

    await db.doc('listRequests/req-1').set({
      listName: '新しいリスト',
      nameLower: '新しいリスト',
      requestedBy: UID.outsider,
      status: 'pending',
    });
  });
}
