/// 容量上限の判定のテスト（仕様書 7.2 / 7.3 / 7.5）
///
/// 12.6 で自動テスト必須にした領域。80%／90% の通知境界と、
/// 上限超過時のアップロードブロックを検証する。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:music_list_app/domain/quota.dart';

void main() {
  // 読みやすさのため、上限 1000 バイトの小さなリストで検証する。
  QuotaStatus status(int used, {int quota = 1000}) =>
      QuotaStatus(usedBytes: used, quotaBytes: quota);

  group('通知レベルの境界（7.3）', () {
    test('80% ちょうどはまだ Notice ではない', () {
      // 仕様は「80% を超えたら」なので、ちょうどは含まない。
      expect(status(800).level, QuotaLevel.normal);
    });

    test('80% を超えたら Notice', () {
      expect(status(801).level, QuotaLevel.notice);
      expect(status(899).level, QuotaLevel.notice);
    });

    test('90% ちょうどはまだ警告ではない', () {
      expect(status(900).level, QuotaLevel.notice);
    });

    test('90% を超えたら警告', () {
      expect(status(901).level, QuotaLevel.warning);
      expect(status(1000).level, QuotaLevel.warning);
    });

    test('上限が 0 のリストは満杯として扱う', () {
      // 上限 0 のリストにアップロードを通してしまわないための保守的な既定値。
      expect(status(0, quota: 0).ratio, 1.0);
      expect(status(0, quota: 0).isOverQuota, isTrue);
    });
  });

  group('アップロードの可否（7.3 / 7.5）', () {
    test('余裕があればアップロードできる', () {
      final decision = QuotaPolicy.canStartUpload(
        status: status(500),
        fileSizeBytes: 100,
      );
      expect(decision.allowed, isTrue);
    });

    test('ちょうど上限に収まる場合はアップロードできる', () {
      final decision = QuotaPolicy.canStartUpload(
        status: status(900),
        fileSizeBytes: 100,
      );
      expect(decision.allowed, isTrue);
    });

    test('1 バイトでも超えるならブロックする', () {
      final decision = QuotaPolicy.canStartUpload(
        status: status(900),
        fileSizeBytes: 101,
      );
      expect(decision.allowed, isFalse);
      expect(decision.reason, UploadBlockReason.wouldExceedQuota);
    });

    test('すでに上限に達していればブロックする', () {
      final decision = QuotaPolicy.canStartUpload(
        status: status(1000),
        fileSizeBytes: 1,
      );
      expect(decision.allowed, isFalse);
      expect(decision.reason, UploadBlockReason.alreadyOverQuota);
    });

    test('上限を超過した状態でもブロックする', () {
      // 同時アップロードで開始時のチェックをすり抜けた場合（7.5）。
      final decision = QuotaPolicy.canStartUpload(
        status: status(1200),
        fileSizeBytes: 1,
      );
      expect(decision.allowed, isFalse);
      expect(decision.reason, UploadBlockReason.alreadyOverQuota);
    });

    test('サイズ 0 以下は不正として弾く', () {
      expect(
        QuotaPolicy.canStartUpload(status: status(0), fileSizeBytes: 0).reason,
        UploadBlockReason.invalidSize,
      );
    });
  });

  // 通知の重複防止・送信済みフラグのリセットのテストはここに無い。
  // 判定はサーバー側 functions/src/domain/quota.ts が正で、
  // クライアントには置かないため（監査 第4回）。

  group('残り容量', () {
    test('残りを計算できる', () {
      expect(status(300).remainingBytes, 700);
    });

    test('超過していても負にはならない', () {
      expect(status(1200).remainingBytes, 0);
    });
  });

  test('容量上限の初期値は 1GB（7.2）', () {
    expect(kDefaultQuotaBytes, 1024 * 1024 * 1024);
  });
}
