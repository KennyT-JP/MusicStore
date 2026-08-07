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

describe('死蔵コード', () => {
  test('export したものは、本番のどこかから呼ばれている', () => {
    const files = sourceFiles(SRC);
    const contents = new Map(
      files.map((path) => [path, readFileSync(path, 'utf8')])
    );
    const everything = [...contents.values()].join('\n');

    // index.ts が外へ出すものは Firebase が呼ぶ。コード上の参照は無い。
    const entryPoints = new Set(
      [...(contents.get(join(SRC, 'index.ts')) ?? '').matchAll(/\b(\w+)\b/g)].map(
        (m) => m[1]
      )
    );

    const dead: string[] = [];
    for (const [path, text] of contents) {
      if (path.endsWith('index.ts')) continue;
      for (const match of text.matchAll(
        /export (?:async )?(?:function|const) (\w+)/g
      )) {
        const name = match[1];
        if (entryPoints.has(name)) continue;

        const usesEverywhere = (everything.match(new RegExp(`\\b${name}\\b`, 'g')) ?? [])
          .length;
        const usesInOwnFile = (text.match(new RegExp(`\\b${name}\\b`, 'g')) ?? [])
          .length;
        // 自分のファイル内だけで完結しているものは、export する必要がない。
        if (usesEverywhere <= usesInOwnFile && usesInOwnFile <= 1) {
          dead.push(`${name}（${path.slice(SRC.length + 1)}）`);
        }
      }
    }

    expect(
      dead,
      `本番から呼ばれていない export があります。\n` +
        `テストがあっても、呼ばれていなければ何も守っていません。\n` +
        `使う場所を作るか、消してください:\n  ${dead.join('\n  ')}`
    ).toEqual([]);
  });
});
