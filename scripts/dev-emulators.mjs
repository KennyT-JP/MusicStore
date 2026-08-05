#!/usr/bin/env node
/**
 * エミュレータを起動する（仕様書 12.6）
 *
 * Functions のビルドを先に済ませてから起動する。ビルドを忘れると
 * 「Failed to load function definition from source」で起動に失敗するため。
 *
 *   ./scripts/dev-emulators.sh   （macOS / Linux）
 *   scripts\dev-emulators.cmd    （Windows）
 *
 * 停止するときは Ctrl+C。データは毎回消える。
 *
 * ---
 *
 * **処理の本体をここに置いている理由**
 *
 * 以前は .sh と .cmd に同じ内容を二重に書いていたが、2 つ問題があった。
 *
 * 1. 片方を直してもう片方を直し忘れる。
 * 2. **Windows のコマンドプロンプトで日本語が壊れる。** バッチファイルは
 *    その時のコードページ（日本語環境では CP932）で読まれるため、UTF-8 で
 *    書いた日本語が別の文字として解釈され、コマンド行そのものが壊れる。
 *
 * Node は Windows でもコンソールへ UTF-16 で直接書き込むため、
 * コードページに関係なく日本語がそのまま出る。
 * .sh と .cmd はこのファイルを呼ぶだけの薄い入り口にしてある。
 */
import { execSync, spawn } from 'node:child_process';
import { existsSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');

// エミュレータ専用のダミープロジェクト。
// demo- で始まる ID を使うと、Firebase CLI がクラウドへ一切アクセスしなくなる。
// （firebase login も不要）
const PROJECT = 'demo-musiclist';

const isWindows = process.platform === 'win32';

/**
 * コマンドを実行して、終わるまで待つ。
 *
 * Windows では firebase / npm の実体が .cmd なので shell 経由でないと
 * 起動できない（Node 20 以降は .cmd の直接起動を拒否する）。
 */
function run(command, args, options = {}) {
  return new Promise((resolve) => {
    const child = spawn(command, args, {
      stdio: 'inherit',
      shell: isWindows,
      ...options,
    });
    child.on('error', () => resolve(null));
    child.on('close', (code) => resolve(code));
  });
}

/** コマンドが使えるか（--version が動くか）で判定する。 */
function exists(command) {
  return new Promise((resolve) => {
    const child = spawn(command, ['--version'], {
      stdio: 'ignore',
      shell: isWindows,
    });
    child.on('error', () => resolve(false));
    child.on('close', (code) => resolve(code === 0));
  });
}

function fail(message, howToFix) {
  console.error(`\n[エラー] ${message}`);
  if (howToFix) console.error(`         → ${howToFix}`);
  process.exit(1);
}

// ---------------------------------------------------------------------------
if (!(await exists('firebase'))) {
  fail(
    'firebase コマンドが見つかりません。',
    isWindows
      ? 'npm install -g firebase-tools を実行し、そのあとコマンドプロンプトを開き直してください（PATH の反映に必要です）'
      : 'npm install -g firebase-tools を実行してください',
  );
}

// Firestore エミュレータは JVM 上で動く。Java が古いと
// 起動の途中で分かりにくいエラーになるので、先に弾く。
{
  let javaVersion = null;
  try {
    javaVersion = execSync('java -version 2>&1', { stdio: ['ignore', 'pipe', 'pipe'] })
      .toString()
      .match(/version "([^"]+)"/)?.[1];
  } catch {
    javaVersion = null;
  }

  const hint = isWindows
    ? 'winget install EclipseAdoptium.Temurin.21.JDK'
    : 'https://adoptium.net/';

  if (!javaVersion) {
    fail('Java が見つかりません。', `Firestore エミュレータに必要です。JDK 21 を入れてください（${hint}）`);
  }

  // Java 8 以前は "1.8.0_492"、9 以降は "21.0.10"。
  const parts = javaVersion.split('.').map((n) => Number.parseInt(n, 10));
  const major = parts[0] === 1 ? parts[1] : parts[0];

  if (Number.isFinite(major) && major < 11) {
    fail(
      `Java が古いです（Java ${major}）。Firestore エミュレータは Java 11 以上が必要です。`,
      `JDK 21 を入れてください（${hint}）`,
    );
  }
}

console.log('==> functions の依存パッケージを確認');
if (!existsSync(join(root, 'functions', 'node_modules'))) {
  const code = await run('npm', ['install'], { cwd: join(root, 'functions') });
  if (code !== 0) fail('npm install に失敗しました。');
}

console.log('==> functions をビルド');
{
  const code = await run('npm', ['run', 'build'], { cwd: join(root, 'functions') });
  if (code !== 0) {
    fail(
      'functions のビルドに失敗しました。',
      'このまま起動しても Failed to load function definition from source で失敗します',
    );
  }
}

console.log(`\n==> エミュレータを起動（プロジェクト: ${PROJECT}）`);
console.log('    管理画面: http://127.0.0.1:4000');
console.log('');
console.log('    別のウィンドウで次を実行するとアプリが繋がります:');
console.log('      flutter run -d chrome --dart-define=USE_EMULATOR=true');
console.log('');
console.log('    停止するときは Ctrl+C。データは毎回消えます。');
console.log('');

// localhost がプロキシ経由になる環境だと、エミュレータ同士の通信が失敗する。
// 念のため除外しておく。
const noProxy = [process.env.NO_PROXY, '127.0.0.1', 'localhost', '::1']
  .filter(Boolean)
  .join(',');

const code = await run('firebase', ['emulators:start', '--project', PROJECT], {
  cwd: root,
  env: { ...process.env, NO_PROXY: noProxy, no_proxy: noProxy },
});

process.exit(code ?? 1);
