#!/usr/bin/env node
/**
 * 容量の上限を「人ごとの合計」へ変える前に、影響を受ける人を数える
 *
 *   node scripts/check-quota-impact.mjs --project music-storage-d79b2 --key <鍵.json>
 *
 * **読むだけです。何も書き換えません。**
 *
 * ---
 *
 * ## なぜ要るか
 *
 * いま容量は**リストごとに 1GB**（既定）です。これを
 * **人ごとの合計 2GB** へ変えると、持っているリストの数で有利不利が
 * 変わります。
 *
 * | 持っているリスト | いま使える量 | 変更後 |
 * | --- | --- | --- |
 * | 1 個 | 1GB | 2GB（増える） |
 * | 2 個 | 2GB | 2GB（同じ） |
 * | 3 個以上 | 3GB 以上 | **2GB（減る）** |
 *
 * **昨日までアップロードできた人が、今日からできなくなる**ことが
 * 起こり得ます（docs/AUDIT-CHECKLIST.md 観点 6「既存利用者が使えなく
 * なる変更は無いか」）。ファイルは消えませんが、追加が止まります。
 *
 * **配信の前に、該当者がいないことを数えてください。**
 * いれば、その人にだけ上限を足す（サイト管理の setUserQuota）などの
 * 手当てが要ります。
 */
import { existsSync } from 'node:fs';

import { initializeApp, applicationDefault } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';

const args = process.argv.slice(2);
const option = (name) => {
  const i = args.indexOf(`--${name}`);
  return i >= 0 ? args[i + 1] : undefined;
};

const projectId = option('project') ?? process.env.GCLOUD_PROJECT;
const keyPath = option('key');

/** 変更後の上限（人ごとの合計）。docs/PREMIUM-DESIGN.md と合わせる。 */
const NEW_QUOTA_BYTES = 2 * 1024 * 1024 * 1024;

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

initializeApp({ credential: applicationDefault(), projectId });
const db = getFirestore();

const mib = (bytes) => `${(bytes / 1024 / 1024).toFixed(1)} MB`;

console.log(`プロジェクト: ${projectId ?? '(エミュレータ)'}`);
console.log('**読むだけです。何も書き換えません。**');
console.log('');

const lists = await db.collection('lists').get();

/** 作った人ごとに、リストの数と使用量を集める。 */
const byOwner = new Map();

for (const list of lists.docs) {
  const owner = list.get('createdBy');
  // 作った人が分からないリストは、手当ての判断ができないので別に出す。
  const key = typeof owner === 'string' && owner ? owner : '(createdBy なし)';

  const stats = await db.doc(`lists/${list.id}/meta/stats`).get();
  const used = Number(stats.get('usedBytes') ?? 0);
  const quota = Number(stats.get('quotaBytes') ?? 0);

  const entry = byOwner.get(key) ?? { lists: 0, used: 0, quota: 0, names: [] };
  entry.lists += 1;
  entry.used += used;
  entry.quota += quota;
  entry.names.push(list.get('name') ?? list.id);
  byOwner.set(key, entry);
}

console.log(`リスト: ${lists.size} 件 / 作った人: ${byOwner.size} 人`);
console.log('');

// **減る人と、すでに超えている人を分けて出す。**
// 「上限が減る」だけならまだ猶予があるが、「すでに超えている」人は
// 配信した瞬間にアップロードできなくなる。
const shrinking = [];
const overflowing = [];

for (const [uid, e] of byOwner) {
  if (e.quota > NEW_QUOTA_BYTES) shrinking.push([uid, e]);
  if (e.used > NEW_QUOTA_BYTES) overflowing.push([uid, e]);
}

if (overflowing.length > 0) {
  console.log('=== すでに新しい上限を超えている人（配信した瞬間に追加できなくなります） ===');
  for (const [uid, e] of overflowing) {
    console.log(`  ${uid}  リスト ${e.lists} 個 / 使用 ${mib(e.used)}（新上限 ${mib(NEW_QUOTA_BYTES)}）`);
    console.log(`    ${e.names.join(' / ')}`);
  }
  console.log('');
}

if (shrinking.length > 0) {
  console.log('=== 使える量が減る人（いまは超えていません） ===');
  for (const [uid, e] of shrinking) {
    console.log(`  ${uid}  リスト ${e.lists} 個 / いまの上限 合計 ${mib(e.quota)} → ${mib(NEW_QUOTA_BYTES)}`);
  }
  console.log('');
}

if (overflowing.length === 0 && shrinking.length === 0) {
  console.log('該当者はいません。そのまま配信して構いません。');
} else {
  console.log('--- 手当ての候補 ---');
  console.log('  1. その人にだけ上限を足す（サイト管理の「容量を変える」／setUserQuota）');
  console.log('  2. 移行のあいだ、上限を「合計 2GB か、リスト数×1GB の大きいほう」にする');
  console.log('');
  console.log('**ファイルは消えません。** 追加が止まるだけです（docs/PREMIUM-DESIGN.md）。');
}

process.exit(overflowing.length > 0 ? 1 : 0);
