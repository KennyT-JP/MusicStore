#!/usr/bin/env node
/**
 * クラウドの Firebase プロジェクトへデプロイする（仕様書 12.2）
 *
 *   ./scripts/deploy.sh            検証環境（既定）
 *   ./scripts/deploy.sh prod       本番環境（確認を求める）
 *
 *   scripts\deploy.cmd             Windows も同じ
 *
 * 実行前に一度だけ `firebase login` と `flutterfire configure` が必要です。
 * 何が足りないかは、このスクリプトが実行前に調べて教えます。
 *
 * 処理の本体をここに置いている理由は dev-emulators.mjs の冒頭を参照。
 */
import { spawn } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { createInterface } from 'node:readline/promises';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const isWindows = process.platform === 'win32';

// -------------------------------------------------------------------------
// 引数

const argv = process.argv.slice(2);
const wantsProd = argv.includes('prod');
const skipConfirm = argv.includes('--yes');

/** デプロイ先。.firebaserc のエイリアスと対応する。 */
const target = wantsProd
  ? { alias: 'prod', label: '本番環境', optionsFile: 'firebase_options_prod.dart', dartDefine: ['--dart-define=APP_ENV=prod'] }
  : { alias: 'staging', label: '検証環境', optionsFile: 'firebase_options_staging.dart', dartDefine: [] };

// -------------------------------------------------------------------------
// 部品

function run(command, args, options = {}) {
  return new Promise((resolve) => {
    // Windows では firebase / flutter の実体が .bat や .cmd なので shell 経由で起動する。
    const child = spawn(command, args, { stdio: 'inherit', shell: isWindows, cwd: root, ...options });
    child.on('error', () => resolve(null));
    child.on('close', (code) => resolve(code));
  });
}

function capture(command, args) {
  return new Promise((resolve) => {
    const child = spawn(command, args, { shell: isWindows, cwd: root });
    let out = '';
    child.stdout?.on('data', (d) => (out += d));
    child.stderr?.on('data', (d) => (out += d));
    child.on('error', () => resolve(null));
    child.on('close', (code) => resolve(code === 0 ? out : null));
  });
}

function fail(message, howToFix) {
  console.error(`\n[エラー] ${message}`);
  if (howToFix) console.error(`         → ${howToFix}`);
  process.exit(1);
}

// -------------------------------------------------------------------------
// 実行前の確認

console.log(`==> デプロイ先: ${target.label}`);

const projectId = (() => {
  try {
    const rc = JSON.parse(readFileSync(join(root, '.firebaserc'), 'utf8'));
    return rc.projects?.[target.alias] ?? null;
  } catch {
    return null;
  }
})();

if (!projectId) {
  fail(`.firebaserc に ${target.alias} のプロジェクト ID がありません。`);
}
console.log(`    プロジェクト: ${projectId}`);

// 1. Firebase CLI にログインしているか。
console.log('\n==> ログイン状態を確認');
{
  const out = await capture('firebase', ['login:list']);
  if (out === null) {
    fail('firebase コマンドを実行できません。', 'npm install -g firebase-tools');
  }
  if (/No authorized accounts|no currently logged/i.test(out)) {
    fail(
      'Firebase CLI にログインしていません。',
      'firebase login を実行してください（ブラウザが開き、Google アカウントでの許可を求められます）',
    );
  }
  console.log('    ログイン済み');
}

// 2. Flutter 側の接続設定が生成されているか。
//    **一番忘れられやすい。** 未設定のままビルドすると、実行時に
//    FirebaseNotConfiguredError で止まるアプリが配信されてしまう。
console.log('\n==> 接続設定を確認');
{
  const path = join(root, 'lib', 'env', target.optionsFile);
  let source = '';
  try {
    source = readFileSync(path, 'utf8');
  } catch {
    fail(`lib/env/${target.optionsFile} を読めません。`);
  }
  if (source.includes('REPLACE_ME')) {
    fail(
      `${target.label}の接続設定が未生成です（lib/env/${target.optionsFile}）。`,
      isWindows
        ? `scripts\\configure-firebase.cmd${wantsProd ? ' prod' : ''} を実行してください`
        : `./scripts/configure-firebase.sh${wantsProd ? ' prod' : ''} を実行してください`,
    );
  }
  console.log(`    lib/env/${target.optionsFile} は設定済み`);
}

// 3. 本番は取り違えると戻せないので、明示的に確認する。
if (wantsProd && !skipConfirm) {
  console.log('');
  console.log('  ┌────────────────────────────────────────────┐');
  console.log('  │  これは本番環境へのデプロイです。          │');
  console.log('  └────────────────────────────────────────────┘');
  console.log(`  続ける場合は、本番のプロジェクト ID「${projectId}」を入力してください。`);
  const rl = createInterface({ input: process.stdin, output: process.stdout });
  const answer = (await rl.question('  > ')).trim();
  rl.close();
  if (answer !== projectId) {
    console.log('\n  入力が一致しないため中止しました。');
    process.exit(1);
  }
}

// -------------------------------------------------------------------------
// ビルドとデプロイ

console.log('\n==> Flutter Web をビルド');
{
  const code = await run('flutter', ['build', 'web', '--release', ...target.dartDefine]);
  if (code === null) fail('flutter コマンドが見つかりません。', 'https://docs.flutter.dev/get-started/install');
  if (code !== 0) fail('flutter build web に失敗しました。');
}

// functions のビルドは firebase.json の predeploy が行う。
console.log('\n==> デプロイ');
{
  const code = await run('firebase', [
    'deploy',
    '--project',
    projectId,
    '--only',
    'firestore:rules,firestore:indexes,storage,functions,hosting',
  ]);
  if (code !== 0) {
    fail(
      'デプロイに失敗しました。',
      '上の出力の最後を確認してください。初回は Cloud Scheduler API などの有効化を求められることがあります',
    );
  }
}

console.log('');
console.log(`==> 完了（${target.label} / ${projectId}）`);
console.log(`    https://${projectId}.web.app`);
console.log('');
console.log('    最初のサイト管理者の登録がまだなら、docs/SETUP.md の 6 章を行ってください。');
