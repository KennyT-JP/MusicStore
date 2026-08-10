/**
 * 手順書に載せた「呼び出し可能関数の一覧」が実装とずれていないか
 *
 * **回帰テスト。** 2026-08-07 に本番で起きた不具合の再発防止。
 *
 * `onCall` の関数は、Cloud Run の側で「誰でも呼べる」設定が要る。
 * Firebase CLI は**新規作成のときだけ**それを入れるため、初回のデプロイが
 * 途中で失敗すると、関数はできたのに許可だけが入らない状態になる。
 * アプリからは `internal` としか見えない。
 *
 * 直し方は docs/SETUP.md に関数名を並べて書いてある。
 * **その一覧から漏れた関数は、いつまでも直らない。**
 * 関数を足したときに手順書を直し忘れないよう、ここで突き合わせる。
 */
import { readFileSync, readdirSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

/**
 * 実装にある `onCall` の関数名を集める。
 *
 * **ファイルの一覧を書き写さない。** 以前はここに 4 本の道を並べて
 * いたため、`user_admin.ts` を足したときに**新しい関数が数に入らず**、
 * 見張りが空振りしかけた（2026-08-09）。書き写した一覧は、
 * 増えたときに誰も直さない（docs/AUDIT-CHECKLIST.md 観点 4）。
 * その場で読む。
 */
function callableFunctionNames(): string[] {
  const dir = new URL('../src/callable/', import.meta.url);

  const names: string[] = [];
  for (const file of readdirSync(dir).sort()) {
    if (!file.endsWith('.ts')) continue;
    const text = readFileSync(new URL(file, dir), 'utf8');
    // 空白は `\s` で受ける。`export const NAME =` と `onCall` の間で
    // 改行される書き方（整形ツールが行を折る）だと、1 行前提の
    // 正規表現では新しい関数が突き合わせから漏れる（監査 第4回）。
    for (const match of text.matchAll(/export\s+const\s+(\w+)\s*=\s*onCall\b/g)) {
      names.push(match[1]);
    }
  }
  return names.sort();
}

/** 手順書の復旧手順に並んでいる関数名を集める。 */
function documentedNames(): string[] {
  const text = readFileSync(new URL('../../docs/SETUP.md', import.meta.url), 'utf8');

  const section = text.split('#### 直し方 1：許可だけ与える')[1];
  expect(section, '手順書の「直し方 1」が見つかりません').toBeDefined();

  const loop = section.split('for f in')[1]?.split('; do')[0] ?? '';
  return loop
    .split(/[\s\\]+/)
    .filter((token) => /^[a-z]\w+$/i.test(token))
    .sort();
}

describe('internal で失敗したときの復旧手順', () => {
  it('手順書の一覧が、実装の onCall と一致する', () => {
    // ずれていたら、漏れた関数は復旧手順を実行しても直らない。
    expect(documentedNames()).toEqual(callableFunctionNames());
  });

  it('作り直す側の手順にも、同じ関数が並んでいる', () => {
    const text = readFileSync(
      new URL('../../docs/SETUP.md', import.meta.url),
      'utf8',
    );
    const section = text.split('#### 直し方 2：作り直す')[1] ?? '';

    for (const name of callableFunctionNames()) {
      expect(section, `${name} が作り直しの手順に無い`).toContain(name);
    }
  });
});
