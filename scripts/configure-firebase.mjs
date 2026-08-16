#!/usr/bin/env node
/**
 * Flutter 側の Firebase 接続設定を生成する（仕様書 12.2）
 *
 *   ./scripts/configure-firebase.sh          検証環境（既定）
 *   ./scripts/configure-firebase.sh prod     本番環境
 *
 *   scripts\configure-firebase.cmd           Windows も同じ
 *
 * 実行前に `firebase login` が必要です。
 *
 * ---
 *
 * **flutterfire コマンドを直接呼ばない理由**
 *
 * `dart pub global activate flutterfire_cli` は実行ファイルを
 * pub のキャッシュ（Windows なら %LOCALAPPDATA%\Pub\Cache\bin）に置くが、
 * **このフォルダは PATH に入っていないことが多い。** そのため
 * `flutterfire` と打っても「認識されていません」になる。
 *
 * `dart pub global run` 経由なら PATH に関係なく起動できるので、
 * こちらを使う。未導入なら activate も自動で行う。
 */
import { spawn } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const isWindows = process.platform === 'win32';

const argv = process.argv.slice(2);
const wantsProd = argv.includes('prod');

// 既定は web だけ。Android / iOS を含めたくなったら --platforms で上書きする。
// Web だけ先に作っておいて、あとから足しても問題ない（生成し直しは安全）。
const platforms =
  argv.find((a) => a.startsWith('--platforms='))?.split('=')[1] ?? 'web';

const target = wantsProd
  ? { alias: 'prod', label: '本番環境', out: 'lib/env/firebase_options_prod.dart' }
  : { alias: 'staging', label: '検証環境', out: 'lib/env/firebase_options_staging.dart' };

function run(command, args, options = {}) {
  return new Promise((resolve) => {
    const child = spawn(command, args, { stdio: 'inherit', shell: isWindows, cwd: root, ...options });
    child.on('error', () => resolve(null));
    child.on('close', (code) => resolve(code));
  });
}

function fail(message, howToFix) {
  console.error(`\n[エラー] ${message}`);
  if (howToFix) console.error(`         → ${howToFix}`);
  process.exit(1);
}

// -------------------------------------------------------------------------
const projectId = (() => {
  try {
    const rc = JSON.parse(readFileSync(join(root, '.firebaserc'), 'utf8'));
    return rc.projects?.[target.alias] ?? null;
  } catch {
    return null;
  }
})();

if (!projectId) fail(`.firebaserc に ${target.alias} のプロジェクト ID がありません。`);

console.log(`==> ${target.label}の接続設定を生成`);
console.log(`    プロジェクト: ${projectId}`);
console.log(`    出力先      : ${target.out}`);
console.log(`    対象        : ${platforms}`);

// dart は Flutter に同梱されている。見つからなければ flutter 経由で試す。
console.log('\n==> flutterfire_cli を準備');
let dartCommand = 'dart';
{
  const code = await run('dart', ['--version'], { stdio: 'ignore' });
  if (code !== 0) {
    const viaFlutter = await run('flutter', ['--version'], { stdio: 'ignore' });
    if (viaFlutter !== 0) {
      fail('dart も flutter も見つかりません。', 'https://docs.flutter.dev/get-started/install');
    }
    dartCommand = 'flutter';
  }
}

/** `dart pub ...` / `flutter pub ...` のどちらでも通る形にする。 */
const pub = (...args) => run(dartCommand, ['pub', ...args]);

{
  // 導入済みでも実行してよい（更新されるだけ）。
  const code = await pub('global', 'activate', 'flutterfire_cli');
  if (code !== 0) fail('flutterfire_cli の導入に失敗しました。');
}

console.log('\n==> flutterfire configure を実行');
console.log('    途中で確認を求められたら、そのまま応答してください。\n');
{
  // PATH を通さずに済ませるため、pub global run 経由で起動する。
  const code = await pub(
    'global',
    'run',
    'flutterfire_cli:flutterfire',
    'configure',
    `--project=${projectId}`,
    `--out=${target.out}`,
    `--platforms=${platforms}`,
    // **検証環境のパッケージ名を明示する（2026-08-16 に追加）。**
    //
    // `android/app/build.gradle.kts` にフレーバーを入れ、検証環境は
    // `applicationIdSuffix = ".dev"` が付くようにした。ところが
    // **flutterfire は `applicationId`（接尾辞なし＝本番の値）を既定に使う。**
    //
    // 明示しないまま検証環境へ流すと、**検証プロジェクトに「本番と同じ
    // パッケージ名」のアプリが新しく作られる。** しかもエラーにならない
    // ——作成に成功してしまうので、気づくのは「Google ログインが検証環境で
    // 動かない」と分かったときになる（パッケージ名＋SHA-1 の組み合わせは
    // プロジェクトをまたいで一意なので、本番が押さえている側が勝つ）。
    //
    // **接尾辞は build.gradle.kts が正本。** ここに書き写した値がずれると
    // 同じ事故が起きるので、`test/domain/android_platform_test.dart` が
    // 両者の一致を見張っている。
    ...(platforms.includes('android') && !wantsProd
      ? ['--android-package-name=jp.sessionconcierge.trackcabinet.dev']
      : []),
    // **無人で流せるようにする。** 生成物の上書き確認で止まると、
    // 自動で回している経路（配信前の準備など）が無言で固まる。
    '--yes',
  );
  if (code !== 0) {
    fail(
      'flutterfire configure に失敗しました。',
      'firebase login が済んでいるか、そのアカウントがこのプロジェクトを見られるか確認してください',
    );
  }
}

console.log('');
console.log(`==> 完了（${target.out}）`);
console.log('    続けてデプロイする場合:');
console.log(isWindows ? '      scripts\\deploy.cmd' : '      ./scripts/deploy.sh');
