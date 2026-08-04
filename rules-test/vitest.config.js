import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    // テストファイルを順番に実行する。
    //
    // 各ファイルの beforeEach で clearFirestore() / clearStorage() を呼んで
    // データを作り直しているため、並列に走らせると互いのデータを消し合う。
    // エミュレータは 1 つのプロジェクトを共有するので、分離できない。
    fileParallelism: false,

    // ルールの評価とエミュレータの応答待ちがあるため、既定より長めにする。
    testTimeout: 20000,
    hookTimeout: 20000,
  },
});
