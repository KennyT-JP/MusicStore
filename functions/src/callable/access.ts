/**
 * 権限判定の共通部分（呼び出し元の確認）
 */
import { getAuth } from 'firebase-admin/auth';
import { getFirestore } from 'firebase-admin/firestore';
import { HttpsError, type CallableRequest } from 'firebase-functions/v2/https';

import { paths } from '../config';
import { type ListAccess, isListAdmin, parseRole } from '../domain/roles';

/** ログイン済みであることを確かめ、uid を返す。 */
export function requireUid(request: CallableRequest): string {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError('unauthenticated', 'ログインが必要です。');
  }
  return uid;
}

/**
 * サイト管理者かどうか（仕様書 13.5）。
 *
 * 呼び出しのトークンに載っているクレームを見る。
 */
export function isSiteAdminRequest(request: CallableRequest): boolean {
  return request.auth?.token?.siteAdmin === true;
}

export function requireSiteAdmin(request: CallableRequest): string {
  const uid = requireUid(request);
  if (!isSiteAdminRequest(request)) {
    throw new HttpsError(
      'permission-denied',
      'この操作はサイト管理者のみ行えます。'
    );
  }
  return uid;
}

/** そのリストに対する呼び出し元の権限を取り出す。 */
export async function accessFor(
  request: CallableRequest,
  listId: string
): Promise<ListAccess> {
  const uid = requireUid(request);
  const isSiteAdmin = isSiteAdminRequest(request);

  const member = await getFirestore().doc(paths.listMember(listId, uid)).get();
  return {
    isSiteAdmin,
    role: member.exists ? parseRole(member.data()?.role) : null,
  };
}

/** リスト管理者以上でなければ拒否する。 */
export async function requireListAdmin(
  request: CallableRequest,
  listId: string
): Promise<string> {
  const uid = requireUid(request);
  const access = await accessFor(request, listId);
  if (!isListAdmin(access)) {
    throw new HttpsError(
      'permission-denied',
      'この操作はリスト管理者のみ行えます。'
    );
  }
  return uid;
}

/**
 * 現在のサイト管理者の人数を数え直す（仕様書 4.5）。
 *
 * siteConfig の値がずれても正しく判定できるよう、Auth 側を数える。
 */
export async function countSiteAdmins(): Promise<number> {
  let count = 0;
  let pageToken: string | undefined;
  do {
    const page = await getAuth().listUsers(1000, pageToken);
    count += page.users.filter(
      (user) => user.customClaims?.siteAdmin === true
    ).length;
    pageToken = page.pageToken;
  } while (pageToken);
  return count;
}

/** 文字列の入力を取り出す。空や型違いは弾く。 */
export function requireString(
  data: unknown,
  key: string,
  { maxLength = 500 }: { maxLength?: number } = {}
): string {
  const value = (data as Record<string, unknown> | undefined)?.[key];
  if (typeof value !== 'string' || value.trim().length === 0) {
    throw new HttpsError('invalid-argument', `${key} を指定してください。`);
  }
  const trimmed = value.trim();
  if (trimmed.length > maxLength) {
    throw new HttpsError('invalid-argument', `${key} が長すぎます。`);
  }
  return trimmed;
}

export function optionalString(data: unknown, key: string): string | undefined {
  const value = (data as Record<string, unknown> | undefined)?.[key];
  return typeof value === 'string' && value.trim().length > 0
    ? value.trim()
    : undefined;
}
