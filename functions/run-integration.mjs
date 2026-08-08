#!/usr/bin/env node
/**
 * 統合テストを、エミュレータごと実行する（仕様書 12.6）
 *
 *   cd functions
 *   npm run test:integration
 *
 * エミュレータの起動・テストの実行・後片付けまでを 1 つのコマンドで行う。
 * **ウィンドウを 2 つ開く必要はない。**
 *
 * ---
 *
 * ## なぜこれを足したのか
 *
 * 以前は「1 枚目で `npm run serve`、2 枚目で `npm run test:integration`」
 * という形だった。人が 2 つの窓を並べる前提の手順は、**手順書に書いても
 * 実行されない**。実際、2026-08-08 までこのテストは一度も実行されておらず、
 * 赤いまま本番へ配信されていた（docs/DEVLOG.md）。
 *
 * `rules-test/run.mjs` は最初からこの形（`emulators:exec`）で、
 * 124 件が毎回そのまま走っている。**同じ作りに揃える。**
 *
 * すでに別の窓でエミュレータが動いているときは、そちらへ繋いで
 * テストだけを走らせる。開発中に何度も試すときのため。
 *
 * ---
 *
 * ## 実装で気をつけていること
 *
 * 1. **`--project demo-musiclist` を必ず付ける**（`serve.mjs` と同じ理由）。
 *    付け忘れると `.firebaserc` の既定（検証環境）で立ち上がり、
 *    テストと噛み合わないまま「起きなかったこと」だけが緑になる。
 *
 * 2. **関数の中身を調べる工程の待ち時間を延ばす**（`serve.mjs`・
 *    `scripts/deploy.mjs` と同じ理由）。既定の 10 秒では足りない。
 *    **この指定を渡す入口は 3 つある。1 つ直したら残りも数えること**
 *    （docs/AUDIT-CHECKLIST.md 観点 4）。
 *
 * 3. **Windows では 1 本の文字列で渡す。** 配列と `shell:true` を混ぜると
 *    引用符が付かずに連結され、`node test/integration.mjs` が
 *    2 つの引数として渡ってしまう（`rules-test/run.mjs` に同じ記述）。
 */
import { spawn } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { connect } from 'node:net';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const isWindows = process.platform === 'win32';

/** このテストが相手にする架空のプロジェクト。 */
const PROJECT = 'demo-musiclist';

/**
 * 統合テストが必要とするエミュレータ。
 *
 * **pubsub は入れない。** 理由は 2 つある。
 *
 * 1. **統合テストは定期実行の関数を一度も呼ばない。**
 *    `purgeDeletedFiles` を確かめる項目は 61 件の中に無い。
 *    起動しても、読み込まれるだけで何も確かめられない。
 *
 * 2. **Pub/Sub エミュレータだけが、画面に窓を出す。**
 *    firebase-tools は firestore と storage の出力を受け取って
 *    自分のログに混ぜるが、**pubsub は別の窓で起動する**（Windows で実測）。
 *    自動で回す以上、実行のたびに窓が開くのは邪魔になる。
 *
 * **`npm run serve`（手で立ち上げるほう）には pubsub を残してある。**
 * 定期実行の関数が読み込まれないと、エミュレータ上で一度も起動できず、
 * ログにも「pubsub エミュレータが無いので無視した」としか出ない
 * （監査 第 2 回）。手で触るときはそちらが要る。
 *
 * **つまり、定期実行の関数は自動テストの対象外である。**
 * 元から確かめる項目が無く、ここで減らしたものは無い。
 * 確かめたくなったら docs/BACKLOG.md の「定期実行の確認」を見ること。
 */
const ONLY = 'functions,firestore,auth,storage';

/** エミュレータを立ち上げたうえで実行させたいコマンド。 */
const SCRIPT = 'node test/integration.mjs';

const env = {
  ...process.env,
  FUNCTIONS_DISCOVERY_TIMEOUT: process.env.FUNCTIONS_DISCOVERY_TIMEOUT ?? '120',
};

function run(command, args) {
  return new Promise((resolve) => {
    const child = isWindows
      ? spawn([command, ...args].join(' '), { stdio: 'inherit', cwd: here, shell: true, env })
      : spawn(command, args, { stdio: 'inherit', cwd: here, env });
    child.on('error', () => resolve(null));
    child.on('close', resolve);
  });
}

/** そのポートで誰かが待ち受けているか。 */
function portInUse(port) {
  return new Promise((resolve) => {
    const socket = connect({ port, host: '127.0.0.1' });
    const done = (inUse) => {
      socket.destroy();
      resolve(inUse);
    };
    socket.once('connect', () => done(true));
    socket.once('error', () => done(false));
    socket.setTimeout(1000, () => done(false));
  });
}

/** firebase.json からエミュレータのポートを読む。 */
function emulatorPorts() {
  const fallback = {
    functions: 5001, firestore: 8080, auth: 9099, storage: 9199, pubsub: 8085,
  };
  try {
    const config = JSON.parse(readFileSync(join(here, '..', 'firebase.json'), 'utf8'));
    return Object.fromEntries(
      Object.entries(fallback).map(([name, port]) => [
        name,
        config.emulators?.[name]?.port ?? port,
      ])
    );
  } catch {
    return fallback;
  }
}

const PORTS = emulatorPorts();

/** 実行ファイル名つきで、そのポートを握っているプロセスを返す。 */
function listenerOn(port) {
  return new Promise((resolve) => {
    // Windows は netstat、それ以外は lsof。どちらも標準で入っている。
    const command = isWindows
      ? `netstat -ano -p tcp | findstr LISTENING | findstr :${port}`
      : `lsof -nP -t -iTCP:${port} -sTCP:LISTEN`;
    const child = spawn(command, { shell: true });
    let out = '';
    child.stdout?.on('data', (d) => (out += d));
    child.on('error', () => resolve(null));
    child.on('close', () => {
      const pid = isWindows
        ? out.trim().split(/\r?\n/)[0]?.trim().split(/\s+/).pop()
        : out.trim().split(/\r?\n/)[0]?.trim();
      resolve(/^\d+$/.test(pid ?? '') ? Number(pid) : null);
    });
  });
}

/** そのプロセスの実行ファイル名。判断を誤って別のものを落とさないために見る。 */
function imageName(pid) {
  return new Promise((resolve) => {
    const command = isWindows
      ? `tasklist /FI "PID eq ${pid}" /FO CSV /NH`
      : `ps -p ${pid} -o comm=`;
    const child = spawn(command, { shell: true });
    let out = '';
    child.stdout?.on('data', (d) => (out += d));
    child.on('error', () => resolve(null));
    child.on('close', () => {
      const text = out.trim();
      resolve(isWindows ? (text.split(',')[0] ?? '').replace(/"/g, '') : text);
    });
  });
}

function killPid(pid) {
  return new Promise((resolve) => {
    const command = isWindows ? `taskkill /F /PID ${pid}` : `kill -9 ${pid}`;
    const child = spawn(command, { shell: true, stdio: 'ignore' });
    child.on('error', () => resolve(false));
    child.on('close', (code) => resolve(code === 0));
  });
}

/**
 * 前回の実行が残していったエミュレータを片付ける。
 *
 * **firebase の後片付けは、Windows では取りこぼす。** 実測では
 * `emulators:exec` を終えても **Pub/Sub エミュレータ（8085）だけが
 * 生き残る**。次の実行は `Could not start Pub/Sub Emulator, port taken.`
 * で止まり、**テストを 1 件も走らせないまま失敗する**。
 * 自動で回す以上、ここで詰まると誰も気づかないので、こちらで片付ける。
 *
 * **落としてよいと判断できるときだけ落とす。** この関数は
 * 「関数エミュレータ（5001）が居ない」ときにしか呼ばれない。
 * 開発用に立てているエミュレータなら 5001 が居るはずなので、
 * ここへ来る時点で残骸だと判断できる。
 * さらに、実行ファイルが java / node であることまで確かめてから落とす。
 */
async function reapStaleEmulators() {
  const reaped = [];
  for (const [name, port] of Object.entries(PORTS)) {
    const pid = await listenerOn(port);
    if (pid === null) continue;
    const image = (await imageName(pid)) ?? '';
    if (!/^(java|node)(\.exe)?$/i.test(image.trim())) {
      console.error('');
      console.error(`ポート ${port}（${name}）を ${image || '不明なプロセス'} が使っています。`);
      console.error('  エミュレータではないため、こちらでは止めません。');
      console.error('  そのプロセスを終了してから、もう一度実行してください。');
      console.error('');
      process.exit(1);
    }
    if (await killPid(pid)) reaped.push(`${name}（${port}）`);
  }
  if (reaped.length > 0) {
    console.log(`==> 前回の残り物を片付けました: ${reaped.join('、')}`);
  }
}

// ---------------------------------------------------------------------------
// すでに動いているエミュレータがあれば、そちらへ繋ぐ。
//
// **勝手に落とさない。** 開発用に立てている窓を、テストの都合で
// 止めてよいものとして扱わない。
// ---------------------------------------------------------------------------

if (await portInUse(PORTS.functions)) {
  console.log('==> エミュレータはすでに動いています。そこへ繋いで実行します。');
  console.log('');
  const code = await run('node', ['test/integration.mjs']);
  process.exit(code ?? 1);
}

// ---------------------------------------------------------------------------
// 自分で起動して実行する。
// ---------------------------------------------------------------------------

await reapStaleEmulators();

const build = await run('npm', ['run', 'build']);
if (build !== 0) {
  console.error('\nビルドに失敗しました。エミュレータは起動しません。');
  process.exit(1);
}

console.log(`\n==> エミュレータを起動して統合テストを実行（プロジェクト: ${PROJECT}）`);
console.log(`    関数の読み取り待ち時間: ${env.FUNCTIONS_DISCOVERY_TIMEOUT} 秒`);
console.log('    終わったらエミュレータは自動で止まります。');
console.log('');

const options = ['emulators:exec', '--project', PROJECT, '--only', ONLY];

const child = isWindows
  ? spawn(`firebase ${options.join(' ')} "${SCRIPT}"`, { stdio: 'inherit', cwd: here, shell: true, env })
  : spawn('firebase', [...options, SCRIPT], { stdio: 'inherit', cwd: here, env });

child.on('error', (error) => {
  console.error('firebase コマンドを起動できませんでした:', error.message);
  console.error('npm install -g firebase-tools で導入してください。');
  process.exit(1);
});
child.on('exit', (code) => process.exit(code ?? 1));
