/**
 * セキュリティルールのテスト用ヘルパー（仕様書 12.6 / 13.5）
 *
 * ルールは「クライアントを信用しない最後の防波堤」なので、
 * ルール単体で検証する。エミュレータ上で動くため、本番・検証プロジェクトには
 * 一切触れない。
 */
import { readFileSync } from 'node:fs';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';

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

/**
 * エミュレータを立ち上げ、ルールを読み込む。
 *
 * **ポートはこのフォルダの firebase.json から読む。** ここに数字を
 * 直接書くと、設定を変えたときにテストだけ古いポートへ繋ぎに行く。
 * 統合テストのエミュレータと同時に走らせるため、ルート設定とは
 * 別のポートにしてある（firebase.json の //why を参照）。
 */
export async function createTestEnv() {
  const config = JSON.parse(readFileSync('../firebase.rules-test.json', 'utf8'));
  return initializeTestEnvironment({
    projectId: 'demo-musiclist',
    firestore: {
      rules: readFileSync('../firestore.rules', 'utf8'),
      host: config.emulators.firestore.host,
      port: config.emulators.firestore.port,
    },
    storage: {
      rules: readFileSync('../storage.rules', 'utf8'),
      host: config.emulators.storage.host,
      port: config.emulators.storage.port,
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
 * データが書き換わったか（＝次のテストの前に作り直しが要るか）。
 *
 * **2026-08-09 の計測から。** 124 テストが毎回 17 件のドキュメントを
 * 作り直しており、その下ごしらえだけで約 45 秒——個々の判定の合計
 * （10.6 秒）の 4 倍以上を、確かめたい内容と無関係に払っていた。
 *
 * **拒否されたテストは、データを 1 バイトも変えない。** これは約束事では
 * なく Firestore の意味論そのもの（拒否された書き込みは何も書かない）。
 * だから作り直しが要るのは、**許可された操作のあとだけ**でよい。
 *
 * 見張り：テスト本文から assertSucceeds / assertFails /
 * withSecurityRulesDisabled を直接呼ぶことは discipline.test.js が禁じて
 * いる。下の allow / deny / mutateAsAdmin を通らない書き込みが混ざると、
 * この印が嘘になるため。
 */
const state = { dirty: true };

/**
 * 許可されることを確かめる。**データが変わった印を残す。**
 *
 * 読み取りにも使うので、印は保守的（変えていなくても付く）。
 * その分の作り直しは無駄になるが、漏らすよりよい。
 */
export function allow(promise) {
  state.dirty = true;
  return assertSucceeds(promise);
}

/** 拒否されることを確かめる。拒否された操作は何も書かない。 */
export function deny(promise) {
  return assertFails(promise);
}

/** ルールを迂回してデータをいじる（テスト内の前提づくり用）。 */
export function mutateAsAdmin(env, fn) {
  state.dirty = true;
  return env.withSecurityRulesDisabled(fn);
}

/**
 * 必要なときだけ、データを作り直す。各テストの beforeEach から呼ぶ。
 *
 * [clearStorage] は Storage も消したいとき（storage.rules.test.js）。
 */
export async function maybeReseed(env, { clearStorage = false } = {}) {
  if (!state.dirty) return;
  await seed(env);
  if (clearStorage) await env.clearStorage();
  state.dirty = false;
}

/**
 * ルールを迂回して、テストの前提となるデータを作る。
 *
 * メンバー登録や項目の作成は Cloud Functions が行うものも多く、
 * クライアントからは書けないため、ここで直接投入する。
 *
 * **1 件ずつ待たず、バッチで 1 往復にする（2026-08-09）。**
 * 以前は 17 件を直列に `await` しており、124 テストぶんで約 2,100 往復、
 * 実測 62.5 秒かかっていた。バッチなら半分以下になる。
 */
export async function seed(env) {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    const batch = db.batch();
    const put = (path, data) => batch.set(db.doc(path), data);

    put('siteConfig/global', {
      defaultQuotaBytes: 1073741824,
      itemPurgeGraceDays: 30,
      orphanFileGraceHours: 24,
      siteAdminCount: 1,
    });

    put(`users/${UID.listAdmin}`, {
      displayName: '管理者',
      isWithdrawn: false,
    });
    put(`users/${UID.superUser}`, {
      displayName: '投稿者',
      isWithdrawn: false,
    });
    put(`users/${UID.readOnly}`, {
      displayName: '閲覧者',
      isWithdrawn: false,
    });
    put(`users/${UID.outsider}`, {
      displayName: '部外者',
      isWithdrawn: false,
    });
    put(`users/${UID.viewer}`, {
      displayName: '見るだけの人',
      isWithdrawn: false,
    });

    // 公開してよい情報のみ（仕様書 13.2）
    put(`lists/${LIST_ID}`, {
      name: 'テストリスト',
      nameLower: 'テストリスト',
      createdBy: UID.listAdmin,
      adminCount: 1,
      memberCount: 3,
    });
    put(`lists/${OTHER_LIST_ID}`, {
      name: '別のリスト',
      nameLower: '別のリスト',
      createdBy: UID.outsider,
      adminCount: 1,
      memberCount: 1,
    });

    // 容量・連番などの内部情報（メンバーのみ）
    put(`lists/${LIST_ID}/meta/stats`, {
      nextSeq: 2,
      usedBytes: 100,
      quotaBytes: 1073741824,
      notifiedNotice80: false,
      notifiedWarning90: false,
    });

    put(`lists/${LIST_ID}/members/${UID.listAdmin}`, {
      uid: UID.listAdmin,
      role: 'listAdmin',
      via: 'founder',
    });
    put(`lists/${LIST_ID}/members/${UID.superUser}`, {
      uid: UID.superUser,
      role: 'superUser',
      via: 'request',
    });
    put(`lists/${LIST_ID}/members/${UID.readOnly}`, {
      uid: UID.readOnly,
      role: 'readOnly',
      via: 'invite',
    });

    // **参加せずに見るだけの人（仕様書 3.3）。**
    // メンバーではないので members には入れない。
    put(`lists/${LIST_ID}/viewers/${UID.viewer}`, {
      uid: UID.viewer,
      viaLink: 'link-1',
    });

    put('shareLinks/link-1', {
      listId: LIST_ID,
      role: 'readOnly',
      createdBy: UID.listAdmin,
      revoked: false,
    });

    put(`lists/${LIST_ID}/items/${ITEM_ID}`, {
      seq: 1,
      date: '2026-08-04',
      kind: 'url',
      url: 'https://example.com/song',
      createdBy: UID.superUser,
      status: 'active',
    });

    put(`lists/${LIST_ID}/items/${ITEM_ID}/comments/${COMMENT_ID}`, {
        body: 'いいですね',
        parentId: null,
        path: [],
        depth: 0,
        createdBy: UID.superUser,
        status: 'active',
      });

    put('listNames/テストリスト', { listId: LIST_ID });

    put('listRequests/req-1', {
      listName: '新しいリスト',
      nameLower: '新しいリスト',
      requestedBy: UID.outsider,
      status: 'pending',
    });

    // **ここで初めて送る。** put は積むだけで、1 往復で全部書く。
    await batch.commit();
  });
}
