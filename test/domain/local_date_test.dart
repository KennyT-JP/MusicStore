/// タイムゾーンを持たない日付のテスト（仕様書 6.2）
///
/// 「8月4日の録音」が、見る人によって 8月3日 にならないことを保証する。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:music_list_app/domain/local_date.dart';

void main() {
  group('文字列との相互変換', () {
    test('YYYY-MM-DD 形式で保存する', () {
      expect(const LocalDate(2026, 8, 4).toIso8601Date(), '2026-08-04');
      expect(const LocalDate(2026, 12, 31).toIso8601Date(), '2026-12-31');
    });

    test('1 桁の月日はゼロ埋めする', () {
      expect(const LocalDate(2026, 1, 5).toIso8601Date(), '2026-01-05');
    });

    test('保存した文字列から復元できる', () {
      const date = LocalDate(2026, 8, 4);
      expect(LocalDate.tryParse(date.toIso8601Date()), date);
    });
  });

  group('不正な値の扱い', () {
    test('形式が違えば復元しない', () {
      expect(LocalDate.tryParse('2026/08/04'), isNull);
      expect(LocalDate.tryParse('2026-8-4'), isNull);
      expect(LocalDate.tryParse('20260804'), isNull);
      expect(LocalDate.tryParse(''), isNull);
      expect(LocalDate.tryParse(null), isNull);
    });

    test('存在しない日付は復元しない', () {
      expect(LocalDate.tryParse('2026-02-30'), isNull);
      expect(LocalDate.tryParse('2026-13-01'), isNull);
      expect(LocalDate.tryParse('2026-00-01'), isNull);
      expect(LocalDate.tryParse('2026-04-31'), isNull);
    });

    test('うるう年を正しく扱う', () {
      expect(LocalDate.tryParse('2024-02-29'), const LocalDate(2024, 2, 29));
      expect(LocalDate.tryParse('2026-02-29'), isNull);
      expect(LocalDate.tryParse('2000-02-29'), const LocalDate(2000, 2, 29));
      expect(LocalDate.tryParse('1900-02-29'), isNull);
    });
  });

  group('タイムゾーンの影響を受けない（6.2）', () {
    test('文字列は時差で変化しない', () {
      // タイムスタンプではなく年月日だけを保存するため、
      // どこで表示しても同じ日付になる。
      const date = LocalDate(2026, 8, 4);
      expect(date.toIso8601Date(), '2026-08-04');

      // 正午を使うのは、日付選択ダイアログとのやり取りで
      // 前後の日にまたがるのを避けるため。
      final asDateTime = date.toDateTimeAtNoon();
      expect(asDateTime.year, 2026);
      expect(asDateTime.month, 8);
      expect(asDateTime.day, 4);
      expect(asDateTime.hour, 12);
    });

    test('端末のローカル日付から初期値を作る', () {
      // 項目追加時の初期値は「入力する人の端末のローカル日付」（6.2）。
      final today = LocalDate.today(DateTime(2026, 8, 4, 23, 30));
      expect(today, const LocalDate(2026, 8, 4));
    });
  });

  group('比較', () {
    test('日付順に並べられる', () {
      final dates = [
        const LocalDate(2026, 8, 20),
        const LocalDate(2026, 7, 15),
        const LocalDate(2025, 12, 31),
        const LocalDate(2026, 8, 1),
      ]..sort();
      expect(dates.map((d) => d.toIso8601Date()), [
        '2025-12-31',
        '2026-07-15',
        '2026-08-01',
        '2026-08-20',
      ]);
    });

    test('同じ日付は等しい', () {
      expect(const LocalDate(2026, 8, 4), const LocalDate(2026, 8, 4));
      expect(
        const LocalDate(2026, 8, 4).hashCode,
        const LocalDate(2026, 8, 4).hashCode,
      );
    });
  });
}
