/**
 * サイト管理者の昇格・降格と退会（仕様書 4.4 / 4.5 / 3.5）
 */
import { getAuth } from 'firebase-admin/auth';
import { FieldValue, getFirestore } from 'firebase-admin/firestore';
import { onCall } from 'firebase-functions/v2/https';

import { REGION, paths } from '../config';
import { canStepDownAsSiteAdmin } from '../domain/roles';
import {
  countSiteAdmins,
  isSiteAdminRequest,
  requireSiteAdmin,
  requireString,
  requireUid,
  syncSiteAdminCount,
} from './access';
import { leaveAllLists } from './user_admin';
import { fail } from '../errors';

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
    throw fail('not-found', 'userNotFound');
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
    throw fail('not-found', 'userNotFound');
  }
  if (user.customClaims?.siteAdmin !== true) {
    return { ok: true, alreadyNotAdmin: true };
  }

  const count = await countSiteAdmins();
  if (!canStepDownAsSiteAdmin(true, count)) {
    throw fail('failed-precondition', 'lastSiteAdmin');
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
      throw fail('failed-precondition', 'lastSiteAdmin');
    }
  }

  const db = getFirestore();

  // 参加中のリストと、参加せずに見ているリストから抜ける（仕様書 5.4 / 3.3）。
  // 投稿は残るが、members から消えることで表示が
  // 「退会したユーザー」に切り替わる（仕様書 13.3）。
  //
  // クエリの成立条件（uid 項目で引く／監査 S14）と「引けなかったら止める」
  // 判断は leaveAllLists（user_admin.ts）にまとめてある。以前はここに
  // members だけの写しがあり、**退会だけ viewers を外し忘れていた**
  // （監査 第4回）。
  await leaveAllLists(uid);

  // **users ドキュメントが無い場合に update は失敗する。**
  // その先の Auth 削除まで到達できなくなるため set(merge) にする。
  //
  // **`isWithdrawn` はここ（誰でも読める側）に残す。** この 1 か所で
  // 過去の全投稿の表示が「退会したユーザー」に切り替わる（仕様書 13.3）。
  await db.doc(paths.user(uid)).set(
    {
      isWithdrawn: true,
      withdrawnAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true }
  );

  // **本人だけの控えは消す（2026-08-11）。** ここにはメールアドレス・
  // 表示言語・通知設定・プレミアムの期限・容量が入っている。すぐ下で
  // Auth のアカウントごと消すので、**本人も含めて誰も二度と読まない**。
  // 読まれないものを残すのは、個人情報を持ち続けるだけになる。
  // 無効化（disableSiteUser）は戻せる操作なので、あちらでは消さない。
  await db.doc(paths.userPrivate(uid)).delete().catch(() => undefined);

  // Auth のアカウントを消す。以後このメールアドレスで再登録できる。
  await getAuth().deleteUser(uid);

  // 退会したのがサイト管理者なら、siteConfig の控え（人数と uid の一覧）を
  // 実態に合わせ直す。昇格・降格は同期していたのに、退会だけ控えが
  // 残り続けていた（監査 第4回）。
  if (isSiteAdminRequest(request)) await syncSiteAdminCount();

  return { ok: true };
});
