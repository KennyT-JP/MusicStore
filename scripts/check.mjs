#!/usr/bin/env node
/**
 * 配信前の検証を、全部まとめて並列に実行する
 *
 *   scripts\check.cmd        Windows
 *   ./scripts/check.sh       macOS / Linux
 *
 * 5 本を同時に走らせる。互いに独立なので待ち合わせる理由が無い。
 *
 *   ├─ dart analyze --fatal-infos   （info も失敗。基準は「指摘 0 件」）
 *   ├─ flutter test                 （321 件）
 *   ├─ functions の単体テスト       （85 件）
 *   ├─ functions の統合テスト       （96 件。起動〜後片付けまで自動）
 *   └─ セキュリティルール           （130 件。同上・専用ポートで並走）
 *
 * 直列だと 7〜8 分かかっていたものが、いちばん遅い 1 本（統合テスト）
 * ぶんで終わる。出力は本ごとに貯めて、終わった順に結果だけを出す。
 * 失敗した本だけ、最後にログの末尾を並べる。
 *
 * **全部緑なら、そのコミットの ID を `.last-check.json` に書く。**
 * `scripts/deploy.mjs` はこれを見て「このコミットは検証済みか」を判断する。
 * 検証と配信を別々の約束にせず、機械的に繋ぐため。
 */
import { spawn } from 'node:child_process';
import { existsSync, readdirSync, writeFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const isWindows = process.platform === 'win32';

// ---------------------------------------------------------------------------
// Java（エミュレータは JVM の上で動く）
//
// **21 以上でなければならない**（firebase-tools 15 以降の要件）。
// 「入っているか」だけを見ると、17 と 21 が並んでいる環境で古いほうを
// 掴む（2026-08-08 に実際に起きた）。版まで見て、いちばん新しいものを選ぶ。
// ---------------------------------------------------------------------------

const JAVA_MIN = 21;

function javaVersionOf(javaPath, env) {
  return new Promise((resolve) => {
    const child = spawn(`"${javaPath}" -version`, { shell: true, env });
    let out = '';
    child.stdout?.on('data', (d) => (out += d));
    child.stderr?.on('data', (d) => (out += d));
    child.on('error', () => resolve(null));
    child.on('close', () => resolve(out.match(/version "(\d+)/)?.[1] * 1 || null));
  });
}

async function withJava(env) {
  const pathKey = Object.keys(env).find((k) => k.toUpperCase() === 'PATH') ?? 'PATH';
  const onPath = await javaVersionOf('java', env);
  if (onPath !== null && onPath >= JAVA_MIN) return env;

  let best = null;
  const bases = isWindows
    ? ['C:\\Program Files\\Microsoft', 'C:\\Program Files\\Java', 'C:\\Program Files\\Eclipse Adoptium']
    : [];
  for (const base of bases) {
    if (!existsSync(base)) continue;
    for (const entry of readdirSync(base)) {
      const exe = join(base, entry, 'bin', 'java.exe');
      if (!existsSync(exe)) continue;
      const version = await javaVersionOf(exe, env);
      if (version !== null && version >= JAVA_MIN && (best === null || version > best.version)) {
        best = { version, bin: join(base, entry, 'bin') };
      }
    }
  }
  if (best === null) {
    console.error(`\nJava ${JAVA_MIN} 以上が見つかりません（firebase-tools 15 以降の要件）。`);
    console.error(`  winget install --id Microsoft.OpenJDK.${JAVA_MIN}\n`);
    process.exit(1);
  }
  env[pathKey] = [best.bin, env[pathKey]].filter(Boolean).join(isWindows ? ';' : ':');
  return env;
}

// ---------------------------------------------------------------------------
// 実行の部品
// ---------------------------------------------------------------------------

const env = await withJava({ ...process.env });

/** 出力を貯めて実行する。並列で走らせても画面が混ざらないように。 */
function runQuiet(command, args, cwd) {
  return new Promise((resolve) => {
    const started = Date.now();
    // Windows では 1 本の文字列で渡す（配列 + shell は引用符が壊れる）。
    const child = isWindows
      ? spawn([command, ...args].join(' '), { shell: true, cwd, env })
      : spawn(command, args, { cwd, env });
    let output = '';
    child.stdout?.on('data', (d) => (output += d));
    child.stderr?.on('data', (d) => (output += d));
    child.on('error', (e) => resolve({ ok: false, ms: Date.now() - started, output: String(e) }));
    child.on('close', (code) => resolve({ ok: code === 0, ms: Date.now() - started, output }));
  });
}

const seconds = (ms) => `${Math.round(ms / 1000)}s`;

/** 1 本ぶんの検証。終わった時点で 1 行だけ結果を出す。 */
async function step(name, summaryPattern, command, args, cwd) {
  const result = await runQuiet(command, args, cwd);
  if (!result.ok) {
    console.log(`  ✗ ${name}（${seconds(result.ms)}）`);
    return { name, ok: false, ms: result.ms, output: result.output };
  }
  const summary = result.output.match(summaryPattern)?.[0] ?? '';
  console.log(`  ✓ ${name}（${seconds(result.ms)}）${summary ? `  ${summary}` : ''}`);
  return { name, ok: true, ms: result.ms, output: result.output };
}

// ---------------------------------------------------------------------------
// 実行
// ---------------------------------------------------------------------------

console.log('==> 検証を並列で開始（5 本）');
const startedAll = Date.now();

// **5 本とも同時に走らせる（2026-08-09）。**
//
// 以前はエミュレータを使う 2 本（統合・ルール）がポートを取り合うため
// 内部で直列だった。ルールテスト専用の設定（firebase.rules-test.json）で
// 別のポートに立てるようにしたので、いまは取り合わない。
// 全体の長さは、いちばん遅い 1 本（統合テスト）でほぼ決まる。
//
// **並列と直列は実測で比べた（2026-08-09）。** 全部並列 = 189 秒。
// 1 本ずつの単独実行の合計（= 直列の見積もり）≈ 300 秒。
// 「統合だけ後回しで残りを並列」も試算したが約 230 秒で、全部並列に
// 及ばない。取り合いで統合が伸びる（単独 135 秒 → 並列中 189 秒）より、
// 重ねて隠れる時間のほうが大きい。
//
// **エミュレータ系は、同時に走る他の本から割を食う。** JVM と Node の
// 上で動くので、混んでいる機械では応答が目に見えて遅くなる（実測で
// 280 秒 → 1111 秒）。**遅いだけで失敗にしない**よう、待ち時間には
// 余裕を持たせてある（functions/test/integration.mjs の CALL_TIMEOUT_MS、
// rules-test/vitest.config.js の testTimeout）。
const results = await Promise.all([
  step('dart analyze', /No issues found!/, 'dart', ['analyze', '--fatal-infos'], root),
  step('flutter test', /\+\d+: All tests passed!/, 'flutter', ['test'], root),
  step('functions 単体', /Tests\s+\d+ passed/, 'npm', ['test'], join(root, 'functions')),
  step('functions 統合', /=== \d+ \/ \d+ 成功 ===/, 'node', ['run-integration.mjs'], join(root, 'functions')),
  step('セキュリティルール', /Tests\s+\d+ passed/, 'npm', ['test'], join(root, 'rules-test')),
]);

const failed = results.filter((r) => !r.ok);

console.log('');
if (failed.length > 0) {
  for (const f of failed) {
    console.error(`----- ${f.name} の出力（末尾） -----`);
    console.error(f.output.split('\n').slice(-40).join('\n'));
  }
  console.error(`\n[失敗] ${failed.map((f) => f.name).join('、')}`);
  console.error('  1 件でも赤い状態で配信してはいけません（CLAUDE.md）。');
  process.exit(1);
}

// 全部緑。このコミットが検証済みであることを配信スクリプトへ伝える。
//
// **未コミットの変更があるときは印を書かない。** 印は「このコミット ID の
// 中身を検証した」という意味であって、作業ツリーが違えば嘘になる。
// （接続設定の 2 ファイルは、手元だけ実際の値なのが正常なので除く）
const generated = new Set([
  'lib/env/firebase_options_staging.dart',
  'lib/env/firebase_options_prod.dart',
]);
const dirty = (await runQuiet('git', ['status', '--porcelain'], root)).output
  .split('\n').map((l) => l.trim()).filter(Boolean)
  .map((l) => l.replace(/^\S+\s+/, ''))
  .filter((p) => !generated.has(p));

if (dirty.length > 0) {
  console.log('==> すべて成功。ただし未コミットの変更があるため、検証済みの印は残しません');
  console.log(`    （${dirty.length} 件: ${dirty.slice(0, 5).join(', ')}）`);
  console.log('    コミットしてから配信すると、配信側がもう一度検証を回します。');
  process.exit(0);
}

// コミット ID に加えて**ツリー（内容そのもの）の ID** も残す。
// dev で検証したあと main へ --no-ff でマージすると、コミット ID は
// 変わるが内容は同一になる。内容が同じなら検証し直す理由は無いので、
// 配信側はツリーで突き合わせる。
// ツリーは `HEAD^{tree}` ではなく `--format=%T` で取る。
// Windows では shell（cmd.exe）越しに起動しており、cmd は `^` を
// エスケープ文字として食べてしまう（`HEAD^{tree}` → `HEAD{tree}`）。
const commit = (await runQuiet('git', ['rev-parse', 'HEAD'], root)).output.trim();
const tree = (await runQuiet('git', ['show', '-s', '--format=%T', 'HEAD'], root)).output.trim();
writeFileSync(join(root, '.last-check.json'), JSON.stringify({
  commit,
  tree,
  when: new Date().toISOString(),
  steps: results.map((r) => ({ name: r.name, ms: r.ms })),
}, null, 2));

console.log(`==> すべて成功（${seconds(Date.now() - startedAll)}）`);
console.log('    配信する: ' + (isWindows ? 'scripts\\deploy.cmd' : './scripts/deploy.sh'));
