// 拡張子が .mts なのは、このパッケージが CommonJS（package.json に
// "type": "module" が無い）ため。.ts だと Vite が「CommonJS として読んだ
// ファイルに ESM 構文がある」と実行のたびに警告を出す。
import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    // **時間制限は歯止めであって、速さの基準にしない**
    // （rules-test/vitest.config.js と同じ考え方）。
    //
    // リポジトリの時間制限のうち、ここだけ既定の 5 秒のままだった
    // （監査 第4回）。単体テストは通信をしないので普段は一瞬で終わるが、
    // `scripts/check.mjs` が検証を並列に走らせるため、機械が混んでいると
    // プロセスの起動やファイル読みだけで既定を超えうる。遅いだけの実行を
    // 失敗にすると「赤いのは環境のせい」に慣れて、本物の後退を見逃す側に
    // 倒れる（docs/AUDIT-CHECKLIST.md 観点 2）。
    testTimeout: 120000,
    hookTimeout: 120000,
  },
});
