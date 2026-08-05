/**
 * 共通の設定と定数（仕様書 13.3 / 13.4）
 */
import { getFirestore } from 'firebase-admin/firestore';

export { parseItemStoragePath } from './domain/paths';

/**
 * Cloud Functions を動かすリージョン。
 *
 * 主な利用者が日本にいる想定で東京を既定にしている。
 * **Firestore のロケーションと揃えるのが望ましい**（別リージョンだと
 * トリガーのたびにリージョン間の通信が発生し、遅延と費用が増える）。
 *
 * プロジェクトを別のロケーションで作ってしまった場合は、コードを直さずに
 * `functions/.env.<プロジェクト ID>` で上書きできる。本番と検証でロケーションが
 * 違っても、同じコードをそのまま配信できるようにするため。
 *
 * ```
 * FUNCTIONS_REGION=us-east1
 * ```
 */
export const REGION = process.env.FUNCTIONS_REGION ?? 'asia-northeast1';

/**
 * Storage のトリガーを動かすリージョン。
 *
 * **バケットと同じリージョンでなければデプロイできない。** 違うと
 * 「A function in region X cannot listen to a bucket in region Y」で失敗する。
 *
 * Cloud Storage のバケットは作成後にリージョンを変更できないため、
 * ここだけ別に指定できるようにしてある。既定は [REGION] と同じ。
 */
export const STORAGE_REGION = process.env.STORAGE_REGION ?? REGION;

/** Firestore のパス（Flutter 側 lib/data/firestore_paths.dart と対応）。 */
export const paths = {
  users: 'users',
  user: (uid: string) => `users/${uid}`,
  userNotifications: (uid: string) => `users/${uid}/notifications`,

  lists: 'lists',
  list: (listId: string) => `lists/${listId}`,
  listStats: (listId: string) => `lists/${listId}/meta/stats`,
  listMembers: (listId: string) => `lists/${listId}/members`,
  listMember: (listId: string, uid: string) => `lists/${listId}/members/${uid}`,
  listJoinRequest: (listId: string, uid: string) =>
    `lists/${listId}/joinRequests/${uid}`,
  listItems: (listId: string) => `lists/${listId}/items`,
  listItem: (listId: string, itemId: string) =>
    `lists/${listId}/items/${itemId}`,

  listName: (nameLower: string) => `listNames/${nameLower}`,
  listRequest: (requestId: string) => `listRequests/${requestId}`,
  invite: (inviteId: string) => `invites/${inviteId}`,
  siteConfig: 'siteConfig/global',
} as const;

/** サイト設定の既定値（仕様書 13.3）。 */
export interface SiteConfig {
  inviteExpiryHours: number;
  defaultQuotaBytes: number;
  itemPurgeGraceDays: number;
  orphanFileGraceHours: number;
  siteAdminCount: number;
}

export const defaultSiteConfig: SiteConfig = {
  inviteExpiryHours: 24,
  defaultQuotaBytes: 1073741824, // 1GB
  itemPurgeGraceDays: 30,
  orphanFileGraceHours: 24,
  siteAdminCount: 0,
};

/**
 * サイト設定を読む。未作成なら既定値を返す。
 *
 * 設定がないだけで処理全体が止まらないようにする。
 */
export async function readSiteConfig(): Promise<SiteConfig> {
  const snapshot = await getFirestore().doc(paths.siteConfig).get();
  const data = snapshot.data() ?? {};
  return {
    inviteExpiryHours:
      asNumber(data.inviteExpiryHours) ?? defaultSiteConfig.inviteExpiryHours,
    defaultQuotaBytes:
      asNumber(data.defaultQuotaBytes) ?? defaultSiteConfig.defaultQuotaBytes,
    itemPurgeGraceDays:
      asNumber(data.itemPurgeGraceDays) ?? defaultSiteConfig.itemPurgeGraceDays,
    orphanFileGraceHours:
      asNumber(data.orphanFileGraceHours) ??
      defaultSiteConfig.orphanFileGraceHours,
    siteAdminCount:
      asNumber(data.siteAdminCount) ?? defaultSiteConfig.siteAdminCount,
  };
}

function asNumber(value: unknown): number | undefined {
  return typeof value === 'number' && Number.isFinite(value)
    ? value
    : undefined;
}

