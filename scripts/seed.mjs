#!/usr/bin/env node
/**
 * 動作確認用のデータをエミュレータに入れる
 *
 *   ./scripts/seed.sh   （macOS / Linux）
 *   scripts\seed.cmd    （Windows）
 *
 * エミュレータが起動している状態で実行してください。
 *
 * 処理の本体をここに置いている理由は dev-emulators.mjs の冒頭を参照。
 */
import { spawn } from 'node:child_process';
import { existsSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const isWindows = process.platform === 'win32';

function run(command, args, options = {}) {
  return new Promise((resolve) => {
    // Windows では npm の実体が npm.cmd なので shell 経由で起動する。
    const child = spawn(command, args, { stdio: 'inherit', shell: isWindows, ...options });
    child.on('error', () => resolve(null));
    child.on('close', (code) => resolve(code));
  });
}

if (!existsSync(join(here, 'node_modules'))) {
  console.log('==> 依存パッケージを取得');
  const code = await run('npm', ['install'], { cwd: here });
  if (code !== 0) {
    console.error('\n[エラー] npm install に失敗しました。');
    process.exit(1);
  }
}

const code = await run('node', ['seed-emulator.js'], {
  cwd: here,
  env: {
    ...process.env,
    FIREBASE_AUTH_EMULATOR_HOST: '127.0.0.1:9099',
    FIRESTORE_EMULATOR_HOST: '127.0.0.1:8080',
  },
});

if (code !== 0) {
  console.error('\n[エラー] データの投入に失敗しました。');
  console.error('         エミュレータが起動しているか確認してください。');
  console.error('         確認: node scripts/doctor.mjs');
}

process.exit(code ?? 1);
