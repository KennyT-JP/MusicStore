/**
 * 招待の受諾可否（仕様書 3.3）
 *
 * **ここが本番で実際に動く判断。**
 *
 * 以前は同じ規則が Flutter 側（lib/domain/invite.dart）にもあり、
 * そちらは 13 件のテストで手厚く守られていた。ところが
 * **本番コードからは一度も呼ばれておらず**、実際に動いていたのは
 * `functions/src/callable/membership.ts` に直接書かれた判定で、
 * そちらは単体テストが 0 件だった（監査 S11・第2回）。
 *
 * 「テストがあること」と「守られていること」は別。
 * 動いている側をここへ切り出し、テストもこちらに置く。
 */

/** 受諾できなかった理由。画面の文言に対応する（functions/src/errors.ts）。 */
export type InviteRejection =
  | 'inviteNotFound'
  | 'inviteAlreadyUsed'
  | 'inviteRevoked'
  | 'inviteExpired'
  | 'alreadyMember';

export interface InviteSnapshot {
  /** 招待ドキュメントが存在するか。 */
  exists: boolean;
  /** `active` / `used` / `revoked`。 */
  status?: unknown;
  /** 期限（ミリ秒）。取れなければ undefined。 */
  expiresAtMs?: number;
  listId?: unknown;
}

export interface InviteDecision {
  /** 受け入れるなら参加先のリスト ID。 */
  listId?: string;
  rejection?: InviteRejection;
}

/**
 * 招待を受け入れてよいか。
 *
 * 判定の順番には意味がある。
 * **取消・使用済みを期限切れより先に見る。** 期限が切れた取消済みの招待に
 * 「期限切れです」と出すと、取り消されたことが伝わらない。
 */
export function evaluateInvite(params: {
  invite: InviteSnapshot;
  /** すでにそのリストのメンバーか。 */
  isAlreadyMember: boolean;
  /** 判定する時刻（ミリ秒）。 */
  nowMs: number;
}): InviteDecision {
  const { invite, isAlreadyMember, nowMs } = params;

  if (!invite.exists) return { rejection: 'inviteNotFound' };
  if (invite.status === 'used') return { rejection: 'inviteAlreadyUsed' };
  if (invite.status === 'revoked') return { rejection: 'inviteRevoked' };

  // 期限が読めないものは期限切れ扱いにする。曖昧なまま通さない。
  if (
    typeof invite.expiresAtMs !== 'number' ||
    !Number.isFinite(invite.expiresAtMs) ||
    invite.expiresAtMs <= nowMs
  ) {
    return { rejection: 'inviteExpired' };
  }

  const listId = typeof invite.listId === 'string' ? invite.listId : '';
  if (!listId) return { rejection: 'inviteNotFound' };

  // **メンバー判定は最後。** 期限切れや取消の招待を渡された人に
  // 「すでに参加しています」と返すと、招待の状態が伝わらない。
  if (isAlreadyMember) return { rejection: 'alreadyMember' };

  return { listId };
}
