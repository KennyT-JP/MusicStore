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
import { existsSync, mkdirSync, readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { connect } from 'node:net';
import { delimiter, dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const isWindows = process.platform === 'win32';

const env = { ...process.env };
delete env.JAVA_TOOL_OPTIONS;

// ---------------------------------------------------------------------------
// 一時フォルダを、統合テストと分ける（2026-08-11）
//
// **Storage エミュレータは、置かれたファイルを一時フォルダに書く。**
// その置き場所は `os.tmpdir()/firebase/storage/blobs` で、
// **プロジェクト ID でもポートでも分かれない。**
//
// 統合テストと同時に走らせると、**先に終わったほうがこのフォルダを消し、
// まだ動いているほうの保存が壊れる**。
//
//     ENOENT: no such file or directory, open
//     '…\Temp\firebase\storage\blobs\…'
//
// 検証を並列にしたときだけ落ち、単独ではどちらも通るため、
// 原因が分かりにくい（実際、ポートとプロジェクト ID を分けても直らず、
// エミュレータの詳細ログを読んで初めて分かった）。
//
// Node の `os.tmpdir()` は Windows では TEMP / TMP を見る。
// **こちら専用の場所を渡して、置き場所ごと分ける。**
// ---------------------------------------------------------------------------

const tempDir = join(tmpdir(), 'musicstore-rules-test');
mkdirSync(tempDir, { recursive: true });
env.TEMP = tempDir;
env.TMP = tempDir;
env.TMPDIR = tempDir;

// vitest は依存パッケージなので node_modules/.bin にある。
//
// **firebase emulators:exec は、指定したコマンドを別のシェルで動かす。**
// そのシェルからも見つけられるように、ここで PATH の先頭へ足しておく。
// npm 経由で起動したときは npm が同じことをしてくれるが、
// `node run.mjs` を直に叩いたときは足されないため、こちらで確実にする。
//
// **Windows での変数名は `Path` で、`PATH` ではない。** `env.PATH = ...` と
// 書くと既存の `Path` は残ったまま別の項目ができ、Windows は名前の大小を
// 区別しないので、どちらが使われるか決まらない。実際には中身が
// node_modules/.bin だけの方が採用され、firebase すら見つからなくなった。
// **必ず、今ある項目の綴りを探して、そこへ足す。**
const pathKey =
  Object.keys(env).find((key) => key.toUpperCase() === 'PATH') ?? 'PATH';
env[pathKey] = [join(here, 'node_modules', '.bin'), env[pathKey]]
  .filter(Boolean)
  .join(delimiter);

const options = [
  'emulators:exec',
  '--project',
  // 統合テストと別の ID にする（helpers.js のコメントを参照）。
  'demo-musiclist-rules',
  // **専用の設定で、別のポートに立てる（2026-08-09）。**
  // 統合テストのエミュレータ（ルート設定・8080/9199/4400）と同時に
  // 走らせるため。設定はルートに置いてある——firebase はルールファイルを
  // 設定ファイルの場所から探すので、rules-test の中に置くと
  // 「firestore.rules is outside of project directory」で止まる。
  '--config',
  '../firebase.rules-test.json',
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

// ---------------------------------------------------------------------------
// 依存パッケージ
//
// SETUP.md には `npm install` を先に行うよう書いてあるが、飛ばされると
// 「'vitest' は認識されていません」という、原因の分かりにくい失敗になる。
// エミュレータを起動したあとで失敗するため、なおさら分かりにくい。
// 無ければここで入れる（scripts/seed.mjs と同じ扱い）。
// ---------------------------------------------------------------------------

if (!existsSync(join(here, 'node_modules'))) {
  console.log('==> 依存パッケージを取得します（初回のみ）');
  const code = await new Promise((resolve) => {
    // 引数の配列と shell を併用しない（理由は下の起動処理と同じ）。
    const install = isWindows
      ? spawn('npm install', { stdio: 'inherit', cwd: here, shell: true })
      : spawn('npm', ['install'], { stdio: 'inherit', cwd: here });
    install.on('error', () => resolve(null));
    install.on('close', resolve);
  });
  if (code !== 0) {
    console.error('\nnpm install に失敗しました。');
    process.exit(1);
  }
  console.log('');
}

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

/**
 * このフォルダの firebase.json から、使うエミュレータのポートを読む。
 *
 * **ルートの firebase.json ではない。** ルールテストは統合テストと
 * 同時に走らせるため、専用の設定で別のポートに立てる（2026-08-09。
 * firebase は作業ディレクトリから上へ設定を探すので、ここで起動すれば
 * 自動的にこちらが使われる）。
 */
function readEmulatorPorts() {
  const fallback = [
    { name: 'firestore', port: 8081 },
    { name: 'storage', port: 9198 },
  ];
  try {
    const config = JSON.parse(
      readFileSync(new URL('../firebase.rules-test.json', import.meta.url), 'utf8')
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
