/// 連番の採番のテスト（仕様書 6.2）
///
/// 12.6 で自動テスト必須にした領域。
/// 「振り直しなし・欠番を残す」という仕様が崩れると復旧できない。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:music_list_app/domain/sequence.dart';

void main() {
  group('採番（6.2）', () {
    test('リスト作成直後は 1 から始まる', () {
      const counter = SequenceCounter.initial();
      expect(counter.nextSeq, 1);
      expect(counter.allocate().seq, 1);
    });

    test('採番するとカウンタが 1 進む', () {
      const counter = SequenceCounter.initial();
      final first = counter.allocate();
      expect(first.seq, 1);
      expect(first.updatedCounter.nextSeq, 2);

      final second = first.updatedCounter.allocate();
      expect(second.seq, 2);
      expect(second.updatedCounter.nextSeq, 3);
    });

    test('連続して採番しても番号が重複しない', () {
      var counter = const SequenceCounter.initial();
      final assigned = <int>[];
      for (var i = 0; i < 100; i++) {
        final allocation = counter.allocate();
        assigned.add(allocation.seq);
        counter = allocation.updatedCounter;
      }
      expect(assigned, List.generate(100, (i) => i + 1));
      expect(assigned.toSet().length, 100);
    });

    test('不正なカウンタ値は例外にする', () {
      // 0 や負の値は仕様上ありえない。黙って続けると番号が壊れる。
      expect(() => const SequenceCounter(0).allocate(), throwsStateError);
      expect(() => const SequenceCounter(-1).allocate(), throwsStateError);
    });
  });

  group('振り直しなし・欠番を残す（6.2）', () {
    test('項目を削除してもカウンタは戻らない', () {
      var counter = const SequenceCounter.initial();
      counter = counter.allocate().updatedCounter; // 1 を採番
      counter = counter.allocate().updatedCounter; // 2 を採番
      counter = counter.allocate().updatedCounter; // 3 を採番
      expect(counter.nextSeq, 4);

      // 3 番を削除しても、次は 4 番。3 は欠番のまま残る。
      final afterDelete = SequencePolicy.onItemDeleted(counter);
      expect(afterDelete.nextSeq, 4);
      expect(afterDelete.allocate().seq, 4);
    });

    test('最後の項目を削除しても番号は使い回さない', () {
      var counter = const SequenceCounter.initial();
      final first = counter.allocate();
      counter = SequencePolicy.onItemDeleted(first.updatedCounter);
      expect(counter.allocate().seq, 2);
    });
  });

  group('アップロード中断時（7.5）', () {
    test('中断してもカウンタを消費しない', () {
      // ファイルのアップロードが完全に終わってから項目を作成するため、
      // 失敗した時点では採番自体が行われていない。
      const counter = SequenceCounter.initial();
      final afterAbort = SequencePolicy.onUploadAborted(counter);
      expect(afterAbort.nextSeq, 1);
      expect(afterAbort.allocate().seq, 1);
    });
  });
}
