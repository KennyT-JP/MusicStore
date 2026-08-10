import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    // **実行範囲と見張り範囲を一致させる（監査 第4回）。**
    //
    // discipline.test.js（helpers 経由を強制する見張り）は、このフォルダ
    // **直下**の *.test.js しか読まない。一方 vitest の既定の include は
    // 下位フォルダの **/*.test.js まで拾うため、サブフォルダにテストを
    // 置くと「実行はされるのに見張られない」ものができる。
    // 実行側を直下に限定して、両者の範囲を揃える。
    include: ['*.test.js'],

    // テストファイルを順番に実行する。
    //
    // 各ファイルの beforeEach で clearFirestore() / clearStorage() を呼んで
    // データを作り直しているため、並列に走らせると互いのデータを消し合う。
    // エミュレータは 1 つのプロジェクトを共有するので、分離できない。
    fileParallelism: false,

    // ルールの評価とエミュレータの応答待ちがあるため、既定より長めにする。
    //
    // **これは速さの基準ではなく、止まったまま戻らない事故の歯止め。**
    //
    // 20 秒では足りずに配信が止まった（2026-08-08）。`scripts/check.mjs` が
    // 検証を並列に走らせるようになったうえ、その日は依頼者の機械で
    // 動画編集ソフトが CPU を占めており、エミュレータの起動
    // （beforeAll の createTestEnv）だけで 20 秒を超えた。
    // **ルールは正しく、ただ遅かっただけ**である。
    //
    // 同じ理由で functions/test/integration.mjs の CALL_TIMEOUT_MS も
    // 延ばしてある。**時間制限は片方だけ直しても意味がない**
    // （docs/AUDIT-CHECKLIST.md 観点 4「片側だけ塞ぐと、もう片側で
    // 同じことが起きる」）。実際、統合テスト側だけ直した次の配信で、
    // 今度はここが落ちた。
    testTimeout: 120000,
    hookTimeout: 120000,
  },
});
