/**
 * 共通の設定と定数（仕様書 13.3 / 13.4）
 */
import { getFirestore } from 'firebase-admin/firestore';
import { defineString } from 'firebase-functions/params';

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
 *
 * **`process.env` ではなく `defineString`（パラメータ）を使っている。**
 * Firebase CLI は、どの関数をどこに配置するかを決める「解析」の段階では、
 * 子プロセスに `HOME` / `PATH` などごく一部の環境変数しか渡さない。
 * `.env` の中身が渡るのはその後なので、`process.env.FUNCTIONS_REGION` は
 * 解析時には常に undefined になり、指定しても効かなかった。
 * パラメータは解析時には未解決の式として扱われ、配置を決める直前に
 * `.env` の値で解決されるため、こちらなら効く。
 */
export const REGION = defineString('FUNCTIONS_REGION', {
  default: 'asia-northeast1',
});

/**
 * Storage のトリガーを動かすリージョン。
 *
 * **バケットと同じリージョンでなければデプロイできない。** 違うと
 * 「A function in region X cannot listen to a bucket in region Y」で失敗する。
 *
 * Cloud Storage のバケットは作成後にリージョンを変更できないため、
 * ここだけ別に指定できるようにしてある。既定は [REGION] と同じ。
 */
export const STORAGE_REGION = defineString('STORAGE_REGION', {
  default: REGION,
});

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
  /**
   * 共有リンク（仕様書 3.3）。
   *
   * 以前の `invites/` は「一度きり・24 時間」のものだった。
   * 無期限・何度でも・複数人に変えたので、意味が変わったことが
   * 分かるように名前も変えている。
   */
  shareLink: (linkId: string) => `shareLinks/${linkId}`,

  /**
   * 参加せずに見るだけの人（仕様書 3.3）。
   *
   * **メンバーとは別に持つ。** メンバー一覧にも人数にも通知の宛先にも
   * 入れないため。ここに居る人は、そのリストを読むことだけができる。
   */
  listViewers: (listId: string) => `lists/${listId}/viewers`,
  listViewer: (listId: string, uid: string) =>
    `lists/${listId}/viewers/${uid}`,
  siteConfig: 'siteConfig/global',

  /// **サーバーだけが読み書きする値の置き場（監査 第2回）。**
  /// siteConfig/global は利用者も読めるため、通知の宛先の一覧や
  /// 走査の途中位置といった内部の値を混ぜない。
  siteInternal: 'siteConfig/internal',
} as const;

/** サイト設定の既定値（仕様書 13.3）。 */
export interface SiteConfig {
  defaultQuotaBytes: number;
  itemPurgeGraceDays: number;
  orphanFileGraceHours: number;
  siteAdminCount: number;
}

// export は付けない。使うのは下の readSiteConfig だけで、
// どこからも import されない export は死蔵の見張りが弾く（監査 第4回）。
const defaultSiteConfig: SiteConfig = {
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

