/**
 * 容量の判定（仕様書 7.2 / 7.3）
 *
 * **Flutter 側の lib/domain/quota.dart と同じ規則**。
 * 使用量の集計と通知の送信はサーバー側でしか行わないため、
 * しきい値の判定はここが正となる。
 * 片方を変えたらもう片方も直すこと。
 */

/** Notice を出すしきい値（仕様書 7.3）。 */
export const NOTICE_THRESHOLD = 0.8;

/** 警告を出すしきい値（仕様書 7.3）。 */
export const WARNING_THRESHOLD = 0.9;

export type QuotaLevel = 'normal' | 'notice' | 'warning';

export interface QuotaStatus {
  usedBytes: number;
  quotaBytes: number;
}

/**
 * 使用率。上限が 0 以下なら 1.0（満杯扱い）。
 *
 * 上限 0 のリストにアップロードを通してしまわないための保守的な既定値。
 */
export function ratio(status: QuotaStatus): number {
  if (status.quotaBytes <= 0) return 1;
  return status.usedBytes / status.quotaBytes;
}

/**
 * 通知レベル（仕様書 7.3）。
 *
 * 「80% を超えたら」「90% を超えたら」なので、ちょうどの値は含まない。
 */
export function quotaLevel(status: QuotaStatus): QuotaLevel {
  const r = ratio(status);
  if (r > WARNING_THRESHOLD) return 'warning';
  if (r > NOTICE_THRESHOLD) return 'notice';
  return 'normal';
}

/**
 * 加算後に新たに送るべき通知レベル。
 *
 * すでに同じレベルを送っていれば null を返し、重複通知を防ぐ。
 */
export function levelToNotify(
  after: QuotaStatus,
  noticeAlreadySent: boolean,
  warningAlreadySent: boolean
): QuotaLevel | null {
  switch (quotaLevel(after)) {
    case 'warning':
      return warningAlreadySent ? null : 'warning';
    case 'notice':
      return noticeAlreadySent ? null : 'notice';
    case 'normal':
      return null;
  }
}

/** Notice の送信済みフラグを戻すべきか（仕様書 7.3）。 */
export function shouldResetNotice(
  after: QuotaStatus,
  noticeAlreadySent: boolean
): boolean {
  return noticeAlreadySent && ratio(after) <= NOTICE_THRESHOLD;
}

/** 警告の送信済みフラグを戻すべきか（仕様書 7.3）。 */
export function shouldResetWarning(
  after: QuotaStatus,
  warningAlreadySent: boolean
): boolean {
  return warningAlreadySent && ratio(after) <= WARNING_THRESHOLD;
}
