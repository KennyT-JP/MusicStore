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
// export は付けない。使うのは下の requireListAdmin だけで、
// どこからも import されない export は死蔵の見張りが弾く（監査 第4回）。
async function accessFor(
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
 * 昇格・降格・退会のときだけ呼び、結果は siteConfig に控える
 * （下の syncSiteAdminCount）。
 */
async function scanSiteAdmins(): Promise<string[]> {
  const uids: string[] = [];
  let pageToken: string | undefined;
  do {
    const page = await getAuth().listUsers(1000, pageToken);
    for (const user of page.users) {
      // **無効化されたアカウントは数えない。** 数えると「最後の 1 人」の
      // 判定が実際より多く見え、残った 1 人を降格・退会させて
      // ログインできるサイト管理者が 0 人になる経路があった（監査 第4回）。
      // 通知の宛先としても、ログインできない人に送る意味は無い。
      if (user.customClaims?.siteAdmin === true && !user.disabled) {
        uids.push(user.uid);
      }
    }
    pageToken = page.pageToken;
  } while (pageToken);
  return uids;
}

/** 現在のサイト管理者の人数（仕様書 4.5）。 */
export async function countSiteAdmins(): Promise<number> {
  return (await scanSiteAdmins()).length;
}

/**
 * siteConfig.siteAdminCount を実際の人数に合わせる（仕様書 4.5）。
 *
 * 画面側はこの値を見て「最後の 1 人か」を判断する。
 * 判定そのものはサーバー側でも行うので、ここがずれても権限は守られる。
 *
 * 以前は site_admin.ts の中に閉じており、deleteSiteUser や退会からは
 * 呼べなかった。管理者を消しても控えが残り続けていたため（監査 第4回）、
 * 数える側（scanSiteAdmins）の隣へ移して各所から呼べるようにした。
 */
export async function syncSiteAdminCount(): Promise<void> {
  // **uid の一覧も控える。** 通知の宛先を集めるたびに Auth の全ユーザーを
  // 走査していたため、コメントが 1 件付くだけで利用者数に比例した
  // 往復が発生していた（監査 第2回）。ここで控えておけば読み取り 1 回で済む。
  const uids = await scanSiteAdmins();
  const db = getFirestore();

  // 人数は画面が使うので siteConfig/global に置く。
  await db
    .doc(paths.siteConfig)
    .set({ siteAdminCount: uids.length }, { merge: true });

  // uid の一覧は通知の宛先を集めるためだけのもの。利用者に見せる必要が
  // 無いので、読めない場所に置く。
  await db
    .doc(paths.siteInternal)
    .set({ siteAdminUids: uids }, { merge: true });
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

