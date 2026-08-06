/**
 * アプリ内通知の配信（仕様書 10.2 / 10.3 / 12.7）
 *
 * 初期リリースではアプリ内通知のみを実装する。プッシュ通知（FCM）は
 * モバイル版の開発時にまとめて対応する（仕様書 12.7）。
 *
 * まとめ通知は行わない。受信者ごとに 1 件ずつ作成する。
 */
import { FieldValue, getFirestore } from 'firebase-admin/firestore';
import * as logger from 'firebase-functions/logger';

import { paths } from './config';

/** 通知種別（仕様書 10.2）。 */
export type NotificationType =
  | 'itemAdded'
  | 'commentAdded'
  | 'quotaNotice'
  | 'quotaWarning'
  | 'listRequested'
  | 'joinRequested'
  | 'requestApproved';

export interface NotificationPayload {
  type: NotificationType;
  listId?: string;
  itemId?: string;
  commentId?: string;
  requestId?: string;
  /** 通知のきっかけを作った人。 */
  actorUid?: string;
}

/**
 * 受信者ごとに通知を作成する。
 *
 * - 通知設定（仕様書 10.3）を見て、オフの人には作らない。
 * - **きっかけを作った本人には送らない**。自分の操作の通知が自分に届くのは
 *   雑音にしかならないため。
 * - 同じ人が複数の理由で受信対象になっても 1 件だけにする
 *   （例：自分の項目にコメントが付いたリスト管理者）。
 */
export async function notifyUsers(
  recipientUids: Iterable<string>,
  payload: NotificationPayload
): Promise<void> {
  const db = getFirestore();

  const targets = new Set(
    [...recipientUids].filter((uid) => uid && uid !== payload.actorUid)
  );
  if (targets.size === 0) return;

  const results = await Promise.allSettled(
    [...targets].map(async (uid) => {
      if (!(await inAppEnabled(uid, payload.type))) return;

      await db.collection(paths.userNotifications(uid)).add({
        type: payload.type,
        ...(payload.listId ? { listId: payload.listId } : {}),
        ...(payload.itemId ? { itemId: payload.itemId } : {}),
        ...(payload.commentId ? { commentId: payload.commentId } : {}),
        ...(payload.requestId ? { requestId: payload.requestId } : {}),
        ...(payload.actorUid ? { actorUid: payload.actorUid } : {}),
        isRead: false,
        createdAt: FieldValue.serverTimestamp(),
      });
    })
  );

  // 1 人分の失敗で全体を止めない。通知は本処理の副次的なものなので、
  // 失敗はログに残して先へ進む。
  for (const result of results) {
    if (result.status === 'rejected') {
      logger.warn('通知の作成に失敗しました', { reason: result.reason });
    }
  }
}

/**
 * 通知を送る。失敗しても呼び出し元を巻き込まない。
 *
 * **申請や承認などの本処理が終わったあとに使うこと。**
 * 通知は副次的なものなのに、宛先を集める段階（Auth の走査など）で
 * 例外が出ると呼び出し全体が internal で失敗する。利用者から見ると
 * 「エラーが出たのに実際は登録されている」という分かりにくい状態になる。
 *
 * 宛先を集める処理も含めて包むため、関数として受け取る。
 */
export async function notifySafely(
  collectRecipients: () => Promise<string[]> | string[],
  payload: NotificationPayload
): Promise<void> {
  try {
    await notifyUsers(await collectRecipients(), payload);
  } catch (error) {
    logger.error('通知の送信に失敗しました（本処理は完了しています）', {
      type: payload.type,
      error: error instanceof Error ? error.message : String(error),
    });
  }
}

/**
 * その人がこの種別のアプリ内通知を受け取る設定か（仕様書 10.3）。
 *
 * マスタースイッチがオフなら、種別の設定にかかわらず送らない。
 * 設定が読めない場合は「オン」として扱う（初期状態は全てオン）。
 */
async function inAppEnabled(
  uid: string,
  type: NotificationType
): Promise<boolean> {
  const snapshot = await getFirestore().doc(paths.user(uid)).get();
  const data = snapshot.data();

  // 退会した人には送らない（仕様書 3.5）。
  if (data?.isWithdrawn === true) return false;

  const settings = data?.notificationSettings;
  if (!settings) return true;
  if (settings.master === false) return false;

  const forType = settings.types?.[type];
  if (!forType) return true;
  return forType.inApp !== false;
}

/**
 * そのリストのメンバー全員の uid を集める（仕様書 10.2）。
 *
 * 役割は問わない。**曲が追加されたことは、そのリストに参加している人
 * 全員にとっての知らせ**なので、閲覧のみ（Read Only）の人も宛先に入れる。
 *
 * リスト管理者もメンバーとして登録されている（13.5）ので、この一覧に含まれる。
 * 受け取るかどうかは各自の通知設定で決まる（10.3）。
 */
export async function listMemberUids(listId: string): Promise<string[]> {
  const snapshot = await getFirestore()
    .collection(paths.listMembers(listId))
    .get();
  return snapshot.docs.map((doc) => doc.id);
}

/**
 * そのリストのリスト管理者の uid を集める（仕様書 10.2）。
 */
export async function listAdminUids(listId: string): Promise<string[]> {
  const snapshot = await getFirestore()
    .collection(paths.listMembers(listId))
    .where('role', '==', 'listAdmin')
    .get();
  return snapshot.docs.map((doc) => doc.id);
}

/**
 * サイト管理者の uid を集める（仕様書 10.2）。
 *
 * サイト管理者は Auth のカスタムクレームで持ち、Firestore には
 * メンバー登録を持たない（仕様書 13.5）。そのため Auth 側を走査する。
 *
 * **注意**：利用者が増えると全ユーザーの走査が重くなる。
 * サイト管理者は少人数の想定なので現状はこれで足りるが、
 * 遅くなってきたら uid の一覧を siteConfig に持たせる等の見直しが必要。
 */
export async function siteAdminUids(): Promise<string[]> {
  const { getAuth } = await import('firebase-admin/auth');
  const admins: string[] = [];
  let pageToken: string | undefined;

  do {
    const page = await getAuth().listUsers(1000, pageToken);
    for (const user of page.users) {
      if (user.customClaims?.siteAdmin === true) admins.push(user.uid);
    }
    pageToken = page.pageToken;
  } while (pageToken);

  return admins;
}
