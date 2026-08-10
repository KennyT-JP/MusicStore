/**
 * サーバー側に死蔵コードが増えていないことの確認
 *
 * **回帰テスト。** 同じ指摘が 3 回の監査で続けて出ている。
 *
 * 判定を切り出してテストを厚く書いたのに、**本番からは一度も
 * 呼ばれていない**という形である。テストは緑のまま、実際に動いて
 * いるのは別の場所のコードになる。守っているつもりの範囲が、
 * 実際より広く見える。
 *
 * - 第 1 回：連番と招待 URL のロジックが本番から 0 参照
 * - 第 2 回：`Permissions` の 6 メソッドが本番から 0 参照
 * - 第 3 回：`canWrite` / `isMember` / `optionalString` が 0 参照
 *
 * Dart 側は `test/domain/no_dead_code_test.dart` が見張っている。
 * こちらは TypeScript 側。**片側だけ守っても、もう片側で同じことが起きる。**
 *
 * ---
 *
 * ## 数え方は「他ファイルの import 文」（監査 第4回）
 *
 * 以前は「名前が単語として何回現れるか」を数えていた。その方式には
 * 実験で実証された穴が 3 つあった。
 *
 * 1. **自ファイル内で自己参照する export が検出されない。** 再帰や
 *    自ファイル内の呼び出しで登場回数が増えると、条件（登場 1 回以下）を
 *    満たさなくなり、外から誰も使っていなくても素通りした。
 * 2. **index.ts のコメントの単語まで「入口」として拾う。** 冒頭の対応表に
 *    関数名を書くだけで、その名前は永久に死蔵と判定されなくなっていた。
 * 3. **`export class` と `export { a, b }` を見ない。** その形で出せば
 *    見張りの対象にすら入らなかった。
 *
 * import 文は「他のファイルが実際に取り込んだ」ことの宣言なので、
 * コメントにも自己参照にも騙されない。export の意味は「他のファイルから
 * import できること」だから、**どこからも import されない export は、
 * export である必要がない**（中で使うだけなら export を外す）。
 *
 * テストファイルからの import も「使われている」に数える。`hasAtLeast` の
 * ように、本番では同ファイル内（`isListAdmin`）から呼ばれ、export は
 * 単体テストのためだけ、という判定関数があるため。import 文しか見ない
 * 方式では同ファイル内の呼び出しを数えられない。その分「テストだけが
 * 使う export」への見張りは弱くなるが、そこを機械で見分けるには構文解析が
 * 要る。今の穴 3 つを塞ぐことを優先した。
 */
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { describe, expect, test } from 'vitest';

/// **`new URL(...).pathname` を使わない。**
/// Windows では `/C:/Users/...` のように先頭にスラッシュが付いた形になり、
/// `join` で繋ぐと `C:\C:\Users\...` になって開けない。
/// `fileURLToPath` はその変換まで面倒を見てくれる。
const SRC = fileURLToPath(new URL('../src', import.meta.url));
const TEST = fileURLToPath(new URL('.', import.meta.url));

function sourceFiles(dir: string): string[] {
  const found: string[] = [];
  for (const name of readdirSync(dir)) {
    const path = join(dir, name);
    if (statSync(path).isDirectory()) {
      found.push(...sourceFiles(path));
    } else if (path.endsWith('.ts')) {
      found.push(path);
    }
  }
  return found;
}

/**
 * コメントを除いた本文。
 *
 * コメントに書いた名前を「使われている」と数えないため（上の穴 2）。
 * 文字列リテラルの中の `//` までは区別しない簡易な落とし方だが、
 * ここで見るのは import 文と export 宣言だけなので、行の途中から
 * 消え過ぎても検出には影響しない。
 */
function stripComments(text: string): string {
  return text.replace(/\/\*[\s\S]*?\*\//g, '').replace(/\/\/[^\n]*/g, '');
}

/**
 * そのファイルが import 文で取り込んでいる名前。
 *
 * - `import { a, b as c } from '...'`（`as` は元の名前 a, b を取る）
 * - `export { a } from '...'`（index.ts の再輸出。これも「使う側」）
 * - `const { a } = await import('...')`（テストが使う動的 import）
 */
function importedNames(text: string): string[] {
  const clean = stripComments(text);
  const names: string[] = [];
  const statements = [
    ...clean.matchAll(/(?:import|export)\s+(?:type\s+)?\{([^}]*)\}\s*from\s*['"]/g),
    ...clean.matchAll(/(?:const|let|var)\s*\{([^}]*)\}\s*=\s*await\s+import\s*\(/g),
  ];
  for (const match of statements) {
    for (const piece of (match[1] ?? '').split(',')) {
      const name = piece
        .replace(/^\s*type\s+/, '')
        .trim()
        .split(/\s+as\s+|\s*:\s*/)[0]
        ?.trim();
      if (name) names.push(name);
    }
  }
  return names;
}

/**
 * そのファイルが export している値の名前。
 *
 * `function` / `const` / `class`（async 付き含む）と、まとめ出しの
 * `export { a, b };` を見る（上の穴 3）。`from` 付きの `export { } from`
 * は再輸出（＝使う側）なのでここには入れない。型だけの export
 * （interface / type）は実行コードではないため対象にしない。
 */
function exportedNames(text: string): string[] {
  const clean = stripComments(text);
  const names: string[] = [];
  for (const match of clean.matchAll(
    /export\s+(?:async\s+)?(?:function|const|class)\s+(\w+)/g
  )) {
    if (match[1]) names.push(match[1]);
  }
  for (const match of clean.matchAll(/export\s*\{([^}]*)\}(?!\s*from)/g)) {
    for (const piece of (match[1] ?? '').split(',')) {
      const name = piece.trim().split(/\s+as\s+/)[0]?.trim();
      if (name) names.push(name);
    }
  }
  return names;
}

describe('死蔵コード', () => {
  test('export したものは、他のファイルの import 文に現れる', () => {
    const files = [...sourceFiles(SRC),
      ...readdirSync(TEST)
        .filter((name) => name.endsWith('.ts'))
        .map((name) => join(TEST, name))];
    const contents = new Map(
      files.map((path) => [path, readFileSync(path, 'utf8')])
    );
    const importsByFile = new Map(
      [...contents].map(([path, text]) => [path, new Set(importedNames(text))])
    );

    const dead: string[] = [];
    let checked = 0;
    for (const [path, text] of contents) {
      // export を検査するのは本番側だけ。テストの export は無い。
      if (!path.startsWith(SRC)) continue;
      // index.ts の export は Firebase が呼ぶ入口そのもの。
      if (path === join(SRC, 'index.ts')) continue;

      for (const name of exportedNames(text)) {
        checked += 1;
        const imported = [...importsByFile].some(
          ([other, names]) => other !== path && names.has(name)
        );
        if (!imported) {
          dead.push(`${name}（${path.slice(SRC.length + 1)}）`);
        }
      }
    }

    // 見張り自身の空振りを防ぐ。名前を 1 つも拾えていなければ、
    // 正規表現が現状のソースの書き方と噛み合っていない。
    expect(checked, 'export を 1 つも見つけられていない').toBeGreaterThan(10);
    expect(
      [...importsByFile.values()].some((names) => names.size > 0),
      'import 文を 1 つも読み取れていない'
    ).toBe(true);

    expect(
      dead,
      `どのファイルからも import されていない export があります。\n` +
        `テストがあっても、呼ばれていなければ何も守っていません。\n` +
        `使う場所を作るか、export を外すか、消してください:\n  ${dead.join('\n  ')}`
    ).toEqual([]);
  });
});
