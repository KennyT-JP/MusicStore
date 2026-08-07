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
import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

/** 実装にある `onCall` の関数名を集める。 */
function callableFunctionNames(): string[] {
  const sources = [
    'src/callable/list_requests.ts',
    'src/callable/membership.ts',
    'src/callable/site_admin.ts',
    'src/callable/site_management.ts',
  ];

  const names: string[] = [];
  for (const path of sources) {
    const text = readFileSync(new URL(`../${path}`, import.meta.url), 'utf8');
    for (const match of text.matchAll(/export const (\w+) = onCall\b/g)) {
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
