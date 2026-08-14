/// サイト設定の入力欄（仕様書 13.3）
///
/// **「データとしては持っているのに、画面に無い」設定は変えられない。**
/// `orphanFileGraceHours` は、初期値の 24 時間から動かせない状態が
/// 監査 第2回から残っていた（2026-08-15 に入力欄を追加）。
///
/// 受け付ける値の判定は `lib/domain/site_settings.dart` にある**実物**を
/// 呼ぶ。ここに規則を写すと、画面側を壊しても緑のままになる
/// （共有ドキュメント AP-54）。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:music_list_app/domain/site_settings.dart';
import 'package:music_list_app/providers/app_providers.dart';

void main() {
  group('既定値', () {
    test('行き場を失ったファイルの保持時間は 24 時間', () {
      // **サーバー側（functions/src/config.ts）と揃っていること。**
      // ずれていると、画面に出ている値と実際に使われる値が違う。
      expect(const SiteConfig().orphanFileGraceHours, 24);
    });

    test('削除ファイルの保持日数は 30 日', () {
      expect(const SiteConfig().itemPurgeGraceDays, 30);
    });
  });

  group('受け付ける値', () {
    bool valid({int? quotaMb = 1024, int? grace = 30, int? orphanHours = 24}) =>
        isValidSiteSettings(
          quotaMb: quotaMb,
          purgeGraceDays: grace,
          orphanGraceHours: orphanHours,
        );

    test('ふつうの値は通る', () {
      expect(valid(), isTrue);
    });

    test('行き場を失ったファイルの保持時間は 1 時間以上', () {
      // **0 を許すと、アップロードが終わった直後のファイルが、
      // 曲として登録される前に消される経路ができる。**
      expect(valid(orphanHours: 1), isTrue);
      expect(valid(orphanHours: 0), isFalse);
      expect(valid(orphanHours: -1), isFalse);
    });

    test('容量の上限は 1MB 以上', () {
      expect(valid(quotaMb: 0), isFalse);
      expect(valid(quotaMb: -1), isFalse);
    });

    test('削除ファイルの保持日数は 0 日でもよい（すぐ消す運用）', () {
      expect(valid(grace: 0), isTrue);
      expect(valid(grace: -1), isFalse);
    });

    test('数字として読めないものは受け付けない', () {
      // 画面は `int.tryParse` の結果をそのまま渡す（空欄・全角など）。
      expect(valid(quotaMb: null), isFalse);
      expect(valid(grace: null), isFalse);
      expect(valid(orphanHours: null), isFalse);
    });
  });
}
