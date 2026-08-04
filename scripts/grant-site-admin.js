#!/usr/bin/env node
/**
 * 最初のサイト管理者を登録する（仕様書 4.4）
 *
 * サイト管理者は Auth のカスタムクレームで判定する（仕様書 13.5）。
 * 最初の 1 人だけは、アプリ内から設定する手段がないため手作業で付与する。
 * 2 人目以降はアプリのサイト管理画面から昇格できる。
 *
 * ```sh
 * # クラウドのプロジェクトに対して実行する場合
 * export GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json
 * node scripts/grant-site-admin.js <UID>
 *
 * # ローカルのエミュレータに対して実行する場合
 * export FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9099
 * export FIRESTORE_EMULATOR_HOST=127.0.0.1:8080
 * node scripts/grant-site-admin.js <UID> --project demo-musiclist
 * ```
 *
 * 実行後、対象のユーザーは**再ログインが必要**。カスタムクレームは
 * 認証トークンに埋め込まれるため、トークンを取り直すまで反映されない。
 */
import { initializeApp, applicationDefault } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';

const args = process.argv.slice(2);
const uid = args.find((a) => !a.startsWith('--'));
const projectIndex = args.indexOf('--project');
const projectId =
  projectIndex >= 0 ? args[projectIndex + 1] : process.env.GCLOUD_PROJECT;

if (!uid) {
  console.error(
    '使い方: node scripts/grant-site-admin.js <UID> [--project <プロジェクト ID>]',
  );
  process.exit(1);
}

const usingEmulator = Boolean(process.env.FIREBASE_AUTH_EMULATOR_HOST);

initializeApp({
  projectId,
  // エミュレータでは認証情報が不要。
  ...(usingEmulator ? {} : { credential: applicationDefault() }),
});

const auth = getAuth();
const db = getFirestore();

async function main() {
  const user = await auth.getUser(uid).catch(() => null);
  if (!user) {
    console.error(`UID ${uid} のユーザーが見つかりません。`);
    console.error('先にアプリでサインアップし、Authentication で UID を確認してください。');
    process.exit(1);
  }

  const existing = user.customClaims ?? {};
  if (existing.siteAdmin === true) {
    console.log(`${uid}（${user.email ?? 'メール未設定'}）はすでにサイト管理者です。`);
    return;
  }

  // 他のクレームを消さないよう、既存のものに足す形にする。
  await auth.setCustomUserClaims(uid, { ...existing, siteAdmin: true });

  // siteConfig を作成し、サイト管理者の人数を反映する（仕様書 4.5 / 13.3）。
  const configRef = db.doc('siteConfig/global');
  const snapshot = await configRef.get();
  if (snapshot.exists) {
    await configRef.update({ siteAdminCount: FieldValue.increment(1) });
  } else {
    await configRef.set({
      inviteExpiryHours: 24,
      defaultQuotaBytes: 1073741824,
      itemPurgeGraceDays: 30,
      orphanFileGraceHours: 24,
      siteAdminCount: 1,
    });
    console.log('siteConfig/global を初期値で作成しました。');
  }

  console.log(`${uid}（${user.email ?? 'メール未設定'}）をサイト管理者にしました。`);
  console.log('');
  console.log('※ 反映には再ログインが必要です。');
  console.log('  カスタムクレームは認証トークンに埋め込まれるため、');
  console.log('  トークンを取り直すまでアプリ側では権限が変わりません。');
}

main().then(
  () => process.exit(0),
  (error) => {
    console.error('失敗しました:', error.message);
    process.exit(1);
  },
);
