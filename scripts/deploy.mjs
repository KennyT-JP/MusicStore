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
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
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
// 失敗の原因が「上の出力を見てください」でしか分からないとき用。
// Firebase CLI の詳細ログを出す。
const wantsDebug = argv.includes('--debug');
// ビルドを飛ばして配信だけやり直す。IAM や API の有効化を直したあとの
// 再実行で、5 分かかる Web ビルドを繰り返さずに済む。
const skipBuild = argv.includes('--no-build');

// 配信する対象を絞る（例: --only=functions、--only=functions:onItemCreated）。
// 一部の関数だけ失敗したときに、そこだけやり直すために使う。
const onlyTargets =
  argv.find((a) => a.startsWith('--only='))?.slice('--only='.length) ??
  'firestore:rules,firestore:indexes,storage,functions,hosting';

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

/** Flutter が生成する、この版で使う部品（プラグイン）の一覧。 */
const pluginsFile = join(root, '.flutter-plugins-dependencies');

/** 前回ビルドしたときの部品一覧を控えておく場所。 */
const pluginsMemo = join(root, 'build', '.plugins-of-last-build');

/** いまの部品一覧。Flutter の版によって書式が変わるので中身は解釈しない。 */
function currentPlugins() {
  try {
    return readFileSync(pluginsFile, 'utf8');
  } catch {
    return null;
  }
}

/**
 * 部品の顔ぶれが前回のビルドから変わっていたら `flutter clean` する。
 *
 * **変わっていなければ何もしない。** 毎回消すとビルドが数分延びる。
 */
async function ensureCleanBuildIfPluginsChanged() {
  const now = currentPlugins();
  // 一覧が無い＝まだ一度も pub get していない。ビルド側が教えてくれる。
  if (now === null) return;

  let previous = null;
  try {
    previous = readFileSync(pluginsMemo, 'utf8');
  } catch {
    // 控えが無い（このスクリプトで初めてビルドする）。
    // 既存の生成物が古い可能性を否定できないので、一度だけ作り直す。
  }

  if (previous === now) return;

  console.log('\n==> 部品の顔ぶれが前回のビルドと違うため、生成物を作り直します');
  console.log('    （足した部品が組み込まれないまま配信されるのを防ぐため）');
  const code = await run('flutter', ['clean']);
  if (code !== 0) fail('flutter clean に失敗しました。');

  const getCode = await run('flutter', ['pub', 'get']);
  if (getCode !== 0) fail('flutter pub get に失敗しました。');
}

/** ビルドが通ったので、そのときの部品一覧を控える。 */
function rememberPlugins() {
  const now = currentPlugins();
  if (now === null) return;
  try {
    mkdirSync(dirname(pluginsMemo), { recursive: true });
    writeFileSync(pluginsMemo, now);
  } catch {
    // 控えられなくても配信は続ける。次回に一度余分に作り直すだけ。
  }
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

if (skipBuild) {
  console.log('\n==> Flutter Web のビルドは省略（--no-build）');
} else {
  // **部品（プラグイン）の一覧が前回のビルドから変わっていたら、作り直す。**
  //
  // 追加した部品が組み込まれないままビルドされることがある。前に作った
  // 生成物が残っていると、古い部品一覧がそのまま使われるためである。
  // 画面は動くのに、その部品を使う操作だけが
  // `MissingPluginException(No implementation found for method ...)`
  // で失敗する、という出方をする。ビルドも配信も成功するので気づけない。
  // （2026-08-07、just_audio を足したときに実際に起きた）
  await ensureCleanBuildIfPluginsChanged();

  console.log('\n==> Flutter Web をビルド');
  const code = await run('flutter', ['build', 'web', '--release', ...target.dartDefine]);
  if (code === null) fail('flutter コマンドが見つかりません。', 'https://docs.flutter.dev/get-started/install');
  if (code !== 0) fail('flutter build web に失敗しました。');

  rememberPlugins();
}

// functions のビルドは firebase.json の predeploy が行う。
console.log('\n==> デプロイ');
{
  const code = await run('firebase', [
    'deploy',
    '--project',
    projectId,
    '--only',
    onlyTargets,
    ...(wantsDebug ? ['--debug'] : []),
  ]);
  if (code !== 0) {
    console.error('');
    // **やり直しのコマンドには配信先を必ず含める。**
    // 以前は `prod` を落とした案内を出しており、そのまま実行すると
    // 本番のつもりで検証環境へ配信してしまう状態だった。
    const cmd = isWindows ? 'scripts\\deploy.cmd' : './scripts/deploy.sh';
    const to = `${cmd}${wantsProd ? ' prod' : ''}`;

    console.error('  よくある原因（いずれも初回特有で、再実行すれば通ります）:');
    console.error('   ・送信が途中で切れた → そのまま再実行');
    console.error('     （hosting の uploading が途中で止まった場合など）');
    console.error('   ・初回は権限が行き渡るまで数分かかる → そのまま数分待って再実行');
    console.error('   ・API が未有効 → 出力に出ている URL を開いて有効化');
    console.error('   ・IAM の書き換えに失敗 → **エラーの少し上**に、必要な権限を付ける');
    console.error('     gcloud のコマンドが並んでいます。そこを確認してください');
    console.error('   ・Cloud Build が失敗した関数がある → まずそのまま再実行。');
    console.error('     初回は置き場所（Artifact Registry）の用意と同時に走るため崩れやすい');
    console.error('');
    console.error('  やり直す（Web のビルドは終わっているので省けます）:');
    console.error(`    ${to} --no-build`);
    console.error('');
    console.error('  対象を絞る:');
    console.error(`    ${to} --no-build --only=hosting`);
    console.error(`    ${to} --no-build --only=functions`);
    console.error('');
    console.error('  詳しく見る:');
    console.error(`    ${to} --no-build --debug`);
    if (wantsProd) {
      console.error('');
      console.error('  ※ 本番へのやり直しには prod が要ります。');
      console.error('     付け忘れると検証環境へ配信されます。');
    }
    console.error('');
    fail('デプロイに失敗しました。', 'docs/SETUP.md の「本番へ配信する前の確認」も参照してください');
  }
}

console.log('');
console.log(`==> 完了（${target.label} / ${projectId}）`);
console.log(`    配信した対象: ${onlyTargets}`);

// **URL を出すのは Hosting を配信したときだけ。**
// --only=functions などで絞ったときにも URL を出していたため、
// 「配信できた」と読めてしまった。実際には Hosting が一度も成功して
// おらず、サイトを開くと Site Not Found になった。
if (onlyTargets.includes('hosting')) {
  console.log(`    https://${projectId}.web.app`);
} else {
  console.log('');
  console.log('    ※ Hosting は配信していません（--only で除かれています）。');
  console.log('       Web アプリを反映するには次を実行してください:');
  console.log(
    `       ${isWindows ? 'scripts\\deploy.cmd' : './scripts/deploy.sh'}` +
      `${wantsProd ? ' prod' : ''} --only=hosting`
  );
  console.log('       **--no-build は付けないでください。** ビルド済みの');
  console.log('       build/web が別の環境向けだと、配信先と中身が食い違います。');
}
console.log('');
console.log('    最初のサイト管理者の登録がまだなら、docs/SETUP.md の 6 章を行ってください。');
