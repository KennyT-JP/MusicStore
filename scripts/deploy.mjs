#!/usr/bin/env node
/**
 * クラウドの Firebase プロジェクトへデプロイする（仕様書 12.2）
 *
 *   scripts\deploy.cmd            検証環境（dev の枝から）
 *   scripts\deploy.cmd prod      本番環境（main の枝から）
 *
 *   node scripts\deploy.mjs [prod] --show-app-links
 *       配信せずに、.well-known/ の 2 ファイル（App Links / Universal
 *       Links）がその環境へどう出るかだけを表示する。
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
import { existsSync, mkdirSync, readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

import { acquireLock, releaseLock } from './deploy-lock.mjs';

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
const wantsForce = argv.includes('--force');     // 残留した多重起動ロックの強制解除（AP-76）
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
// App Links / Universal Links の配信面（docs/MOBILE-APP-DESIGN.md 5-8-2）
//
// 共有リンクをスマホで叩いたときにアプリで開くために、ドメイン側へ
// 2 つのファイルを置く。**中身が違っていてもエラーは出ない**——OS の
// 照合が黙って失敗し、リンクがブラウザで開くだけになる。気づく手段が
// 無いので、**ここで機械的に止める**のがこのブロックの目的。
//
// ## 原本は本番の値（index.html / robots.txt / sitemap.xml と同じ流儀）
//
// `web/.well-known/` の 2 ファイルは**本番の値のまま**置き、環境ごとの
// 差し替えは**配信物（build/web）の側だけ**で行う。原本を書き換える形に
// すると、検証環境へ出した直後の作業ツリーが「本番へ出してはいけない
// 状態」になり、それを git で見分けられない。
//
// ## 環境ごとに何が違うか
//
// | | 本番 | 検証 |
// | --- | --- | --- |
// | ホスト | music-storage-d79b2.web.app | music-storage-dev.web.app |
// | assetlinks の `package_name` | jp.sessionconcierge.trackcabinet | **同 + `.dev`**（Android のフレーバー・5-9） |
// | assetlinks の SHA-256 | アップロード鍵＋**Play アプリ署名鍵** | アップロード鍵だけ（Play に出さない） |
// | apple-app-site-association | 要る | **同じ中身のまま出す**（下記） |
//
// **ホストはファイルの中身に現れない。** どちらのファイルにも URL が
// 無く、「どのホストで配られたか」がそのままホストの指定になる。
// だから index.html のような URL の置換は要らない——**差し替えるのは
// `package_name` と鍵の本数だけ**。
//
// **apple-app-site-association は環境で変わらない。** iOS には dev
// フレーバーを作らない（3-4）ので Bundle ID は 1 つしかなく、Team ID も
// 同じ Apple アカウントなので同じ。検証環境のホストへ出しても、アプリの
// entitlement が本番のホストしか宣言していない以上 iOS は読みに来ない
// （効かないだけで害も無い）。**環境ごとに消す・作り分ける必要は無い。**
//
// ## 止めるのは assetlinks.json だけ（**非対称にしてある。理由あり**）
//
// apple-app-site-association に要る値（Apple の Team ID）は**すでに
// 分かっている**ので、プレースホルダが残る余地が無い。
// assetlinks.json に要る 2 つの SHA-256 は **keystore がまだ無く、
// 依頼者にしか作れない**。だから止める判定は assetlinks.json だけに要る。
//
//   **両方へ広げないこと。** AASA 側は永久に発火しない死んだ判定になる。
//   **両方から外さないこと。** 間違った SHA-256 は黙って失敗する。
//
// 値が入れば判定は自然に通る。**判定を消す作業は発生しない。**

const PLACEHOLDER = 'REPLACE_ME';
/** 手元のアップロード鍵。**これだけは検証環境でも必須**（dev の apk を署名する鍵そのもの）。 */
const UPLOAD_KEY_PLACEHOLDER = 'REPLACE_ME_UPLOAD_KEY_SHA256';
/** Play アプリ署名鍵。**本番だけ必須**（Play に出さない検証環境には要らない）。 */
const PLAY_KEY_PLACEHOLDER = 'REPLACE_ME_PLAY_APP_SIGNING_SHA256';
const WELL_KNOWN = '.well-known';
const ASSETLINKS = 'assetlinks.json';
const AASA = 'apple-app-site-association';

const HOW_TO_GET_UPLOAD_KEY =
  'keytool -list -v -keystore <keystore のファイル> -alias <別名> の SHA-256';
const HOW_TO_GET_PLAY_KEY =
  'Play Console → テストとリリース → アプリの完全性 → アプリ署名 の SHA-256';
const NEVER_GUESS =
  '**それらしい値を書いてはいけません。** 間違った SHA-256 は照合が黙って失敗し、' +
  'リンクがブラウザで開くだけになります（エラーは出ません）。';

/**
 * 配信物に書く 2 ファイルの中身を決める。**読むのは原本だけ**なので、
 * 何度呼んでも同じ結果になる（配信物へ二重に適用されない）。
 * 値が足りなければ、この中で止まる。
 */
function planAppLinks(alias) {
  const readOriginal = (name) => {
    const path = join(root, 'web', WELL_KNOWN, name);
    if (!existsSync(path)) {
      fail(`web/${WELL_KNOWN}/${name} がありません。`,
           'App Links / Universal Links の配信面です（docs/MOBILE-APP-DESIGN.md 5-8-2）。無いと共有リンクがアプリで開きません');
    }
    try {
      return JSON.parse(readFileSync(path, 'utf8'));
    } catch (e) {
      fail(`web/${WELL_KNOWN}/${name} が JSON として読めません（${e.message}）。`,
           'Apple / Google はどちらも JSON として読みます。壊れていると黙って弾かれます');
    }
  };

  const statements = readOriginal(ASSETLINKS);
  const dropped = [];
  for (const statement of statements) {
    const target = statement.target;

    // 検証環境の apk は applicationIdSuffix = ".dev" で別アプリになる。
    // ここを直さないと、検証環境のリンクはどの端末でも開かない。
    if (alias !== 'prod') target.package_name = `${target.package_name}.dev`;

    const all = target.sha256_cert_fingerprints;

    if (all.includes(UPLOAD_KEY_PLACEHOLDER)) {
      fail(
        `${WELL_KNOWN}/${ASSETLINKS} の手元の署名鍵の SHA-256 が未設定です（${UPLOAD_KEY_PLACEHOLDER}）。`,
        `keystore を作り、その SHA-256 を web/${WELL_KNOWN}/${ASSETLINKS} に書いてください:\n` +
          `             ${HOW_TO_GET_UPLOAD_KEY}\n` +
          '             形は大文字 16 進のコロン区切り 32 バイト（AB:CD:…）。\n' +
          `             ${NEVER_GUESS}`,
      );
    }

    // **本番は 2 つとも要る。** Play が AAB を署名し直すので、端末に届く
    // アプリの署名は手元の鍵ではない。手元の鍵だけを載せると、
    // **ストアから入れた人だけリンクが開かない**（開発端末では動くので
    // 気づけない。8-2 の Google ログインと同じ形の事故）。
    if (alias === 'prod' && all.includes(PLAY_KEY_PLACEHOLDER)) {
      fail(
        `${WELL_KNOWN}/${ASSETLINKS} の Play アプリ署名鍵の SHA-256 が未設定です（${PLAY_KEY_PLACEHOLDER}）。`,
        '本番は**手元のアップロード鍵と Play アプリ署名鍵の 2 つとも**要ります:\n' +
          `             ① 手元のアップロード鍵: ${HOW_TO_GET_UPLOAD_KEY}\n` +
          `             ② Play アプリ署名鍵: ${HOW_TO_GET_PLAY_KEY}\n` +
          '             ② を落とすと、**ストアから入れた人だけ**リンクが開きません（Play が AAB を署名し直すため）。\n' +
          `             ${NEVER_GUESS}`,
      );
    }

    // 検証環境は Play に出さないので、Play アプリ署名鍵は要らない。
    // **未設定のまま配ってはいけない**——プレースホルダの文字列が鍵の
    // 一覧に混ざると、その一覧ごと壊れたものとして扱われうる。落とす。
    const missing = all.filter((f) => f.includes(PLACEHOLDER));
    if (missing.length > 0) {
      target.sha256_cert_fingerprints = all.filter((f) => !f.includes(PLACEHOLDER));
      dropped.push(...missing);
    }
  }

  return { files: { [ASSETLINKS]: statements, [AASA]: readOriginal(AASA) }, dropped };
}

/** 決めた中身を配信物（build/web）へ書く。**原本は触らない。** */
function writeAppLinks(plan) {
  for (const [name, value] of Object.entries(plan.files)) {
    const built = join(root, 'build', 'web', WELL_KNOWN, name);
    // flutter build web は web/ の中身を丸ごと写す（.well-known も写る。
    // 2026-08-16 に flutter_tools の WebReleaseBundle で確認）。
    // 無いなら写せていない＝配信しても届かない。
    if (!existsSync(built)) {
      fail(`build/web/${WELL_KNOWN}/${name} がありません。`,
           `web/${WELL_KNOWN}/${name} が消えていないか確認し、flutter build web をやり直してください`);
    }
    writeFileSync(built, `${JSON.stringify(value, null, 2)}\n`);
  }
  console.log(`    ${WELL_KNOWN}/ の 2 ファイルを ${target.alias} 向けに書き出しました`);
  if (plan.dropped.length > 0) {
    console.log(`      ※ 未設定の署名鍵を落としました: ${plan.dropped.join(', ')}`);
    console.log('        （検証環境は Play に出さないので、Play アプリ署名鍵は無くて構いません）');
  }
}

// **配信せずに中身だけ見る。** 実機に入れる前に「何が出るか」を確かめる
// 唯一の手段（配信してからでは、間違いに気づく方法が無い）。
if (argv.includes('--show-app-links')) {
  const plan = planAppLinks(target.alias);
  console.log(`==> ${target.label}へ配信される ${WELL_KNOWN}/ の中身（配信はしません）`);
  for (const [name, value] of Object.entries(plan.files)) {
    console.log(`\n----- ${WELL_KNOWN}/${name}`);
    console.log(JSON.stringify(value, null, 2));
  }
  process.exit(0);
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

// **main に、dev を通っていないコミットが積まれていないか。**
//
// 本番へ配信したあと `main` に居たまま次の作業を始めると、新しい
// コミットが `main` へ直接入る。枝の検査だけでは通ってしまい、
// **検証環境で確認していないものが本番へ出る。**
// 2026-08-09 に 2 回やった（どちらも配信前に気づいて移し替えた）。
//
// 決まりは「確認が取れたものだけを main へ入れる」なので、
// main にあって dev に無いコミットは、マージの記録以外は在ってはいけない。
if (branch === 'main') {
  const ahead = ((await capture('git', ['log', '--oneline', '--no-merges', 'dev..main'])) ?? '')
    .split('\n').map((l) => l.trim()).filter(Boolean);
  if (ahead.length > 0) {
    fail(
      `main に、dev を通っていないコミットが ${ahead.length} 件あります。`,
      '検証環境で確認していないものが本番へ出ます。dev へ移してください:\n' +
        `           ${ahead.slice(0, 5).map((l) => `  ${l}`).join('\n           ')}\n` +
        '             git switch dev && git cherry-pick <コミット>\n' +
        '             git switch main && git reset --hard <元の位置>',
    );
  }
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

// 3. どの層が変わったか。
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
             '.metadata', '.firebaserc', 'analysis_options.yaml', '.last-check.json',
             // ルールテスト専用のエミュレータ設定。配信物には関係しない
             'firebase.rules-test.json'].includes(f)) continue;
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
// 容量の「単位」を変える配信への注意（監査 第5回・群C・AP-46）
//
// 容量は **リストごと 1GB**（functions/src/config.ts の defaultQuotaBytes）と、
// **人ごとの土台 2GB**（functions/src/domain/quota.ts の USER_DEFAULT_QUOTA_BYTES）で
// 決まる。この「単位」や既定を変えると、リストを 3 つ以上持つ人など、
// **昨日までアップロードできた人が今日からできなくなる**ことが起こり得る
// （docs/PREMIUM-DESIGN.md／docs/AUDIT-CHECKLIST.md 観点 6）。影響者は
// 本番の実データを数えないと分からない。ここでは配信を止めず、
// 「数えたか」を確認する注意だけ出す（実行の有無までは検証できない）。
//
// 対象は git 差分で前回の配信（deploy/<環境> タグ）から変わったファイル。
// タグが無い初回は差分の起点が無いので確認しない（次回以降タグが起点になる）。
const QUOTA_SENSITIVE_FILES = [
  'functions/src/config.ts',                     // defaultQuotaBytes（リストごと 1GB）
  'functions/src/domain/quota.ts',               // USER_DEFAULT_QUOTA_BYTES・しきい値・自動拡張
  'functions/src/callable/site_management.ts',   // setListQuota（90 行付近）／setUserQuota（149 行付近）
];
{
  const hasQuotaBase = ((await capture('git', ['tag', '-l', deployTag])) ?? '').trim() !== '';
  if (hasQuotaBase) {
    const changed = ((await capture('git', ['diff', '--name-only', `${deployTag}..HEAD`])) ?? '')
      .split('\n').map((l) => l.trim()).filter(Boolean);
    const touched = QUOTA_SENSITIVE_FILES.filter((f) => changed.includes(f));
    if (touched.length > 0) {
      console.log('\n==> ⚠ 容量に関わるファイルが変更されています:');
      for (const f of touched) console.log(`      ${f}`);
      console.log('    容量の「単位」や既定を変えると、既存の利用者が使えなくなることがあります。');
      console.log('    **本番の実データで、影響を受ける人を数えましたか？**');
      console.log('      node scripts/check-quota-impact.mjs --project <本番のプロジェクト> --key <鍵.json>');
      console.log('    （docs/PREMIUM-DESIGN.md／AUDIT 観点 6。数え漏れると、昨日までできた追加が止まります）');
    }
  }
}

// 4. このコミットは検証済みか。
//    check.mjs が全部緑だったときの記録と突き合わせ、違えばその場で
//    検証を回してから進む（テストしてから配信）。
//    **層の判定より後に置く。** 配信するものが無いときに 4 分の検証を
//    回しても、誰の役にも立たない。
// ツリーは `HEAD^{tree}` ではなく `--format=%T` で取る。cmd.exe が
// `^` をエスケープ文字として食べるため（scripts/check.mjs と同じ理由）。
const head = (await capture('git', ['rev-parse', 'HEAD']))?.trim();
const headTree = (await capture('git', ['show', '-s', '--format=%T', 'HEAD']))?.trim();
{
  let checked = null;
  try {
    checked = JSON.parse(readFileSync(join(root, '.last-check.json'), 'utf8'));
  } catch { /* 未実行 */ }

  // コミット ID が違っても、ツリー（内容）が同じなら検証済みと見なす。
  // dev で検証 → main へ --no-ff マージ、の並びで内容は変わらないため。
  if (checked?.commit === head || (checked?.tree && checked.tree === headTree)) {
    console.log(`    検証済み: ${head.slice(0, 7)}（${checked.when}）`);
  } else if (skipTests) {
    console.log('    **検証を飛ばします（--skip-tests）。依頼者の指示があるときだけ。**');
  } else {
    console.log('\n==> このコミットはまだ検証されていません。検証を実行します');
    const code = await run('node', [join('scripts', 'check.mjs')]);
    if (code !== 0) fail('検証が失敗しました。配信しません。');
  }
}

// -------------------------------------------------------------------------
// 多重起動の防止（監査 第5回・群C・AP-76）
//
// ここから先はビルドと配信という重い処理で、build/web・.last-check.json・
// git タグ deploy/<環境> を共有する。2 つ同時に走ると片方の中間生成物を
// もう片方が配信しうる。**枝・作業ツリー・検証のガードをすべて通した後、
// 実際に重い処理へ入る直前**でファイルロックを 1 本だけ握る（配信するものが
// 無いときや --show-app-links のときは、この手前で終わっているのでロックは取らない）。
//
// 残留ロック（クラッシュ後）は持ち主 pid が消えていれば奪う。確実に
// 止まっているのに残るときは --force で解除できる（deploy-lock.mjs）。
const lockPath = join(root, 'build', '.deploy.lock');
let lock;
try {
  lock = acquireLock(lockPath, { force: wantsForce });
} catch (e) {
  if (e.code === 'ELOCKED') {
    fail(e.message,
         `確実に止まっているなら ${isWindows ? 'scripts\\deploy.cmd' : './scripts/deploy.sh'}${wantsProd ? ' prod' : ''} --force で解除できます`);
  }
  throw e;
}
// **どの経路でも必ず外す。** このスクリプトは fail() と process.exit を
// 多用するため finally では拾いきれない。exit フックに載せて確実に解放する
// （releaseLock は同期なので exit ハンドラから呼べる）。
process.on('exit', () => releaseLock(lock));
console.log(`    多重起動ロックを取得しました（pid ${lock.pid}）`);

// -------------------------------------------------------------------------
// ビルド（Hosting を出すときだけ）

const pluginsFile = join(root, '.flutter-plugins-dependencies');
const pluginsMemo = join(root, 'build', '.plugins-of-last-build');

function currentPlugins() {
  try { return readFileSync(pluginsFile, 'utf8'); } catch { return null; }
}

// App Links の値が揃っているか。**ビルドより前に見る。** 5 分かけて
// ビルドしたあとに止まると、確かめ直すたびに 5 分を払うことになる。
// （lib/env の REPLACE_ME 判定と同じ考え方。あちらは flutter clean の
// 後ろに居るので、こちらはもう一段前に置いた。）
const appLinks = layers.includes('hosting') ? planAppLinks(target.alias) : null;

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

  // **共有カードの画像を、配信先のものに差し替える（監査 第4回）。**
  //
  // `web/index.html` の og:image は**絶対 URL でなければならない**
  // （相対だと読み取る側が解決できない）ため、本番の URL を直書きして
  // ある。そのまま検証環境へ出すと、**検証環境のリンクを共有したときに
  // 本番の画像が出る**。どちらの環境の話をしているのか分からなくなる。
  //
  // ビルド結果の側だけを書き換える。`web/index.html`（原本）は触らない。
  //
  // **robots.txt と sitemap.xml も同じ理由で書き換える（2026-08-15）。**
  // 検証環境の sitemap が本番の URL を並べていると、検証環境をクロール
  // した結果が本番の評価に混ざる。逆に検証環境の URL が本番の sitemap に
  // 載ると、**審査に検証環境が引きずり込まれる。**
  {
    for (const name of ['index.html', 'robots.txt', 'sitemap.xml']) {
      const built = join(root, 'build', 'web', name);
      if (!existsSync(built)) {
        fail(`build/web/${name} がありません。`,
             name === 'sitemap.xml'
               ? 'node scripts/build-manual.mjs を実行してから配信してください'
               : `web/${name} が消えていないか確認してください`);
      }
      const text = readFileSync(built, 'utf8');
      const replaced = text.replaceAll(
        'https://music-storage-d79b2.web.app/',
        `https://${projectId}.web.app/`
      );
      if (replaced !== text) {
        writeFileSync(built, replaced);
        console.log(`    ${name} の URL を ${projectId} のものに差し替えました`);
      }
    }
  }

  // **App Links の 2 ファイルも、配信物の側だけ差し替える**（5-8-2）。
  // 中身に URL は無いので、上の置換ではなく専用の作りになっている
  // （差し替えるのは package_name と署名鍵の本数）。
  writeAppLinks(appLinks);
} else if (layers.includes('hosting') && skipBuild) {
  console.log('\n==> Flutter Web のビルドは省略（--no-build）。build/web がこの環境向けか確認してください');
  // **ここでも書き直す。** --no-build は「前回のビルド結果をそのまま出す」
  // であって、「前回の**配信先**のまま出す」ではない。検証環境向けに
  // 差し替えた build/web を、そのまま本番へ出す事故を防ぐ。
  writeAppLinks(appLinks);
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
    // 空白は \s+ で受ける。`export const X =`（改行）`onCall` と書かれた関数が
    // 一覧から漏れる穴が setup_doc.test.ts で実証された（監査 第4回）。
    for (const m of text.matchAll(/export\s+const\s+(\w+)\s*=\s*onCall\b/g)) names.push(m[1]);
  }
  return names;
}

if (layers.includes('functions')) {
  const callables = callableNames();
  // 配信ログの関数名の表記は firebase-tools の版で違う。**両方受ける。**
  //   旧: functions[asia-northeast1-createList] Successful create operation
  //   新: functions[createList(asia-northeast1)] Successful create operation
  // 片方しか見ていないと、CLI を上げた途端に新規 callable の検出が 0 件に
  // なり、invoker 付与が黙って抜ける（403 は後段のプローブで捕まるが、
  // 自動修復が働かない）。
  const createdRe = new RegExp(
    `functions\\[(?:${REGION}-)?(\\w+)(?:\\(${REGION}\\))?\\][^\\n]*Successful create operation`,
    'g',
  );
  const created = [...deployOutput.matchAll(createdRe)]
    .map((m) => m[1])
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

  // B. callable 全件に実際へ HTTP を送り、403（許可欠落）・404・5xx を見つける。
  //    401/400 は「Cloud Run は通った。関数が未認証を弾いた」＝正常。
  //    5xx は関数が起動時に落ちている（初期化クラッシュ等）＝異常。
  //    以前は 403/404 しか見ておらず、500 を返す関数が素通りしていた。
  //
  //    **1 件ずつ送る。** 最初は 15 件を同時に送っていたが、Windows で
  //    9 件が fetch failed になった（HTTP の異常ではなく接続層の失敗。
  //    実体は curl で 401/400 を返す正常な状態だった）。同時接続を
  //    やめ、接続層の失敗だけ少し待って引き直す。
  console.log(`\n==> callable の疎通を確認（${callables.length} 件）`);
  const bad = [];
  const probe = (name) =>
    fetch(`https://${REGION}-${projectId}.cloudfunctions.net/${name}`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: '{"data":{}}',
    });
  for (const name of callables) {
    let status = null;
    let lastError = null;
    for (let attempt = 0; attempt < 3 && status === null; attempt++) {
      if (attempt > 0) await new Promise((r) => setTimeout(r, 2000));
      try {
        status = (await probe(name)).status;
      } catch (e) {
        lastError = e; // 接続層の失敗。引き直す
      }
    }
    if (status === null) bad.push(`${name}（${lastError?.message ?? '接続できない'}）`);
    else if (status === 403 || status === 404 || status >= 500) bad.push(`${name}（${status}）`);
  }
  if (bad.length > 0) {
    verifyFailed = true;
    console.error(`  異常: ${bad.join(', ')}`);
    console.error('  403 は呼び出し許可の欠落です。docs/SETUP.md「呼び出し可能関数が internal で失敗するとき」');
    console.error('  5xx は関数が起動時に落ちています。Cloud Functions のログを読んでください');
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
