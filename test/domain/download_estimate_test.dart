/// 一括ダウンロードの見積もり（docs/DOWNLOAD-DESIGN.md 6.3・論点 20）
///
/// **上限を置かない代わりが、見積もり・進捗・中断の 3 つ。**
/// ここで守るのは見積もり——「残り N 曲・約 X GB」の N と X。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:music_list_app/domain/download_estimate.dart';

const _mb = 1024 * 1024;

BulkDownloadCandidate _audio(String id, int sizeBytes) => BulkDownloadCandidate(
  itemId: id,
  contentType: 'audio/wav',
  fileName: '$id.wav',
  sizeBytes: sizeBytes,
);

void main() {
  group('見積もり（6.3）', () {
    test('すでに落としてあるぶんは、数にもサイズにも入れない', () {
      // 「**12 曲中 8 曲は保存済み。残り 4 曲・約 160 MB**」の形。
      final candidates = [
        for (var i = 1; i <= 12; i++) _audio('item-$i', 40 * _mb),
      ];
      final downloaded = {for (var i = 1; i <= 8; i++) 'item-$i'};

      final estimate = BulkDownloadPolicy.estimate(
        candidates: candidates,
        downloadedItemIds: downloaded,
      );

      expect(estimate.targetCount, 12);
      expect(estimate.alreadyDownloadedCount, 8);
      expect(estimate.remainingCount, 4);
      expect(estimate.remainingBytes, 160 * _mb);
      expect(estimate.isEmpty, isFalse);
    });

    test('曲数と合計サイズの両方を出す（論点 20）', () {
      // **大きさを知らせずに 500 MB を落とし始めるのは、端末の容量にも
      // 通信量にも失礼。** どちらか片方だけでは足りない。
      final estimate = BulkDownloadPolicy.estimate(
        candidates: [_audio('a', 100 * _mb), _audio('b', 400 * _mb)],
        downloadedItemIds: const {},
      );

      expect(estimate.remainingCount, 2);
      expect(estimate.remainingBytes, 500 * _mb);
    });

    test('全部落としてあれば、残りは 0 曲・0 バイト', () {
      final estimate = BulkDownloadPolicy.estimate(
        candidates: [_audio('a', 10), _audio('b', 20)],
        downloadedItemIds: const {'a', 'b'},
      );

      expect(estimate.targetCount, 2);
      expect(estimate.alreadyDownloadedCount, 2);
      expect(estimate.remainingCount, 0);
      expect(estimate.remainingBytes, 0);
      expect(estimate.isEmpty, isTrue);
    });

    test('空のリストは 0 曲', () {
      final estimate = BulkDownloadPolicy.estimate(
        candidates: const [],
        downloadedItemIds: const {},
      );

      expect(estimate.targetCount, 0);
      expect(estimate.remainingCount, 0);
      expect(estimate.remainingBytes, 0);
      expect(estimate.isEmpty, isTrue);
    });

    test('対象外のファイルは「12 曲中」にも入れない（3.3・論点 5）', () {
      // PDF・zip は対象外（論点 5）。白リストに無い拡張子も対象外（3.3）。
      // **数に入れると、落とせないものを「残り」に数えて、
      // いつまでも終わらない見積もりになる。**
      final estimate = BulkDownloadPolicy.estimate(
        candidates: [
          _audio('song', 30 * _mb),
          const BulkDownloadCandidate(
            itemId: 'score',
            contentType: 'application/pdf',
            fileName: 'score.pdf',
            sizeBytes: 5 * _mb,
          ),
          const BulkDownloadCandidate(
            itemId: 'aiff',
            contentType: 'audio/x-aiff',
            fileName: 'take.aiff',
            sizeBytes: 90 * _mb,
          ),
        ],
        downloadedItemIds: const {},
      );

      expect(estimate.targetCount, 1);
      expect(estimate.remainingCount, 1);
      expect(estimate.remainingBytes, 30 * _mb);
    });

    test('画像も対象に数える（論点 5）', () {
      final estimate = BulkDownloadPolicy.estimate(
        candidates: [
          _audio('song', 30 * _mb),
          const BulkDownloadCandidate(
            itemId: 'cover',
            contentType: 'image/jpeg',
            fileName: 'cover.jpg',
            sizeBytes: 2 * _mb,
          ),
        ],
        downloadedItemIds: const {},
      );

      expect(estimate.targetCount, 2);
      expect(estimate.remainingBytes, 32 * _mb);
    });

    test('目録に別のリストの曲が入っていても、数え方は変わらない', () {
      // downloadedItemIds は端末が持っている全曲。候補に無い ID が
      // 混じっていても、このリストの見積もりには影響しない。
      final estimate = BulkDownloadPolicy.estimate(
        candidates: [_audio('a', 10), _audio('b', 20)],
        downloadedItemIds: const {'a', 'other-list-item'},
      );

      expect(estimate.targetCount, 2);
      expect(estimate.alreadyDownloadedCount, 1);
      expect(estimate.remainingCount, 1);
      expect(estimate.remainingBytes, 20);
    });
  });
}
