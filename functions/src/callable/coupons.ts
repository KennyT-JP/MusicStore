/**
 * クーポンの発行・停止・一覧・引き換え（docs/PREMIUM-DESIGN.md 2 / 3.2 / 5）
 *
 * **クーポンはクライアントから直接読めない**（ルールで全面禁止）。
 * 読めると、コードの一覧がそのまま漏れて誰でもプレミアムになれる（9-3）。
 * 発行・一覧・停止はサイト管理者だけ、引き換えは本人だけがここを通す。
 */
import { FieldValue, Timestamp, getFirestore } from 'firebase-admin/firestore';
import { onCall } from 'firebase-functions/v2/https';

import { REGION, paths } from '../config';
import {
  evaluateCouponRedemption,
  generateCouponCode,
  hashCouponCode,
  normalizeCouponCode,
} from '../domain/coupon';
import { extendedPremiumUntil } from '../domain/premium';
import { fail } from '../errors';
import { requireSiteAdmin, requireString, requireUid } from './access';

/** 付与できる月数の上限。桁を 1 つ間違えても 100 年にならないための歯止め。 */
const MAX_MONTHS = 120;

/** 指定コードの長さの範囲。短すぎるものは総当たりで当てられる。 */
const MIN_CODE_LENGTH = 4;
const MAX_CODE_LENGTH = 64;

/**
 * クーポンを発行する（D1 / D2 / D8）。
 *
 * コードは**自動生成（24 文字）と、文字列の指定**の両方を選べる。
 * 指定したときは短く覚えやすくなるぶん推測されやすいので、
 * 人数（`maxUses`）と期限（`expiresAt`）を必ず付けて配ること（画面で伝える）。
 */
export const createCoupon = onCall({ region: REGION }, async (request) => {
  const adminUid = requireSiteAdmin(request);
  const data = (request.data ?? {}) as Record<string, unknown>;

  const months = requireMonths(data.months, { allowNegative: false });
  const maxUses = requireMaxUses(data.maxUses);
  const expiresAt = optionalTimestamp(data.expiresAt);

  // 指定が無ければ自動生成。**指定されたコードも同じ形に揃えてから扱う**
  // （大文字小文字と前後の空白を吸収する／normalizeCouponCode）。
  const requested = data.code === undefined || data.code === null
    ? null
    : normalizeCouponCode(
        requireString(data, 'code', { maxLength: MAX_CODE_LENGTH })
      );
  if (requested !== null && requested.length < MIN_CODE_LENGTH) {
    throw fail('invalid-argument', 'missingField', { field: 'code' });
  }
  const code = requested ?? generateCouponCode();
  const codeHash = hashCouponCode(code);

  const db = getFirestore();
  const couponRef = db.collection(paths.coupons).doc();

  await db.runTransaction(async (tx) => {
    // **重複はトランザクションの中で確かめる。** 読んでから書くまでの間に
    // 同じコードが発行されると、引き換えの照合がどちらを指すか決まらない。
    const existing = await tx.get(
      db.collection(paths.coupons).where('codeHash', '==', codeHash).limit(1)
    );
    if (!existing.empty) {
      throw fail('already-exists', 'couponCodeTaken');
    }

    tx.set(couponRef, {
      code, // 表示用。照合は codeHash で行う
      codeHash,
      months,
      maxUses,
      usedCount: 0,
      expiresAt,
      disabled: false,
      createdBy: adminUid,
      createdAt: FieldValue.serverTimestamp(),
    });
  });

  return { couponId: couponRef.id, code };
});

/**
 * 使える人数を変える・停止する（D1）。
 *
 * **`maxUses` は `usedCount` を下回る値も許す。** 配りすぎたので止めたい、
 * という求めに停止とは別の粒度で応えるため。そのときは**それ以上
 * 使えなくなるだけ**で、すでに使った人のプレミアムには触れない。
 *
 * **消す手段は用意しない。** 消すと誰が使ったかの記録まで消える（5）。
 */
export const updateCoupon = onCall({ region: REGION }, async (request) => {
  requireSiteAdmin(request);
  const data = (request.data ?? {}) as Record<string, unknown>;
  const couponId = requireString(data, 'couponId', { maxLength: 200 });

  const patch: Record<string, unknown> = {};
  if (data.maxUses !== undefined && data.maxUses !== null) {
    patch.maxUses = requireMaxUses(data.maxUses);
  }
  if (data.disabled !== undefined && data.disabled !== null) {
    if (typeof data.disabled !== 'boolean') {
      throw fail('invalid-argument', 'missingField', { field: 'disabled' });
    }
    patch.disabled = data.disabled;
  }
  if (Object.keys(patch).length === 0) {
    throw fail('invalid-argument', 'missingField', { field: 'maxUses' });
  }

  const ref = getFirestore().doc(paths.coupon(couponId));
  if (!(await ref.get()).exists) {
    throw fail('not-found', 'couponNotFound');
  }
  await ref.update(patch);

  return { ok: true };
});

/**
 * クーポンの一覧（5）。
 *
 * **コードも返す。** 配ったあとに「どのコードを渡したか」を確かめられないと、
 * 問い合わせに答えられない。ここを通る相手はサイト管理者だけ。
 */
export const listCoupons = onCall({ region: REGION }, async (request) => {
  requireSiteAdmin(request);

  const snapshot = await getFirestore()
    .collection(paths.coupons)
    .orderBy('createdAt', 'desc')
    .get();

  return {
    coupons: snapshot.docs.map((doc) => {
      const data = doc.data();
      return {
        couponId: doc.id,
        // **`id` でも取れるようにする。** 発行（createCoupon）が返すのは
        // `couponId` で、画面のモデルは `id` で読む。どちらか片方に
        // 寄せると、読む側と書く側のどちらかを必ず直すことになり、
        // 直し忘れると**一覧の行がどのクーポンか分からなくなる**
        // （停止も上限の変更も効かない形で壊れる）。
        id: doc.id,
        code: String(data.code ?? ''),
        months: Number(data.months ?? 0),
        maxUses: Number(data.maxUses ?? 0),
        usedCount: Number(data.usedCount ?? 0),
        // **時刻はミリ秒で返す。** Timestamp をそのまま返すと
        // 呼び出し可能関数の応答（JSON）で形が定まらない。
        expiresAt: toMillis(data.expiresAt),
        createdAt: toMillis(data.createdAt),
        disabled: data.disabled === true,
        createdBy: String(data.createdBy ?? ''),
      };
    }),
  };
});

/** 誰がいつ使ったか（5：追跡と、問い合わせへの回答用）。 */
export const listCouponRedemptions = onCall(
  { region: REGION },
  async (request) => {
    requireSiteAdmin(request);
    const couponId = requireString(request.data, 'couponId', {
      maxLength: 200,
    });

    const snapshot = await getFirestore()
      .collection(paths.couponRedemptions(couponId))
      .get();

    return {
      redemptions: snapshot.docs.map((doc) => ({
        uid: doc.id,
        redeemedAt: toMillis(doc.data().redeemedAt),
      })),
    };
  }
);

/**
 * クーポンを引き換える（3 / 9-1）。
 *
 * **二重取りはトランザクションで防ぐ。** 使用記録（ドキュメント ID が uid）が
 * 無いこと・上限に達していないこと・停止されていないこと・期限を過ぎて
 * いないことを**同じトランザクションの中で**確かめ、記録を作って
 * `usedCount` を 1 増やす。読んでから書くまでの間に別の要求が入るため、
 * 確認と書き込みを分けると 2 回取れてしまう。
 *
 * **2 枚目は月数を足す（上書きしない／D4）。** いまの期限が未来なら
 * そこから、過ぎていれば今から数える（extendedPremiumUntil）。
 */
export const redeemCoupon = onCall({ region: REGION }, async (request) => {
  const uid = requireUid(request);
  const code = requireString(request.data, 'code', {
    maxLength: MAX_CODE_LENGTH,
  });
  const codeHash = hashCouponCode(code);

  const db = getFirestore();
  const nowMs = Date.now();

  const untilMs = await db.runTransaction(async (tx) => {
    // --- 読み取りはすべて先に行う（Firestore のトランザクションの決まり） ---
    const found = await tx.get(
      db.collection(paths.coupons).where('codeHash', '==', codeHash).limit(1)
    );
    const couponDoc = found.docs[0] ?? null;

    const redemptionRef = couponDoc
      ? db.doc(paths.couponRedemption(couponDoc.id, uid))
      : null;
    const redemption = redemptionRef ? await tx.get(redemptionRef) : null;
    const userRef = db.doc(paths.user(uid));
    const user = await tx.get(userRef);

    const data = couponDoc?.data();
    const verdict = evaluateCouponRedemption({
      coupon: data
        ? {
            disabled: data.disabled === true,
            expiresAtMs: toMillis(data.expiresAt),
            usedCount: Number(data.usedCount ?? 0),
            maxUses: Number(data.maxUses ?? 0),
          }
        : null,
      alreadyRedeemed: redemption?.exists === true,
      nowMs,
    });
    if ('rejection' in verdict) {
      // 見つからないときだけ not-found。ほかは「条件を満たしていない」。
      throw fail(
        verdict.rejection === 'couponNotFound' ? 'not-found' : 'failed-precondition',
        verdict.rejection
      );
    }

    const until = extendedPremiumUntil({
      currentUntilMs: toMillis(user.data()?.premium?.until),
      months: Number(data?.months ?? 0),
      nowMs,
    });

    // --- ここから書き込み ---
    tx.set(redemptionRef!, { redeemedAt: FieldValue.serverTimestamp() });
    tx.update(couponDoc!.ref, { usedCount: FieldValue.increment(1) });
    tx.set(
      userRef,
      {
        premium: {
          until: Timestamp.fromMillis(until),
          // どのクーポンで付いたかを残す（3.1 の追跡用）。
          grantedBy: couponDoc!.id,
          updatedAt: FieldValue.serverTimestamp(),
        },
      },
      { merge: true }
    );

    return until;
  });

  return { premiumUntil: untilMs };
});

/**
 * 月数の検証（`monthsInvalid`）。
 *
 * 管理画面からの延長（callable/premium.ts）は**負でもよい**（縮める）。
 * クーポンは付与するものなので正だけ。
 */
export function requireMonths(
  value: unknown,
  { allowNegative }: { allowNegative: boolean }
): number {
  const months = Number(value);
  if (!Number.isFinite(months) || !Number.isInteger(months) || months === 0) {
    throw fail('invalid-argument', 'monthsInvalid');
  }
  if (!allowNegative && months < 0) {
    throw fail('invalid-argument', 'monthsInvalid');
  }
  if (Math.abs(months) > MAX_MONTHS) {
    throw fail('invalid-argument', 'monthsInvalid');
  }
  return months;
}

function requireMaxUses(value: unknown): number {
  const maxUses = Number(value);
  if (!Number.isFinite(maxUses) || !Number.isInteger(maxUses) || maxUses < 1) {
    throw fail('invalid-argument', 'maxUsesInvalid');
  }
  return maxUses;
}

/**
 * 省略できる期限。無期限は null（3.2 の `expiresAt: Timestamp | null`）。
 *
 * **ミリ秒でも ISO 8601 の文字列でも受ける。** 呼び出し可能関数の引数は
 * JSON になるため Timestamp をそのまま渡せず、画面側がどちらの形で
 * 送るかは実装の都合で変わる。**受け取る側が広く受ける**ほうが、
 * 片方だけ直したときに「期限を入れた瞬間に発行できない」形で壊れない。
 */
function optionalTimestamp(value: unknown): Timestamp | null {
  if (value === undefined || value === null) return null;

  const ms =
    typeof value === 'string' ? Date.parse(value) : Number(value);
  if (!Number.isFinite(ms) || ms <= 0) {
    throw fail('invalid-argument', 'missingField', { field: 'expiresAt' });
  }
  return Timestamp.fromMillis(ms);
}

/** Timestamp をミリ秒へ。無いものは null。 */
function toMillis(value: unknown): number | null {
  if (value instanceof Timestamp) return value.toMillis();
  if (typeof value === 'number' && Number.isFinite(value)) return value;
  return null;
}
