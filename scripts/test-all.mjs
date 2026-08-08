#!/usr/bin/env node
/**
 * 手順書にある検証を、まとめて全部実行する（CLAUDE.md / 仕様書 12.6）
 *
 *   scripts\test-all.cmd      Windows
 *   ./scripts/test-all.sh     macOS / Linux
 *
 * **ウィンドウは 1 つでよい。** エミュレータの起動と後片付けは
 * それぞれの実行役（rules-test/run.mjs・functions/run-integration.mjs）が行う。
 *
 * ---
 *
 * ## なぜこれを足したのか
 *
 * 配信の前に通すべき検証は 5 つある。以前はそれを手順書に箇条書きで
 * 書いてあるだけで、**人が 5 回コマンドを打ち、統合テストのためだけに
 * 窓をもう 1 つ開く**必要があった。
 *
 * 結果として統合テストは一度も実行されず、**赤いまま本番へ配信された**
 * （2026-08-08 に判明。docs/DEVLOG.md）。
 * **手順書に書いてあることは、実行されるとは限らない。**
 * 機械的に確かめられるものは、注意書きではなく実行できる形にする
 * （docs/AUDIT-CHECKLIST.md 観点 4）。
 *
 * ## 途中で止める
 *
 * **1 つでも赤ければ、そこで止める。** 後続を走らせても、最初の赤を
 * 直すまで意味が無い。どこで止まったかは最後にまとめて出す。
 *
 * ## flutter analyze ではなく dart analyze を使う理由
 *
 * **`flutter analyze` は、パスに日本語が含まれると異常終了する**
 * （Flutter 3.44.9 で実測。解析サーバとのやりとりが壊れる）。
 * `dart analyze` は同じ解析器を使い、同じ指摘を出す。
 * 置き場所に左右されないほうを既定にする。
 */
import { spawn } from 'node:child_process';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const isWindows = process.platform === 'win32';

/**
 * 通すべき検証。**順番は速い順。** 手前で落とせるものは手前で落とす。
 * エミュレータを使う 2 つは最後。
 */
const steps = [
  { name: 'dart analyze', command: 'dart', args: ['analyze'], cwd: root },
  { name: 'flutter test', command: 'flutter', args: ['test'], cwd: root },
  { name: 'functions（単体）', command: 'npm', args: ['test'], cwd: join(root, 'functions') },
  { name: 'rules-test', command: 'npm', args: ['test'], cwd: join(root, 'rules-test') },
  { name: 'functions（統合）', command: 'npm', args: ['run', 'test:integration'], cwd: join(root, 'functions') },
];

/**
 * Java を使えるようにする。
 *
 * **エミュレータは JVM の上で動く**（Firestore・Storage）。
 *
 * 気をつけることが 2 つある。
 *
 * 1. **版が 21 以上でなければならない。** `firebase-tools` 15 以降の要件で、
 *    17 では `Please install a JDK at version 21 or above` で止まる。
 *    **入っているかどうかだけを見ると、古いほうを掴む。** 実際に、
 *    17 と 21 が両方ある環境で 17 を選んで失敗した（2026-08-08）。
 *
 * 2. **Windows では、入れた直後のシェルに PATH が反映されていない。**
 *    入っているのに「見つからない」で止まるのは分かりにくいので、
 *    既定の置き場所を探して補う。
 */
const JAVA_MIN_VERSION = 21;

function javaHomeCandidates() {
  if (!isWindows) return [];
  return [
    'C:\\Program Files\\Microsoft',
    'C:\\Program Files\\Java',
    'C:\\Program Files\\Eclipse Adoptium',
  ];
}

/** `java -version` の出力から主要な版番号を取る。読めなければ null。 */
function javaVersionOf(javaPath, env) {
  return new Promise((resolve) => {
    // -version は標準エラーへ出る。
    const child = spawn(`"${javaPath}" -version`, { shell: true, env });
    let out = '';
    child.stdout?.on('data', (d) => (out += d));
    child.stderr?.on('data', (d) => (out += d));
    child.on('error', () => resolve(null));
    child.on('close', () => {
      const match = out.match(/version "(\d+)/);
      resolve(match ? Number(match[1]) : null);
    });
  });
}

async function ensureJavaOnPath(env) {
  const pathKey = Object.keys(env).find((k) => k.toUpperCase() === 'PATH') ?? 'PATH';

  // すでに PATH にあるものが要件を満たしていれば、それを使う。
  const onPath = await javaVersionOf('java', env);
  if (onPath !== null && onPath >= JAVA_MIN_VERSION) {
    console.log(`==> Java ${onPath} を使います（PATH 上）`);
    return env;
  }

  const { existsSync, readdirSync } = await import('node:fs');
  /** 見つかった中でいちばん新しいものを選ぶ。 */
  let best = null;
  for (const base of javaHomeCandidates()) {
    if (!existsSync(base)) continue;
    for (const entry of readdirSync(base)) {
      const exe = join(base, entry, 'bin', 'java.exe');
      if (!existsSync(exe)) continue;
      const version = await javaVersionOf(exe, env);
      if (version === null || version < JAVA_MIN_VERSION) continue;
      if (best === null || version > best.version) best = { version, bin: join(base, entry, 'bin') };
    }
  }

  if (best !== null) {
    // **`PATH` という綴りで足さない。** Windows の既存キーは `Path` で、
    // 別のキーを作ると名前の大小を区別しない Windows 側でどちらが
    // 使われるか決まらなくなる（rules-test/run.mjs に同じ記述）。
    env[pathKey] = [best.bin, env[pathKey]].filter(Boolean).join(isWindows ? ';' : ':');
    console.log(`==> Java ${best.version} を PATH に補いました: ${best.bin}`);
    return env;
  }

  console.error('');
  console.error(
    onPath === null
      ? 'Java が見つかりません。エミュレータを使う検証が実行できません。'
      : `Java ${onPath} が入っていますが、版が足りません。`
  );
  console.error(`  **Java ${JAVA_MIN_VERSION} 以上**が要ります（firebase-tools 15 以降の要件）。`);
  console.error(`  winget install --id Microsoft.OpenJDK.${JAVA_MIN_VERSION}`);
  console.error('');
  process.exit(1);
}

function run(step, env) {
  return new Promise((resolve) => {
    // **Windows では 1 本の文字列で渡す。** 配列と shell:true を混ぜると
    // 引用符が付かずに連結される（rules-test/run.mjs に同じ記述）。
    const child = isWindows
      ? spawn([step.command, ...step.args].join(' '), { stdio: 'inherit', cwd: step.cwd, shell: true, env })
      : spawn(step.command, step.args, { stdio: 'inherit', cwd: step.cwd, env });
    child.on('error', () => resolve(null));
    child.on('close', (code) => resolve(code));
  });
}

// ---------------------------------------------------------------------------

const env = await ensureJavaOnPath({ ...process.env });

const done = [];
for (const step of steps) {
  console.log('');
  console.log(`==> ${step.name}`);
  console.log('');
  const code = await run(step, env);
  if (code !== 0) {
    console.error('');
    console.error(`[失敗] ${step.name}`);
    console.error('');
    console.error('  **ここで止めます。** 1 つでも赤い状態で配信してはいけません（CLAUDE.md）。');
    if (done.length > 0) console.error(`  ここまで通ったもの: ${done.join('、')}`);
    console.error(`  やり直す: ${isWindows ? 'scripts\\test-all.cmd' : './scripts/test-all.sh'}`);
    console.error('');
    process.exit(1);
  }
  done.push(step.name);
}

console.log('');
console.log('==> すべて成功しました');
for (const name of done) console.log(`    - ${name}`);
console.log('');
console.log(`    配信する: ${isWindows ? 'scripts\\deploy.cmd' : './scripts/deploy.sh'}（検証環境）`);
console.log('');
