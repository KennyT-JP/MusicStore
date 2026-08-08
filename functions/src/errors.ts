/**
 * 呼び出し可能関数のエラー（仕様書 2 章 / 14.4）
 *
 * **利用者に見せる文言は画面側が決める。**
 *
 * 以前は日本語の文をそのままエラーメッセージに入れ、画面はそれを
 * `e.message` として無加工で表示していた。呼び出し口 15 本のうち 14 本が
 * この形だったため、**英語表示にしていても申請・承認・招待・退会・容量変更の
 * エラーはすべて日本語で出ていた**（監査 第2回）。しかも
 * 「あなたは現在ただ 1 人のサイト管理者です」のように、**同じ文が
 * l10n にも用意されているのに使われていない**ものが複数あった。
 *
 * ここでは種別を表す短い符号（`code`）を `details` に載せる。
 * 画面はその符号から l10n の文言を引き、知らない符号のときだけ
 * サーバーの文（＝下の既定文）を出す。
 *
 * サーバー側の文は、ログと、まだ翻訳を用意していない符号のための控え。
 */
import { HttpsError, type FunctionsErrorCode } from 'firebase-functions/v2/https';

/**
 * 画面が出し分ける符号。
 *
 * **増やしたら lib/l10n の functionError… も足すこと。**
 * 対応を確かめるテストが functions/test/domain.test.ts にある。
 */
export const ERROR_CODES = [
  'signInRequired',
  'emailNotVerified',
  'siteAdminOnly',
  'listAdminOnly',
  'listNotFound',
  'userNotFound',
  'requestNotFound',
  'requestAlreadyHandled',
  'listNameTaken',
  'listNameMissing',
  'requesterUnknown',
  'invalidTrackCount',
  'invalidUserCount',
  'invalidQuota',
  'lastSiteAdmin',
  'alreadyMember',
  'shareLinkNotFound',
  'shareLinkRevoked',
  'itemNotFound',
  'roleNotAllowed',
  'missingField',
  'fieldTooLong',
] as const;

export type ErrorCode = (typeof ERROR_CODES)[number];

/**
 * 画面が符号を読めなかったときのための、サーバー側の文（日本語）。
 *
 * ここが利用者に出るのは、画面がまだその符号を知らないときだけ。
 */
const FALLBACK: Record<ErrorCode, string> = {
  signInRequired: 'ログインが必要です。',
  emailNotVerified:
    'メールアドレスの確認が済んでいません。確認メールのリンクを開いてください。',
  siteAdminOnly: 'この操作はサイト管理者のみ行えます。',
  listAdminOnly: 'この操作はリスト管理者のみ行えます。',
  listNotFound: 'リストが見つかりません。',
  userNotFound: 'ユーザーが見つかりません。',
  requestNotFound: '申請が見つかりません。',
  requestAlreadyHandled: 'この申請はすでに処理されています。',
  listNameTaken: 'そのリスト名は既に使われているか、申請中です。',
  listNameMissing: 'リスト名がありません。',
  requesterUnknown: '申請者が不明です。',
  invalidTrackCount: '登録曲数を正しく入力してください。',
  invalidUserCount: '使用者数を正しく入力してください。',
  invalidQuota: '上限は 1 バイト以上で指定してください。',
  lastSiteAdmin:
    'あなたは現在ただ 1 人のサイト管理者です。先に別の方をサイト管理者に指名してください。',
  alreadyMember: 'すでにこのリストに参加しています。',
  shareLinkNotFound: 'リンクが見つかりません。',
  shareLinkRevoked: 'このリンクは取り消されています。',
  itemNotFound: '曲が見つかりません。',
  roleNotAllowed: 'その役割は付与できません。',
  missingField: '入力が足りません。',
  fieldTooLong: '入力が長すぎます。',
};

/**
 * 画面が出し分けられるエラーを作る。
 *
 * `details.code` に符号を載せる。`params` は文言の穴埋めに使う値
 * （リスト名など）。画面側で l10n に差し込む。
 */
export function fail(
  status: FunctionsErrorCode,
  code: ErrorCode,
  params?: Record<string, string | number>
): HttpsError {
  return new HttpsError(status, FALLBACK[code], { code, ...(params ?? {}) });
}
