/**
 * リスト作成申請の承認・却下（仕様書 5.1 / 5.2.1 / 13.3）
 */
import { FieldValue, getFirestore } from 'firebase-admin/firestore';
import { HttpsError, onCall } from 'firebase-functions/v2/https';

import { REGION, paths, readSiteConfig } from '../config';
import { normalizeListName } from '../domain/paths';
import { notifySafely, siteAdminUids } from '../notifications';
import { requireSiteAdmin, requireString, requireUid } from './access';

/**
 * リスト作成申請を承認する（仕様書 5.1）。
 *
 * 次を 1 つのトランザクションで行う。
 * - リストの作成と meta/stats の初期化
 * - listNames の確定（名前の重複チェック用）
 * - 申請者を listAdmin として members に登録
 * - 申請の status を approved に更新
 *
 * 途中で失敗しても中途半端な状態が残らないようにするため、まとめて実行する。
 */
export const approveListRequest = onCall(
  { region: REGION },
  async (request) => {
    const adminUid = requireSiteAdmin(request);
    const requestId = requireString(request.data, 'requestId', {
      maxLength: 200,
    });

    const db = getFirestore();
    const config = await readSiteConfig();
    const requestRef = db.doc(paths.listRequest(requestId));

    const listId = await db.runTransaction(async (tx) => {
      const snapshot = await tx.get(requestRef);
      if (!snapshot.exists) {
        throw new HttpsError('not-found', '申請が見つかりません。');
      }

      const data = snapshot.data() ?? {};
      if (data.status !== 'pending') {
        throw new HttpsError(
          'failed-precondition',
          'この申請はすでに処理されています。'
        );
      }

      const listName = String(data.listName ?? '').trim();
      if (!listName) {
        throw new HttpsError('failed-precondition', 'リスト名がありません。');
      }
      const nameLower = normalizeListName(listName);
      const requestedBy = String(data.requestedBy ?? '');
      if (!requestedBy) {
        throw new HttpsError('failed-precondition', '申請者が不明です。');
      }

      // 承認の時点であらためて重複を確かめる。
      // 申請から承認までの間に、同じ名前が確定している可能性があるため。
      const nameRef = db.doc(paths.listName(nameLower));
      const existingName = await tx.get(nameRef);
      if (existingName.exists && existingName.data()?.listId) {
        throw new HttpsError(
          'already-exists',
          `「${listName}」は既に使われています。`
        );
      }

      const listRef = db.collection(paths.lists).doc();

      // 公開してよい情報のみ（仕様書 13.2）。
      tx.set(listRef, {
        name: listName,
        nameLower,
        createdBy: requestedBy,
        adminCount: 1,
        memberCount: 1,
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });

      // 容量・連番などの内部情報（メンバーのみ読める）。
      tx.set(db.doc(paths.listStats(listRef.id)), {
        nextSeq: 1,
        usedBytes: 0,
        quotaBytes: config.defaultQuotaBytes,
        notifiedNotice80: false,
        notifiedWarning90: false,
      });

      // 承認されると申請者がそのリストのリスト管理者になる（仕様書 5.1）。
      tx.set(db.doc(paths.listMember(listRef.id, requestedBy)), {
        role: 'listAdmin',
        via: 'founder',
        joinedAt: FieldValue.serverTimestamp(),
        addedBy: adminUid,
      });

      tx.set(nameRef, {
        listId: listRef.id,
        reservedAt: FieldValue.serverTimestamp(),
      });

      tx.update(requestRef, {
        status: 'approved',
        decidedBy: adminUid,
        decidedAt: FieldValue.serverTimestamp(),
        createdListId: listRef.id,
      });

      return { listId: listRef.id, requestedBy };
    });

    // 申請が承認されたら申請者に通知する（仕様書 10.2）。
    await notifySafely(() => [listId.requestedBy], {
      type: 'requestApproved',
      listId: listId.listId,
      requestId,
      actorUid: adminUid,
    });

    return { listId: listId.listId };
  }
);

/**
 * リスト作成申請を却下する（仕様書 5.2.1）。
 *
 * **却下時は通知しない**。ただし申請一覧を見れば「却下」と分かる。
 * 名前の予約は解放し、その名前を他の人が申請できるようにする。
 */
export const rejectListRequest = onCall({ region: REGION }, async (request) => {
  const adminUid = requireSiteAdmin(request);
  const requestId = requireString(request.data, 'requestId', {
    maxLength: 200,
  });

  const db = getFirestore();
  const requestRef = db.doc(paths.listRequest(requestId));

  await db.runTransaction(async (tx) => {
    const snapshot = await tx.get(requestRef);
    if (!snapshot.exists) {
      throw new HttpsError('not-found', '申請が見つかりません。');
    }
    const data = snapshot.data() ?? {};
    if (data.status !== 'pending') {
      throw new HttpsError(
        'failed-precondition',
        'この申請はすでに処理されています。'
      );
    }

    const nameLower = String(data.nameLower ?? '');
    if (nameLower) {
      const nameRef = db.doc(paths.listName(nameLower));
      const reserved = await tx.get(nameRef);
      // 確定済みのリストが使っている名前は消さない。
      if (reserved.exists && !reserved.data()?.listId) {
        tx.delete(nameRef);
      }
    }

    tx.update(requestRef, {
      status: 'rejected',
      decidedBy: adminUid,
      decidedAt: FieldValue.serverTimestamp(),
    });
  });

  return { ok: true };
});

/**
 * リスト作成を申請する（仕様書 5.1）。
 *
 * 申請は誰でもできる。名前の重複チェックをここで行い、
 * 申請中の名前を予約しておく。
 */
export const submitListRequest = onCall({ region: REGION }, async (request) => {
  // 他の呼び出し可能関数と同じ入口を通す（メール確認まで確かめる／監査 S3）。
  const uid = requireUid(request);

  const listName = requireString(request.data, 'listName', { maxLength: 100 });
  const purpose = requireString(request.data, 'purpose', { maxLength: 1000 });
  const data = request.data as Record<string, unknown>;
  const estimatedTrackCount = Number(data.estimatedTrackCount ?? 0);
  const expectedUserCount = Number(data.expectedUserCount ?? 0);

  if (!Number.isFinite(estimatedTrackCount) || estimatedTrackCount < 0) {
    throw new HttpsError('invalid-argument', '登録曲数を正しく入力してください。');
  }
  if (!Number.isFinite(expectedUserCount) || expectedUserCount < 0) {
    throw new HttpsError('invalid-argument', '使用者数を正しく入力してください。');
  }

  const db = getFirestore();
  const nameLower = normalizeListName(listName);
  const nameRef = db.doc(paths.listName(nameLower));
  const requestRef = db.collection('listRequests').doc();

  await db.runTransaction(async (tx) => {
    const existing = await tx.get(nameRef);
    if (existing.exists) {
      throw new HttpsError(
        'already-exists',
        `「${listName}」は既に使われているか、申請中です。`
      );
    }

    // 申請中の名前として予約する。listId はまだ入れない。
    tx.set(nameRef, {
      requestId: requestRef.id,
      reservedAt: FieldValue.serverTimestamp(),
    });

    tx.set(requestRef, {
      listName,
      nameLower,
      estimatedTrackCount: Math.trunc(estimatedTrackCount),
      expectedUserCount: Math.trunc(expectedUserCount),
      purpose,
      requestedBy: uid,
      requestedAt: FieldValue.serverTimestamp(),
      status: 'pending',
    });
  });

  // リスト作成の申請があったことをサイト管理者へ通知する（仕様書 10.2）。
  await notifySafely(siteAdminUids, {
    type: 'listRequested',
    requestId: requestRef.id,
    actorUid: uid,
  });

  return { requestId: requestRef.id };
});
