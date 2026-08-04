/**
 * 役割と権限判定（仕様書 4.1 / 4.2）
 *
 * **Flutter 側の lib/domain/role.dart / permissions.dart と同じ規則**を
 * サーバー側にも持つ。クライアントを信用しないため、承認・招待などの
 * 重い操作はここで改めて判定する。
 *
 * 二重に持つことになるので、片方を変えたらもう片方も直すこと。
 * 双方に同じ内容のテストを置いてある（Dart: test/domain/permissions_test.dart、
 * TypeScript: functions/test/roles.test.ts）。
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

export function isListAdmin(access: ListAccess): boolean {
  return hasAtLeast(access, 'listAdmin');
}

export function canWrite(access: ListAccess): boolean {
  return hasAtLeast(access, 'superUser');
}

export function isMember(access: ListAccess): boolean {
  return effectiveRole(access) !== null;
}

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
