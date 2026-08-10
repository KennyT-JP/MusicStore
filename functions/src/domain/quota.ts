/**
 * 容量の判定（仕様書 7.2 / 7.3）
 *
 * **Flutter 側の lib/domain/quota.dart と同じ規則**。
 * 使用量の集計と通知の送信はサーバー側でしか行わないため、
 * しきい値の判定はここが正となる。
 * 片方を変えたらもう片方も直すこと。
 */

// しきい値に export は付けない。使うのはこのファイルの判定関数だけで、
// どこからも import されない export は死蔵の見張りが弾く（監査 第4回）。
// 外から要るのは「どのレベルか」の答え（quotaLevel など）であって、数字ではない。

/** Notice を出すしきい値（仕様書 7.3）。 */
const NOTICE_THRESHOLD = 0.8;

/** 警告を出すしきい値（仕様書 7.3）。 */
const WARNING_THRESHOLD = 0.9;

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

/**
 * アップロード済みのファイルを取り消すべきか（仕様書 7.5 / 監査 S5）。
 *
 * 仕様 7.5 は「同時アップロードなどで開始時のチェックをすり抜けて上限を
 * 超えた場合も、**アップロード済みのファイルは削除せず受け入れ**、
 * 以後のアップロードをブロックする」と定めている。
 * 一方、監査 S5 は「上限のサーバー側強制が無い」ことを重大としている。
 *
 * **両立させるには「すり抜け」と「無視」を区別する。**
 *
 * - このファイルを足して初めて上限を超えた（＝すり抜け）
 *   → **残す。** 利用者の正当なアップロードを消さない。以後はブロックされる。
 * - 足す前からすでに上限を超えていた（＝ブロックされているはずなのに来た）
 *   → **取り消す。** 画面を経由しない呼び出しで上限を無視できてしまうため。
 *
 * 以前は前者も削除しており、仕様と逆だった。さらに、クライアントは
 * 「アップロード完了 → 項目作成」の順で動くため、削除と項目作成が競合し、
 * **ファイルの無い項目**が一覧に残りえた（監査 第2回）。
 */
export function shouldRejectUpload(params: {
  /** このファイルを足したあとの使用量。 */
  usedBytesAfter: number;
  /** このファイルの大きさ。 */
  sizeBytes: number;
  quotaBytes: number;
}): boolean {
  const { usedBytesAfter, sizeBytes, quotaBytes } = params;
  if (quotaBytes <= 0) return true; // 上限 0 は満杯扱い（ratio と同じ考え方）
  const before = usedBytesAfter - sizeBytes;
  return before >= quotaBytes;
}
