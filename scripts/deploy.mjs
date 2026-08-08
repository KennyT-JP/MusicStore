#!/usr/bin/env node
/**
 * クラウドの Firebase プロジェクトへデプロイする（仕様書 12.2）
 *
 *   scripts\deploy.cmd            検証環境（dev の枝から）
 *   scripts\deploy.cmd prod      本番環境（main の枝から）
 *
 * ## このスクリプトがやること（2026-08-08 に作り直した）
 *
 * 1. **変更のあった層だけを配信する。** 前回配信したコミット（git タグ
 *    `deploy/staging` / `deploy/prod`）から差分を取り、ルール・索引・
 *    関数・Hosting のどれが変わったかを判定する。関数しか変えていない
 *    のに 5 分の Web ビルドを待つ、という無駄を無くす。
 *
 * 2. **検証済みのコミットしか配信しない。** `scripts/check.mjs` が全部
 *    緑だったコミットの ID を `.last-check.json` に残す。いまの HEAD と
 *    一致しなければ、その場で検証を実行してから配信する。
 *    「テストしてから配信」を、人の記憶ではなく仕組みにする。
 *
 * 3. **新規 callable の呼び出し許可を自動で付ける。** Firebase CLI は
 *    新規作成時にしか Cloud Run の invoker 設定を入れず、初回配信が
 *    途中で失敗すると許可だけが抜けて `internal` になる（本番で実際に
 *    起きた）。配信ログの `Successful create operation` を拾い、
 *    callable なら gcloud で allUsers を付与する。
 *
 * 4. **配信後に疎通を確かめる。** callable 全件へ実際に HTTP を送り、
 *    403（許可欠落）や 404 を検出する。Hosting は 200 が返ることを見る。
 *    「配信は成功と出たがサイトが死んでいる」を配信の中で捕まえる。
 *
 * ## 変えていないこと
 *
 * - 本番へは `main` から、検証環境へは `dev` からだけ配信する（依頼者の指示）
 * - 未コミットの変更があれば止める（接続設定の 2 ファイルは除く）
 * - 部品（プラグイン）の顔ぶれが変わったら flutter clean（実際の事故から）
 * - FUNCTIONS_DISCOVERY_TIMEOUT を延ばす（Node の版が違う環境で必要）
 */
import { spawn } from 'node:child_process';
import { mkdirSync, readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const isWindows = process.platform === 'win32';
const REGION = 'asia-northeast1';

// -------------------------------------------------------------------------
// 引数

const argv = process.argv.slice(2);
const wantsProd = argv.includes('prod');
const wantsDebug = argv.includes('--debug');
const skipBuild = argv.includes('--no-build');   // 失敗後のやり直し用
const skipTests = argv.includes('--skip-tests'); // 依頼者が明示したときだけ
const wantsAll = argv.includes('--all');         // 差分に関係なく全層
const onlyOverride = argv.find((a) => a.startsWith('--only='))?.slice('--only='.length) ?? null;

const ALL_LAYERS = ['firestore:rules', 'firestore:indexes', 'storage', 'functions', 'hosting'];

const target = wantsProd
  ? { alias: 'prod', label: '本番環境', branch: ['main'], optionsFile: 'firebase_options_prod.dart', dartDefine: ['--dart-define=APP_ENV=prod'] }
  : { alias: 'staging', label: '検証環境', branch: ['dev', 'main'], optionsFile: 'firebase_options_staging.dart', dartDefine: [] };

const deployTag = `deploy/${target.alias}`;

// -------------------------------------------------------------------------
// 部品

/**
 * 関数の中身を調べる工程の待ち時間を延ばす。既定は 10 秒しかなく、
 * Node の版が functions/package.json の指定と違うと超える。
 * 同じ指定がエミュレータの起動側にもある（AUDIT-CHECKLIST 観点 4）。
 */
const childEnv = {
  ...process.env,
  FUNCTIONS_DISCOVERY_TIMEOUT: process.env.FUNCTIONS_DISCOVERY_TIMEOUT ?? '120',
};

function run(command, args, options = {}) {
  return new Promise((resolve) => {
    const child = isWindows
      ? spawn([command, ...args].join(' '), { stdio: 'inherit', shell: true, cwd: root, env: childEnv, ...options })
      : spawn(command, args, { stdio: 'inherit', cwd: root, env: childEnv, ...options });
    child.on('error', () => resolve(null));
    child.on('close', (code) => resolve(code));
  });
}

/** 画面に流しつつ、出力も持ち帰る（配信ログから create を拾うため）。 */
function runTee(command, args) {
  return new Promise((resolve) => {
    const child = isWindows
      ? spawn([command, ...args].join(' '), { shell: true, cwd: root, env: childEnv })
      : spawn(command, args, { cwd: root, env: childEnv });
    let output = '';
    const tee = (stream, sink) => stream?.on('data', (d) => { sink.write(d); output += d; });
    tee(child.stdout, process.stdout);
    tee(child.stderr, process.stderr);
    child.on('error', () => resolve({ code: null, output }));
    child.on('close', (code) => resolve({ code, output }));
  });
}

function capture(command, args) {
  return new Promise((resolve) => {
    const child = isWindows
      ? spawn([command, ...args].join(' '), { shell: true, cwd: root, env: childEnv })
      : spawn(command, args, { cwd: root, env: childEnv });
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
if (!projectId) fail(`.firebaserc に ${target.alias} のプロジェクト ID がありません。`);
console.log(`    プロジェクト: ${projectId}`);

// 1. ログイン
{
  const out = await capture('firebase', ['login:list']);
  if (out === null) fail('firebase コマンドを実行できません。', 'npm install -g firebase-tools');
  if (/No authorized accounts|no currently logged/i.test(out)) {
    fail('Firebase CLI にログインしていません。', 'firebase login を実行してください');
  }
}

// 2. 枝と作業ツリー。
//    配信されるのは「いまの作業ツリーの中身」なので、枝が違えば
//    確認していないものが出る。本番は main、検証環境は dev からだけ。
const branch = (await capture('git', ['rev-parse', '--abbrev-ref', 'HEAD']))?.trim();
if (!branch) fail('git の枝を読めません。');
if (!target.branch.includes(branch)) {
  fail(
    `${target.label}へは ${target.branch.map((b) => `\`${b}\``).join(' か ')} からのみ配信します（いまは \`${branch}\`）。`,
    wantsProd ? 'git switch main && git merge --no-ff dev' : 'git switch dev',
  );
}

// 接続設定の 2 ファイルは、手元だけ実際の値になっているのが正常（SETUP 4 章）。
const generated = new Set([
  'lib/env/firebase_options_staging.dart',
  'lib/env/firebase_options_prod.dart',
]);
const dirty = ((await capture('git', ['status', '--porcelain'])) ?? '')
  .split('\n').map((l) => l.trim()).filter(Boolean)
  .map((l) => l.replace(/^\S+\s+/, ''))
  .filter((p) => !generated.has(p));
if (dirty.length > 0) {
  fail(`コミットしていない変更があります（${dirty.length} 件）: ${dirty.slice(0, 5).join(', ')}`,
       '配信するのは作業ツリーの中身です。先にコミットしてください');
}
console.log(`    枝: ${branch} ／ 作業ツリーはコミット済み`);

// 3. このコミットは検証済みか。
//    check.mjs が全部緑だったコミットの ID と HEAD を突き合わせる。
//    違えば、その場で検証を回してから進む（テストしてから配信）。
const head = (await capture('git', ['rev-parse', 'HEAD']))?.trim();
{
  let checked = null;
  try {
    checked = JSON.parse(readFileSync(join(root, '.last-check.json'), 'utf8'));
  } catch { /* 未実行 */ }

  if (checked?.commit === head) {
    console.log(`    検証済み: ${head.slice(0, 7)}（${checked.when}）`);
  } else if (skipTests) {
    console.log('    **検証を飛ばします（--skip-tests）。依頼者の指示があるときだけ。**');
  } else {
    console.log('\n==> このコミットはまだ検証されていません。検証を実行します');
    const code = await run('node', [join('scripts', 'check.mjs')]);
    if (code !== 0) fail('検証が失敗しました。配信しません。');
  }
}

// 4. どの層が変わったか。
//    前回配信したコミット（deploy/<環境> タグ）からの差分で決める。
//    タグが無い＝このスクリプトでの初回。全層を出す。
function layersFromDiff(files) {
  const layers = new Set();
  for (const f of files) {
    if (f === 'firestore.rules') layers.add('firestore:rules');
    else if (f === 'firestore.indexes.json') layers.add('firestore:indexes');
    else if (f === 'storage.rules') layers.add('storage');
    else if (f.startsWith('functions/')) {
      if (!f.startsWith('functions/test/')) layers.add('functions'); // テストは配信物に入らない
    }
    else if (f.startsWith('lib/') || f.startsWith('web/') || f.startsWith('assets/') ||
             f === 'pubspec.yaml' || f === 'pubspec.lock' || f === 'l10n.yaml') layers.add('hosting');
    else if (f === 'firebase.json') return null; // 配信設定そのもの。安全側に倒して全層
    else if (f.startsWith('docs/') || f.startsWith('test/') || f.startsWith('rules-test/') ||
             f.startsWith('scripts/') || f.startsWith('.claude/') || f.startsWith('android/') ||
             f.startsWith('ios/') || ['CLAUDE.md', 'README.md', '.gitignore', '.gitattributes',
             '.metadata', '.firebaserc', 'analysis_options.yaml', '.last-check.json'].includes(f)) continue;
    else return null; // 判定できないものが混ざったら、安全側に倒して全層
  }
  return [...layers];
}

let layers;
let movesTag = false; // タグを動かすのは「差分を全部出した」ときだけ
if (onlyOverride) {
  layers = onlyOverride.split(',');
  console.log(`\n==> 配信する層（--only 指定）: ${layers.join(', ')}`);
} else if (wantsAll) {
  layers = ALL_LAYERS;
  movesTag = true;
  console.log('\n==> 配信する層（--all 指定）: すべて');
} else {
  const hasTag = ((await capture('git', ['tag', '-l', deployTag])) ?? '').trim() !== '';
  if (!hasTag) {
    layers = ALL_LAYERS;
    movesTag = true;
    console.log('\n==> 前回の配信の記録が無いため、すべての層を配信します（初回）');
  } else {
    const diff = ((await capture('git', ['diff', '--name-only', `${deployTag}..HEAD`])) ?? '')
      .split('\n').map((l) => l.trim()).filter(Boolean);
    const detected = layersFromDiff(diff);
    layers = detected ?? ALL_LAYERS;
    movesTag = true;
    if (detected === null) {
      console.log('\n==> 判定できない変更が混ざっているため、すべての層を配信します');
    } else if (layers.length === 0) {
      const base = ((await capture('git', ['rev-parse', '--short', deployTag])) ?? '').trim();
      console.log(`\n==> ${base} から配信に関わる変更はありません。何もしません`);
      console.log('    全層を出し直すには --all を付けてください。');
      process.exit(0);
    } else {
      console.log(`\n==> 前回（${deployTag}）からの差分で配信する層: ${layers.join(', ')}`);
    }
  }
}

// -------------------------------------------------------------------------
// ビルド（Hosting を出すときだけ）

const pluginsFile = join(root, '.flutter-plugins-dependencies');
const pluginsMemo = join(root, 'build', '.plugins-of-last-build');

function currentPlugins() {
  try { return readFileSync(pluginsFile, 'utf8'); } catch { return null; }
}

if (layers.includes('hosting') && !skipBuild) {
  // 部品の顔ぶれが変わっていたら作り直す。古い生成物が残っていると、
  // 足した部品が組み込まれないまま配信される（just_audio で実際に起きた）。
  const now = currentPlugins();
  let previous = null;
  try { previous = readFileSync(pluginsMemo, 'utf8'); } catch { /* 初回 */ }
  if (now !== null && previous !== now) {
    console.log('\n==> 部品の顔ぶれが前回のビルドと違うため、生成物を作り直します');
    if (await run('flutter', ['clean']) !== 0) fail('flutter clean に失敗しました。');
    if (await run('flutter', ['pub', 'get']) !== 0) fail('flutter pub get に失敗しました。');
  }

  // 接続設定が REPLACE_ME のままなら、起動と同時に死ぬアプリが公開される。
  const source = readFileSync(join(root, 'lib', 'env', target.optionsFile), 'utf8');
  if (source.includes('REPLACE_ME')) {
    fail(`${target.label}の接続設定が未生成です（lib/env/${target.optionsFile}）。`,
         `scripts${isWindows ? '\\' : '/'}configure-firebase.${isWindows ? 'cmd' : 'sh'}${wantsProd ? ' prod' : ''} を実行してください（終わったら firebase.json が壊れていないか git status で確認）`);
  }

  console.log(`\n==> Flutter Web をビルド（${target.label}向け）`);
  const code = await run('flutter', ['build', 'web', '--release', ...target.dartDefine]);
  if (code !== 0) fail('flutter build web に失敗しました。');
  if (now !== null) {
    try { mkdirSync(dirname(pluginsMemo), { recursive: true }); writeFileSync(pluginsMemo, now); } catch { /* 次回作り直すだけ */ }
  }
} else if (layers.includes('hosting') && skipBuild) {
  console.log('\n==> Flutter Web のビルドは省略（--no-build）。build/web がこの環境向けか確認してください');
}

// -------------------------------------------------------------------------
// デプロイ

console.log('\n==> デプロイ');
const { code: deployCode, output: deployOutput } = await runTee('firebase', [
  'deploy', '--project', projectId, '--only', layers.join(','),
  ...(wantsDebug ? ['--debug'] : []),
]);

if (deployCode !== 0) {
  const cmd = `${isWindows ? 'scripts\\deploy.cmd' : './scripts/deploy.sh'}${wantsProd ? ' prod' : ''}`;
  console.error('');
  console.error('  エラーの本文を読んでください。よくあるもの:');
  console.error('   ・Cannot determine backend specification → functions で npm run build が通るか確認');
  console.error('   ・送信が途中で切れた／初回の権限待ち → 数分待ってそのまま再実行');
  console.error('   ・API が未有効 → 出力の URL を開いて有効化');
  console.error(`  やり直す: ${cmd} --no-build`);
  fail('デプロイに失敗しました。', 'docs/SETUP.md の「本番へ配信する前の確認」も参照');
}

// -------------------------------------------------------------------------
// 配信後の確認（ここからが品質の本体）

let verifyFailed = false;

// A. 新規作成された callable に呼び出し許可を付ける。
//    実装の onCall 一覧はソースから機械的に取る（setup_doc.test.ts と同じ規則）。
function callableNames() {
  const dir = join(root, 'functions', 'src', 'callable');
  const names = [];
  for (const file of readdirSync(dir)) {
    if (!file.endsWith('.ts')) continue;
    const text = readFileSync(join(dir, file), 'utf8');
    for (const m of text.matchAll(/export const (\w+) = onCall\b/g)) names.push(m[1]);
  }
  return names;
}

if (layers.includes('functions')) {
  const callables = callableNames();
  const created = [...deployOutput.matchAll(/functions\[([\w-]+)\][^\n]*Successful create operation/g)]
    .map((m) => m[1].replace(`${REGION}-`, ''))
    .filter((name) => callables.includes(name));

  if (created.length > 0) {
    console.log(`\n==> 新規作成された callable に呼び出し許可を付けます: ${created.join(', ')}`);
    for (const name of created) {
      const code = await run('gcloud', [
        'run', 'services', 'add-iam-policy-binding', name.toLowerCase(),
        `--region=${REGION}`, `--project=${projectId}`,
        '--member=allUsers', '--role=roles/run.invoker', '--quiet',
      ]);
      if (code !== 0) {
        verifyFailed = true;
        console.error(`  付与に失敗: ${name}。docs/SETUP.md「直し方 1」を手で実行してください`);
      }
    }
  }

  // B. callable 全件に実際へ HTTP を送り、403（許可欠落）と 404 を見つける。
  //    401/400 は「Cloud Run は通った。関数が未認証を弾いた」＝正常。
  console.log(`\n==> callable の疎通を確認（${callables.length} 件）`);
  const bad = [];
  await Promise.all(callables.map(async (name) => {
    try {
      const res = await fetch(`https://${REGION}-${projectId}.cloudfunctions.net/${name}`, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: '{"data":{}}',
      });
      if (res.status === 403 || res.status === 404) bad.push(`${name}（${res.status}）`);
    } catch (e) {
      bad.push(`${name}（${e.message}）`);
    }
  }));
  if (bad.length > 0) {
    verifyFailed = true;
    console.error(`  異常: ${bad.join(', ')}`);
    console.error('  403 は呼び出し許可の欠落です。docs/SETUP.md「呼び出し可能関数が internal で失敗するとき」');
  } else {
    console.log('    全件、Cloud Run を通って関数に届いています');
  }
}

// C. Hosting が実際に配れているか。
if (layers.includes('hosting')) {
  console.log('\n==> Hosting の疎通を確認');
  try {
    const res = await fetch(`https://${projectId}.web.app/main.dart.js`, { method: 'HEAD' });
    if (res.status !== 200) {
      verifyFailed = true;
      console.error(`  異常: main.dart.js が ${res.status} を返しました（Site Not Found の疑い）`);
    } else {
      console.log('    200 OK');
    }
  } catch (e) {
    verifyFailed = true;
    console.error(`  異常: ${e.message}`);
  }
}

if (verifyFailed) {
  fail('配信後の確認で異常が見つかりました。上の内容を直してから再実行してください。');
}

// -------------------------------------------------------------------------
// 記録

// 「どこまで配信済みか」をタグで残す。次回の差分の起点になる。
// --only で絞ったときは動かさない（残りの層が未配信のままになるため）。
if (movesTag) {
  await capture('git', ['tag', '-f', deployTag, 'HEAD']);
}

console.log('');
console.log(`==> 完了（${target.label} / ${projectId}）`);
console.log(`    配信した層: ${layers.join(', ')}`);
if (layers.includes('hosting')) console.log(`    https://${projectId}.web.app`);
if (!movesTag) console.log(`    ※ --only 指定のため、配信済みの記録（${deployTag}）は動かしていません。`);
