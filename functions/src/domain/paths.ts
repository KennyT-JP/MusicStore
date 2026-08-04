/**
 * パスと名前の扱い（仕様書 13.7 / 5.1）
 *
 * Firebase に依存しない純粋な関数だけを置く。
 * 通信なしでテストできるようにするため。
 */

/**
 * Storage のパスからリスト ID と項目 ID を取り出す（仕様書 13.7）。
 *
 * `lists/{listId}/items/{itemId}/{ファイル名}`
 * 形が違うものは null を返し、無関係なファイルには反応しないようにする。
 */
export function parseItemStoragePath(
  path: string
): { listId: string; itemId: string; fileName: string } | null {
  const parts = path.split('/');
  if (parts.length < 5) return null;
  if (parts[0] !== 'lists' || parts[2] !== 'items') return null;
  const listId = parts[1];
  const itemId = parts[3];
  const fileName = parts.slice(4).join('/');
  if (!listId || !itemId || !fileName) return null;
  return { listId, itemId, fileName };
}

/**
 * リスト名の正規化（仕様書 5.1）。
 *
 * 重複チェックのためにドキュメント ID として使うので、
 * 大文字小文字と前後の空白の違いを吸収する。
 *
 * **Flutter 側 lib/data/firestore_paths.dart の normalizeListName と
 * 同じ結果になること。**
 */
export function normalizeListName(name: string): string {
  return name.trim().toLowerCase();
}
