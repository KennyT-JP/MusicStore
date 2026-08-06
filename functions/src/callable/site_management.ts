/**
 * サイト管理画面のための操作（仕様書 11.1 / 7.2 / 5.6）
 *
 * いずれもサイト管理者のみ。セキュリティルールでは直接の書き込みを
 * 禁じているため（仕様書 13.5）、ここを経由する。
 */
import { getAuth } from 'firebase-admin/auth';
import { FieldValue, getFirestore } from 'firebase-admin/firestore';
import { onCall } from 'firebase-functions/v2/https';

import { REGION, paths } from '../config';
import { shouldResetNotice, shouldResetWarning } from '../domain/quota';
import { requireSiteAdmin, requireString } from './access';
import { fail } from '../errors';

/**
 * ユーザーの一覧を返す（仕様書 11.1 ユーザー管理）。
 *
 * サイト管理者かどうかは Auth のカスタムクレームにしかないため
 * （仕様書 13.5）、クライアントからは他人の状態を知る手段がない。
 * ここで Auth と Firestore を突き合わせて返す。
 *
 * **注意**：全ユーザーを走査する。人数が増えたらページングが必要になる。
 */
export const listSiteUsers = onCall({ region: REGION }, async (request) => {
  requireSiteAdmin(request);

  const auth = getAuth();
  const db = getFirestore();

  const users: Array<{
    uid: string;
    email: string;
    displayName: string;
    isSiteAdmin: boolean;
    isWithdrawn: boolean;
  }> = [];

  let pageToken: string | undefined;
  do {
    const page = await auth.listUsers(1000, pageToken);
    for (const user of page.users) {
      users.push({
        uid: user.uid,
        email: user.email ?? '',
        displayName: user.displayName ?? '',
        isSiteAdmin: user.customClaims?.siteAdmin === true,
        isWithdrawn: false,
      });
    }
    pageToken = page.pageToken;
  } while (pageToken);

  // 表示名は users ドキュメントが正（仕様書 3.4）。Auth 側は初期値のまま
  // 変わらないことがあるため、こちらで上書きする。
  const profiles = await db.collection(paths.users).get();
  const byUid = new Map(profiles.docs.map((doc) => [doc.id, doc.data()]));

  for (const user of users) {
    const profile = byUid.get(user.uid);
    if (!profile) continue;
    if (typeof profile.displayName === 'string' && profile.displayName) {
      user.displayName = profile.displayName;
    }
    user.isWithdrawn = profile.isWithdrawn === true;
  }

  users.sort((a, b) => a.displayName.localeCompare(b.displayName));
  return { users };
});

/**
 * リストごとの容量上限を設定する（仕様書 7.2）。
 *
 * 上限は meta/stats にあり、クライアントからは書けない。
 */
export const setListQuota = onCall({ region: REGION }, async (request) => {
  requireSiteAdmin(request);
  const listId = requireString(request.data, 'listId', { maxLength: 200 });

  const quotaBytes = Number(
    (request.data as Record<string, unknown>)?.quotaBytes
  );
  if (!Number.isFinite(quotaBytes) || quotaBytes <= 0) {
    throw fail('invalid-argument', 'invalidQuota');
  }

  const statsRef = getFirestore().doc(paths.listStats(listId));
  const snapshot = await statsRef.get();
  if (!snapshot.exists) {
    throw fail('not-found', 'listNotFound');
  }

  // 上限を上げた結果しきい値を下回ることがあるので、通知フラグも戻す。
  // 次に超えたときに改めて通知されるようにするため（仕様書 7.3）。
  //
  // **しきい値をここに書かない。** 以前は 0.8 / 0.9 をベタ書きしており、
  // domain/quota.ts の値を変えてもここだけ古いまま残る状態だった（監査 S15）。
  const status = {
    usedBytes: Number(snapshot.data()?.usedBytes ?? 0),
    quotaBytes: Math.trunc(quotaBytes),
  };
  const noticeSent = snapshot.data()?.notifiedNotice80 === true;
  const warningSent = snapshot.data()?.notifiedWarning90 === true;

  await statsRef.update({
    quotaBytes: status.quotaBytes,
    ...(shouldResetNotice(status, noticeSent) ? { notifiedNotice80: false } : {}),
    ...(shouldResetWarning(status, warningSent) ? { notifiedWarning90: false } : {}),
  });

  return { ok: true };
});

/**
 * 管理者不在のリストにリスト管理者を指名する（仕様書 5.6）。
 *
 * すでにメンバーであれば役割を上げ、そうでなければ新たに登録する。
 */
export const assignListAdmin = onCall({ region: REGION }, async (request) => {
  const actorUid = requireSiteAdmin(request);
  const listId = requireString(request.data, 'listId', { maxLength: 200 });
  const targetUid = requireString(request.data, 'uid', { maxLength: 200 });

  const db = getFirestore();

  const list = await db.doc(paths.list(listId)).get();
  if (!list.exists) {
    throw fail('not-found', 'listNotFound');
  }

  const user = await getAuth().getUser(targetUid).catch(() => null);
  if (!user) {
    throw fail('not-found', 'userNotFound');
  }

  const memberRef = db.doc(paths.listMember(listId, targetUid));
  const member = await memberRef.get();

  if (member.exists) {
    // 既存のメンバーにも uid を入れ直す。移行前に作られた行や、
    // この関数が以前に作った行には uid が無い。
    await memberRef.update({ role: 'listAdmin', uid: targetUid });
  } else {
    await memberRef.set({
      // **uid を必ず入れる。** メンバーを横断で引くクエリは
      // ドキュメント ID ではなくこの項目で絞る（仕様書 13.3）。
      // ここだけ入れ忘れており、指名されたリスト管理者は
      // ホームにそのリストが出ず、退会してもメンバーから外れなかった。
      uid: targetUid,
      role: 'listAdmin',
      via: 'assigned',
      joinedAt: FieldValue.serverTimestamp(),
      addedBy: actorUid,
    });
  }

  return { ok: true };
});
