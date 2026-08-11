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
 * 人ごとの上限の**土台**の既定値（PREMIUM-DESIGN「容量の数字」）。
 *
 * **上限は人ごとの合計。リストごとの上限は判定に使わない。**
 * リストが無制限に作れると、リストごとの上限では 1 人が持てる総量に
 * 上限が無くなり、費用の裏口が開く。
 *
 * `stats.quotaBytes`（リストごと）は表示のために残してあるが、
 * アップロードを止めるかどうかを決めるのはこちらの数字である。
 *
 * **上限は 2 つの値でできている。**
 *
 * | | 置き場所 | 誰が決めるか |
 * | --- | --- | --- |
 * | 土台 | `users/{uid}.storage.quotaBytesBase` | サイト管理者（`setUserQuota`）。既定はこの値 |
 * | 実効値 | `users/{uid}.storage.quotaBytes` | 自動拡張がここを上げる。判定と表示に使う |
 *
 * **2 つに分けた理由。** 期限切れで「2GB へ戻す」と決め打ちにすると、
 * 移行の手当て——既存の利用者で使える量が減る人に、サイト管理から個別に
 * 上限を足す（PREMIUM-DESIGN「既存の利用者への影響」）——が、
 * **次にファイルが増減した瞬間に黙って消える。**
 * 戻す先を土台にすれば、手当ても、意図的に下げた上限も残る。
 */
export const USER_DEFAULT_QUOTA_BYTES = 2147483648; // 2GB

/** 自動拡張の 1 回分（2GB）。プレミアムのみ。 */
const EXPANSION_STEP_BYTES = 2147483648;

/**
 * 自動拡張が届く上限（10GB）。
 *
 * **実効値に対してかける。** 土台が既定（2GB）なら 2→4→6→8→10、
 * 土台が 5GB なら 5→7→9→10 で止まる。**土台そのものは制限しない**
 * ——サイト管理者が 12GB と決めたなら、それがその人の上限である。
 * ここが縛るのは「黙って増える」ぶんだけ。
 */
const MAX_EXPANDED_QUOTA_BYTES = 10737418240;

/**
 * その人のいまの上限（純関数）。
 *
 * **「あるべき実効値」を返すだけ**で、書き込みは呼び出し側
 * （triggers/storage.ts）が行う。変わったときだけ書けば、
 * 無駄な書き込みも通知も出ない。
 *
 * | 相手 | 返す値 |
 * | --- | --- |
 * | プレミアム | 土台から始めて、90% を**超えていれば** 2GB ずつ足す（実効値 10GB まで） |
 * | それ以外 | **土台そのまま**。自動拡張で増えた分だけが返る |
 *
 * **しきい値をここに書かない。** 「90% を超えたら」の判定は
 * [quotaLevel] が持っている。0.9 をもう 1 か所に書くと、片方だけ変わる
 * （監査 S15 で `setListQuota` が実際にそうなっていた）。
 * PREMIUM-DESIGN も「新しい判定を別に作らないこと」と決めている。
 *
 * **戻す先は土台であって、既定の 2GB ではない。** 決め打ちで 2GB へ
 * 戻すと、移行の手当てで足した上限（無償の人に 5GB など）が、
 * 次にファイルが増減した瞬間に黙って消える。逆に、意図的に下げてある
 * 上限を 2GB へ引き上げてしまうこともない。
 *
 * **実効値は土台を下回らない。** 土台を上げたら、その場で効く。
 */
export function resolveUserQuota(params: {
  usedBytes: number;
  /** いまの実効値（前回までに自動拡張した結果）。 */
  quotaBytes: number;
  /** サイト管理者が決めた土台。 */
  quotaBytesBase: number;
  premiumActive: boolean;
}): number {
  const { usedBytes, quotaBytes, quotaBytesBase, premiumActive } = params;

  // **プレミアムでない人は拡張しない。** 期限が切れた人もここを通り、
  // 自動拡張で増えていた分だけが土台へ戻る。既存のファイルは消さない
  // （追加だけできなくなる／D3）。
  if (!premiumActive) return quotaBytesBase;

  let quota = Math.max(quotaBytes, quotaBytesBase);
  while (
    quota < MAX_EXPANDED_QUOTA_BYTES &&
    quotaLevel({ usedBytes, quotaBytes: quota }) === 'warning'
  ) {
    quota = Math.min(quota + EXPANSION_STEP_BYTES, MAX_EXPANDED_QUOTA_BYTES);
  }
  return quota;
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
