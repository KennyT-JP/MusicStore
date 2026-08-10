/**
 * 役割と権限判定（仕様書 4.1 / 4.2）
 *
 * **Flutter 側の lib/domain/role.dart / permissions.dart と同じ規則**を
 * サーバー側にも持つ。クライアントを信用しないため、承認・招待などの
 * 重い操作はここで改めて判定する。
 *
 * 二重に持つことになるので、片方を変えたらもう片方も直すこと。
 * 双方に同じ内容のテストを置いてある（Dart: test/domain/permissions_test.dart、
 * TypeScript: functions/test/domain.test.ts）。
 */

export type ListRole = 'listAdmin' | 'superUser' | 'readOnly';

const RANK: Record<ListRole, number> = {
  readOnly: 1,
  superUser: 2,
  listAdmin: 3,
};

/**
 * Firestore の値から役割を復元する。
 *
 * 未知の値は復元しない（null）。不明な役割を強い権限として扱うと
 * 権限昇格になるため。
 */
export function parseRole(value: unknown): ListRole | null {
  if (value === 'listAdmin' || value === 'superUser' || value === 'readOnly') {
    return value;
  }
  return null;
}

/** 招待や承認で付与してよい役割（仕様書 3.3 / 5.2）。 */
export function isAssignableRole(value: unknown): value is ListRole {
  return value === 'superUser' || value === 'readOnly';
}

/** 「今このユーザーがこのリストに対して何ができるか」を表す文脈。 */
export interface ListAccess {
  isSiteAdmin: boolean;
  role: ListRole | null;
}

/** 実効的な役割。サイト管理者は常にリスト管理者以上として扱う（仕様書 4.2）。 */
export function effectiveRole(access: ListAccess): ListRole | null {
  if (access.isSiteAdmin) return 'listAdmin';
  return access.role;
}

export function hasAtLeast(access: ListAccess, required: ListRole): boolean {
  const effective = effectiveRole(access);
  if (effective === null) return false;
  return RANK[effective] >= RANK[required];
}

/**
 * 参加した人の初期役割（仕様書 3.3 / 5.4）。
 *
 * **共有リンクは役割を持たない。** URL は「どのリスト（どの曲）か」
 * 以外の意味を持ってはいけない。リンクに役割を持たせると、
 * その URL を渡すこと自体が書き込み権限を配ることになる。
 *
 * そこで、リンクから参加した人は**一番低い役割**で入る。
 * こうするとリンクが与える範囲は「参加せずに見る」と同じになり、
 * URL は入口以上のものにならない。
 *
 * **書けるようにするかどうかは、リスト管理者が後から決める**（5.4）。
 */
export const INITIAL_JOIN_ROLE: ListRole = 'readOnly';

export function isListAdmin(access: ListAccess): boolean {
  return hasAtLeast(access, 'listAdmin');
}

/**
 * **「Super User 以上か」「メンバーか」の判定はここに置かない。**
 *
 * かつて `canWrite` と `isMember` を用意し、テストも書いていたが、
 * **本番からは一度も呼ばれていなかった**（監査 第3回）。
 * 項目とコメントはクライアントが直接書き込むため、判定を行うのは
 * `firestore.rules` の `canWrite()` / `isMember()` であって、
 * ここではない。
 *
 * テストがあるのに本番から呼ばれていない関数は、守っているつもりの
 * 範囲を実際より広く見せる。同じ指摘が 3 回続けて出ている
 * （AUDIT-CHECKLIST 観点 4）。
 *
 * 呼び出し可能関数（onCall）で必要になるのは、いまのところ
 * 「リスト管理者以上か」だけなので `isListAdmin` だけを置く。
 * 増やすときは、**本番から呼ぶ場所と対で**足すこと。
 */

/**
 * サイト管理者が自分を降格・退会できるか（仕様書 4.5）。
 *
 * 最後の 1 人は抜けられない。0 人になるとアプリ内から復旧できないため。
 */
export function canStepDownAsSiteAdmin(
  isSiteAdmin: boolean,
  siteAdminCount: number
): boolean {
  if (!isSiteAdmin) return true;
  return siteAdminCount > 1;
}
