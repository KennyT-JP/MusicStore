/**
 * 共有リンクの受け入れ可否（仕様書 3.3）
 *
 * **ここが本番で実際に動く判断。**
 *
 * 以前の招待 URL は「一度きり・24 時間で期限切れ」だった。
 * 2026-08-07 に**無期限・何度でも・複数人**へ変更した。
 * リンクを受け取った人は、開いた先で
 * **参加する**か**参加せずに見るだけ**かを選ぶ。
 *
 * そのため、判断から消えたものと残ったものがある。
 *
 * | 以前 | いま |
 * | --- | --- |
 * | 期限切れ | **無い**（無期限） |
 * | 使用済み | **無い**（何度でも使える） |
 * | 取り消し済み | 残す（誤って配ったリンクを止める手段は要る） |
 * | すでにメンバー | **拒否しない**（3 参照） |
 */

/** 受け入れられなかった理由。画面の文言に対応する（functions/src/errors.ts）。 */
export type ShareLinkRejection = 'shareLinkNotFound' | 'shareLinkRevoked';

/** リンクを開いた人が選べる進み方。 */
export type ShareLinkMode =
  /** そのリストのメンバーになる。 */
  | 'join'
  /** メンバーにはならず、中身を見るだけ。 */
  | 'view';

export interface ShareLinkSnapshot {
  /** リンクのドキュメントが存在するか。 */
  exists: boolean;
  /** 取り消されていれば真。 */
  revoked?: unknown;
  listId?: unknown;
  /** 曲を指すリンクなら、その項目 ID。 */
  itemId?: unknown;
  /** 参加を選んだときに与える役割。 */
  role?: unknown;
}

export interface ShareLinkDecision {
  listId?: string;
  itemId?: string;
  rejection?: ShareLinkRejection;
}

/**
 * リンクを受け入れてよいか。
 *
 * **1. 取り消しは残す。** 期限が無いということは、**一度配ったリンクを
 * 止める手段が取り消ししか無い**ということでもある。以前は期限切れが
 * 事実上の歯止めになっていた。無期限にした以上、取り消しの重みは増す。
 *
 * **2. 存在しないことと取り消しは区別する。** 「リンクが違う」のと
 * 「もう使えなくなった」のとでは、受け取った人が次に取る行動が違う。
 *
 * **3. すでにメンバーでも拒否しない。** 複数人が何度でも使うリンクでは、
 * 同じ人が二度開くことが普通に起きる。以前は一度きりだったので
 * 「使用済み」と伝える意味があったが、いまは**そのままリストを開けば
 * よい**。エラーにすると、参加済みの人がリンクから入れなくなる。
 */
export function evaluateShareLink(params: {
  link: ShareLinkSnapshot;
}): ShareLinkDecision {
  const { link } = params;

  if (!link.exists) return { rejection: 'shareLinkNotFound' };
  if (link.revoked === true) return { rejection: 'shareLinkRevoked' };

  const listId = typeof link.listId === 'string' ? link.listId : '';
  if (!listId) return { rejection: 'shareLinkNotFound' };

  const itemId = typeof link.itemId === 'string' ? link.itemId : undefined;
  return { listId, ...(itemId ? { itemId } : {}) };
}
