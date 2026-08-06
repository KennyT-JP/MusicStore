/**
 * 参加申請の承認と招待 URL（仕様書 3.3 / 5.2 / 13.3）
 */
import { randomBytes } from 'node:crypto';

import { FieldValue, Timestamp, getFirestore } from 'firebase-admin/firestore';
import { onCall } from 'firebase-functions/v2/https';

import { REGION, paths, readSiteConfig } from '../config';
import { isAssignableRole } from '../domain/roles';
import { listAdminUids, notifySafely } from '../notifications';
import { requireListAdmin, requireString, requireUid } from './access';
import { fail } from '../errors';

/**
 * 参加を申請する（仕様書 5.2）。
 *
 * 申請者は役割を選べない。承認時にリスト管理者が決める。
 * 却下後の再申請もこの経路で行う（仕様書 5.2.1）。
 */
export const submitJoinRequest = onCall({ region: REGION }, async (request) => {
  const uid = requireUid(request);
  const listId = requireString(request.data, 'listId', { maxLength: 200 });

  const db = getFirestore();

  const list = await db.doc(paths.list(listId)).get();
  if (!list.exists) {
    throw fail('not-found', 'listNotFound');
  }

  const member = await db.doc(paths.listMember(listId, uid)).get();
  if (member.exists) {
    throw fail('already-exists', 'alreadyMember');
  }

  // ドキュメント ID を申請者の uid にすることで二重申請を防ぐ（仕様書 13.3）。
  //
  // **すでに審査中なら何もしない。** ドキュメントは上書きされるだけなので
  // 実害が無いように見えるが、呼ぶたびに管理者へ通知が作られる。通知は
  // 本人でも消せないため、連打すると片付けられない通知が積み上がる
  // （監査 S13）。
  const requestRef = db.doc(paths.listJoinRequest(listId, uid));
  const existing = await requestRef.get();
  if (existing.exists && existing.data()?.status === 'pending') {
    return { ok: true, alreadyPending: true };
  }

  await requestRef.set({
    // 自分の申請を横断的に引くために持たせる（ドキュメント ID だけでは
    // コレクショングループを引けない／監査 S14 と同じ制約）。
    uid,
    status: 'pending',
    requestedAt: FieldValue.serverTimestamp(),
    // 却下後の再申請では前回の判断を消す。
    decidedBy: FieldValue.delete(),
    decidedAt: FieldValue.delete(),
    assignedRole: FieldValue.delete(),
  }, { merge: true });

  await notifySafely(() => listAdminUids(listId), {
    type: 'joinRequested',
    listId,
    actorUid: uid,
  });

  return { ok: true };
});

/**
 * 参加申請を承認する（仕様書 5.2）。
 *
 * リスト管理者が承認時に役割（Super User / Read Only）を決める。
 * リスト管理者の役割はここでは付与できない（昇格は別操作）。
 */
export const approveJoinRequest = onCall(
  { region: REGION },
  async (request) => {
    const listId = requireString(request.data, 'listId', { maxLength: 200 });
    const adminUid = await requireListAdmin(request, listId);
    const targetUid = requireString(request.data, 'uid', { maxLength: 200 });

    const role = (request.data as Record<string, unknown>)?.role;
    if (!isAssignableRole(role)) {
      throw fail('invalid-argument', 'roleNotAllowed');
    }

    const db = getFirestore();
    const requestRef = db.doc(paths.listJoinRequest(listId, targetUid));

    await db.runTransaction(async (tx) => {
      const snapshot = await tx.get(requestRef);
      if (!snapshot.exists) {
        throw fail('not-found', 'requestNotFound');
      }
      if (snapshot.data()?.status !== 'pending') {
        throw fail('failed-precondition', 'requestAlreadyHandled');
      }

      tx.set(db.doc(paths.listMember(listId, targetUid)), {
        uid: targetUid,
        role,
        via: 'request',
        joinedAt: FieldValue.serverTimestamp(),
        addedBy: adminUid,
      });

      // 承認したら申請ドキュメントは残さない（仕様書 13.3）。
      tx.delete(requestRef);
    });

    await notifySafely(() => [targetUid], {
      type: 'requestApproved',
      listId,
      actorUid: adminUid,
    });

    return { ok: true };
  }
);

/**
 * 参加申請を却下する（仕様書 5.2.1）。
 *
 * **通知は送らない**。申請者は申請一覧で状態を確認でき、再申請もできる。
 */
export const rejectJoinRequest = onCall({ region: REGION }, async (request) => {
  const listId = requireString(request.data, 'listId', { maxLength: 200 });
  const adminUid = await requireListAdmin(request, listId);
  const targetUid = requireString(request.data, 'uid', { maxLength: 200 });

  // **状態を確かめてから書く。** 承認・却下の他の関数は pending 以外を
  // 弾いているのに、ここだけ無条件に update していた。ドキュメントが
  // 無ければ例外になり、処理済みでも上書きしてしまう（監査 低-2）。
  const ref = getFirestore().doc(paths.listJoinRequest(listId, targetUid));
  const snapshot = await ref.get();

  if (!snapshot.exists) {
    throw fail('not-found', 'requestNotFound');
  }
  if (snapshot.data()?.status !== 'pending') {
    throw fail('failed-precondition', 'requestAlreadyHandled');
  }

  await ref.update({
    status: 'rejected',
    decidedBy: adminUid,
    decidedAt: FieldValue.serverTimestamp(),
  });

  return { ok: true };
});

/**
 * 招待 URL を発行する（仕様書 3.3）。
 *
 * 発行できるのはサイト管理者とリスト管理者。
 * ID は推測できないランダムな文字列にする（これがそのまま URL に載る）。
 */
export const createInvite = onCall({ region: REGION }, async (request) => {
  const listId = requireString(request.data, 'listId', { maxLength: 200 });
  const adminUid = await requireListAdmin(request, listId);

  const role = (request.data as Record<string, unknown>)?.role;
  if (!isAssignableRole(role)) {
    throw fail('invalid-argument', 'inviteRoleNotAllowed');
  }

  const config = await readSiteConfig();
  // 256 ビット相当。総当たりで当てられない長さにする。
  const inviteId = randomBytes(32).toString('base64url');

  const expiresAt = Timestamp.fromMillis(
    Date.now() + config.inviteExpiryHours * 60 * 60 * 1000
  );

  await getFirestore().doc(paths.invite(inviteId)).set({
    listId,
    role,
    createdBy: adminUid,
    createdAt: FieldValue.serverTimestamp(),
    expiresAt,
    status: 'active',
  });

  return { inviteId, expiresAt: expiresAt.toMillis() };
});

/**
 * 招待を受諾する（仕様書 3.3）。
 *
 * **有効期限は受諾した時点で判定する。** URL を開いた時点ではなく、
 * サインアップやメール確認を終えて実際に参加処理が走る瞬間を見る。
 *
 * ワンタイム性はトランザクションで担保する。同じ URL を複数人が同時に
 * 開いても、成立するのは 1 人だけになる。
 */
export const acceptInvite = onCall({ region: REGION }, async (request) => {
  const uid = requireUid(request);
  const inviteId = requireString(request.data, 'inviteId', { maxLength: 200 });

  const db = getFirestore();
  const inviteRef = db.doc(paths.invite(inviteId));

  const listId = await db.runTransaction(async (tx) => {
    const snapshot = await tx.get(inviteRef);
    if (!snapshot.exists) {
      throw fail('not-found', 'inviteNotFound');
    }

    const data = snapshot.data() ?? {};
    if (data.status === 'used') {
      throw fail('failed-precondition', 'inviteAlreadyUsed');
    }
    if (data.status === 'revoked') {
      throw fail('failed-precondition', 'inviteRevoked');
    }

    const expiresAt = data.expiresAt as Timestamp | undefined;
    if (!expiresAt || expiresAt.toMillis() <= Date.now()) {
      throw fail('failed-precondition', 'inviteExpired');
    }

    const targetListId = String(data.listId ?? '');
    if (!targetListId) {
      throw fail('failed-precondition', 'inviteNotFound');
    }

    const memberRef = db.doc(paths.listMember(targetListId, uid));
    const member = await tx.get(memberRef);
    if (member.exists) {
      throw fail('already-exists', 'alreadyMember');
    }

    tx.set(memberRef, {
      uid,
      role: data.role,
      via: 'invite',
      joinedAt: FieldValue.serverTimestamp(),
      addedBy: data.createdBy,
    });

    tx.update(inviteRef, {
      status: 'used',
      usedBy: uid,
      usedAt: FieldValue.serverTimestamp(),
    });

    return targetListId;
  });

  return { listId };
});

/**
 * 招待を取り消す（仕様書 13.3）。
 *
 * 誤って発行した URL を無効にできるようにする。
 */
export const revokeInvite = onCall({ region: REGION }, async (request) => {
  const inviteId = requireString(request.data, 'inviteId', { maxLength: 200 });

  const db = getFirestore();
  const snapshot = await db.doc(paths.invite(inviteId)).get();
  if (!snapshot.exists) {
    throw fail('not-found', 'inviteNotFound');
  }

  const listId = String(snapshot.data()?.listId ?? '');
  await requireListAdmin(request, listId);

  await db.doc(paths.invite(inviteId)).update({ status: 'revoked' });
  return { ok: true };
});
