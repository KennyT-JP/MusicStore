/// リスト詳細（項目一覧）（仕様書 6.4 / 14.2）
///
/// 並び替え（連番／日付／登録者）、検索、削除済みの表示切替を備える。
/// 検索と並び替えはアプリのメモリ上で行う（仕様書 13.6）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/list_item.dart';
import '../../domain/item_query.dart';
import '../../domain/permissions.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/app_providers.dart';
import '../routes.dart';
import '../widgets/async_view.dart';
import 'requests_screens.dart';

/// 一覧の絞り込み・並び替えの状態。
///
/// リストごとに保持する。削除済みの表示切替は既定でオン（仕様書 6.4）。
final itemQueryProvider =
    NotifierProvider.family<ItemQueryNotifier, ItemQuery, String>(
      ItemQueryNotifier.new,
    );

class ItemQueryNotifier extends Notifier<ItemQuery> {
  ItemQueryNotifier(this.listId);

  /// どのリストの絞り込み状態かを示す。状態はリストごとに独立している。
  final String listId;

  @override
  ItemQuery build() => const ItemQuery();

  void setKeyword(String keyword) => state = state.copyWith(keyword: keyword);

  void setShowDeleted(bool show) => state = state.copyWith(showDeleted: show);

  /// 同じキーを再度選んだら昇順・降順を入れ替える。
  void toggleSort(ItemSortKey key) {
    if (state.sortKey == key) {
      state = state.copyWith(
        direction: state.direction == SortDirection.ascending
            ? SortDirection.descending
            : SortDirection.ascending,
      );
    } else {
      state = state.copyWith(sortKey: key, direction: SortDirection.ascending);
    }
  }
}

class ListDetailScreen extends ConsumerWidget {
  const ListDetailScreen({super.key, required this.listId});

  final String listId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final list = ref.watch(listProvider(listId));
    final access = ref.watch(listAccessProvider(listId));

    // **未参加者はここで参加申請の画面へ振り替える（仕様書 5.3）。**
    // 共有 URL は誰でも開けるため、そのまま項目一覧を出そうとすると
    // ルールに弾かれて「権限がありません」になる。実装済みの
    // JoinRequestScreen へ繋がっていなかった（監査 S9）。
    //
    // 参加の判定は自分のメンバー情報が読めるまで待つ。読み込み中に
    // 振り替えると、メンバーでも一瞬だけ申請画面が出てしまう。
    //
    // **取れなかったときに「未参加」と決めつけない。** 取得が失敗すると
    // 役割は null になるが、それは「参加していない」ことを意味しない。
    // 申請画面へ振り替えると、参加しているのに申請を促される（監査 第2回）。
    final memberships = ref.watch(myMembershipsProvider);
    if (memberships.hasError) {
      return Scaffold(
        body: AsyncView<void>(
          value: AsyncValue.error(
            memberships.error!,
            memberships.stackTrace ?? StackTrace.empty,
          ),
          onRetry: () => ref.invalidate(myMembershipsProvider),
          builder: (_) => const SizedBox.shrink(),
        ),
      );
    }
    if (memberships.hasValue && !access.canView) {
      return JoinRequestScreen(listId: listId);
    }

    return Scaffold(
      body: AsyncView(
        value: list,
        builder: (musicList) {
          if (musicList == null) {
            return EmptyState(icon: Icons.search_off, title: l10n.notFound);
          }
          return Column(
            children: [
              _Header(listId: listId, name: musicList.name),
              const Divider(height: 1),
              Expanded(child: _ItemList(listId: listId)),
            ],
          );
        },
      ),
      floatingActionButton: Permissions.canAddItem(access)
          ? FloatingActionButton.extended(
              onPressed: () => context.go(AppRoutes.addItem(listId)),
              icon: const Icon(Icons.add),
              label: Text(l10n.addItem),
            )
          : null,
    );
  }
}

/// リスト名・検索・並び替え・管理への導線。
class _Header extends ConsumerWidget {
  const _Header({required this.listId, required this.name});

  final String listId;
  final String name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final query = ref.watch(itemQueryProvider(listId));
    final notifier = ref.read(itemQueryProvider(listId).notifier);
    final access = ref.watch(listAccessProvider(listId));

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                onPressed: () => context.go(AppRoutes.home),
                icon: const Icon(Icons.arrow_back),
                tooltip: l10n.navHome,
              ),
              Expanded(
                child: Text(
                  name,
                  style: Theme.of(context).textTheme.titleLarge,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (Permissions.canManageMembers(access))
                PopupMenuButton<String>(
                  icon: const Icon(Icons.settings_outlined),
                  onSelected: (value) => context.go(value),
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: AppRoutes.listMembers(listId),
                      child: Text(l10n.manageMembers),
                    ),
                    PopupMenuItem(
                      value: AppRoutes.listJoinRequests(listId),
                      child: Text(l10n.joinRequests),
                    ),
                    PopupMenuItem(
                      value: AppRoutes.listSettings(listId),
                      child: Text(l10n.listSettings),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            decoration: InputDecoration(
              hintText: l10n.searchHint,
              prefixIcon: const Icon(Icons.search),
              border: const OutlineInputBorder(),
              isDense: true,
              suffixIcon: query.keyword.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () => notifier.setKeyword(''),
                    ),
            ),
            onChanged: notifier.setKeyword,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(l10n.sortBy, style: Theme.of(context).textTheme.bodySmall),
              _SortChip(
                listId: listId,
                sortKey: ItemSortKey.seq,
                label: l10n.columnSeq,
              ),
              _SortChip(
                listId: listId,
                sortKey: ItemSortKey.date,
                label: l10n.columnDate,
              ),
              _SortChip(
                listId: listId,
                sortKey: ItemSortKey.registrant,
                label: l10n.columnRegistrant,
              ),
              const SizedBox(width: 8),
              FilterChip(
                label: Text(l10n.showDeletedItems),
                selected: query.showDeleted,
                onSelected: notifier.setShowDeleted,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SortChip extends ConsumerWidget {
  const _SortChip({
    required this.listId,
    required this.sortKey,
    required this.label,
  });

  final String listId;
  final ItemSortKey sortKey;
  final String label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = ref.watch(itemQueryProvider(listId));
    final selected = query.sortKey == sortKey;

    return FilterChip(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label),
          if (selected)
            Icon(
              query.direction == SortDirection.ascending
                  ? Icons.arrow_upward
                  : Icons.arrow_downward,
              size: 14,
            ),
        ],
      ),
      selected: selected,
      onSelected: (_) =>
          ref.read(itemQueryProvider(listId).notifier).toggleSort(sortKey),
    );
  }
}

class _ItemList extends ConsumerWidget {
  const _ItemList({required this.listId});

  final String listId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final args = (listId: listId, withdrawnLabel: l10n.withdrawnUser);
    final items = ref.watch(listItemsProvider(args));
    final query = ref.watch(itemQueryProvider(listId));
    final access = ref.watch(listAccessProvider(listId));

    return AsyncView(
      value: items,
      onRetry: () => ref.invalidate(listItemsProvider(args)),
      builder: (all) {
        final filtered = ItemQueryRunner.apply(all, query);

        if (filtered.isEmpty) {
          return EmptyState(
            icon: query.keyword.isEmpty
                ? Icons.library_music_outlined
                : Icons.search_off,
            title: query.keyword.isEmpty ? l10n.noItemsYet : l10n.noSearchResults,
            description: query.keyword.isEmpty && Permissions.canAddItem(access)
                ? l10n.noItemsHint(l10n.addItem)
                : null,
          );
        }

        // 画面幅が広いときは表形式に近い行、狭いときは 2 段のカードにする
        // （仕様書 12.5 レスポンシブ）。
        final isWide = MediaQuery.sizeOf(context).width >= 700;

        return ListView.separated(
          padding: const EdgeInsets.only(bottom: 96),
          itemCount: filtered.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, index) =>
              _ItemRow(listId: listId, item: filtered[index], isWide: isWide),
        );
      },
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({
    required this.listId,
    required this.item,
    required this.isWide,
  });

  final String listId;
  final ListItem item;
  final bool isWide;

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final theme = Theme.of(context);

    // 削除済みは中身を出さず「削除されました」とだけ表示する（仕様書 6.4）。
    if (item.isDeleted) {
      return ListTile(
        leading: _SeqBadge(seq: item.seq, muted: true),
        title: Text(
          l10n.itemDeleted,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.outline,
            fontStyle: FontStyle.italic,
          ),
        ),
        onTap: () => context.go(AppRoutes.item(listId, item.id)),
      );
    }

    final subtitle = [
      item.date,
      if (item.artist?.trim().isNotEmpty == true) item.artist!.trim(),
      item.registrantDisplayName,
    ].join(' · ');

    return ListTile(
      leading: _SeqBadge(seq: item.seq),
      title: Text(item.displayLabel(), overflow: TextOverflow.ellipsis),
      subtitle: Text(subtitle, overflow: TextOverflow.ellipsis),
      trailing: Icon(
        item.kind == ItemKind.file
            ? Icons.audio_file_outlined
            : Icons.link_outlined,
        color: theme.colorScheme.outline,
      ),
      isThreeLine: !isWide && subtitle.length > 40,
      onTap: () => context.go(AppRoutes.item(listId, item.id)),
    );
  }
}

/// 連番。欠番があることが分かるよう、削除済みも同じ形で出す（仕様書 6.2）。
class _SeqBadge extends StatelessWidget {
  const _SeqBadge({required this.seq, this.muted = false});

  final int seq;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 40,
      child: Text(
        '$seq',
        textAlign: TextAlign.right,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: muted ? scheme.outline : scheme.onSurfaceVariant,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}
