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

const options = [
  'emulators:exec',
  '--project',
  'demo-musiclist',
  '--only',
  'firestore,storage',
];

// エミュレータを立ち上げたうえで実行させたいコマンド。
// **空白を含む 1 つの引数**として firebase へ渡す必要がある。
const script = 'vitest run';

/**
 * Windows と、それ以外で起動の仕方を分ける。
 *
 * Windows の firebase は `firebase.cmd` というバッチファイルで、
 * Node からは shell を通さないと起動できない。ところが shell を使うと、
 * 引数は**そのまま連結されるだけで引用符が付かない**。
 * `vitest run` が 2 つの引数として渡り、
 * 「Too many arguments」で止まっていた。
 *
 * そこで Windows では、こちらで引用符まで含めた 1 本の文字列を組み立てる。
 * 引数の配列と shell を同時に使わないので、Node の DEP0190 警告も出ない。
 */
const isWindows = process.platform === 'win32';

const child = isWindows
  ? spawn(`firebase ${options.join(' ')} "${script}"`, {
      stdio: 'inherit',
      env,
      shell: true,
    })
  : spawn('firebase', [...options, script], { stdio: 'inherit', env });

child.on('error', (error) => {
  console.error('firebase コマンドを起動できませんでした:', error.message);
  console.error('npm install -g firebase-tools で導入してください。');
  process.exit(1);
});
child.on('exit', (code) => process.exit(code ?? 1));
