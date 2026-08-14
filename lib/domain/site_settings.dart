/// サイト設定として受け付けてよい値か（仕様書 13.3）
///
/// **画面の中に判定を書かない。** 書くと、テストが同じ規則を写すことに
/// なり、**本番を壊しても緑のまま**になる（共有ドキュメント AP-54）。
/// ここに置いて、画面もテストも同じものを呼ぶ。
library;

/// サイト設定の入力が受け付けられるか。
///
/// 数字として読めなかったもの（null）は受け付けない。
bool isValidSiteSettings({
  required int? quotaMb,
  required int? purgeGraceDays,
  required int? orphanGraceHours,
}) {
  if (quotaMb == null || quotaMb <= 0) return false;

  // 0 日は「復元できないが、すぐ容量が空く」運用として許す。
  if (purgeGraceDays == null || purgeGraceDays < 0) return false;

  // **1 時間を下回らせない。** 0 にすると、アップロードが終わった直後の
  // ファイルが、曲として登録される前に消される経路ができる
  // （掃除は「項目から参照されていない古いファイル」を消すため）。
  if (orphanGraceHours == null || orphanGraceHours < 1) return false;

  return true;
}
