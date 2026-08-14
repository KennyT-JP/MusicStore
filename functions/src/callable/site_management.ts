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
import { isAssignableRole } from '../domain/roles';
import { requireSiteAdmin, requireString } from './access';
import { fail } from '../errors';
import { runPurge } from '../scheduled/purge';

/**
 * ユーザーの一覧を返す（仕様書 11.1 ユーザー管理）。
 *
 * サイト管理者かどうかは Auth のカスタムクレームにしかないため
 * （仕様書 13.5）、クライアントからは他人の状態を知る手段がない。
 * ここで Auth と Firestore を突き合わせて返す。
 *
 * **メールアドレスは Auth から取る。Firestore からは読まない**
 * （2026-08-11）。控えは `users/{uid}/private/state` へ移してあり、
 * そこは本人しか読めない。Auth 側が本来の持ち主なので、こちらを見るほうが
 * 確実で、控えが古くてもずれない。**リスト管理者には見せない**——
 * メールアドレスを見るのは本人と、ここを通るサイト管理者だけ。
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
    /** 無効にされているか（仕様書 11.1）。ログインできない状態。 */
    isDisabled: boolean;
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
        // **Auth 側の状態が正。** Firestore に控えを持たせると、
        // 片方だけ書き換わったときにどちらが本当か分からなくなる。
        isDisabled: user.disabled === true,
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
 * 人ごとの容量上限の**土台**を設定する（PREMIUM-DESIGN「容量の数字」）。
 *
 * **アップロードを止めるかどうかを決めるのはこちらの数字。**
 * [setListQuota] のリストごとの上限は表示のために残してあるが、
 * リストが無制限に作れる以上、費用の上限はここでしか押さえられない。
 *
 * **書くのは土台（`quotaBytesBase`）。** プレミアムが切れたときに戻る先が
 * ここになる（`resolveUserQuota`）。既定の 2GB へ決め打ちで戻すと、
 * 移行の手当て——リストを 3 つ以上持つ無償の方に個別に足す
 * （PREMIUM-DESIGN「既存の利用者への影響」）——が、次にファイルが
 * 増減した瞬間に黙って消える。**契約の有無にかかわらず保つ。**
 *
 * **実効値も同じ値に戻す。** 自動拡張で増えていた分は、いったん土台まで
 * 下げる。まだ 90% を超えていれば、次にファイルが増減したときに
 * 同じ規則でもう一度増える（判定は 1 か所しかない）。
 *
 * **他のリストの stats に写した値（ownerQuotaBytes）はここでは直さない。**
 * 直すには、その人が作ったリストを全部引く必要がある。写しは表示用で、
 * 次にそのリストのファイルが増減したときに更新される。
 */
export const setUserQuota = onCall({ region: REGION }, async (request) => {
  requireSiteAdmin(request);
  const uid = requireString(request.data, 'uid', { maxLength: 200 });

  const quotaBytes = Number(
    (request.data as Record<string, unknown>)?.quotaBytes
  );
  if (!Number.isFinite(quotaBytes) || quotaBytes <= 0) {
    throw fail('invalid-argument', 'invalidQuota');
  }

  const user = await getAuth().getUser(uid).catch(() => null);
  if (!user) {
    throw fail('not-found', 'userNotFound');
  }

  // **容量は本人だけの場所にある（config.ts の userPrivate）。**
  // `users/{uid}` は誰でも ID 指定で読めるため、使用量をそこに置くと
  // 「誰がどれだけ溜め込んでいるか」が他の利用者にも見えていた。
  const ref = getFirestore().doc(paths.userPrivate(uid));

  // **使用量も一緒に埋める。** 画面は `usedBytes` と `quotaBytes` の
  // 両方が揃って初めて容量を出す（片方だけでは「まだ集計されていない」と
  // 「使っていない」を区別できないため）。上限だけ入れると、
  // 一度もアップロードしていない人の容量表示が出ないままになる。
  const used = Number((await ref.get()).data()?.storage?.usedBytes ?? 0);

  await ref.set(
    {
      storage: {
        usedBytes: Number.isFinite(used) ? used : 0,
        quotaBytesBase: Math.trunc(quotaBytes),
        quotaBytes: Math.trunc(quotaBytes),
      },
    },
    { merge: true }
  );

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

/**
 * サイト管理者が、ユーザーをリストのメンバーに加える（仕様書 5.7）。
 *
 * **なぜ要るか。** これまで人がリストに入る道は3つで、いずれも
 * **入る側か、そのリストの管理者の操作**を要した——参加申請（5.2）・
 * 共有リンク（3.3）・管理者不在時の指名（5.6）。**運営が「この人を
 * このリストに入れておく」ことができなかった**。
 *
 * **役割は呼び出し側が渡す。** 既定を決め打ちにしない——加える人が
 * 曲を足せるのか見るだけなのかは、加える側が知っていることで、
 * こちらが推測してよいものではない。付けてよいのは Super User と
 * Read Only だけ（`isAssignableRole`）。**リスト管理者にはできない**
 * ——それは [assignListAdmin]（5.6）の仕事で、意味も条件も違う。
 *
 * **すでにメンバーなら断る。** 役割の上げ下げはリスト管理者の仕事
 * （5.4）で、ここで黙って書き換えると、**リスト管理者が決めた役割を
 * サイト管理者が知らずに巻き戻す**ことが起きる。
 */
export const addListMember = onCall({ region: REGION }, async (request) => {
  const actorUid = requireSiteAdmin(request);
  const listId = requireString(request.data, 'listId', { maxLength: 200 });
  const targetUid = requireString(request.data, 'uid', { maxLength: 200 });
  const role = (request.data as Record<string, unknown> | undefined)?.role;
  if (!isAssignableRole(role)) {
    throw fail('invalid-argument', 'roleNotAllowed');
  }

  const db = getFirestore();

  const list = await db.doc(paths.list(listId)).get();
  if (!list.exists) {
    throw fail('not-found', 'listNotFound');
  }

  // **Auth と Firestore の両方を見る。** 無効化は Auth 側、退会は
  // Firestore 側にあり、片方だけ見ると**もう片方の状態の人が入れる**。
  const user = await getAuth().getUser(targetUid).catch(() => null);
  if (!user) {
    throw fail('not-found', 'userNotFound');
  }
  if (user.disabled) {
    throw fail('failed-precondition', 'userDisabled');
  }
  // **`isWithdrawn` は `users/{uid}` に残してある**（2026-08-11 の移動の対象外）。
  // 退会した人の表示名を「退会したユーザー」に切り替えるのに要るので、
  // 誰でも読める側に置いたままにする（仕様書 3.5）。
  const profile = await db.doc(paths.user(targetUid)).get();
  if (profile.get('isWithdrawn') === true) {
    throw fail('failed-precondition', 'userWithdrawn');
  }

  const memberRef = db.doc(paths.listMember(listId, targetUid));
  if ((await memberRef.get()).exists) {
    throw fail('already-exists', 'alreadyMember');
  }

  await memberRef.set({
    // uid を必ず入れる（理由は assignListAdmin のコメント）。
    uid: targetUid,
    role,
    via: 'assigned',
    joinedAt: FieldValue.serverTimestamp(),
    addedBy: actorUid,
  });

  return { ok: true };
});

/**
 * 掃除をいますぐ動かす（サイト管理者だけ／仕様書 13.4・2026-08-15）。
 *
 * **定期実行（毎日 4:00）と同じ中身を呼ぶ。** 別に書くと、手で試した
 * 結果が夜中に走るものの確認にならない。
 *
 * 用途は 2 つ。
 *
 *   - **通しの確認**（統合テスト）。定期実行そのものは自動テストから
 *     呼べないため、ここが唯一の「最後まで動かす」経路になる
 *   - 猶予を短くしたあと、すぐ空けたいとき
 *
 * **消したファイルは戻せない。** 判断（何を消すか）は共有した実装が
 * 持ち、ここは入口だけ。
 */
export const runPurgeNow = onCall({ region: REGION }, async (request) => {
  requireSiteAdmin(request);
  return await runPurge();
});
