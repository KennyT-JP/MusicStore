/// タイムゾーンを持たない日付（仕様書 6.2）
///
/// 項目の「日付」（録音日）は時刻もタイムゾーンも持たない年月日の値として
/// 扱い、`YYYY-MM-DD` 形式の文字列で Firestore に保存する。
/// どの国・どの端末から見ても、登録した人が入力したとおりの日付を表示する。
///
/// 投稿日時・更新日時などシステムが記録する日時はこの型を使わず、
/// 通常のタイムスタンプとして保存して見る人の現地時刻で表示する。
library;

/// 年月日だけを持つ日付。
class LocalDate implements Comparable<LocalDate> {
  const LocalDate(this.year, this.month, this.day);

  /// 端末のローカル日付から作る。項目追加時の初期値に使う（6.2）。
  factory LocalDate.today([DateTime? now]) {
    final n = now ?? DateTime.now();
    return LocalDate(n.year, n.month, n.day);
  }

  /// `YYYY-MM-DD` 形式の文字列から復元する。
  ///
  /// 形式が違う場合や、存在しない日付（2026-02-30 など）は null を返す。
  static LocalDate? tryParse(String? value) {
    if (value == null) return null;
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
    if (match == null) return null;
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    if (month < 1 || month > 12) return null;
    if (day < 1 || day > _daysInMonth(year, month)) return null;
    return LocalDate(year, month, day);
  }

  final int year;
  final int month;
  final int day;

  /// Firestore に保存する `YYYY-MM-DD` 形式。
  String toIso8601Date() =>
      '${year.toString().padLeft(4, '0')}-'
      '${month.toString().padLeft(2, '0')}-'
      '${day.toString().padLeft(2, '0')}';

  /// 日付選択ダイアログとのやり取り用。
  ///
  /// 正午を使うのは、ローカル時刻とのずれで前後の日にまたがるのを避けるため。
  DateTime toDateTimeAtNoon() => DateTime(year, month, day, 12);

  @override
  String toString() => toIso8601Date();

  @override
  int compareTo(LocalDate other) {
    if (year != other.year) return year.compareTo(other.year);
    if (month != other.month) return month.compareTo(other.month);
    return day.compareTo(other.day);
  }

  @override
  bool operator ==(Object other) =>
      other is LocalDate &&
      other.year == year &&
      other.month == month &&
      other.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);

  static int _daysInMonth(int year, int month) {
    const lengths = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
    if (month == 2 && _isLeapYear(year)) return 29;
    return lengths[month - 1];
  }

  static bool _isLeapYear(int year) =>
      (year % 4 == 0 && year % 100 != 0) || year % 400 == 0;
}
