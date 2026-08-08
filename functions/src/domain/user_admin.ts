/**
 * サイト管理者によるユーザーの追加・無効化・削除の判断（仕様書 11.1）
 *
 * **判断だけをここに置く。** Firebase にも Firestore にも依存させない。
 * 通信なしでテストできる形にしておくことで、「消してよいか」「止めて
 * よいか」の規則を確実に検証できる（仕様書 12.6）。
 *
 * ---
 *
 * ## 無効と削除の違い（2026-08-09 の依頼者指示）
 *
 * | | 無効 | 削除 |
 * | --- | --- | --- |
 * | ログイン | できない | できない（アカウントが無い） |
 * | Auth のアカウント | **残す**（`disabled`）。戻せる | 消す |
 * | `users` ドキュメント | **残す** | 消す |
 * | 参加中のリスト | 外す（退会と同じ） | 外す |
 * | 登録した曲・音源ファイル | **残す** | **消す** |
 * | 書いたコメント | 残す | **残す**（表示名は「退会したユーザー」） |
 *
 * **無効は戻せる。削除は戻せない。** 迷ったら無効にする。
 */

/** ユーザーに対してサイト管理者ができること。 */
export type UserAdminAction = 'disable' | 'enable' | 'delete';

/** 判断に要る、対象ユーザーの状態。 */
export interface UserAdminTarget {
  /** 対象の uid。 */
  readonly uid: string;
  /** 対象はサイト管理者か。 */
  readonly isSiteAdmin: boolean;
}

/** 断る理由。画面はこの符号から文言を引く（多言語化のため）。 */
export type UserAdminRejection =
  /** 自分自身は無効化も削除もできない。締め出しを防ぐ。 */
  | 'selfNotAllowed'
  /** 最後のサイト管理者は止められない（仕様書 4.5）。 */
  | 'lastSiteAdmin';

/**
 * その操作を行ってよいか。`null` なら行ってよい。
 *
 * **自分自身を対象にできない。** 無効化すれば自分が締め出され、
 * 削除すればアカウントごと消える。どちらも「やり直す手段」を
 * 自分から奪う操作で、サイト管理者が 0 人になる道でもある。
 * 自分をやめたいときは、設定の退会を使う（仕様書 3.5）。
 *
 * **最後のサイト管理者は止められない**（仕様書 4.5）。
 * 誰も承認できなくなり、リストが 1 つも作れなくなる。
 * サイト管理者が 2 人以上いれば、片方を止めてよい。
 */
export function rejectUserAdminAction(params: {
  action: UserAdminAction;
  actorUid: string;
  target: UserAdminTarget;
  siteAdminCount: number;
}): UserAdminRejection | null {
  const { action, actorUid, target, siteAdminCount } = params;

  // 有効に戻すのは、誰も締め出さないし誰も消えない。止める理由が無い。
  if (action === 'enable') return null;

  if (target.uid === actorUid) return 'selfNotAllowed';

  if (target.isSiteAdmin && siteAdminCount <= 1) return 'lastSiteAdmin';

  return null;
}

/**
 * 新しいユーザーの入力を確かめる。`null` なら受け付けてよい。
 *
 * **パスワードの長さは Firebase の要件（6 文字以上）に合わせる。**
 * ここで弾かないと、Auth まで届いてから読みにくい英語のエラーになる。
 */
export type NewUserRejection = 'emailInvalid' | 'passwordTooShort';

export function rejectNewUser(params: {
  email: string;
  password: string;
}): NewUserRejection | null {
  const { email, password } = params;

  // **形だけを見る。** 実在するかどうかは送ってみるまで分からない。
  // ここでの役目は、明らかな打ち間違いをその場で返すこと。
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) return 'emailInvalid';

  if (password.length < 6) return 'passwordTooShort';

  return null;
}
