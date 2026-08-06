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
import { readFileSync } from 'node:fs';
import { connect } from 'node:net';

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

// ---------------------------------------------------------------------------
// 先にポートの空きを見る
//
// このテストは自前でエミュレータを起動して、終わったら落とす。
// 開発用のエミュレータ（scripts/dev-emulators）を別のウィンドウで動かしたまま
// だと、ポートが埋まっていて起動できない。
//
// firebase が出す「port taken」は、**何が原因でどうすればよいのかが読み取れない**。
// ここで先に見て、止め方まで案内する。
// ---------------------------------------------------------------------------

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

const ports = readEmulatorPorts();
const taken = [];
for (const { name, port } of ports) {
  if (await portInUse(port)) taken.push(`${name}（${port}）`);
}

if (taken.length > 0) {
  console.error('');
  console.error(`ポートがすでに使われています: ${taken.join('、')}`);
  console.error('');
  console.error('  エミュレータを別のウィンドウで動かしていませんか。');
  console.error('  そのウィンドウで Ctrl+C を押して止めてから、もう一度実行してください。');
  console.error('');
  console.error('  ウィンドウが見当たらない場合は、残ったプロセスを落とします。');
  if (isWindows) {
    console.error(`    netstat -ano | findstr :${ports[0].port}`);
    console.error('    taskkill /PID <いちばん右の数字> /F');
  } else {
    console.error(`    lsof -i :${ports[0].port}`);
    console.error('    kill <PID>');
  }
  console.error('');
  process.exit(1);
}

/** firebase.json から、このテストが使うエミュレータのポートを読む。 */
function readEmulatorPorts() {
  const fallback = [
    { name: 'firestore', port: 8080 },
    { name: 'storage', port: 9199 },
  ];
  try {
    const config = JSON.parse(
      readFileSync(new URL('../firebase.json', import.meta.url), 'utf8')
    );
    return fallback.map(({ name, port }) => ({
      name,
      port: config.emulators?.[name]?.port ?? port,
    }));
  } catch {
    // 読めなくても本題ではない。既定値で進める。
    return fallback;
  }
}

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
