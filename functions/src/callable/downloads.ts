/**
 * オフライン用ダウンロードの権限確認（docs/DOWNLOAD-DESIGN.md 5.1）
 *
 * 端末は起動時に、持っているリストの一覧を渡してここを呼ぶ（4.2）。
 *
 * ```
 * 入力  { listIds: string[] }
 * 出力  { premiumActive: boolean,
 *         verifiedAt: number,
 *         lists: { [listId: string]: 'member' | 'notMember' } }
 * ```
 *
 * **判定そのものは domain/downloads.ts にある。** ここは Firestore から
 * 読んで渡すだけにする（domain/premium.ts・domain/quota.ts と同じ形）。
 *
 * ---
 *
 * ## **プレミアムでないことを例外にしない**（5.1 / 10 節の危険 4）
 *
 * **5 節でいちばん大事な点である。** ここが投げるのは、
 * ログイン・メール確認（`requireUid`）と、`listIds` の形が壊れている
 * ときの 2 つだけ。**プレミアムの有無も、メンバーかどうかも、
 * 正常応答の中身として返す。**
 *
 * 例外にすると、呼び出し側は「呼び出しが失敗した」と「プレミアムでない」を
 * 区別できない。そして**この関数の失敗は端末のファイル削除を引き起こす**ので、
 * **電波の悪い場所で 1 回失敗しただけで全曲が消える。**
 *
 * ```
 * 呼び出しが失敗した      → 何もしない。オフラインとして扱う
 * premiumActive: false    → 削除する
 * lists[X] == 'notMember' → X のぶんだけ削除する
 * ```
 *
 * この形を崩していないことは `functions/test/downloads.test.ts` の
 * 静的な見張りが確かめている（本文に `premiumRequired` が現れないこと）。
 *
 * ## **サイト管理者は実効プレミアムとして扱う**（仕様書 4.1）
 *
 * 仕様書 4.1「上位の役割は下位の権限をすべて包含する」に揃え、
 * **サイト管理者はプレミアム機能をすべて持つ**（2026-08-22。旧・論点 18 を
 * 上書き）。ここでは `isSiteAdminRequest(request)` を `evaluateDownloadAccess`
 * へ渡し、判定側で `premiumActive` に OR する（実効プレミアム）。
 *
 * **混ぜるのは「プレミアムか」だけ。** 「メンバーか」は
 * `lists/{listId}/members/{uid}` の存在で決めるまま——サイト管理者でも、
 * そのリストのメンバーでなければ `notMember` を返す。メンバーの軸は
 * クライアント側（`Permissions.canDownload` の `role != null`）と揃っている。
 */
import { Timestamp, getFirestore } from 'firebase-admin/firestore';
import { onCall } from 'firebase-functions/v2/https';

import { REGION, paths } from '../config';
import { evaluateDownloadAccess, parseDownloadListIds } from '../domain/downloads';
import { fail } from '../errors';
import { isSiteAdminRequest, requireUid } from './access';

export const verifyDownloadAccess = onCall({ region: REGION }, async (request) => {
  // ログイン・メール確認は自前で書かない（3.1／監査 S3）。
  const uid = requireUid(request);

  const parsed = parseDownloadListIds(
    (request.data as Record<string, unknown> | undefined)?.listIds
  );
  if ('rejection' in parsed) {
    // 件数超過は 5.1 のとおり専用の符号 `tooManyLists` で返す。
    // 一時期、`ERROR_CODES` を増やすと `lib/l10n` の `functionError…` を
    // 対で足す必要がある（errors.ts の注記／test/ui/function_error_test.dart
    // が突き合わせている）ため、意味の近い `fieldTooLong` で代用していた。
    // **代用をやめても `field: 'listIds'` は残す。** 「どの入力が悪いのか」は
    // 符号の名前ではなく `details.field` から読む決まりにしてある
    // （callable/access.ts の `requireString` と同じ形）。
    throw parsed.rejection === 'tooManyLists'
      ? fail('invalid-argument', 'tooManyLists', { field: 'listIds' })
      : fail('invalid-argument', 'missingField', { field: 'listIds' });
  }
  const { listIds } = parsed;

  // **時刻はここで 1 回だけ取る。** 期限の判定と、端末へ返す
  // `verifiedAt` が同じ瞬間を指していないと、「確認が取れた時刻」が
  // 判定の時刻とずれる。
  const nowMs = Date.now();

  const db = getFirestore();

  // **プレミアムは本人だけの場所から読む**（config.ts の userPrivate）。
  // `users/{uid}` は誰でも ID 指定で読めるので、そこには置いていない。
  const priv = await db.doc(paths.userPrivate(uid)).get();
  const until = priv.data()?.premium?.until;

  // **メンバーかどうかはリストごとに見る**（2.3）。脱退・除外はリスト
  // ごとに起きるため。`getAll` は引数 0 個を受け付けないので、
  // 空の一覧のときは読みに行かない（端末が 1 曲も持っていない場合。
  // それでも `premiumActive` は返す必要がある）。
  const snapshots =
    listIds.length > 0
      ? await db.getAll(...listIds.map((id) => db.doc(paths.listMember(id, uid))))
      : [];

  return evaluateDownloadAccess({
    premiumUntilMs: until instanceof Timestamp ? until.toMillis() : null,
    nowMs,
    // 実効プレミアム＝プレミアム有効 OR サイト管理者（仕様書 4.1）。
    isSiteAdmin: isSiteAdminRequest(request),
    memberships: listIds.map((listId, index) => ({
      listId,
      // **存在だけで決める。役割（role）は読まない**（論点 9・18）。
      //
      // **読めなかったときは「メンバーでない」に倒さない。** `getAll` は
      // 要求した順に同じ件数を返すので `undefined` にはならないが、
      // 万一ずれたときに `notMember` を返すと、それは端末のファイル削除に
      // なる。安全側は「メンバーである」——消さないほう。
      isMember: snapshots[index]?.exists !== false,
    })),
  });
});
