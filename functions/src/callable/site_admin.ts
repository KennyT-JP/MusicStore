/**
 * サイト管理者の昇格・降格と退会（仕様書 4.4 / 4.5 / 3.5）
 */
import { getAuth } from 'firebase-admin/auth';
import { FieldValue, getFirestore } from 'firebase-admin/firestore';
import { HttpsError, onCall } from 'firebase-functions/v2/https';

import { REGION, paths } from '../config';
import { canStepDownAsSiteAdmin } from '../domain/roles';
import {
  countSiteAdmins,
  isSiteAdminRequest,
  requireSiteAdmin,
  requireString,
  requireUid,
} from './access';

/** サイト管理者が 0 人になる操作をブロックするときの文言（仕様書 4.5）。 */
const LAST_SITE_ADMIN_MESSAGE =
  'あなたは現在ただ 1 人のサイト管理者です。先に別の方をサイト管理者に指名してください。';

/**
 * サイト管理者に昇格させる（仕様書 4.4）。
 *
 * カスタムクレームを付け、siteConfig の人数を数え直す。
 * 対象のユーザーは**再ログインするまで反映されない**（仕様書 13.5）。
 */
export const grantSiteAdmin = onCall({ region: REGION }, async (request) => {
  const actorUid = requireSiteAdmin(request);
  const targetUid = requireString(request.data, 'uid', { maxLength: 200 });

  const auth = getAuth();
  const user = await auth.getUser(targetUid).catch(() => null);
  if (!user) {
    throw new HttpsError('not-found', 'ユーザーが見つかりません。');
  }
  if (user.customClaims?.siteAdmin === true) {
    return { ok: true, alreadyAdmin: true };
  }

  // 他のクレームを消さないよう、既存のものに足す。
  await auth.setCustomUserClaims(targetUid, {
    ...(user.customClaims ?? {}),
    siteAdmin: true,
  });
  await syncSiteAdminCount();

  return { ok: true, actorUid };
});

/**
 * サイト管理者から外す（仕様書 4.5）。
 *
 * **最後の 1 人は外せない。** 0 人になるとアプリ内から復旧できないため、
 * 画面上のボタンを無効にするだけでなくサーバー側でも拒否する。
 */
export const revokeSiteAdmin = onCall({ region: REGION }, async (request) => {
  const actorUid = requireSiteAdmin(request);
  const targetUid = requireString(request.data, 'uid', { maxLength: 200 });

  const auth = getAuth();
  const user = await auth.getUser(targetUid).catch(() => null);
  if (!user) {
    throw new HttpsError('not-found', 'ユーザーが見つかりません。');
  }
  if (user.customClaims?.siteAdmin !== true) {
    return { ok: true, alreadyNotAdmin: true };
  }

  const count = await countSiteAdmins();
  if (!canStepDownAsSiteAdmin(true, count)) {
    throw new HttpsError('failed-precondition', LAST_SITE_ADMIN_MESSAGE);
  }

  const claims = { ...(user.customClaims ?? {}) };
  delete claims.siteAdmin;
  await auth.setCustomUserClaims(targetUid, claims);
  await syncSiteAdminCount();

  return { ok: true, actorUid };
});

/**
 * 退会する（仕様書 3.5）。
 *
 * - 投稿・履歴は残す。表示名だけ「退会したユーザー」になる。
 * - users ドキュメントは削除せず、isWithdrawn を立てる。
 *   この 1 か所を変えるだけで、過去の全投稿の表示が切り替わる（仕様書 13.3）。
 * - 参加中のリストからは抜ける。
 * - **最後のサイト管理者は退会できない**（仕様書 4.5）。
 */
export const withdrawAccount = onCall({ region: REGION }, async (request) => {
  const uid = requireUid(request);

  if (isSiteAdminRequest(request)) {
    const count = await countSiteAdmins();
    if (!canStepDownAsSiteAdmin(true, count)) {
      throw new HttpsError('failed-precondition', LAST_SITE_ADMIN_MESSAGE);
    }
  }

  const db = getFirestore();

  // 参加中のリストから抜ける（仕様書 5.4）。
  // 投稿は残るが、members から消えることで表示が
  // 「退会したユーザー」に切り替わる（仕様書 13.3）。
  const memberships = await db
    .collectionGroup('members')
    .where('__name__', '==', uid)
    .get()
    .catch(() => null);

  if (memberships) {
    await Promise.all(
      memberships.docs.map((doc) => doc.ref.delete().catch(() => undefined))
    );
  }

  await db.doc(paths.user(uid)).update({
    isWithdrawn: true,
    withdrawnAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });

  // Auth のアカウントを消す。以後このメールアドレスで再登録できる。
  await getAuth().deleteUser(uid);

  return { ok: true };
});

/**
 * siteConfig.siteAdminCount を実際の人数に合わせる（仕様書 4.5）。
 *
 * 画面側はこの値を見て「最後の 1 人か」を判断する。
 * 判定そのものはサーバー側でも行うので、ここがずれても権限は守られる。
 */
async function syncSiteAdminCount(): Promise<void> {
  const count = await countSiteAdmins();
  await getFirestore()
    .doc(paths.siteConfig)
    .set({ siteAdminCount: count }, { merge: true });
}
