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

/**
 * 行き場を失ったファイルとして削除してよいか（仕様書 7.5）。
 *
 * **復旧できない処理なので、判断はここに集めてテストする。**
 * 定期削除（functions/src/scheduled/purge.ts）は、リポジトリ全体で
 * もっとも取り返しのつかない処理なのに、**テストが 1 件も無かった**
 * （監査 第2回）。実際に Storage を消すところは動かせなくても、
 * 「消してよいか」の判断だけなら確かめられる。
 */
export function shouldDeleteOrphan(params: {
  /** Storage のオブジェクト名。 */
  path: string;
  /** アップロードされた時刻（ミリ秒）。読めなければ NaN。 */
  createdAtMs: number;
  /** これより古いものだけが対象（ミリ秒）。 */
  cutoffMs: number;
  /** 対応する項目。無ければ null。 */
  item: {
    file?: { storagePath?: unknown } | null;
    previousFiles?: unknown;
  } | null;
}): boolean {
  const { path, createdAtMs, cutoffMs, item } = params;

  // 項目のファイル置き場でないものには触らない。
  if (!parseItemStoragePath(path)) return false;

  // **時刻が読めないものは消さない。** 読めない＝新しいかもしれない。
  if (!Number.isFinite(createdAtMs)) return false;

  // 猶予期間内。アップロード完了から項目作成までの短い間かもしれない。
  if (createdAtMs > cutoffMs) return false;

  // 項目が無ければ孤児。
  if (!item) return true;

  // 項目が今このファイルを指している。
  if (item.file?.storagePath === path) return false;

  // **差し替えの旧ファイルは、猶予のあいだだけ残す**（2026-08-14）。
  //
  // 以前はここで無条件に守っていたため、**差し替えた古いファイルが
  // 永久に残り、容量を食い続けた**。積んだ側（callable/items.ts）が
  // `purgeAt` を入れるので、それを過ぎたものは孤児として扱う。
  //
  // **`purgeAt` が無い行も守る。** 差し替え機能より前に積まれたものが
  // あれば、時刻が分からない＝消してよいか判断できない。
  // **判断できないものは消さない**（この関数の他の枝と同じ方針）。
  const previous = item.previousFiles;
  if (Array.isArray(previous)) {
    const entry = previous.find(
      (old: { storagePath?: unknown } | null) => old?.storagePath === path
    );
    if (entry) {
      const purgeAtMs = toMillis((entry as { purgeAt?: unknown }).purgeAt);
      if (purgeAtMs === null) return false; // 時刻が無い／読めない
      return purgeAtMs <= Date.now();
    }
  }

  return true;
}

/** Firestore の Timestamp・Date・数値のどれでもミリ秒にする。読めなければ null。 */
function toMillis(value: unknown): number | null {
  if (value == null) return null;
  if (typeof value === 'number' && Number.isFinite(value)) return value;
  if (value instanceof Date) return value.getTime();
  const asTimestamp = value as { toMillis?: () => number };
  if (typeof asTimestamp.toMillis === 'function') {
    const ms = asTimestamp.toMillis();
    return Number.isFinite(ms) ? ms : null;
  }
  return null;
}
