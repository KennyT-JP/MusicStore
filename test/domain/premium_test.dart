/// プレミアム判定のテスト（docs/PREMIUM-DESIGN.md 3.1）
///
/// `lib/domain/premium.dart` のコメントで「サーバーの `until > now` と
/// 同じ向きにそろえる」と警告されている境界を固定する。サーバー側の同種
/// テスト（`functions/test/premium.test.ts` の `isPremiumActive`、
/// `functions/test/coupon_code_validation.test.ts` が参照する
/// `functions/src/domain/coupon.ts` の `normalizeCouponCode`）と同じ
/// 境界・同じ入力で確認し、クライアントとサーバーがずれていないことを見る。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:music_list_app/domain/premium.dart';

void main() {
  group('プレミアムの期限判定（isActive・3.1）', () {
    // TS 側（functions/test/premium.test.ts）と同じ固定時刻。
    // 2026-08-11 12:00:00。
    final now = DateTime.utc(2026, 8, 11, 12, 0, 0);

    test('期限ちょうどは、もう有効ではない', () {
      // サーバーの isPremiumActive(NOW, NOW) === false と同じ境界。
      expect(PremiumPolicy.isActive(now, now: now), isFalse);
    });

    test('1 ミリ秒でも先（まだ来ていない）なら有効', () {
      final until = now.add(const Duration(milliseconds: 1));
      expect(PremiumPolicy.isActive(until, now: now), isTrue);
    });

    test('1 ミリ秒でも過ぎていたら無効', () {
      final until = now.subtract(const Duration(milliseconds: 1));
      expect(PremiumPolicy.isActive(until, now: now), isFalse);
    });

    test('1 秒前・1 秒後', () {
      expect(
        PremiumPolicy.isActive(
          now.subtract(const Duration(seconds: 1)),
          now: now,
        ),
        isFalse,
      );
      expect(
        PremiumPolicy.isActive(
          now.add(const Duration(seconds: 1)),
          now: now,
        ),
        isTrue,
      );
    });

    test('until が null（premium を持たない）なら常に無効（7 節）', () {
      // users/{uid}.premium が無い人は「プレミアムでない」と読む。
      expect(PremiumPolicy.isActive(null, now: now), isFalse);
    });

    test('now を省略すると DateTime.now() が使われる', () {
      // 呼び出し側の既定値経路も確認する（明示的な now は上のテストで固定済み）。
      final farFuture = DateTime.now().add(const Duration(days: 365));
      final farPast = DateTime.now().subtract(const Duration(days: 365));
      expect(PremiumPolicy.isActive(farFuture), isTrue);
      expect(PremiumPolicy.isActive(farPast), isFalse);
    });
  });

  group('クーポンコードの正規化（normalizeCouponCode・D8）', () {
    test('前後の空白は落ちる', () {
      expect(PremiumPolicy.normalizeCouponCode('  ABCD1234  '), 'ABCD1234');
    });

    test('貼り付けで紛れ込む改行・タブも落ちる', () {
      expect(PremiumPolicy.normalizeCouponCode('ABCD\n1234'), 'ABCD1234');
      expect(PremiumPolicy.normalizeCouponCode('ABCD\t1234'), 'ABCD1234');
      expect(PremiumPolicy.normalizeCouponCode('\r\nABCD1234\r\n'), 'ABCD1234');
    });

    test('前後・内部が混ざっていても空白はすべて落ちる', () {
      // 実装は `RegExp(r'\s')` で全空白文字を対象にしており、前後だけでなく
      // コード内部の空白も落ちる（TS の `trim()` は前後だけを落とし、
      // 内部の空白は残す点で異なる。詳細は本ファイル末尾の報告コメント参照）。
      expect(PremiumPolicy.normalizeCouponCode('  abcd - 1 \t\n '), 'abcd-1');
    });

    test('大文字小文字はここでは変えない（サーバー側と役割分担）', () {
      // コメント: 「大文字小文字はここで変えない。照合はサーバーが codeHash
      // で行い、その手前で大文字に揃えている」。
      // TS の normalizeCouponCode は trim().toUpperCase() で大文字化するが、
      // Dart 側は意図的に大文字化しない（コメントに理由あり）。
      expect(PremiumPolicy.normalizeCouponCode('spring2026'), 'spring2026');
      expect(PremiumPolicy.normalizeCouponCode('  abcd-1  '), 'abcd-1');
    });

    test('TS 側と同じ入力（trim+大文字化前）を通しても、大文字化はしない', () {
      // functions/test/coupon_code_validation.test.ts が使う
      // normalizeCouponCode('  abcd-1  ') は TS では 'ABCD-1' になるが、
      // Dart 側は大文字化を担わないため 'abcd-1' のままになる。
      expect(PremiumPolicy.normalizeCouponCode('  abcd-1  '), 'abcd-1');
    });

    test('空白を含まない入力はそのまま', () {
      expect(PremiumPolicy.normalizeCouponCode('ABCD1234'), 'ABCD1234');
    });

    test('空白だけの入力は空文字列になる', () {
      expect(PremiumPolicy.normalizeCouponCode('   \t\n  '), '');
    });
  });
}
