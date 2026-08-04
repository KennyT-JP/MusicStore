/// 検索・並び替えのテスト（仕様書 6.4 / 13.6）
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:music_list_app/domain/item_query.dart';

void main() {
  const items = [
    ItemQueryInput(
      seq: 1,
      date: '2026-08-01',
      registrantDisplayName: '佐藤',
      isDeleted: false,
      title: 'サザンオールスターズメドレー',
      artist: null,
      fileName: 'take01.mp3',
    ),
    ItemQueryInput(
      seq: 2,
      date: '2026-07-15',
      registrantDisplayName: '鈴木',
      isDeleted: false,
      title: null,
      artist: null,
      fileName: 'Rehearsal_Take2.MP3',
    ),
    ItemQueryInput(
      seq: 3,
      date: '2026-08-20',
      registrantDisplayName: '田中',
      isDeleted: false,
      title: '夏の思い出',
      artist: 'サザン',
      fileName: null,
    ),
    ItemQueryInput(
      seq: 4,
      date: '2026-07-01',
      registrantDisplayName: '佐藤',
      isDeleted: true,
      title: '削除された曲',
      artist: null,
      fileName: 'old.mp3',
    ),
  ];

  List<int> seqsOf(List<ItemQueryInput> result) =>
      result.map((i) => i.seq).toList();

  group('検索（6.4）', () {
    test('曲名の部分一致で引ける', () {
      final result = ItemQueryRunner.apply(
        items,
        const ItemQuery(keyword: 'オールスターズ'),
      );
      expect(seqsOf(result), [1]);
    });

    test('アーティスト名でも引ける', () {
      final result = ItemQueryRunner.apply(
        items,
        const ItemQuery(keyword: 'サザン'),
      );
      // 曲名に「サザン」を含む 1 番と、アーティスト名が「サザン」の 3 番。
      expect(seqsOf(result), [1, 3]);
    });

    test('曲名・アーティスト名が未記入の項目はファイル名で引ける', () {
      final result = ItemQueryRunner.apply(
        items,
        const ItemQuery(keyword: 'rehearsal'),
      );
      expect(seqsOf(result), [2]);
    });

    test('大文字小文字を区別しない', () {
      final upper = ItemQueryRunner.apply(
        items,
        const ItemQuery(keyword: 'REHEARSAL'),
      );
      final lower = ItemQueryRunner.apply(
        items,
        const ItemQuery(keyword: 'rehearsal'),
      );
      expect(seqsOf(upper), seqsOf(lower));
    });

    test('前後の空白は無視する', () {
      final result = ItemQueryRunner.apply(
        items,
        const ItemQuery(keyword: '  サザン  '),
      );
      expect(seqsOf(result), [1, 3]);
    });

    test('キーワードが空なら絞り込まない', () {
      final result = ItemQueryRunner.apply(items, const ItemQuery());
      expect(result.length, 4);
    });

    test('削除済み項目は検索の対象外', () {
      // showDeleted が true でも、検索中は削除済みを除外する（6.4）。
      final result = ItemQueryRunner.apply(
        items,
        const ItemQuery(keyword: '削除された', showDeleted: true),
      );
      expect(result, isEmpty);
    });
  });

  group('削除済みの表示切替（6.4）', () {
    test('既定では削除済みも表示する', () {
      final result = ItemQueryRunner.apply(items, const ItemQuery());
      expect(seqsOf(result), contains(4));
    });

    test('切替で非表示にできる', () {
      final result = ItemQueryRunner.apply(
        items,
        const ItemQuery(showDeleted: false),
      );
      expect(seqsOf(result), isNot(contains(4)));
      expect(result.length, 3);
    });
  });

  group('並び替え（6.4）', () {
    test('連番順', () {
      final result = ItemQueryRunner.apply(
        items,
        const ItemQuery(sortKey: ItemSortKey.seq),
      );
      expect(seqsOf(result), [1, 2, 3, 4]);
    });

    test('日付順（YYYY-MM-DD の文字列比較がそのまま日付順になる）', () {
      final result = ItemQueryRunner.apply(
        items,
        const ItemQuery(sortKey: ItemSortKey.date),
      );
      expect(seqsOf(result), [4, 2, 1, 3]);
    });

    test('登録者順（表示名で並べる）', () {
      final result = ItemQueryRunner.apply(
        items,
        const ItemQuery(sortKey: ItemSortKey.registrant, showDeleted: false),
      );
      // 文字コード順なので 佐藤(4F50) → 田中(7530) → 鈴木(9234)。
      // 五十音順（佐藤 → 鈴木 → 田中）にはならない。
      // 五十音順にするには読み仮名が必要なため、初期リリースでは
      // この挙動を仕様とする（ItemSortKey.registrant のコメント参照）。
      expect(seqsOf(result), [1, 3, 2]);
    });

    test('同じ登録者の項目はまとまって並ぶ', () {
      // 五十音順にはならないが、「同じ人の投稿を固めて見る」という
      // 並び替えの目的は果たせることを確認する。
      const sameRegistrant = [
        ItemQueryInput(
          seq: 1,
          date: '2026-08-01',
          registrantDisplayName: '田中',
          isDeleted: false,
        ),
        ItemQueryInput(
          seq: 2,
          date: '2026-08-02',
          registrantDisplayName: '佐藤',
          isDeleted: false,
        ),
        ItemQueryInput(
          seq: 3,
          date: '2026-08-03',
          registrantDisplayName: '田中',
          isDeleted: false,
        ),
      ];
      final result = ItemQueryRunner.apply(
        sameRegistrant,
        const ItemQuery(sortKey: ItemSortKey.registrant),
      );
      expect(result.map((i) => i.registrantDisplayName), ['佐藤', '田中', '田中']);
      expect(seqsOf(result), [2, 1, 3]);
    });

    test('英字の名前は期待どおりアルファベット順になる', () {
      const alphabetic = [
        ItemQueryInput(
          seq: 1,
          date: '2026-08-01',
          registrantDisplayName: 'Suzuki',
          isDeleted: false,
        ),
        ItemQueryInput(
          seq: 2,
          date: '2026-08-02',
          registrantDisplayName: 'Sato',
          isDeleted: false,
        ),
        ItemQueryInput(
          seq: 3,
          date: '2026-08-03',
          registrantDisplayName: 'Tanaka',
          isDeleted: false,
        ),
      ];
      final result = ItemQueryRunner.apply(
        alphabetic,
        const ItemQuery(sortKey: ItemSortKey.registrant),
      );
      expect(result.map((i) => i.registrantDisplayName), [
        'Sato',
        'Suzuki',
        'Tanaka',
      ]);
    });

    test('降順にできる', () {
      final result = ItemQueryRunner.apply(
        items,
        const ItemQuery(
          sortKey: ItemSortKey.seq,
          direction: SortDirection.descending,
        ),
      );
      expect(seqsOf(result), [4, 3, 2, 1]);
    });

    test('同じ値のときは連番で安定させる', () {
      const sameName = [
        ItemQueryInput(
          seq: 2,
          date: '2026-08-01',
          registrantDisplayName: '佐藤',
          isDeleted: false,
        ),
        ItemQueryInput(
          seq: 1,
          date: '2026-08-01',
          registrantDisplayName: '佐藤',
          isDeleted: false,
        ),
      ];
      final byDate = ItemQueryRunner.apply(
        sameName,
        const ItemQuery(sortKey: ItemSortKey.date),
      );
      expect(seqsOf(byDate), [1, 2]);

      final byName = ItemQueryRunner.apply(
        sameName,
        const ItemQuery(sortKey: ItemSortKey.registrant),
      );
      expect(seqsOf(byName), [1, 2]);
    });
  });
}
