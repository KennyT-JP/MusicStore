/// 画面に出す日時の整形（仕様書 6.2）
///
/// **1 か所にまとめてある。** 以前は同じ関数が 2 つの画面に写しで置かれ、
/// さらに項目詳細だけがゼロ埋めのない別の書き方をしていた。
/// 同じアプリの中で `2026/08/06 10:30` と `2026-8-6` が混ざっていた
/// （監査 第2回）。
library;

/// システム日時を、見る人の現地時刻で表示する（仕様書 6.2）。
///
/// 日付そのもの（曲の日付）は `LocalDate` を使う。あちらはタイムゾーンを
/// 持たない「その日」なので、現地時刻へ変換してはいけない。
String formatDateTime(DateTime value) {
  final local = value.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${local.year}/${two(local.month)}/${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}
