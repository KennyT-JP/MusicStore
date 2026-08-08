/**
 * Cloud Functions のエントリポイント（仕様書 13.4）
 *
 * | 契機 | 関数 |
 * | --- | --- |
 * | Storage へのファイル保存 | onFileUploaded |
 * | Storage からのファイル削除 | onFileDeleted |
 * | 項目の作成 | onItemCreated |
 * | コメントの作成 | onCommentCreated |
 * | メンバーの追加・削除 | onMemberWritten |
 * | リストの削除 | onListDeleted |
 * | リスト作成の申請・承認・却下 | submitListRequest / approveListRequest / rejectListRequest |
 * | 参加申請の提出・承認・却下 | submitJoinRequest / approveJoinRequest / rejectJoinRequest |
 * | 共有リンクの発行・受け入れ・取消 | createShareLink / acceptShareLink / revokeShareLink |
 * | サイト管理者の昇格・降格 | grantSiteAdmin / revokeSiteAdmin |
 * | ユーザー一覧・容量上限・管理者の指名 | listSiteUsers / setListQuota / assignListAdmin |
 * | 退会 | withdrawAccount |
 * | 定期実行（1 日 1 回） | purgeDeletedFiles |
 *
 * **users ドキュメントの初期化はここに含めていない。**
 * firebase-functions v2 には Auth のユーザー作成トリガーがなく、
 * blocking function は Identity Platform の有効化が要る。
 * 初期化はクライアント側（lib/data/repositories/auth_repository.dart）で
 * 行っており、既にあれば何もしないため二重に作られることはない。
 */
import { initializeApp } from 'firebase-admin/app';

initializeApp();

// --- Firestore / Storage のトリガー ---
export { onFileUploaded, onFileDeleted } from './triggers/storage';
export {
  onItemCreated,
  onItemWritten,
  onCommentCreated,
  onMemberWritten,
  onListDeleted,
} from './triggers/content';

// --- 呼び出し可能な関数 ---
export {
  submitListRequest,
  approveListRequest,
  rejectListRequest,
} from './callable/list_requests';
export {
  submitJoinRequest,
  approveJoinRequest,
  rejectJoinRequest,
  createShareLink,
  acceptShareLink,
  revokeShareLink,
} from './callable/membership';
export {
  grantSiteAdmin,
  revokeSiteAdmin,
  withdrawAccount,
} from './callable/site_admin';
export {
  listSiteUsers,
  setListQuota,
  assignListAdmin,
} from './callable/site_management';
export {
  createSiteUser,
  disableSiteUser,
  enableSiteUser,
  deleteSiteUser,
} from './callable/user_admin';

// --- 定期実行 ---
export { purgeDeletedFiles } from './scheduled/purge';
