/// 項目の検索・並び替え（仕様書 6.4 / 13.6）
///
/// Firestore は部分一致検索に対応していないため、リストを開いた時点で
/// 項目を読み込んでおき、アプリのメモリ上で絞り込む（13.6）。
library;

/// 並び替えのキー（6.4）。
enum ItemSortKey {
  /// 連番。
  seq,

  /// 日付（録音日）。
  date,

  /// 登録者。uid ではなく**解決後の表示名**で並べる（13.6）。
  ///
  /// **制約**：比較は文字コード順で行うため、**漢字の名前は五十音順にならない**。
  /// たとえば「佐藤・鈴木・田中」は「佐藤 → 田中 → 鈴木」の順に並ぶ。
  /// 五十音順にするには各ユーザーの読み仮名が必要になるため、
  /// 初期リリースでは文字コード順のままとする。
  /// 同じ人の項目がまとまって並ぶという目的は果たせる。
  registrant,
}

/// 並び順。
enum SortDirection { ascending, descending }

/// 検索・並び替えの対象となる項目。
///
/// 表示名は uid から解決したあとの値を渡す（13.3：表示名は参照で解決）。
class ItemQueryInput {
  const ItemQueryInput({
    required this.seq,
    required this.date,
    required this.registrantDisplayName,
    required this.isDeleted,
    this.title,
    this.artist,
    this.fileName,
  });

  final int seq;

  /// `YYYY-MM-DD` 形式。タイムゾーンを持たない（6.2）。
  final String date;

  final String registrantDisplayName;

  /// ソフト削除済みか（6.2）。
  final bool isDeleted;

  final String? title;
  final String? artist;
  final String? fileName;
}

/// 検索・並び替えの条件。
class ItemQuery {
  const ItemQuery({
    this.keyword = '',
    this.sortKey = ItemSortKey.seq,
    this.direction = SortDirection.ascending,
    this.showDeleted = true,
  });

  /// 検索キーワード。空なら絞り込まない。
  final String keyword;

  final ItemSortKey sortKey;
  final SortDirection direction;

  /// 削除済み項目を一覧に出すか。既定は表示（6.4）。
  final bool showDeleted;

  ItemQuery copyWith({
    String? keyword,
    ItemSortKey? sortKey,
    SortDirection? direction,
    bool? showDeleted,
  }) => ItemQuery(
    keyword: keyword ?? this.keyword,
    sortKey: sortKey ?? this.sortKey,
    direction: direction ?? this.direction,
    showDeleted: showDeleted ?? this.showDeleted,
  );
}

/// 項目の絞り込みと並び替え。
class ItemQueryRunner {
  const ItemQueryRunner._();

  /// [query] を [items] に適用する。
  ///
  /// 絞り込みの規則（6.4 / 13.6）:
  /// - キーワードは**曲名／アーティスト名／ファイル名のいずれか**に含まれれば一致。
  /// - 大文字小文字は区別しない。
  /// - **削除済み項目は検索の対象外**。キーワードが空でないときは、
  ///   [ItemQuery.showDeleted] にかかわらず除外する。
  static List<T> apply<T extends ItemQueryInput>(
    Iterable<T> items,
    ItemQuery query,
  ) {
    final keyword = query.keyword.trim().toLowerCase();
    final searching = keyword.isNotEmpty;

    final filtered = items.where((item) {
      if (item.isDeleted) {
        // 検索中は削除済みを常に除外する（6.4）。
        if (searching) return false;
        if (!query.showDeleted) return false;
        return true;
      }
      if (!searching) return true;
      return _matches(item, keyword);
    }).toList();

    filtered.sort((a, b) {
      final result = _compare(a, b, query.sortKey);
      return query.direction == SortDirection.ascending ? result : -result;
    });

    return filtered;
  }

  static bool _matches(ItemQueryInput item, String lowerKeyword) {
    for (final field in [item.title, item.artist, item.fileName]) {
      if (field == null) continue;
      if (field.toLowerCase().contains(lowerKeyword)) return true;
    }
    return false;
  }

  static int _compare(ItemQueryInput a, ItemQueryInput b, ItemSortKey key) {
    switch (key) {
      case ItemSortKey.seq:
        return a.seq.compareTo(b.seq);
      case ItemSortKey.date:
        // `YYYY-MM-DD` は文字列比較がそのまま日付順になる。
        final byDate = a.date.compareTo(b.date);
        return byDate != 0 ? byDate : a.seq.compareTo(b.seq);
      case ItemSortKey.registrant:
        // 文字コード順。漢字の名前は五十音順にならない（ItemSortKey.registrant 参照）。
        final byName = a.registrantDisplayName.compareTo(
          b.registrantDisplayName,
        );
        return byName != 0 ? byName : a.seq.compareTo(b.seq);
    }
  }
}
