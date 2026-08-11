/**
 * 利用者のプレミアム期限を管理画面から動かす（docs/PREMIUM-DESIGN.md D4 / 6-3b）
 *
 * **決済サービスは入れない**（1 節）。期限が延びる道は 2 つだけで、
 * クーポンの引き換え（callable/coupons.ts）と、ここからの操作である。
 */
import { FieldValue, Timestamp, getFirestore } from 'firebase-admin/firestore';
import { getAuth } from 'firebase-admin/auth';
import { onCall } from 'firebase-functions/v2/https';

import { REGION, paths } from '../config';
import { extendedPremiumUntil } from '../domain/premium';
import { fail } from '../errors';
import { requireMonths } from './coupons';
import { requireSiteAdmin, requireString } from './access';

/**
 * 期限を延ばす／縮める（D4）。
 *
 * **月数は負でもよい。** 誤って配ったぶんを戻す手段が無いと、
 * クーポンを止めても付いてしまった期限だけが残る。
 *
 * 縮めても**既存のデータは消えない**（D3）。新しいリストを作れなくなり、
 * 容量の上限が既定へ戻るだけ（domain/quota.ts の resolveUserQuota）。
 */
export const extendPremium = onCall({ region: REGION }, async (request) => {
  requireSiteAdmin(request);
  const uid = requireString(request.data, 'uid', { maxLength: 200 });
  const months = requireMonths(
    (request.data as Record<string, unknown>)?.months,
    { allowNegative: true }
  );

  // **Auth 側で実在を確かめる。** users ドキュメントは初回ログイン時に
  // クライアントが作るため、「まだ無い＝居ない」ではない（index.ts の注記）。
  const user = await getAuth().getUser(uid).catch(() => null);
  if (!user) {
    throw fail('not-found', 'userNotFound');
  }

  const db = getFirestore();
  // **期限は本人だけの場所に置く（config.ts の userPrivate）。**
  // `users/{uid}` は誰でも ID 指定で読めるので、そこに置くと
  // 「誰がいつまでプレミアムか」が他の利用者にも見える。
  const privateRef = db.doc(paths.userPrivate(uid));
  const nowMs = Date.now();

  const untilMs = await db.runTransaction(async (tx) => {
    const snapshot = await tx.get(privateRef);
    const current = snapshot.data()?.premium?.until;
    const until = extendedPremiumUntil({
      currentUntilMs: current instanceof Timestamp ? current.toMillis() : null,
      months,
      nowMs,
    });

    tx.set(
      privateRef,
      {
        premium: {
          until: Timestamp.fromMillis(until),
          updatedAt: FieldValue.serverTimestamp(),
        },
      },
      { merge: true }
    );

    return until;
  });

  return { premiumUntil: untilMs };
});
