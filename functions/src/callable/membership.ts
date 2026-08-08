/**
 * 参加申請の承認と共有リンク（仕様書 3.3 / 5.2 / 13.3）
 */
import { randomBytes } from 'node:crypto';

import { FieldValue, getFirestore } from 'firebase-admin/firestore';
import { onCall } from 'firebase-functions/v2/https';

import { REGION, paths } from '../config';
import { INITIAL_JOIN_ROLE, isAssignableRole } from '../domain/roles';
import { listAdminUids, notifySafely } from '../notifications';
import { requireListAdmin, requireString, requireUid } from './access';
import { fail } from '../errors';
import { evaluateShareLink, type ShareLinkMode } from '../domain/share_link';

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
 * 共有リンクを発行する（仕様書 3.3）。
 *
 * 発行できるのはサイト管理者とリスト管理者。
 * ID は推測できないランダムな文字列にする（これがそのまま URL に載る）。
 *
 * **無期限・何度でも・複数人が使える。** 以前は「一度きり・24 時間」
 * だったが、渡した相手が期限内に開けないと配り直しになっていた。
 *
 * `itemId` を渡すと、その曲を指すリンクになる（開くとその曲が出る）。
 *
 * **役割は指定できない。** 発行する側は「誰に渡すか」だけを考えればよく、
 * 受け取った人が参加するか見るだけかを選ぶ（3.3）。
 */
export const createShareLink = onCall({ region: REGION }, async (request) => {
  const listId = requireString(request.data, 'listId', { maxLength: 200 });
  const adminUid = await requireListAdmin(request, listId);

  const data = (request.data ?? {}) as Record<string, unknown>;

  // 曲を指すリンクなら、その曲が本当にこのリストにあることを確かめる。
  // 確かめずに受け取ると、開いた人が「無い曲」へ案内される。
  const itemId =
    typeof data.itemId === 'string' && data.itemId.trim().length > 0
      ? data.itemId.trim()
      : undefined;
  if (itemId) {
    const item = await getFirestore().doc(paths.listItem(listId, itemId)).get();
    if (!item.exists) throw fail('not-found', 'itemNotFound');
  }

  // 256 ビット相当。総当たりで当てられない長さにする。
  // **期限が無いぶん、ID の推測されにくさがそのまま守りになる。**
  const linkId = randomBytes(32).toString('base64url');

  await getFirestore()
    .doc(paths.shareLink(linkId))
    .set({
      listId,
      ...(itemId ? { itemId } : {}),
      // **役割は持たせない（仕様書 3.3）。**
      // リンクに役割を書くと、その URL を渡すこと自体が
      // 書き込み権限を配ることになる。ここに持たせるのは
      // 「どのリストか」「どの曲か」だけ。
      createdBy: adminUid,
      createdAt: FieldValue.serverTimestamp(),
      revoked: false,
    });

  return { linkId, ...(itemId ? { itemId } : {}) };
});

/**
 * 共有リンクを開いた人を受け入れる（仕様書 3.3）。
 *
 * 受け取った人は 2 つから選ぶ。
 *
 * - `join`：そのリストの**メンバーになる**。役割は一番低いところから始まる
 *   （`INITIAL_JOIN_ROLE`。リンクは役割を持たない）
 * - `view`：**メンバーにはならず**、中身を見るだけ
 *
 * `view` を選んだ人は `lists/{listId}/viewers/{uid}` に入る。
 * メンバー一覧にも人数にも通知の宛先にも入らない。
 *
 * **どちらもログインとメール確認は必要。** 誰が見たか分からない状態に
 * しないため（3.3）。
 */
export const acceptShareLink = onCall({ region: REGION }, async (request) => {
  const uid = requireUid(request);
  const linkId = requireString(request.data, 'linkId', { maxLength: 200 });

  const rawMode = (request.data as Record<string, unknown>)?.mode;
  if (rawMode !== 'join' && rawMode !== 'view') {
    throw fail('invalid-argument', 'missingField', { field: 'mode' });
  }
  const mode: ShareLinkMode = rawMode;

  const db = getFirestore();
  const linkRef = db.doc(paths.shareLink(linkId));

  return db.runTransaction(async (tx) => {
    const snapshot = await tx.get(linkRef);
    const data = snapshot.data() ?? {};

    // **判断は domain/share_link.ts に集めてある。**
    const decision = evaluateShareLink({
      link: {
        exists: snapshot.exists,
        revoked: data.revoked,
        listId: data.listId,
        itemId: data.itemId,
      },
    });

    if (decision.rejection) {
      throw fail(
        decision.rejection === 'shareLinkNotFound'
          ? 'not-found'
          : 'failed-precondition',
        decision.rejection
      );
    }

    const listId = decision.listId!;
    const memberRef = db.doc(paths.listMember(listId, uid));
    const member = await tx.get(memberRef);

    // **すでにメンバーなら、そのまま通す。** 何度でも使えるリンクでは
    // 同じ人が二度開くことが普通に起きる。役割は書き換えない。
    if (member.exists) {
      return { listId, itemId: decision.itemId, joined: true };
    }

    if (mode === 'join') {
      tx.set(memberRef, {
        uid,
        // **リンクからは役割を読まない（仕様書 3.3）。**
        // リンクは役割を持たない。一番低いところから始めて、
        // 上げるかどうかはリスト管理者が決める（5.4）。
        role: INITIAL_JOIN_ROLE,
        via: 'shareLink',
        joinedAt: FieldValue.serverTimestamp(),
        addedBy: data.createdBy,
      });
      // 参加したなら、閲覧だけの記録は要らない。
      tx.delete(db.doc(paths.listViewer(listId, uid)));
      return { listId, itemId: decision.itemId, joined: true };
    }

    tx.set(
      db.doc(paths.listViewer(listId, uid)),
      {
        uid,
        viaLink: linkId,
        firstSeenAt: FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
    return { listId, itemId: decision.itemId, joined: false };
  });
});

/**
 * 共有リンクを取り消す（仕様書 3.3 / 13.3）。
 *
 * **期限が無いぶん、ここが唯一の止める手段になる。**
 * 取り消すと、そのリンクからは参加も閲覧もできなくなる。
 * すでに参加した人・閲覧中の人はそのまま残る（外すのはメンバー管理から）。
 */
export const revokeShareLink = onCall({ region: REGION }, async (request) => {
  const linkId = requireString(request.data, 'linkId', { maxLength: 200 });

  const db = getFirestore();
  const snapshot = await db.doc(paths.shareLink(linkId)).get();
  if (!snapshot.exists) {
    throw fail('not-found', 'shareLinkNotFound');
  }

  const listId = String(snapshot.data()?.listId ?? '');
  await requireListAdmin(request, listId);

  await db.doc(paths.shareLink(linkId)).update({
    revoked: true,
    revokedAt: FieldValue.serverTimestamp(),
  });
  return { ok: true };
});
