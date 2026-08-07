#!/usr/bin/env node
/**
 * 統合テスト用にエミュレータを起動する（仕様書 12.6）
 *
 *   cd functions
 *   npm run serve
 *
 * ---
 *
 * ## なぜ素の npm スクリプトではなく .mjs なのか
 *
 * 1. **関数の中身を調べる工程には制限時間がある。**
 *    firebase-tools は起動時にこのコードを一度読み込み、どんな関数が
 *    あるかを聞き出す。既定の待ち時間は **10 秒**しかない。
 *    Node の版が `package.json` の指定（22）と違うときや、初回の
 *    読み込みが遅いときにここを超え、こう出て**関数が 1 つも
 *    読み込まれないまま**エミュレータが立ち上がる。
 *
 *    ```
 *    !!  functions: Failed to load function definition from source:
 *        Cannot determine backend specification. Timeout after 10000.
 *    ```
 *
 *    **この状態でも `All emulators ready!` は出る。** そのため気づかず
 *    統合テストへ進み、「プロジェクト ID が違う」という別の原因を
 *    疑うことになった（2026-08-07）。時間を延ばして起きなくする。
 *
 * 2. **`--project demo-musiclist` の付け忘れを構造的に防ぐ。**
 *    付け忘れると `.firebaserc` の既定（検証環境）で立ち上がり、
 *    関数の URL もカスタムクレームの付与先も噛み合わなくなる。
 *
 * 3. **Windows でも同じ手順で動かせるようにする。**
 *    `FUNCTIONS_DISCOVERY_TIMEOUT=120 firebase ...` という書き方は
 *    cmd.exe では動かない。処理を .mjs に寄せる方針にしている（SETUP.md）。
 */
import { spawn } from 'node:child_process';
import { dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const isWindows = process.platform === 'win32';

/** このテストが相手にする架空のプロジェクト。 */
const PROJECT = 'demo-musiclist';

/** 統合テストが必要とするエミュレータ。 */
const ONLY = 'functions,firestore,auth,storage,pubsub';

const env = {
  ...process.env,
  // 既定の 10 秒では足りないことがある（上の 1 参照）。
  FUNCTIONS_DISCOVERY_TIMEOUT: process.env.FUNCTIONS_DISCOVERY_TIMEOUT ?? '120',
};

function run(command, args) {
  return new Promise((resolve) => {
    // **Windows では 1 本の文字列で渡す。** 配列と shell:true を混ぜると
    // 引用符が付かずに連結され、引数が壊れる（監査で実際に起きた）。
    const child = isWindows
      ? spawn([command, ...args].join(' '), {
          stdio: 'inherit',
          cwd: here,
          shell: true,
          env,
        })
      : spawn(command, args, { stdio: 'inherit', cwd: here, env });
    child.on('error', () => resolve(null));
    child.on('close', resolve);
  });
}

const build = await run('npm', ['run', 'build']);
if (build !== 0) {
  console.error('\nビルドに失敗しました。エミュレータは起動しません。');
  process.exit(1);
}

console.log(`\n==> エミュレータを起動（プロジェクト: ${PROJECT}）`);
console.log(`    関数の読み取り待ち時間: ${env.FUNCTIONS_DISCOVERY_TIMEOUT} 秒`);
console.log('');
console.log('    **出力に次が出ていないか確かめてください。**');
console.log('    「Failed to load function definition from source」');
console.log('    出ていたら関数が 1 つも読み込まれておらず、');
console.log('    All emulators ready! が出ていても統合テストは通りません。');
console.log('');

const code = await run('firebase', [
  'emulators:start',
  '--project',
  PROJECT,
  '--only',
  ONLY,
]);

if (code === null) {
  console.error('\nfirebase コマンドが見つかりません。');
  console.error('  npm install -g firebase-tools');
  process.exit(1);
}
process.exit(code ?? 0);
