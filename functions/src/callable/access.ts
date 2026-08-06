/**
 * 権限判定の共通部分（呼び出し元の確認）
 */
import { getAuth } from 'firebase-admin/auth';
import { getFirestore } from 'firebase-admin/firestore';
import { type CallableRequest } from 'firebase-functions/v2/https';

import { paths } from '../config';
import { type ListAccess, isListAdmin, parseRole } from '../domain/roles';
import { fail } from '../errors';

/**
 * ログイン済みかつメール確認済みであることを確かめ、uid を返す。
 *
 * **メール確認は画面のリダイレクトだけでは守れない。** 直接呼べば通って
 * しまうため、ここでも確かめる（仕様書 3.1／監査 S3）。
 * Google 連携で入った場合、このクレームは最初から true になる。
 */
export function requireUid(request: CallableRequest): string {
  const uid = request.auth?.uid;
  if (!uid) {
    throw fail('unauthenticated', 'signInRequired');
  }
  if (request.auth?.token?.email_verified !== true) {
    throw fail('permission-denied', 'emailNotVerified');
  }
  return uid;
}

/**
 * サイト管理者かどうか（仕様書 13.5）。
 *
 * 呼び出しのトークンに載っているクレームを見る。
 */
export function isSiteAdminRequest(request: CallableRequest): boolean {
  return (
    request.auth?.token?.siteAdmin === true &&
    request.auth?.token?.email_verified === true
  );
}

export function requireSiteAdmin(request: CallableRequest): string {
  const uid = requireUid(request);
  if (!isSiteAdminRequest(request)) {
    throw fail('permission-denied', 'siteAdminOnly');
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
    throw fail('permission-denied', 'listAdminOnly');
  }
  return uid;
}

/**
 * 現在のサイト管理者を Auth から数え直す（仕様書 4.5）。
 *
 * siteConfig の値がずれても正しく判定できるよう、Auth 側を数える。
 *
 * **全ユーザーの走査になるため、頻繁に呼んではいけない。**
 * 昇格・降格・退会のときだけ呼び、結果は siteConfig に控える。
 */
export async function scanSiteAdmins(): Promise<string[]> {
  const uids: string[] = [];
  let pageToken: string | undefined;
  do {
    const page = await getAuth().listUsers(1000, pageToken);
    for (const user of page.users) {
      if (user.customClaims?.siteAdmin === true) uids.push(user.uid);
    }
    pageToken = page.pageToken;
  } while (pageToken);
  return uids;
}

/** 現在のサイト管理者の人数（仕様書 4.5）。 */
export async function countSiteAdmins(): Promise<number> {
  return (await scanSiteAdmins()).length;
}

/** 文字列の入力を取り出す。空や型違いは弾く。 */
export function requireString(
  data: unknown,
  key: string,
  { maxLength = 500 }: { maxLength?: number } = {}
): string {
  const value = (data as Record<string, unknown> | undefined)?.[key];
  if (typeof value !== 'string' || value.trim().length === 0) {
    throw fail('invalid-argument', 'missingField', { field: key });
  }
  const trimmed = value.trim();
  if (trimmed.length > maxLength) {
    throw fail('invalid-argument', 'fieldTooLong', { field: key });
  }
  return trimmed;
}

export function optionalString(data: unknown, key: string): string | undefined {
  const value = (data as Record<string, unknown> | undefined)?.[key];
  return typeof value === 'string' && value.trim().length > 0
    ? value.trim()
    : undefined;
}
