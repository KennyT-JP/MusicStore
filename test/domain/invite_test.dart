/// 招待 URL の検証のテスト（仕様書 3.3）
///
/// 12.6 で自動テスト必須にした領域。ワンタイム性と有効期限を検証する。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:music_list_app/domain/invite.dart';

void main() {
  final now = DateTime.utc(2026, 8, 4, 12, 0);

  InviteSnapshot invite({
    InviteStatus status = InviteStatus.active,
    Duration expiresIn = const Duration(hours: 1),
  }) => InviteSnapshot(
    listId: 'list-1',
    status: status,
    expiresAt: now.add(expiresIn),
  );

  group('有効な招待', () {
    test('期限内・未使用・未参加なら受諾できる', () {
      final result = InvitePolicy.validate(
        invite: invite(),
        now: now,
        alreadyMember: false,
      );
      expect(result.accepted, isTrue);
      expect(result.rejection, isNull);
    });
  });

  group('有効期限（3.3）', () {
    test('期限を過ぎていたら受諾できない', () {
      final result = InvitePolicy.validate(
        invite: invite(expiresIn: const Duration(minutes: -1)),
        now: now,
        alreadyMember: false,
      );
      expect(result.accepted, isFalse);
      expect(result.rejection, InviteRejection.expired);
    });

    test('期限ちょうどは受諾できない', () {
      final result = InvitePolicy.validate(
        invite: invite(expiresIn: Duration.zero),
        now: now,
        alreadyMember: false,
      );
      expect(result.rejection, InviteRejection.expired);
    });

    test('判定は受諾時点で行う', () {
      // URL を開いた時点では期限内でも、サインアップとメール確認に
      // 手間取って期限を過ぎたら受諾できない（3.3）。
      final target = invite(expiresIn: const Duration(minutes: 10));

      expect(
        InvitePolicy.validate(
          invite: target,
          now: now,
          alreadyMember: false,
        ).accepted,
        isTrue,
      );

      final afterSignUp = now.add(const Duration(minutes: 15));
      expect(
        InvitePolicy.validate(
          invite: target,
          now: afterSignUp,
          alreadyMember: false,
        ).rejection,
        InviteRejection.expired,
      );
    });

    test('発行時の有効期限はサイト設定の時間数で決まる', () {
      // 初期値は 24 時間（3.3）。
      expect(
        InvitePolicy.expiresAtFrom(now, 24),
        now.add(const Duration(hours: 24)),
      );
      expect(
        InvitePolicy.expiresAtFrom(now, 72),
        now.add(const Duration(hours: 72)),
      );
    });
  });

  group('ワンタイム性（3.3）', () {
    test('使用済みの招待は受諾できない', () {
      final result = InvitePolicy.validate(
        invite: invite(status: InviteStatus.used),
        now: now,
        alreadyMember: false,
      );
      expect(result.rejection, InviteRejection.alreadyUsed);
    });

    test('取り消された招待は受諾できない', () {
      final result = InvitePolicy.validate(
        invite: invite(status: InviteStatus.revoked),
        now: now,
        alreadyMember: false,
      );
      expect(result.rejection, InviteRejection.revoked);
    });

    test('使用済みかどうかを期限より先に判定する', () {
      // 使用済みかつ期限切れの場合、「すでに使用されています」を優先する。
      // 何が起きたのかが分かりやすいため。
      final result = InvitePolicy.validate(
        invite: invite(
          status: InviteStatus.used,
          expiresIn: const Duration(hours: -1),
        ),
        now: now,
        alreadyMember: false,
      );
      expect(result.rejection, InviteRejection.alreadyUsed);
    });
  });

  group('その他の拒否理由', () {
    test('招待が存在しなければ受諾できない', () {
      final result = InvitePolicy.validate(
        invite: null,
        now: now,
        alreadyMember: false,
      );
      expect(result.rejection, InviteRejection.notFound);
    });

    test('すでにメンバーなら受諾しない', () {
      final result = InvitePolicy.validate(
        invite: invite(),
        now: now,
        alreadyMember: true,
      );
      expect(result.rejection, InviteRejection.alreadyMember);
    });
  });

  group('状態の復元', () {
    test('既知の値を復元できる', () {
      expect(InviteStatus.tryParse('active'), InviteStatus.active);
      expect(InviteStatus.tryParse('used'), InviteStatus.used);
      expect(InviteStatus.tryParse('revoked'), InviteStatus.revoked);
    });

    test('未知の値は復元しない', () {
      expect(InviteStatus.tryParse('expired'), isNull);
      expect(InviteStatus.tryParse(null), isNull);
    });
  });
}
