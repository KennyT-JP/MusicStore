#!/usr/bin/env node
/**
 * セキュリティルールのテストを実行する（仕様書 12.6）
 *
 *   cd rules-test
 *   npm test
 *
 * ---
 *
 * ## なぜ素の npm スクリプトではなく .mjs なのか
 *
 * 1. **`JAVA_TOOL_OPTIONS` を消す必要がある。**
 *    値が空でも、変数が設定されているだけで JVM は起動時に
 *    `Picked up JAVA_TOOL_OPTIONS: ` を標準エラーへ出す。Storage エミュレータの
 *    ルールランタイムはその 1 行を解釈できずに落ち、`firestore.exists()` を
 *    使う判定がすべて不許可になる。**空にするのでは足りず、変数ごと消す。**
 *
 * 2. **Windows でも同じ手順で動かせるようにする。**
 *    `JAVA_TOOL_OPTIONS= firebase ...` という書き方は cmd.exe では動かない。
 *    このプロジェクトでは、処理を .mjs に寄せる方針にしている（SETUP.md）。
 */
import { spawn } from 'node:child_process';

const env = { ...process.env };
delete env.JAVA_TOOL_OPTIONS;

const args = [
  'emulators:exec',
  '--project',
  'demo-musiclist',
  '--only',
  'firestore,storage',
  'vitest run',
];

// Windows では firebase は firebase.cmd なので shell 経由で起動する。
const child = spawn('firebase', args, {
  stdio: 'inherit',
  env,
  shell: process.platform === 'win32',
});

child.on('error', (error) => {
  console.error('firebase コマンドを起動できませんでした:', error.message);
  console.error('npm install -g firebase-tools で導入してください。');
  process.exit(1);
});
child.on('exit', (code) => process.exit(code ?? 1));
