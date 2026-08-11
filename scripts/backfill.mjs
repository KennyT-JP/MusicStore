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
 * ### 5. users に容量の合計を入れる（2026-08-11・プレミアム対応）
 *
 * 容量の上限を**リストごと**から**人ごとの合計**へ変えた
 * （docs/PREMIUM-DESIGN.md）。集計はファイルの保存・削除のたびに
 * 加減算する形なので、**この変更より前からあるファイルは合計に
 * 入っていない**。入れておかないと、実際には使っているのに
 * 「0 バイト使用」と見え、上限をすり抜ける。
 *
 * 各リストの `stats.usedBytes` を、そのリストを作った人ごとに合計して
 * `users/{uid}.storage.usedBytes` に入れる。**毎回ゼロから数え直す**ので、
 * 何度実行しても同じ結果になる。
 *
 * ### 4. stats が無いリストを作る（監査 第2回）
 *
 * stats が無いと項目追加のトランザクションが NOT_FOUND で失敗し、
 * **そのリストには曲を 1 曲も追加できない**。以前は「無い」ことを
 * 報告するだけで直していなかった。
 */
import { existsSync } from 'node:fs';
import { join } from 'node:path';

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


// gcloud で用意した資格情報（ADC）があれば、鍵のファイルは要らない。
// firebase-admin の applicationDefault() が、この場所を自動で見る。
const adcPath = process.platform === 'win32'
  ? join(process.env.APPDATA ?? '', 'gcloud', 'application_default_credentials.json')
  : join(process.env.HOME ?? '', '.config', 'gcloud', 'application_default_credentials.json');
const hasAdc = existsSync(adcPath);
const usingEmulator = Boolean(process.env.FIRESTORE_EMULATOR_HOST);

if (!usingEmulator) {
  if (!process.env.GOOGLE_APPLICATION_CREDENTIALS && !hasAdc) {
    // **鍵のファイルを作らなくてもよい。**
    // `gcloud auth application-default login` を一度実行しておけば、
    // その資格情報を firebase-admin が自動で拾う（applicationDefault）。
    // 長く残る鍵をパソコンに置かずに済むので、こちらを先に案内する。
    console.error('この操作には、プロジェクトを操作できる資格情報が要ります。');
    console.error('');
    console.error('  【おすすめ】鍵のファイルを作らない方法');
    console.error('    gcloud auth application-default login');
    console.error('    （ブラウザが開くので、プロジェクトを操作できる Google アカウントで許可します）');
    console.error('');
    console.error('  【別の方法】サービスアカウントの鍵を使う');
    console.error('    Firebase コンソール → プロジェクトの設定 → サービス アカウント');
    console.error('    → 「新しい秘密鍵の生成」で JSON を保存し、--key <保存先> を付けます');
    console.error('    **その JSON は誰にも渡さず、リポジトリにも置かないでください。**');
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
  let storageFixed = 0;
  let storageOk = 0;
  let ownerless = 0;
  let missingUser = 0;

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

  // ---------------------------------------------------------------------
  // 5. users に容量の合計を入れる（プレミアム対応）
  //
  // **毎回ゼロから数え直す。** 差分を足す作りにすると、途中で失敗した
  // ときに二重に足さる。数え直しなら、何度実行しても同じ結果になる。
  // ---------------------------------------------------------------------

  /** 既定の上限（人ごとの合計）。docs/PREMIUM-DESIGN.md と合わせる。 */
  const USER_DEFAULT_QUOTA_BYTES = 2 * 1024 * 1024 * 1024;

  const usedByOwner = new Map();
  for (const list of lists.docs) {
    const owner = list.get('createdBy');
    // 作った人が分からないリストは、誰の枠にも入れられない。
    // 黙って捨てると合計が合わなくなるので、数えて報告する。
    if (typeof owner !== 'string' || !owner) {
      ownerless++;
      continue;
    }
    const stats = await db.doc(`lists/${list.id}/meta/stats`).get();
    const used = Number(stats.get('usedBytes') ?? 0);
    usedByOwner.set(owner, (usedByOwner.get(owner) ?? 0) + used);
  }

  for (const [uid, used] of usedByOwner) {
    const userRef = db.doc(`users/${uid}`);
    const user = await userRef.get();
    if (!user.exists) {
      // リストは作ったが users が無い人。触らずに報告だけする。
      missingUser++;
      continue;
    }

    const storage = user.get('storage') ?? {};
    const base = Number(storage.quotaBytesBase ?? USER_DEFAULT_QUOTA_BYTES);
    // 実効値は、すでに自動拡張されていればそれを尊重する。
    const quota = Number(storage.quotaBytes ?? base);

    if (Number(storage.usedBytes ?? -1) === used
        && Number(storage.quotaBytesBase ?? -1) === base
        && Number(storage.quotaBytes ?? -1) === quota) {
      storageOk++;
      continue;
    }

    console.log(`  合計容量を設定: ${uid} → ${(used / 1024 / 1024).toFixed(1)} MB`);
    if (!dryRun) {
      await userRef.set(
        { storage: { usedBytes: used, quotaBytes: quota, quotaBytesBase: base } },
        { merge: true },
      );
    }
    storageFixed++;
  }

  console.log('');
  console.log('結果');
  console.log(`  members に uid を追加      : ${memberFixed} 件（すでに正しい: ${memberOk} 件）`);
  console.log(`  joinRequests に uid を追加 : ${joinRequestFixed} 件`);
  console.log(`  stats の itemCount         : ${statsFixed} 件`);
  console.log(`  stats を新しく作成         : ${statsCreated} 件`);
  console.log(`  users の合計容量           : ${storageFixed} 件（すでに正しい: ${storageOk} 人）`);
  if (ownerless > 0) console.log(`  ** 作った人が不明のリスト  : ${ownerless} 件（合計に入れていません）**`);
  if (missingUser > 0) console.log(`  ** users が無い作成者      : ${missingUser} 人（触っていません）**`);
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
