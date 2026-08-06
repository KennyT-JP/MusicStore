#!/usr/bin/env node
/**
 * 既存データの手当て（2026-08-06 の監査対応にともなう移行）
 *
 *   node scripts/backfill.mjs --project music-storage-dev --key <鍵.json>
 *   node scripts/backfill.mjs --project music-storage-dev --key <鍵.json> --dry-run
 *
 * **配信の直後に 1 度だけ実行してください。** 何度実行しても安全です。
 *
 * ---
 *
 * ## 何をするか
 *
 * ### 1. members に uid を足す（監査 S14）
 *
 * 退会時に「その人が参加しているリスト」を引くために、メンバーの
 * ドキュメントへ uid を持たせるようにした。collectionGroup を
 * documentId() で引くには完全なドキュメントパスが必要で、素の uid では
 * 引けないため。**この変更より前に作られたメンバーには uid が無く、
 * そのままでは退会してもリストから外れない。**
 *
 * ### 2. stats に itemCount を入れる（監査 S6）
 *
 * ホーム画面が件数表示のためだけに全項目を購読していたのをやめ、
 * サーバー側が持つ値を使うようにした。**既存のリストには itemCount が
 * 無いため、入れておかないと項目があっても 0 件と表示される。**
 */
import { existsSync } from 'node:fs';

import { initializeApp, applicationDefault } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';

const args = process.argv.slice(2);
const option = (name) => {
  const i = args.indexOf(`--${name}`);
  return i >= 0 ? args[i + 1] : undefined;
};

const dryRun = args.includes('--dry-run');
const projectId = option('project') ?? process.env.GCLOUD_PROJECT;
const keyPath = option('key');

if (keyPath) {
  if (!existsSync(keyPath)) {
    console.error(`鍵のファイルが見つかりません: ${keyPath}`);
    process.exit(1);
  }
  process.env.GOOGLE_APPLICATION_CREDENTIALS = keyPath;
}

const usingEmulator = Boolean(process.env.FIRESTORE_EMULATOR_HOST);

if (!usingEmulator) {
  if (!process.env.GOOGLE_APPLICATION_CREDENTIALS) {
    console.error('サービスアカウント鍵が指定されていません。--key <鍵のパス> を付けてください。');
    process.exit(1);
  }
  if (!projectId) {
    console.error('プロジェクト ID が指定されていません。--project を付けてください。');
    process.exit(1);
  }
}

console.log(`プロジェクト: ${projectId ?? '(エミュレータ)'}`);
if (dryRun) console.log('*** 下見だけ行います（--dry-run）。書き込みません。***');
console.log('');

initializeApp({
  projectId,
  ...(usingEmulator ? {} : { credential: applicationDefault() }),
});

const db = getFirestore();

async function main() {
  const lists = await db.collection('lists').get();
  console.log(`リスト: ${lists.size} 件`);

  let memberFixed = 0;
  let memberOk = 0;
  let statsFixed = 0;

  for (const list of lists.docs) {
    // --- 1. members に uid を足す ---
    const members = await list.ref.collection('members').get();
    for (const member of members.docs) {
      if (member.data().uid === member.id) {
        memberOk++;
        continue;
      }
      console.log(`  uid を追加: ${member.ref.path}`);
      if (!dryRun) await member.ref.update({ uid: member.id });
      memberFixed++;
    }

    // --- 2. stats に itemCount を入れる ---
    // 削除済み（status === 'deleted'）は数えない（仕様書 6.2）。
    const items = await list.ref.collection('items').get();
    const itemCount = items.docs.filter(
      (doc) => doc.data().status !== 'deleted'
    ).length;

    const statsRef = list.ref.collection('meta').doc('stats');
    const stats = await statsRef.get();

    if (!stats.exists) {
      console.log(`  ! stats が無いため飛ばします: ${list.id}`);
      continue;
    }
    if (stats.data()?.itemCount === itemCount) continue;

    console.log(`  itemCount を設定: ${list.id} → ${itemCount}`);
    if (!dryRun) await statsRef.update({ itemCount });
    statsFixed++;
  }

  console.log('');
  console.log('結果');
  console.log(`  members に uid を追加 : ${memberFixed} 件（すでに正しい: ${memberOk} 件）`);
  console.log(`  stats の itemCount    : ${statsFixed} 件`);
  if (dryRun) console.log('\n下見のみでした。実行するには --dry-run を外してください。');
}

main().then(
  () => process.exit(0),
  (error) => {
    console.error('\n失敗しました:', error.message);
    if (error.code) console.error('  コード:', error.code);
    process.exit(1);
  }
);
