/// ダウンロード済み（docs/DOWNLOAD-DESIGN.md 6.1・論点 8 / 21）
///
/// **この画面は Firestore を一切読まない。** 読むと、圏外で真っ白になる。
/// 出すものはすべて `index.json`（3.5）と `comments.json` から来る。
///
/// | 項目 | 中身 |
/// | --- | --- |
/// | 並び | **リストごとにまとめる**（論点 8 の「どのリストのものか」）。リスト内は `seq` 順 |
/// | 1 行 | 曲名・アーティスト・録音日・大きさ |
/// | 行を押したら | オフライン用の詳細（曲の情報＋コメント）。**投稿欄を出さない**（論点 8） |
/// | 再生 | ローカルファイルから（4.3） |
/// | 削除 | 行のスワイプ、または詳細から |
///
/// ## 残り日数の予告（6.1・論点 21）
///
/// **帯は 3 段**で、判定は `OfflineAccessPolicy.band`（domain）にある。
/// **プッシュ通知は使わない**——届けたい相手は 30 日近くオフラインでいる人で、
/// プッシュはオンラインでなければ届かない。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/list_item.dart';
import '../../domain/comment_tree.dart';
import '../../domain/download_index.dart';
import '../../domain/offline_access.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/download_provider.dart';
import '../../providers/playback_provider.dart';
import '../format.dart';
import '../routes.dart';
import '../widgets/async_view.dart';
import '../widgets/download_button.dart';

/// 目録の 1 件を、再生の入口（`PlaybackController.play`）へ渡せる形にする。
///
/// **再生の入口を増やさない**（4.3）。オフライン用に別の再生経路を作ると、
/// 猶予（論点 13b）の判定がそちらだけ抜ける。
ListItem listItemForDownloaded(DownloadedItem item) => ListItem(
  id: item.itemId,
  seq: item.seq,
  itemDate: item.date,
  kind: ItemKind.file,
  file: ItemFile(
    storagePath: item.storagePath,
    fileName: item.fileName,
    sizeBytes: item.sizeBytes,
    contentType: item.contentType,
  ),
  title: item.title,
  artist: item.artist,
  createdBy: '',
  registrantDisplayName: '',
  status: ContentStatus.active,
);

class DownloadsScreen extends ConsumerWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final index = ref.watch(downloadsProvider);

    return Scaffold(
      body: AsyncView(
        value: index,
        onRetry: () => ref.invalidate(downloadsProvider),
        builder: (data) {
          final items = [...data.items]
            ..sort((a, b) {
              final byList = a.listName.compareTo(b.listName);
              if (byList != 0) return byList;
              return a.seq.compareTo(b.seq);
            });

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const OfflineNoticeBanner(),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Text(
                  l10n.downloadsTitle,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              Expanded(
                child: items.isEmpty
                    ? EmptyState(
                        icon: Icons.cloud_download_outlined,
                        title: l10n.downloadsEmpty,
                        description: l10n.downloadsEmptyHint,
                      )
                    : _DownloadedList(items: items),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 残り日数の帯（6.1・論点 21）。**3 段。**
///
/// | 最終確認からの経過 | 帯 |
/// | --- | --- |
/// | 23 日未満（残り 8 日以上） | 出さない |
/// | 23 日以上 30 日未満（残り 7 日以下） | 「あと N 日で……」 |
/// | 30 日以上 | 「期間が過ぎました。**端末のファイルは残っています。**」 |
///
/// **「あと 0 日」を出すことを許す**（8.1）。残り 12 時間を「あと 1 日」と
/// 切り上げると、その表示のまま止まる。**短めに出すのが安全側。**
class OfflineNoticeBanner extends ConsumerWidget {
  const OfflineNoticeBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final band = ref.watch(offlineNoticeBandProvider);
    if (band == OfflineNoticeBand.none) return const SizedBox.shrink();

    final l10n = AppL10n.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final stopped = band == OfflineNoticeBand.stopped;

    return Container(
      width: double.infinity,
      color: stopped ? scheme.errorContainer : scheme.tertiaryContainer,
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            stopped ? Icons.cloud_off : Icons.schedule,
            size: 20,
            color: stopped
                ? scheme.onErrorContainer
                : scheme.onTertiaryContainer,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              stopped
                  ? l10n.offlineNoticeStopped
                  : l10n.offlineNoticeExpiring(
                      ref.watch(offlineRemainingDaysProvider),
                    ),
              style: theme.textTheme.bodySmall?.copyWith(
                color: stopped
                    ? scheme.onErrorContainer
                    : scheme.onTertiaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// リストごとにまとめた一覧（6.1）。
class _DownloadedList extends ConsumerWidget {
  const _DownloadedList({required this.items});

  final List<DownloadedItem> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final theme = Theme.of(context);

    final rows = <Widget>[];
    String? currentList;
    for (final item in items) {
      if (item.listName != currentList) {
        currentList = item.listName;
        final ofList = items.where((i) => i.listName == currentList).toList();
        rows.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(currentList, style: theme.textTheme.titleMedium),
                Text(
                  formatDownloadUsage(
                    l10n,
                    bytes: ofList.fold(0, (sum, i) => sum + i.localBytes),
                    count: ofList.length,
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        );
      }
      rows.add(_DownloadedRow(item: item));
    }

    return ListView(padding: const EdgeInsets.only(bottom: 32), children: rows);
  }
}

class _DownloadedRow extends ConsumerWidget {
  const _DownloadedRow({required this.item});

  final DownloadedItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final playback = ref.watch(playbackProvider);
    final playing = playback.isPlaying(item.itemId);
    final asItem = listItemForDownloaded(item);

    final subtitle = [
      item.date.toIso8601Date(),
      if (item.artist?.trim().isNotEmpty == true) item.artist!.trim(),
      formatBytes(item.localBytes),
    ].join(' · ');

    return Dismissible(
      key: ValueKey('${item.listId}/${item.itemId}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        color: Theme.of(context).colorScheme.errorContainer,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Icon(
          Icons.delete_outline,
          color: Theme.of(context).colorScheme.onErrorContainer,
        ),
      ),
      confirmDismiss: (_) async {
        await confirmRemoveDownload(
          context,
          ref,
          listId: item.listId,
          itemId: item.itemId,
          title: asItem.displayLabel(),
        );
        // **自分では消さない。** 目録が正なので、消えたかどうかは
        // `downloadsProvider` の次の値が決める。ここで true を返すと、
        // 削除に失敗しても行だけが消える。
        return false;
      },
      child: ListTile(
        leading: IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: playing ? l10n.pausePlayback : l10n.startPlayback,
          icon: Icon(playing ? Icons.pause : Icons.play_arrow),
          onPressed: () => playing
              ? ref.read(playbackProvider.notifier).pause()
              : ref.read(playbackProvider.notifier).play(asItem),
        ),
        title: Text(asItem.displayLabel(), overflow: TextOverflow.ellipsis),
        subtitle: Text(subtitle, overflow: TextOverflow.ellipsis),
        onTap: () =>
            context.go(AppRoutes.downloadedItem(item.listId, item.itemId)),
      ),
    );
  }
}

/// オフライン用の詳細（6.1・論点 8）。
///
/// **曲の情報＋コメント。コメントは読むだけで、投稿欄を出さない。**
/// 溜めて後から送ると、送った順と表示される順が食い違い、
/// 返信の親子関係（`comment_tree.dart` の `path` / `depth`）が壊れる（9 節）。
class DownloadedItemScreen extends ConsumerWidget {
  const DownloadedItemScreen({
    super.key,
    required this.listId,
    required this.itemId,
  });

  final String listId;
  final String itemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final theme = Theme.of(context);

    final index = ref.watch(downloadsProvider).value;
    final match = index?.items
        .where((i) => i.listId == listId && i.itemId == itemId)
        .toList();

    if (match == null || match.isEmpty) {
      return Scaffold(
        body: EmptyState(icon: Icons.search_off, title: l10n.notFound),
      );
    }
    final item = match.first;
    final asItem = listItemForDownloaded(item);

    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              IconButton(
                onPressed: () => context.go(AppRoutes.downloads),
                icon: const Icon(Icons.arrow_back),
              ),
              Text('#${item.seq}', style: theme.textTheme.titleMedium),
            ],
          ),
          const SizedBox(height: 8),
          Text(asItem.displayLabel(), style: theme.textTheme.headlineSmall),
          if (item.artist?.trim().isNotEmpty == true) ...[
            const SizedBox(height: 4),
            Text(
              item.artist!.trim(),
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 16),
          _Meta(label: l10n.columnDate, value: item.date.toIso8601Date()),
          _Meta(label: l10n.downloadsListLabel, value: item.listName),
          _Meta(
            label: l10n.downloadedToDevice,
            value: '${item.fileName} · ${formatBytes(item.localBytes)}',
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.delete_outline),
              label: Text(l10n.downloadRemove),
              onPressed: () async {
                await confirmRemoveDownload(
                  context,
                  ref,
                  listId: listId,
                  itemId: itemId,
                  title: asItem.displayLabel(),
                );
                if (context.mounted) context.go(AppRoutes.downloads);
              },
            ),
          ),
          const Divider(height: 32),
          Text(l10n.offlineComments, style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            l10n.offlineCommentsReadOnly,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          _OfflineComments(listId: listId, itemId: itemId),
        ],
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

/// 端末に持っているコメント（3.5 の `comments.json`）。
///
/// **ツリーの組み立ては `comment_tree.dart` をそのまま使う**（3.5）。
/// `parentId` / `path` を解決済みで持っているので、別の組み立て方は要らない。
class _OfflineComments extends ConsumerWidget {
  const _OfflineComments({required this.listId, required this.itemId});

  final String listId;
  final String itemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final theme = Theme.of(context);

    return FutureBuilder<List<OfflineComment>>(
      future: ref
          .read(downloadsProvider.notifier)
          .offlineComments(listId: listId, itemId: itemId),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final comments = snapshot.data ?? const <OfflineComment>[];
        if (comments.isEmpty) {
          return Text(
            l10n.offlineCommentsEmpty,
            style: theme.textTheme.bodyMedium,
          );
        }

        final flattened = CommentTree.flatten(CommentTree.build(comments));
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final node in flattened)
              Padding(
                padding: EdgeInsets.fromLTRB(16.0 * node.depth, 8, 0, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${node.value.authorName} · '
                      '${formatDateTime(node.value.createdAt)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      node.value.status == 'deleted'
                          ? l10n.commentDeleted
                          : node.value.body,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}
