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
import { execSync, spawnSync } from 'node:child_process';
import { existsSync, readFileSync } from 'node:fs';
import { createConnection } from 'node:net';
import { hostname } from 'node:os';
import { join } from 'node:path';

const root = process.cwd();
let problems = 0;

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

const flutter = version('flutter --version');
flutter
  ? ok('Flutter', flutter)
  : ng('Flutter が見つかりません', 'https://docs.flutter.dev/get-started/install');

const node = version('node --version');
node && Number(node.replace('v', '').split('.')[0]) >= 20
  ? ok('Node.js', node)
  : ng(`Node.js 20 以上が必要です（現在 ${node ?? '未検出'}）`, 'Node.js を更新してください');

// JAVA_TOOL_OPTIONS が設定されていると先頭に長い行が出るので取り除く。
const javaRaw = version('java -version 2>&1');
const java = javaRaw?.startsWith('Picked up')
  ? (version('java -version 2>&1 | grep -v "^Picked up"') ?? javaRaw)
  : javaRaw;
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
      'cd functions && npm run build（または scripts/dev-emulators.sh を使う）',
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
  console.log('      ./scripts/dev-emulators.sh を実行してから、もう一度この診断を動かしてください。');
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
  const probe = spawnSync(
    'curl',
    ['-sf', '-o', '/dev/null', '-w', '%{http_code}', 'http://127.0.0.1:9099/'],
    { encoding: 'utf8', timeout: 5000 },
  );
  probe.stdout?.startsWith('2')
    ? ok('Authentication エミュレータに接続できました')
    : warn(
        'Authentication エミュレータに接続できませんでした',
        'プロキシ設定が localhost を横取りしていないか確認してください（NO_PROXY に 127.0.0.1 を追加）。',
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
