#!/usr/bin/env node
/**
 * エミュレータに動作確認用のデータを入れる
 *
 * クラウドのプロジェクトを作らなくても、画面を動かしながら開発できるようにする。
 * **エミュレータ以外には絶対に書き込まない**（環境変数が設定されていなければ中止する）。
 *
 * ```sh
 * firebase emulators:start --project demo-musiclist
 *
 * export FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9099
 * export FIRESTORE_EMULATOR_HOST=127.0.0.1:8080
 * node scripts/seed-emulator.js
 * ```
 *
 * 投入するもの:
 * - サイト設定（siteConfig/global）
 * - ユーザー 4 人（サイト管理者・リスト管理者・Super User・Read Only）
 * - リスト 1 つと、そのメンバー・項目・コメント
 *
 * ログインは Auth エミュレータの UI（http://127.0.0.1:4000/auth）から、
 * 下記のメールアドレスとパスワード `password` で行える。
 */
import { initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore } from 'firebase-admin/firestore';

// 本番・検証プロジェクトを誤って壊さないための歯止め。
if (!process.env.FIRESTORE_EMULATOR_HOST || !process.env.FIREBASE_AUTH_EMULATOR_HOST) {
  console.error('このスクリプトはエミュレータ専用です。');
  console.error('次の環境変数を設定してから実行してください。');
  console.error('  export FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9099');
  console.error('  export FIRESTORE_EMULATOR_HOST=127.0.0.1:8080');
  process.exit(1);
}

initializeApp({ projectId: 'demo-musiclist' });

const auth = getAuth();
const db = getFirestore();

const PASSWORD = 'password';

const USERS = [
  { key: 'siteAdmin', email: 'site-admin@example.com', name: 'サイト管理者', siteAdmin: true },
  { key: 'listAdmin', email: 'list-admin@example.com', name: '山田（リスト管理者）' },
  { key: 'superUser', email: 'super-user@example.com', name: '佐藤（Super User）' },
  { key: 'readOnly', email: 'read-only@example.com', name: '鈴木（Read Only）' },
];

const LIST_ID = 'demo-list';

async function ensureUser({ email, name, siteAdmin }) {
  let user = await auth.getUserByEmail(email).catch(() => null);
  if (!user) {
    user = await auth.createUser({
      email,
      password: PASSWORD,
      displayName: name,
      emailVerified: true, // メール確認済みの状態にしておく（仕様書 3.1）
    });
  }
  if (siteAdmin) {
    await auth.setCustomUserClaims(user.uid, { siteAdmin: true });
  }
  await db.doc(`users/${user.uid}`).set({
    displayName: name,
    email,
    locale: 'ja',
    isWithdrawn: false,
    notificationSettings: {
      master: true,
      types: {
        itemAdded: { inApp: true, push: true },
        commentAdded: { inApp: true, push: true },
        quotaNotice: { inApp: true, push: true },
        quotaWarning: { inApp: true, push: true },
        listRequested: { inApp: true, push: true },
        joinRequested: { inApp: true, push: true },
        requestApproved: { inApp: true, push: true },
      },
    },
    createdAt: new Date(),
    updatedAt: new Date(),
  });
  return user.uid;
}

async function main() {
  const uids = {};
  for (const user of USERS) {
    uids[user.key] = await ensureUser(user);
  }

  await db.doc('siteConfig/global').set({
    inviteExpiryHours: 24,
    defaultQuotaBytes: 1073741824,
    itemPurgeGraceDays: 30,
    orphanFileGraceHours: 24,
    siteAdminCount: 1,
  });

  // 公開可能な情報のみ（仕様書 13.2）
  await db.doc(`lists/${LIST_ID}`).set({
    name: '練習音源',
    nameLower: '練習音源',
    createdBy: uids.listAdmin,
    adminCount: 1,
    memberCount: 3,
    createdAt: new Date(),
    updatedAt: new Date(),
  });
  await db.doc('listNames/練習音源').set({ listId: LIST_ID, reservedAt: new Date() });

  // 内部情報（メンバーのみ）
  await db.doc(`lists/${LIST_ID}/meta/stats`).set({
    nextSeq: 4,
    usedBytes: 0,
    quotaBytes: 1073741824,
    notifiedNotice80: false,
    notifiedWarning90: false,
  });

  await db.doc(`lists/${LIST_ID}/members/${uids.listAdmin}`).set({
    role: 'listAdmin',
    via: 'founder',
    joinedAt: new Date(),
  });
  await db.doc(`lists/${LIST_ID}/members/${uids.superUser}`).set({
    role: 'superUser',
    via: 'request',
    joinedAt: new Date(),
    addedBy: uids.listAdmin,
  });
  await db.doc(`lists/${LIST_ID}/members/${uids.readOnly}`).set({
    role: 'readOnly',
    via: 'invite',
    joinedAt: new Date(),
    addedBy: uids.listAdmin,
  });

  // 項目。連番は 1 から、削除済みは欠番として残す（仕様書 6.2）
  const items = [
    {
      id: 'item-1',
      seq: 1,
      date: '2026-07-15',
      kind: 'url',
      url: 'https://www.youtube.com/watch?v=example',
      title: '夏の思い出',
      artist: 'サザンオールスターズ',
      createdBy: uids.superUser,
      status: 'active',
    },
    {
      id: 'item-2',
      seq: 2,
      date: '2026-08-01',
      kind: 'file',
      file: {
        storagePath: `lists/${LIST_ID}/items/item-2/take01.mp3`,
        fileName: 'take01.mp3',
        sizeBytes: 5242880,
        contentType: 'audio/mpeg',
      },
      createdBy: uids.listAdmin,
      status: 'active',
    },
    {
      // 削除済み。一覧には「削除されました」と出て、連番 3 は欠番のまま残る。
      id: 'item-3',
      seq: 3,
      date: '2026-08-02',
      kind: 'file',
      file: {
        storagePath: `lists/${LIST_ID}/items/item-3/old.mp3`,
        fileName: 'old.mp3',
        sizeBytes: 3145728,
        contentType: 'audio/mpeg',
      },
      createdBy: uids.superUser,
      status: 'deleted',
      deletedBy: uids.listAdmin,
      deletedAt: new Date(),
      purgeAt: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000),
    },
  ];

  for (const { id, ...data } of items) {
    await db.doc(`lists/${LIST_ID}/items/${id}`).set({
      ...data,
      createdAt: new Date(),
      updatedAt: new Date(),
    });
  }

  // コメント。無制限の入れ子を確認できるよう 3 段にしておく（仕様書 9）
  const comments = [
    { id: 'c1', body: 'これ良い演奏ですね', parentId: null, path: [], depth: 0, createdBy: uids.listAdmin },
    { id: 'c2', body: 'ありがとうございます', parentId: 'c1', path: ['c1'], depth: 1, createdBy: uids.superUser },
    { id: 'c3', body: 'サビのところをもう一度録りたいです', parentId: 'c2', path: ['c1', 'c2'], depth: 2, createdBy: uids.superUser },
    { id: 'c4', body: '別のテイクも上げておきます', parentId: null, path: [], depth: 0, createdBy: uids.superUser },
  ];

  for (const { id, ...data } of comments) {
    await db.doc(`lists/${LIST_ID}/items/item-1/comments/${id}`).set({
      ...data,
      status: 'active',
      createdAt: new Date(),
      updatedAt: new Date(),
    });
  }

  console.log('エミュレータにデータを投入しました。');
  console.log('');
  console.log('ログイン用アカウント（パスワードはすべて password）:');
  for (const user of USERS) {
    console.log(`  ${user.email.padEnd(28)} ${user.name}`);
  }
  console.log('');
  console.log(`リスト: 練習音源（${LIST_ID}）／項目 3 件（うち 1 件は削除済み）／コメント 4 件`);
}

main().then(
  () => process.exit(0),
  (error) => {
    console.error('失敗しました:', error.message);
    process.exit(1);
  },
);
