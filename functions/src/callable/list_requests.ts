/**
 * リスト作成申請の承認・却下（仕様書 5.1 / 5.2.1 / 13.3）
 */
import {
  FieldValue,
  Timestamp,
  getFirestore,
  type Transaction,
} from 'firebase-admin/firestore';
import { onCall } from 'firebase-functions/v2/https';

import { REGION, paths, readSiteConfig } from '../config';
import { normalizeListName } from '../domain/paths';
import { isPremiumActive } from '../domain/premium';
import { USER_DEFAULT_QUOTA_BYTES } from '../domain/quota';
import { notifySafely, siteAdminUids } from '../notifications';
import {
  isSiteAdminRequest,
  requireSiteAdmin,
  requireString,
  requireUid,
} from './access';
import { fail } from '../errors';

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
        throw fail('not-found', 'requestNotFound');
      }

      const data = snapshot.data() ?? {};
      if (data.status !== 'pending') {
        throw fail('failed-precondition', 'requestAlreadyHandled');
      }

      const listName = String(data.listName ?? '').trim();
      if (!listName) {
        throw fail('failed-precondition', 'listNameMissing');
      }
      const nameLower = normalizeListName(listName);
      const requestedBy = String(data.requestedBy ?? '');
      if (!requestedBy) {
        throw fail('failed-precondition', 'requesterUnknown');
      }

      // 承認の時点であらためて重複を確かめる。
      // 申請から承認までの間に、同じ名前が確定している可能性があるため。
      const nameRef = db.doc(paths.listName(nameLower));
      const existingName = await tx.get(nameRef);
      if (existingName.exists && existingName.data()?.listId) {
        throw fail('already-exists', 'listNameTaken', { listName });
      }

      // **作った人の合計は、書き込みの前に読む**（トランザクションの決まり）。
      const ownerStorage = await readOwnerStorage(tx, requestedBy);

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
      tx.set(
        db.doc(paths.listStats(listRef.id)),
        initialStats(config.defaultQuotaBytes, ownerStorage)
      );

      // 承認されると申請者がそのリストのリスト管理者になる（仕様書 5.1）。
      tx.set(db.doc(paths.listMember(listRef.id, requestedBy)), {
        // **uid を持たせる。** 退会時に「この人が入っているリスト」を
        // 引くために要る。collectionGroup では documentId() に完全パスしか
        // 渡せないため、ドキュメント ID だけでは横断的に引けない（監査 S14）。
        uid: requestedBy,
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
      throw fail('not-found', 'requestNotFound');
    }
    const data = snapshot.data() ?? {};
    if (data.status !== 'pending') {
      throw fail('failed-precondition', 'requestAlreadyHandled');
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
    throw fail('invalid-argument', 'invalidTrackCount');
  }
  if (!Number.isFinite(expectedUserCount) || expectedUserCount < 0) {
    throw fail('invalid-argument', 'invalidUserCount');
  }

  const db = getFirestore();
  const nameLower = normalizeListName(listName);
  const nameRef = db.doc(paths.listName(nameLower));
  const requestRef = db.collection('listRequests').doc();

  await db.runTransaction(async (tx) => {
    const existing = await tx.get(nameRef);
    if (existing.exists) {
      throw fail('already-exists', 'listNameTaken', { listName });
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

/**
 * 申請なしでリストを作る（PREMIUM-DESIGN 4.2）。
 * **実効プレミアムの人だけ（プレミアム有効 or サイト管理者／仕様書 4.1）。**
 *
 * **承認（approveListRequest）と同じトランザクション・同じ名前の予約を通す。**
 * 行うのは 1〜5 で、申請の更新（6）だけを行わない。
 *
 * > 名前の予約を飛ばしてはいけない。承認の流れに組み込まれているので、
 * > 飛ばすと**同じ名前のリストが 2 つできる**（9-2）。あとから直せない。
 *
 * 確かめることは順序も含めてすべてサーバー側で行う。プレミアムの状態は
 * Firestore にあり（3.1）、**セキュリティルールでは判定しない**——リストの
 * 作成は名前の予約・容量の初期化・メンバー登録をまとめて行う必要があるため、
 * 必ずここを通るからである。
 *
 * **作れる数に上限は無い**（D5）。数える処理も、そのための索引も要らない。
 */
export const createListDirectly = onCall({ region: REGION }, async (request) => {
  // 他の呼び出し可能関数と同じ入口（ログイン＋メール確認／監査 S3）。
  const uid = requireUid(request);
  const listName = requireString(request.data, 'listName', { maxLength: 100 });

  const db = getFirestore();
  const config = await readSiteConfig();
  const nameLower = normalizeListName(listName);
  const nameRef = db.doc(paths.listName(nameLower));
  const nowMs = Date.now();

  const listId = await db.runTransaction(async (tx) => {
    // **プレミアムの確認もトランザクションの中で行う。** 外で読むと、
    // 読んでから作るまでの間に期限が切れた場合に通ってしまう。
    // プレミアムの状態は本人だけの場所にある（config.ts の userPrivate）。
    //
    // **サイト管理者は実効プレミアムとして通す**（仕様書 4.1。旧方針では
    // サイト管理者もプレミアムが要ったが、上位の役割は下位の権限をすべて
    // 包含する方針へ上書きした）。クレームはトランザクションに依存しないので
    // 外で判定してよい。
    const state = await tx.get(db.doc(paths.userPrivate(uid)));
    const until = state.data()?.premium?.until;
    if (
      !isPremiumActive(
        until instanceof Timestamp ? until.toMillis() : null,
        nowMs
      ) &&
      !isSiteAdminRequest(request)
    ) {
      // **符号を分ける。** 未ログインでもメール未確認でもなく、
      // 「契約が要る」ことが画面に伝わらないと導線を出せない。
      throw fail('permission-denied', 'premiumRequired');
    }

    // **予約があれば、それが申請中でも作らない。** 承認側は
    // 「listId が入っていない予約」を自分の申請のものとして通すが、
    // こちらには対応する申請が無い。素通しすると、申請中の名前を
    // 横取りして同じ名前のリストが 2 つできる。
    const existingName = await tx.get(nameRef);
    if (existingName.exists) {
      throw fail('already-exists', 'listNameTaken', { listName });
    }

    const ownerStorage = await readOwnerStorage(tx, uid);

    const listRef = db.collection(paths.lists).doc();

    tx.set(listRef, {
      name: listName,
      nameLower,
      createdBy: uid,
      adminCount: 1,
      memberCount: 1,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });

    tx.set(
      db.doc(paths.listStats(listRef.id)),
      initialStats(config.defaultQuotaBytes, ownerStorage)
    );

    tx.set(db.doc(paths.listMember(listRef.id, uid)), {
      // uid を持たせる理由は approveListRequest のコメントと同じ（監査 S14）。
      uid,
      role: 'listAdmin',
      via: 'founder',
      joinedAt: FieldValue.serverTimestamp(),
      addedBy: uid,
    });

    tx.set(nameRef, {
      listId: listRef.id,
      reservedAt: FieldValue.serverTimestamp(),
    });

    return listRef.id;
  });

  return { listId };
});

/**
 * リストを作った人の合計使用量と上限（PREMIUM-DESIGN「容量の数字」）。
 *
 * **トランザクションの中で、書き込みより先に読むこと。**
 */
async function readOwnerStorage(
  tx: Transaction,
  ownerUid: string
): Promise<{ usedBytes: number; quotaBytes: number }> {
  // 容量は本人だけの場所にある（config.ts の userPrivate）。**写す先の
  // stats はメンバーが読める**ので、写すのは合計と上限の 2 つだけにする。
  const snapshot = await tx.get(getFirestore().doc(paths.userPrivate(ownerUid)));
  const storage = snapshot.data()?.storage;
  // 写すのは**実効値**（画面が出すのはこちら）。まだ何も無ければ土台、
  // 土台も無ければ既定（domain/quota.ts）へ倒す。
  const base = Number(storage?.quotaBytesBase ?? USER_DEFAULT_QUOTA_BYTES);
  return {
    usedBytes: Number(storage?.usedBytes ?? 0),
    quotaBytes: Number(storage?.quotaBytes ?? base),
  };
}

/**
 * 新しいリストの meta/stats（仕様書 13.3 / PREMIUM-DESIGN「波及するところ」）。
 *
 * `usedBytes` / `quotaBytes` は**このリストのぶん**。表示に要るので残す。
 *
 * `ownerUsedBytes` / `ownerQuotaBytes` は**リストを作った人の合計の写し**。
 * 画面側がメンバーとして読めるのは stats だけで、他人の users ドキュメントは
 * 読めないため、ここに写す。**多少古くてもよい**——本当の判定は
 * サーバー側（triggers/storage.ts）で人ごとの合計に対して行う。
 */
function initialStats(
  defaultQuotaBytes: number,
  owner: { usedBytes: number; quotaBytes: number }
): Record<string, unknown> {
  return {
    nextSeq: 1,
    usedBytes: 0,
    quotaBytes: defaultQuotaBytes,
    ownerUsedBytes: owner.usedBytes,
    ownerQuotaBytes: owner.quotaBytes,
    notifiedNotice80: false,
    notifiedWarning90: false,
  };
}
