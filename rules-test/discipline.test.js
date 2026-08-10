/**
 * 「作り直しの省略」が嘘にならないための見張り
 *
 * helpers.js は「データが変わった印（dirty）が付いたときだけ作り直す」
 * 形にしてある（2026-08-09。毎テスト 17 件の作り直しに約 45 秒
 * 払っていたため）。
 *
 * この省略が成り立つのは、**データを変えうる操作がすべて印を付ける**
 * ときだけである。テスト本文が assertSucceeds や
 * withSecurityRulesDisabled を直接呼ぶと、印の付かない書き込みが生まれ、
 * **前のテストの残骸の上で次のテストが走る**。しかも大半のテストは
 * 拒否の確認なので、残骸があっても緑のまま——壊れたことに気づけない。
 *
 * だからここで機械的に禁じる。**「helpers を使うこと」という注意書きは
 * 仕組みではない**（docs/AUDIT-CHECKLIST.md 観点 4）。
 */
import { readFileSync, readdirSync } from 'node:fs';
import { describe, expect, test } from 'vitest';

/** 見張りの対象。自分自身と helpers は除く。 */
const targets = readdirSync('.').filter(
  (f) => f.endsWith('.test.js') && f !== 'discipline.test.js',
);

describe('ルールテストの書き方', () => {
  test('対象のテストファイルが実在する', () => {
    // 名前が変わって対象が空になると、見張りが空振りする。
    expect(targets).toContain('firestore.rules.test.js');
    expect(targets).toContain('storage.rules.test.js');
  });

  for (const file of targets) {
    test(`${file} は helpers を通す（直接呼びは印が付かない）`, () => {
      const source = readFileSync(file, 'utf8');

      // **呼び方ではなく、持ち込むこと自体を禁じる（監査 第4回）。**
      // 以前は `assertSucceeds(` という呼び出しの形だけを探していたため、
      // `import { assertSucceeds as sneak }` と別名を付ければ素通りだった。
      // 生の判定 API を握ってよいのは helpers.js だけなので、これらの名前が
      // import 文（動的 import 含む）に現れた時点で拒む。
      const imports =
        source.match(/import[\s\S]*?from\s*['"][^'"]+['"]|import\s*\(/g) ?? [];
      for (const statement of imports) {
        expect(
          statement,
          '生の判定 API は import しない（helpers.js の allow / deny / mutateAsAdmin を使う）',
        ).not.toMatch(
          /assertSucceeds|assertFails|withSecurityRulesDisabled/,
        );
      }

      // 名前を経由しない持ち込み（await import した束から呼ぶ等）も、
      // 提供元のパッケージ名ごと禁じれば塞がる。
      expect(
        source,
        '@firebase/rules-unit-testing を直接使わない（helpers.js を通す）',
      ).not.toMatch(/@firebase\/rules-unit-testing/);

      // allow / deny を通らない判定は、dirty の印を付けられない。
      expect(source, 'assertSucceeds は allow() を使う').not.toMatch(
        /assertSucceeds\s*\(/,
      );
      expect(source, 'assertFails は deny() を使う').not.toMatch(
        /assertFails\s*\(/,
      );

      // ルール迂回の書き込みも同じ。mutateAsAdmin() を使う。
      expect(
        source,
        'withSecurityRulesDisabled は mutateAsAdmin() を使う',
      ).not.toMatch(/\.withSecurityRulesDisabled\s*\(/);

      // seed を直接呼ぶと、dirty の管理と食い違う。maybeReseed() を使う。
      expect(source, 'seed は maybeReseed() を使う').not.toMatch(
        /await seed\s*\(/,
      );
    });
  }
});
