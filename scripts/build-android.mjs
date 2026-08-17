#!/usr/bin/env node
/**
 * Android の成果物（AAB / APK）をビルドし、その場で中身を検査する
 *
 *   node scripts\build-android.mjs                 本番 AAB をビルドして検査
 *   node scripts\build-android.mjs --apk           本番 APK をビルドして検査
 *   node scripts\build-android.mjs --verify <path> ビルドせず手元の .aab/.apk を検査
 *
 * ## なぜビルドと検査を 1 本にしたか（監査 第5回・群C・AP-71）
 *
 * かつて **アプリのコードが 1 行も入っていない 42.4MB の空 APK** を
 * 「ビルド成功」として踏んだ。`flutter build` は終了コード 0 を返し、
 * ファイルも出来ているのに、Dart の本体（`libapp.so`）が中身の無い
 * 抜け殻だった。**「ビルドが成功した」と「中身が入っている」は別の話**
 * であって、前者だけを見ると後者を見落とす。
 *
 * だから、ビルドの直後に成果物を開いて `libapp.so` を 2 つの条件で検査し、
 * 欠けていれば**非 0 で明確に落ちる**ようにした。人が目視で確かめる工程を
 * 挟まずに済むよう、機械的に繋ぐのが狙い。
 *
 * ## 検査の 2 条件（正常なら両方満たす）
 *
 *   (a) `libapp.so` のサイズが 5MB 以上
 *   (b) バイト列に ASCII `MusicListApp` を含む
 *
 * 実測（2026-08）: 正常な prod AAB の arm64 `libapp.so` は約 8.26MB で
 * `MusicListApp` を 1 件含む。空 APK 事故のときは約 1.97MB しか無かった。
 * 5MB を下限に置けば、中身の抜けた抜け殻を確実に弾ける。
 *
 * ## zip の展開は JDK の `jar` を使う（依存を増やさない）
 *
 * AAB も APK も実体は zip。`scripts/check.mjs` が JDK21+ を保証しており
 * その `bin/` には `jar` が同梱されている。`unzip` を別途入れる必要が無い。
 * `jar tf` で一覧を確かめ、`jar xf <archive> <entry>` で目的の 1 ファイルだけ
 * を一時ディレクトリへ取り出す（64MB 全体を展開しない）。検査後に掃除する。
 *
 * ## 成果物の中の `libapp.so` の位置
 *
 *   AAB: base/lib/arm64-v8a/libapp.so
 *   APK: lib/arm64-v8a/libapp.so
 *
 * どちらも末尾は `lib/arm64-v8a/libapp.so` なので、一覧からその末尾で
 * 引く（AAB / APK を場合分けしなくてよい）。
 *
 * ## フレーバー（dev / prod）に注意
 *
 * このプロジェクトは Android のフレーバーが dev / prod に分かれている。
 * `--flavor prod` を付けないと Flutter が最後に「.aab が見つからない」と
 * 誤報する（探しに行く先がフレーバー無しの出力先になるため）。既定で
 * `--flavor prod` を付け、出力は下記に決め打ちする。
 *
 *   AAB: build/app/outputs/bundle/prodRelease/app-prod-release.aab
 *   APK: build/app/outputs/flutter-apk/app-prod-release.apk
 */
import { spawn } from 'node:child_process';
import { existsSync, mkdtempSync, readFileSync, readdirSync, rmSync, statSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const isWindows = process.platform === 'win32';

// ---------------------------------------------------------------------------
// 検査の中核（純関数）
//
// **ここだけは外部に一切依存しない。** Buffer を渡すと結果を返すだけの
// 純関数にしてあるので、`node --test` で 3 分のビルド無しに固定できる
// （scripts/build-android.verify.test.mjs）。build-android.mjs 本体は
// この関数へ「取り出した libapp.so の中身」を渡す役に徹する。
// ---------------------------------------------------------------------------

const DEFAULT_MIN_BYTES = 5 * 1024 * 1024; // 5MB。空 APK 事故の 1.97MB を弾ける下限
const DEFAULT_SYMBOL = 'MusicListApp';

/**
 * `libapp.so` の中身（Buffer）が本物かを検査する。
 *
 * @param {Buffer} buffer 取り出した libapp.so の全バイト
 * @param {{minBytes?: number, symbol?: string}} [options]
 * @returns {{ok: boolean, sizeBytes: number, hasSymbol: boolean, reason: string|null}}
 */
export function verifyLibapp(buffer, { minBytes = DEFAULT_MIN_BYTES, symbol = DEFAULT_SYMBOL } = {}) {
  const sizeBytes = buffer?.length ?? 0;
  // Buffer.prototype.includes は部分バイト列の検索。ASCII で符号化して探す。
  const hasSymbol = sizeBytes > 0 && buffer.includes(Buffer.from(symbol, 'ascii'));

  const problems = [];
  if (sizeBytes < minBytes) {
    problems.push(`サイズが ${mib(sizeBytes)} で下限 ${mib(minBytes)} 未満`);
  }
  if (!hasSymbol) {
    problems.push(`ASCII "${symbol}" を含まない（Dart 本体が入っていない疑い）`);
  }
  const ok = problems.length === 0;
  return { ok, sizeBytes, hasSymbol, reason: ok ? null : problems.join(' / ') };
}

/** バイト数を MiB 表示に（検査の下限・実測が MB 桁なので読みやすさ優先）。 */
function mib(bytes) {
  return `${(bytes / (1024 * 1024)).toFixed(2)}MB`;
}

// ---------------------------------------------------------------------------
// 実行の部品（deploy.mjs / check.mjs の流儀に寄せる）
// ---------------------------------------------------------------------------

/** 画面に流しながら実行する（ビルドの進捗を見せる）。終了コードを返す。 */
function runInherit(command, args) {
  return new Promise((resolve) => {
    // flutter は Windows では flutter.bat なので shell 経由で起動する。
    const child = isWindows
      ? spawn([command, ...args].join(' '), { stdio: 'inherit', shell: true, cwd: root })
      : spawn(command, args, { stdio: 'inherit', cwd: root });
    child.on('error', () => resolve(null));
    child.on('close', (code) => resolve(code));
  });
}

/**
 * 実 exe を直接起動して出力を持ち帰る（jar 用）。
 * jar.exe は本物の実行ファイルなので shell を通さず、引数配列のまま渡す
 * （パスに空白があっても引用符の心配が要らない）。
 */
function capture(exe, args, cwd) {
  return new Promise((resolve) => {
    const child = spawn(exe, args, { cwd });
    let out = '';
    let err = '';
    child.stdout?.on('data', (d) => (out += d));
    child.stderr?.on('data', (d) => (err += d));
    child.on('error', (e) => resolve({ code: null, out, err: String(e) }));
    child.on('close', (code) => resolve({ code, out, err }));
  });
}

function fail(message, howToFix) {
  console.error(`\n[エラー] ${message}`);
  if (howToFix) console.error(`         → ${howToFix}`);
  process.exit(1);
}

// ---------------------------------------------------------------------------
// jar の在り処を決める
//
// check.mjs が JDK21+ を保証しているので jar は必ずどこかに在る。
// JAVA_HOME → PATH → check.mjs と同じ Windows の基底、の順で探す。
// ---------------------------------------------------------------------------

const jarExe = isWindows ? 'jar.exe' : 'jar';

/** その jar が起動できるか（--version が動くか）だけ確かめる。 */
function jarRuns(exe) {
  return new Promise((resolve) => {
    const child = spawn(exe, ['--version']);
    child.on('error', () => resolve(false));
    child.on('close', () => resolve(true)); // 起動できれば十分（版は check.mjs が保証）
  });
}

async function resolveJar() {
  // 1. JAVA_HOME/bin/jar
  const home = process.env.JAVA_HOME;
  if (home) {
    const p = join(home, 'bin', jarExe);
    if (existsSync(p)) return p;
  }

  // 2. PATH 上の jar
  if (await jarRuns('jar')) return 'jar';

  // 3. Windows の基底を走査（check.mjs の withJava と同じ場所）。
  //    版までは見ない——check.mjs が既に JDK21+ を通しているので、
  //    ここでは jar が同梱された bin を見つけられれば足りる。
  if (isWindows) {
    const bases = ['C:\\Program Files\\Microsoft', 'C:\\Program Files\\Java', 'C:\\Program Files\\Eclipse Adoptium'];
    for (const base of bases) {
      if (!existsSync(base)) continue;
      for (const entry of readdirSync(base)) {
        const p = join(base, entry, 'bin', jarExe);
        if (existsSync(p)) return p;
      }
    }
  }

  fail(
    'JDK の jar コマンドが見つかりません。',
    'AAB / APK の展開に JDK 同梱の jar を使います。JAVA_HOME を設定するか、JDK21+ を入れてください（check.mjs と同じ要件）',
  );
}

// ---------------------------------------------------------------------------
// 成果物から libapp.so を取り出して検査する
// ---------------------------------------------------------------------------

const LIBAPP_SUFFIX = 'lib/arm64-v8a/libapp.so';

/**
 * 成果物（.aab/.apk）の中の arm64 libapp.so を取り出して検査する。
 * 検査に通らなければ非 0 で落ちる。通れば要点を表示する。
 */
async function inspectArtifact(archivePath, jar) {
  if (!existsSync(archivePath)) {
    fail(`成果物がありません: ${archivePath}`, 'ビルドが本当に生成したか、パスが合っているか確認してください');
  }
  const archiveBytes = statSync(archivePath).size;
  console.log(`==> 成果物を検査: ${archivePath}（${mib(archiveBytes)}）`);

  // 1. 一覧から arm64 の libapp.so の正確なエントリ名を引く。
  //    AAB は base/lib/... 、APK は lib/... 。末尾一致で両方を拾う。
  const listed = await capture(jar, ['tf', archivePath]);
  if (listed.code !== 0) {
    fail(`成果物の一覧取得（jar tf）に失敗しました（code=${listed.code}）。`,
         `壊れた zip でないか確認してください。jar のメッセージ: ${listed.err.trim() || '（無し）'}`);
  }
  const entries = listed.out.split('\n').map((l) => l.trim()).filter(Boolean);
  const entry = entries.find((e) => e === LIBAPP_SUFFIX || e.endsWith(`/${LIBAPP_SUFFIX}`));
  if (!entry) {
    fail(
      `成果物に ${LIBAPP_SUFFIX} が入っていません。`,
      'arm64-v8a 向けのネイティブ本体が抜けています。--target-platform / ABI 分割の設定や、そもそもビルドが通っているかを確認してください',
    );
  }

  // 2. その 1 エントリだけを一時ディレクトリへ取り出す（全体を展開しない）。
  const workDir = mkdtempSync(join(tmpdir(), 'trackcabinet-libapp-'));
  try {
    const extracted = await capture(jar, ['xf', archivePath, entry], workDir);
    if (extracted.code !== 0) {
      fail(`libapp.so の取り出し（jar xf）に失敗しました（code=${extracted.code}）。`,
           extracted.err.trim() || '（jar からのメッセージはありません）');
    }
    // jar はエントリのパス構造を保って展開する（base/lib/... がそのまま出来る）。
    const soPath = join(workDir, entry);
    if (!existsSync(soPath)) {
      fail(`取り出したはずの libapp.so が見当たりません（${entry}）。`, 'jar の展開結果が想定と違います');
    }
    const buffer = readFileSync(soPath);

    // 3. 純関数で検査。ここが本体。
    const result = verifyLibapp(buffer);
    console.log(`    ${entry}`);
    console.log(`    サイズ: ${mib(result.sizeBytes)} ／ "${DEFAULT_SYMBOL}" 記号: ${result.hasSymbol ? 'あり' : 'なし'}`);
    if (!result.ok) {
      fail(
        `成果物の中身の検査に失敗しました: ${result.reason}`,
        'アプリのコードが入っていない抜け殻の疑いです（監査 第5回・AP-71 の空 APK 事故と同型）。' +
          'flutter clean のうえ、フレーバーを付けてビルドし直してください',
      );
    }
    console.log('    検査 OK（サイズ・記号とも条件を満たしています）');
  } finally {
    // 一時ディレクトリは必ず掃除する。
    try { rmSync(workDir, { recursive: true, force: true }); } catch { /* 消せなくても実害は無い */ }
  }
}

// ---------------------------------------------------------------------------
// メイン
// ---------------------------------------------------------------------------

function printHelp() {
  console.log(`Android の成果物（AAB / APK）をビルドして中身を検査します。

使い方:
  node scripts/build-android.mjs                 本番 AAB をビルドして検査（既定）
  node scripts/build-android.mjs --apk           本番 APK をビルドして検査
  node scripts/build-android.mjs --verify <path> ビルドせず手元の .aab/.apk を検査
  node scripts/build-android.mjs --help          この説明

検査の 2 条件（どちらか欠けたら非 0 で終了）:
  (a) libapp.so が 5MB 以上
  (b) libapp.so が ASCII "MusicListApp" を含む

いずれのモードも --flavor prod のビルドを前提にしています。`);
}

async function main() {
  const argv = process.argv.slice(2);
  if (argv.includes('--help') || argv.includes('-h')) {
    printHelp();
    process.exit(0);
  }

  const jar = await resolveJar();

  // --verify <path>: ビルドせず、指定ファイルだけを検査する。
  const verifyIdx = argv.indexOf('--verify');
  if (verifyIdx !== -1) {
    const target = argv[verifyIdx + 1];
    if (!target || target.startsWith('-')) {
      fail('--verify には検査する .aab / .apk のパスを渡してください。',
           '例: node scripts/build-android.mjs --verify build/app/outputs/bundle/prodRelease/app-prod-release.aab');
    }
    await inspectArtifact(target, jar);
    console.log('\n==> 検査のみ完了');
    return;
  }

  // ビルド + 検査。既定は AAB、--apk なら APK。
  //
  // **`--dart-define=APP_ENV=prod` を必ず付ける。** これが無いと Dart 側は
  // 既定の staging に倒れ、native（`--flavor prod` の google-services.json）は
  // 本番、という食い違いになる（Firebase 接続先・広告ユニット・共有オリジンが
  // すべて検証側に落ちる）。ストアへ出すのは本番の設定でなければならない。
  const wantsApk = argv.includes('--apk');
  const kind = wantsApk ? 'APK' : 'AAB';
  const buildArgs = wantsApk
    ? ['build', 'apk', '--release', '--flavor', 'prod', '--dart-define=APP_ENV=prod']
    : ['build', 'appbundle', '--release', '--flavor', 'prod', '--dart-define=APP_ENV=prod'];
  const artifact = wantsApk
    ? join(root, 'build', 'app', 'outputs', 'flutter-apk', 'app-prod-release.apk')
    : join(root, 'build', 'app', 'outputs', 'bundle', 'prodRelease', 'app-prod-release.aab');

  console.log(`==> ${kind} をビルド: flutter ${buildArgs.join(' ')}`);
  const code = await runInherit('flutter', buildArgs);
  if (code !== 0) {
    fail(`flutter build ${wantsApk ? 'apk' : 'appbundle'} に失敗しました（code=${code}）。`,
         '上の flutter の出力を読んでください。--flavor prod が付いているかも確認してください');
  }

  // **ここが AP-71 の肝。** ビルド成功（code 0）と中身が入っていることは別。
  await inspectArtifact(artifact, jar);

  console.log(`\n==> 完了（${kind} をビルドし、中身の検査も通りました）`);
  console.log(`    ${artifact}`);
}

// ---------------------------------------------------------------------------
// 起動
//
// **コマンドとして起動されたときだけ main() を走らせる。** テストが
// `import { verifyLibapp }` するときは素通りさせ、副作用を起こさない。
// 全宣言を読み終えた末尾で呼ぶ（const の初期化前に触らないため）。
// ---------------------------------------------------------------------------
const invokedDirectly = process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1];
if (invokedDirectly) {
  await main();
}
