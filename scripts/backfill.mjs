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
 *
 * ### 3. joinRequests に uid を足す（監査 第2回）
 *
 * members とまったく同じ理由。自分の参加申請一覧は
 * `collectionGroup('joinRequests').where('uid', ...)` で引くため、
 * uid の無い行は**申請者からも見えず、ルールの判定にも合致しない**。
 * アプリの中に復旧手段が無い。
 *
 * ### 4. stats が無いリストを作る（監査 第2回）
 *
 * stats が無いと項目追加のトランザクションが NOT_FOUND で失敗し、
 * **そのリストには曲を 1 曲も追加できない**。以前は「無い」ことを
 * 報告するだけで直していなかった。
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

/// stats を新しく作るときの容量上限（siteConfig の既定と揃える）。
const DEFAULT_QUOTA_BYTES = 1073741824; // 1GB

async function main() {
  const lists = await db.collection('lists').get();
  console.log(`リスト: ${lists.size} 件`);

  let memberFixed = 0;
  let memberOk = 0;
  let statsFixed = 0;
  let joinRequestFixed = 0;
  let statsCreated = 0;

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

    // --- 3. joinRequests に uid を足す ---
    // members と同じ理由。無いと申請者本人の一覧に出ない。
    const joinRequests = await list.ref.collection('joinRequests').get();
    for (const request of joinRequests.docs) {
      if (request.data().uid === request.id) continue;
      console.log(`  uid を追加: ${request.ref.path}`);
      if (!dryRun) await request.ref.update({ uid: request.id });
      joinRequestFixed++;
    }

    // --- 2. stats に itemCount を入れる ---
    // 削除済み（status === 'deleted'）は数えない（仕様書 6.2）。
    const items = await list.ref.collection('items').get();
    const itemCount = items.docs.filter(
      (doc) => doc.data().status !== 'deleted'
    ).length;

    const statsRef = list.ref.collection('meta').doc('stats');
    const stats = await statsRef.get();

    // **無ければ作る。** 以前は報告するだけで飛ばしていたが、stats が
    // 無いリストは項目追加のトランザクションが失敗するため、
    // **曲を 1 曲も追加できない**（監査 第2回）。
    if (!stats.exists) {
      const nextSeq = items.empty
        ? 1
        : Math.max(
            ...items.docs.map((doc) => Number(doc.data().seq) || 0)
          ) + 1;
      console.log(
        `  stats を作成: ${list.id}（itemCount=${itemCount} nextSeq=${nextSeq}）`
      );
      if (!dryRun) {
        await statsRef.set({
          itemCount,
          nextSeq,
          usedBytes: 0,
          quotaBytes: DEFAULT_QUOTA_BYTES,
        });
      }
      statsCreated++;
      continue;
    }
    if (stats.data()?.itemCount === itemCount) continue;

    console.log(`  itemCount を設定: ${list.id} → ${itemCount}`);
    if (!dryRun) await statsRef.update({ itemCount });
    statsFixed++;
  }

  console.log('');
  console.log('結果');
  console.log(`  members に uid を追加      : ${memberFixed} 件（すでに正しい: ${memberOk} 件）`);
  console.log(`  joinRequests に uid を追加 : ${joinRequestFixed} 件`);
  console.log(`  stats の itemCount         : ${statsFixed} 件`);
  console.log(`  stats を新しく作成         : ${statsCreated} 件`);
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
