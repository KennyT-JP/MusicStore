#!/usr/bin/env node
/**
 * 開発環境の診断
 *
 * エミュレータに繋がらないときに、どこで止まっているかを切り分ける。
 *
 * ```sh
 * node scripts/doctor.mjs
 * ```
 *
 * リポジトリのルートから実行してください。
 */
import { execSync } from 'node:child_process';
import { existsSync, readFileSync } from 'node:fs';
import { createConnection } from 'node:net';
import { hostname } from 'node:os';
import { join } from 'node:path';

const root = process.cwd();
let problems = 0;

/** Windows かどうか。案内するコマンドを出し分けるために使う。 */
const isWindows = process.platform === 'win32';

/** エミュレータ起動スクリプト（OS で名前が違う）。 */
const startCommand = isWindows
  ? 'scripts\\dev-emulators.cmd'
  : './scripts/dev-emulators.sh';

function ok(label, detail = '') {
  console.log(`  ✓ ${label}${detail ? `  ${detail}` : ''}`);
}

function ng(label, howToFix) {
  problems++;
  console.log(`  ✗ ${label}`);
  console.log(`      → ${howToFix}`);
}

function warn(label, detail) {
  console.log(`  ! ${label}`);
  if (detail) console.log(`      ${detail}`);
}

function section(title) {
  console.log(`\n${title}`);
}

function version(command) {
  try {
    return execSync(command, { stdio: ['ignore', 'pipe', 'ignore'] })
      .toString()
      .trim()
      .split('\n')[0];
  } catch {
    return null;
  }
}

/**
 * 標準エラー出力にバージョンを出すコマンド（java など）用。
 *
 * Windows には grep がないので、絞り込みは JS 側で行う。
 */
function versionFromStderr(command, skipLine = () => false) {
  try {
    const out = execSync(`${command} 2>&1`, { stdio: ['ignore', 'pipe', 'pipe'] })
      .toString()
      .trim()
      .split(/\r?\n/)
      .filter((line) => line.trim() && !skipLine(line));
    return out[0] ?? null;
  } catch {
    return null;
  }
}

/** ポートが使われているか（＝何かが待ち受けているか）。 */
function portInUse(port) {
  return new Promise((resolve) => {
    const socket = createConnection({ host: '127.0.0.1', port });
    const done = (result) => {
      socket.destroy();
      resolve(result);
    };
    socket.setTimeout(1200);
    socket.on('connect', () => done(true));
    socket.on('timeout', () => done(false));
    socket.on('error', () => done(false));
  });
}

console.log('音楽リスト共有アプリ — 開発環境の診断');
console.log(`実行しているマシン: ${hostname()}`);
console.log('（この診断は「いま実行しているマシン」の状態だけを見ます）\n');

// -------------------------------------------------------------------------
section('1. 必要なコマンド');

// pubspec.yaml が要求する Dart のバージョン。ここを満たさないと
// flutter pub get が version solving failed で止まる。**よくある詰まりどころ。**
const REQUIRED_DART = [3, 12, 2];

/** 'a.b.c' が REQUIRED_DART 以上か。 */
function dartIsNewEnough(text) {
  const parts = text.split('.').map(Number);
  for (let i = 0; i < REQUIRED_DART.length; i++) {
    const got = parts[i] ?? 0;
    if (got !== REQUIRED_DART[i]) return got > REQUIRED_DART[i];
  }
  return true;
}

let flutterOut = null;
try {
  flutterOut = execSync('flutter --version', { stdio: ['ignore', 'pipe', 'ignore'] }).toString();
} catch {
  flutterOut = null;
}

if (!flutterOut) {
  ng('Flutter が見つかりません', 'https://docs.flutter.dev/get-started/install');
} else {
  const summary = flutterOut.trim().split(/\r?\n/).find((l) => l.startsWith('Flutter')) ?? '';
  const dart = flutterOut.match(/Dart version (\d+\.\d+\.\d+)/)?.[1];

  if (!dart) {
    ok('Flutter', summary);
  } else if (dartIsNewEnough(dart)) {
    ok('Flutter', `${summary}（Dart ${dart}）`);
  } else {
    ng(
      `Flutter が古いです（Dart ${dart} — このアプリは ${REQUIRED_DART.join('.')} 以上が必要）`,
      'flutter upgrade を実行してください。これをしないと flutter pub get が version solving failed で失敗します',
    );
  }
}

const node = version('node --version');
node && Number(node.replace('v', '').split('.')[0]) >= 20
  ? ok('Node.js', node)
  : ng(`Node.js 20 以上が必要です（現在 ${node ?? '未検出'}）`, 'Node.js を更新してください');

// JAVA_TOOL_OPTIONS が設定されていると先頭に "Picked up ..." が出るので取り除く。
const java = versionFromStderr('java -version', (line) => line.startsWith('Picked up'));
java
  ? ok('Java', java)
  : ng(
      'Java が見つかりません',
      'Firestore エミュレータは JVM 上で動きます。JDK 11 以上を入れてください',
    );

const firebase = version('firebase --version');
firebase
  ? ok('Firebase CLI', firebase)
  : ng('Firebase CLI が見つかりません', 'npm install -g firebase-tools');

// -------------------------------------------------------------------------
section('2. プロジェクトの状態');

existsSync(join(root, 'firebase.json'))
  ? ok('firebase.json')
  : ng(
      'firebase.json が見つかりません',
      'リポジトリのルート（pubspec.yaml がある場所）で実行してください',
    );

existsSync(join(root, 'functions', 'node_modules'))
  ? ok('functions の依存パッケージ')
  : ng(
      'functions の依存パッケージが入っていません',
      'cd functions && npm install',
    );

// Functions はビルドしてからでないとエミュレータに読み込まれない。
// **エミュレータに繋がらない原因として一番多い。**
existsSync(join(root, 'functions', 'lib', 'index.js'))
  ? ok('functions のビルド結果（functions/lib）')
  : ng(
      'functions がビルドされていません',
      `cd functions && npm run build（または ${startCommand} を使う）`,
    );

// -------------------------------------------------------------------------
section('3. エミュレータのポート');

const ports = [
  { port: 4000, name: 'Emulator UI' },
  { port: 4400, name: 'Emulator Hub' },
  { port: 5001, name: 'Functions' },
  { port: 8080, name: 'Firestore' },
  { port: 9099, name: 'Authentication' },
  { port: 9199, name: 'Storage' },
];

const running = [];
for (const { port, name } of ports) {
  const inUse = await portInUse(port);
  if (inUse) running.push(name);
  console.log(`  ${inUse ? '●' : '○'} ${String(port).padEnd(5)} ${name}${inUse ? '（起動中）' : ''}`);
}

if (running.length === 0) {
  warn(
    'エミュレータが起動していません',
    'このマシンでは、どのエミュレータも待ち受けていません。',
  );
  console.log(`      ${startCommand} を実行してから、もう一度この診断を動かしてください。`);
  console.log('');
  console.log('      なお 127.0.0.1 は「いま自分が使っているマシン」を指します。');
  console.log('      別のマシン（WSL / Dev Container / SSH 先など）で起動した場合は、');
  console.log('      そのままではブラウザから開けません。ポート転送が必要です。');
  console.log('      詳しくは docs/SETUP.md の「エミュレータに繋がらないとき」を参照してください。');
} else if (running.length < ports.length) {
  warn(
    `一部だけ起動しています（${running.join(' / ')}）`,
    'firebase emulators:start の --only の指定を確認してください。',
  );
} else {
  ok('すべてのエミュレータが起動しています');
}

// -------------------------------------------------------------------------
section('4. 接続の確認');

if (running.length > 0) {
  // Auth エミュレータに実際に話しかけてみる。
  // curl は Windows に無い場合があるので Node 本体の fetch を使う。
  let reached = false;
  try {
    const res = await fetch('http://127.0.0.1:9099/', {
      signal: AbortSignal.timeout(5000),
    });
    reached = res.ok;
  } catch {
    reached = false;
  }

  reached
    ? ok('Authentication エミュレータに接続できました')
    : warn(
        'Authentication エミュレータに接続できませんでした',
        `プロキシ設定が localhost を横取りしていないか確認してください（NO_PROXY に 127.0.0.1 を追加。${
          isWindows ? 'Windows は set NO_PROXY=127.0.0.1,localhost' : 'export NO_PROXY=127.0.0.1,localhost'
        }）。`,
      );
}

// -------------------------------------------------------------------------
section('5. アプリの起動方法');

console.log('  エミュレータに繋ぐには --dart-define が必要です：');
console.log('      flutter run -d chrome --dart-define=USE_EMULATOR=true');
console.log('');
console.log('  これを付けないと検証環境（クラウド）に繋ごうとして、');
console.log('  接続設定が未記入なら FirebaseNotConfiguredError で止まります。');

// -------------------------------------------------------------------------
section('6. Firebase プロジェクトの設定');

try {
  const rc = JSON.parse(readFileSync(join(root, '.firebaserc'), 'utf8'));
  const projects = rc.projects ?? {};
  console.log(`  default : ${projects.default ?? '(未設定)'}`);
  console.log(`  staging : ${projects.staging ?? '(未設定)'}`);
  console.log(`  prod    : ${projects.prod ?? '(未設定)'}`);
  console.log('');
  console.log('  エミュレータを使うときは --project demo-musiclist を付けてください。');
  console.log('  付けないと上の実プロジェクトに接続しようとし、firebase login が必要になります。');
} catch {
  warn('.firebaserc を読めませんでした');
}

// -------------------------------------------------------------------------
console.log('');
if (problems === 0) {
  console.log('問題は見つかりませんでした。');
} else {
  console.log(`${problems} 件の問題が見つかりました。上の → の手順を試してください。`);
}
process.exit(problems === 0 ? 0 : 1);
