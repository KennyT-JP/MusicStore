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
 * **スラッシュを `_` に置き換えるのが要点。** そのままだと
 * `listNames/foo/x/y` のような入れ子パスになり、
 * `listNames/foo` とは別のドキュメントとして重複チェックをすり抜ける
 * （監査 低-1）。
 *
 * **Flutter 側 lib/data/firestore_paths.dart の normalizeListName と
 * 同じ結果になること。**
 */
export function normalizeListName(name: string): string {
  return name.trim().toLowerCase().split('/').join('_');
}

/**
 * その Storage のパスが、指定したリスト・項目のものか（仕様書 13.7）。
 *
 * **定期削除がファイルを消す前に必ず通すこと。** 項目ドキュメントの
 * `file.storagePath` はクライアントが書けるため、他人のリストのパスを
 * 書き込んでおくと、サーバーの権限でそのファイルを消させられる
 * （監査 S1）。パスと保存場所の対応をここで検証する。
 */
export function isPathOwnedByItem(
  path: unknown,
  listId: string,
  itemId: string
): path is string {
  if (typeof path !== 'string' || !path) return false;
  const parsed = parseItemStoragePath(path);
  return parsed !== null && parsed.listId === listId && parsed.itemId === itemId;
}
