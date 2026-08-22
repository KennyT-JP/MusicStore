/**
 * オフライン用ダウンロードの権限判定（docs/DOWNLOAD-DESIGN.md 5.1 / 論点 9・12・18）
 *
 * Firebase に依存しない純粋な関数だけを置く（domain/premium.ts と同じ方針）。
 * 呼び出し可能関数（callable/downloads.ts）は Firestore から読んで、
 * ここへ渡して、返ったものをそのまま返すだけにする。
 *
 * ---
 *
 * ## **プレミアムでないことは、例外ではない**（5.1 / 10 節の危険 4）
 *
 * `createListDirectly` は非プレミアムに `premiumRequired` を投げるが、
 * **この判定では投げない。** 例外にすると、呼び出し側は
 * 「呼び出しが失敗した」と「プレミアムでない」を区別できない。
 * 圏外・タイムアウト・コールドスタートの失敗も同じ「失敗」として届く。
 *
 * そして**この判定の結果は端末のファイル削除**である。
 * **電波の悪い場所で 1 回失敗しただけで、全曲が消える。**
 *
 * だから [evaluateDownloadAccess] は throw する道を 1 本も持たない。
 * 状態は戻り値（`premiumActive` / `'notMember'`）で表す。
 * 呼び出し側は「答えが返ったこと」と「その中身」を分けて扱える。
 *
 * ## **サイト管理者は「メンバーか」も「プレミアムか」も包含する**
 * （仕様書 4.1 / 4.2。旧・論点 18 を 2026-08-22 に上書き）
 *
 * 仕様書 4.1「上位の役割は下位の権限をすべて包含する」／4.2「サイト
 * 管理者は全リストの項目を扱える」に揃え、**サイト管理者はプレミアム機能を
 * すべて、全リストで使える**ことにした。この判定では 2 か所に効かせる。
 *
 * - **プレミアムの軸**：`premiumActive` を「プレミアム有効 OR サイト管理者」。
 * - **メンバーの軸**：`lists[listId]` を「members が有る OR サイト管理者」で
 *   `'member'` にする。メンバー登録が無いリストでも、サイト管理者なら
 *   `'member'` を返し、端末のファイルが保持される。
 *
 * 一般利用者の判定は変えない。**メンバーは `lists/{listId}/members/{uid}`
 * の存在だけ**で決め、役割の段階（readOnly / superUser / listAdmin）は
 * 見ない。閲覧者は members に居ないので通らない（論点 9）。
 *
 * 初稿は「サイト管理者もプレミアムが要る・メンバーでなければ不可・例外を
 * 作らない」で、このファイルは `isSiteAdmin` を受け取らなかった
 * （旧・論点 18）。上の決定で上書きした。クライアント側
 * （`Permissions.canDownload` の `role != null || isSiteAdmin`）と揃う。
 */
import { isPremiumActive } from './premium';

/**
 * 1 回の確認で受け取るリストの上限（5.1）。
 *
 * **export は付けない。** 外から要るのは「多すぎたか」の答えであって
 * 数字ではない（domain/quota.ts のしきい値と同じ扱い）。
 */
const MAX_LIST_IDS = 50;

/**
 * リスト ID として受け付ける長さの上限。
 *
 * `callable/access.ts` の `requireString` が uid / listId に使っている
 * 200 に揃える。判定の数字をここで別に決めない。
 */
const MAX_LIST_ID_LENGTH = 200;

/** そのリストに対して、その人がメンバーかどうか（5.1 の出力）。 */
export type ListDownloadAccess = 'member' | 'notMember';

/** [evaluateDownloadAccess] の答え。そのまま呼び出し側へ返す形（5.1）。 */
export interface DownloadAccessVerdict {
  /**
   * その時刻で**実効プレミアム**か（プレミアム有効 OR サイト管理者）。
   *
   * **false は正常な答えである。** 例外ではない（このファイルの冒頭）。
   */
  premiumActive: boolean;
  /**
   * サーバーの時刻（ミリ秒）。
   *
   * 端末はこれを `lastVerifiedAt` として持つ（4.2）。端末の時計で
   * 決めると、時計を進めるだけで確認を偽装できる。
   */
  verifiedAt: number;
  lists: Record<string, ListDownloadAccess>;
}

/** 1 リストぶんの読み取り結果（Firestore を読むのは呼び出し側）。 */
export interface ListMembership {
  listId: string;
  /** `lists/{listId}/members/{uid}` が存在するか。**役割は見ない。** */
  isMember: boolean;
}

/**
 * ダウンロードの権限（5.1）。
 *
 * **この関数は throw しない。** プレミアムでないことも、メンバーで
 * ないことも、正常な答えとして戻り値で返す（冒頭の説明）。
 *
 * **期限の判定は [isPremiumActive] を使い回す。** ここで `until > now` を
 * 書き直さない。境界（ちょうどの瞬間は含まない）がファイルごとに違うと、
 * どちらが正しいかを読む側が毎回調べ直すことになる（domain/premium.ts）。
 *
 * **役割の段階（readOnly / superUser / listAdmin）は見ない。**
 * 論点 9 は「メンバーのみ（Read Only を含む）」なので、
 * members ドキュメントが有るかどうかだけで決まる。`hasAtLeast` を
 * 持ち込むと、サイト管理者が通って**落とした直後の再起動で消える**。
 */
export function evaluateDownloadAccess(params: {
  /** `users/{uid}/private/state` の `premium.until`。無ければ null。 */
  premiumUntilMs: number | null | undefined;
  /** サーバーの時刻。 */
  nowMs: number;
  /**
   * 呼び出し元がサイト管理者か（仕様書 4.1 / 13.5）。
   *
   * **`premiumActive` にだけ効く（実効プレミアム）。** 「メンバーか」の
   * 判定には混ぜない——サイト管理者でも、そのリストのメンバーでなければ
   * `notMember` を返す（冒頭の説明）。
   */
  isSiteAdmin: boolean;
  memberships: readonly ListMembership[];
}): DownloadAccessVerdict {
  const { premiumUntilMs, nowMs, isSiteAdmin, memberships } = params;

  const lists: Record<string, ListDownloadAccess> = {};
  for (const { listId, isMember } of memberships) {
    // メンバー登録が無いリストでも、サイト管理者なら 'member' を返す
    // （仕様書 4.2「全リストの項目を扱える」／4.1 の包含。冒頭の説明）。
    lists[listId] = isMember || isSiteAdmin ? 'member' : 'notMember';
  }

  return {
    // 実効プレミアム＝プレミアム有効 OR サイト管理者（仕様書 4.1）。
    premiumActive: isPremiumActive(premiumUntilMs, nowMs) || isSiteAdmin,
    verifiedAt: nowMs,
    lists,
  };
}

/**
 * 入力の検証で断る理由（5.1 の表）。
 *
 * **ここだけは例外にしてよい。** 呼び出しの形が壊れているのであって、
 * 「権限が無い」という答えではない。端末は自分が組み立てた入力を
 * 送っているので、この 2 つが返るのは端末側の不具合のときだけであり、
 * ファイル削除の判断材料にはならない。
 */
export type ListIdsRejection = 'missingField' | 'tooManyLists';

/** [parseDownloadListIds] の答え。 */
export type ListIdsVerdict =
  | { listIds: string[] }
  | { rejection: ListIdsRejection };

/**
 * `listIds` を検証して取り出す（5.1）。
 *
 * | 断る場合 | 理由 |
 * | --- | --- |
 * | 配列でない・要素が文字列でない | `missingField` |
 * | 51 件以上 | `tooManyLists`（**50 件は通る**） |
 *
 * **ドキュメント ID として不正なものも断る。** 空文字や `a/items/b` の
 * ような値を通すと、`lists/{listId}/members/{uid}` が別の場所を指す。
 * 呼び出し側はその存在だけを返すので、**他人のドキュメントが有るか
 * どうかを 1 件ずつ試せる**入口になる（5.1 の骨格には無い手当て）。
 *
 * **重複は 1 件にまとめる。** 上限は送られてきた件数で数えてから
 * まとめる——重複で水増しした 60 件を通さないため。
 */
export function parseDownloadListIds(value: unknown): ListIdsVerdict {
  if (!Array.isArray(value)) {
    return { rejection: 'missingField' };
  }
  if (value.length > MAX_LIST_IDS) {
    return { rejection: 'tooManyLists' };
  }
  for (const id of value) {
    if (typeof id !== 'string' || !isUsableDocumentId(id)) {
      return { rejection: 'missingField' };
    }
  }
  return { listIds: [...new Set(value as string[])] };
}

/**
 * Firestore のドキュメント ID として使える文字列か。
 *
 * `/` を含むもの、`.` と `..`、前後を `__` で挟んだもの（Firestore の
 * 予約形）を弾く。長さは `requireString` の 200 に揃える。
 */
function isUsableDocumentId(id: string): boolean {
  if (id.length === 0 || id.length > MAX_LIST_ID_LENGTH) return false;
  if (id.includes('/')) return false;
  if (id === '.' || id === '..') return false;
  if (/^__.*__$/.test(id)) return false;
  return true;
}
