/// リスト一括ダウンロード（docs/DOWNLOAD-DESIGN.md 6.3・論点 20）
///
/// **曲数にも容量にも上限を置かない**（論点 20。端末側の上限を置かないと
/// 決めた論点 6 と揃える）。**代わりに、始める前に見積もりを出して確認を取る。**
///
/// > **上限を置かない代わりが、見積もり・進捗・中断の 3 つ。**
/// > どれか 1 つでも欠けると、「押したら何が起きるか分からないボタン」になる。
/// > **上限が無いことと、無警告で始めることは違う。**
///
/// | 3 つ | どこ |
/// | --- | --- |
/// | 見積もり | [confirmBulkDownload]（判定は `BulkDownloadPolicy.estimate`） |
/// | 進捗 | [BulkDownloadBanner] |
/// | 中断 | [BulkDownloadBanner] の「中止」 |
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/app_providers.dart';
import '../../providers/download_provider.dart';
import '../widgets/async_view.dart';
import '../widgets/download_button.dart';
import 'download_jobs.dart';

/// 一括ダウンロードを、確認を取ってから始める（6.3）。
///
/// **すでに落としてあるぶんは数にもサイズにも入れない**（6.3）——
/// 入れると「残り 4 曲」と言いながら 12 曲ぶんの大きさを出すことになる。
/// 絞り込みは `DownloadsController.estimateBulk` が行う。
Future<void> confirmBulkDownload(
  BuildContext context,
  WidgetRef ref, {
  required String listId,
  required String listName,
}) async {
  final l10n = AppL10n.of(context);

  // **プレミアムでなければ、まず案内**（6.5・論点 19）。
  if (ref.read(canDownloadProvider(listId)).value != true) {
    await showPremiumRequiredForDownload(context);
    return;
  }

  // **`.value` では読まない**（test/domain/async_provider_read_test.dart）。
  // まだ届いていないと空に倒れ、「すべて保存済みです」と嘘をつく。
  final items = await ref.read(
    listItemsProvider((
      listId: listId,
      withdrawnLabel: l10n.withdrawnUser,
    )).future,
  );

  final estimate = ref.read(downloadsProvider.notifier).estimateBulk(items);
  if (!context.mounted) return;

  // **落とすものが 1 つも無いなら、確認を出す必要すらない**（6.3）。
  if (estimate.isEmpty) {
    _say(context, l10n.downloadListNothing);
    return;
  }

  final start = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.downloadList),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // **曲数と合計サイズを必ず両方出す**（論点 20）。大きさを知らせずに
          // 500 MB を落とし始めるのは、端末の容量にも通信量にも失礼。
          Text(
            l10n.downloadListEstimate(
              estimate.targetCount,
              estimate.alreadyDownloadedCount,
              estimate.remainingCount,
              formatBytes(estimate.remainingBytes),
            ),
          ),
          const SizedBox(height: 8),
          // **「再開」とは書かない**（4.1）。閉じると最初から取り直しになる。
          Text(
            l10n.downloadKeepAppOpen,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(l10n.downloadListStart),
        ),
      ],
    ),
  );
  if (start != true) return;

  final result = await ref
      .read(downloadJobsProvider.notifier)
      .downloadList(
        listId: listId,
        listName: listName,
        items: items,
        withdrawnLabel: l10n.withdrawnUser,
      );

  if (!context.mounted) return;
  // **1 曲失敗しても止めない**ので、終わってからまとめて知らせる（4.1）。
  if (result.canceled) {
    _say(context, l10n.downloadListStopped);
  } else if (result.failed > 0) {
    _say(context, l10n.downloadListFailed(result.failed));
  } else {
    _say(context, l10n.downloadListDone(result.completed));
  }
}

/// 進行中の帯（6.3）。「5 / 12 曲目 · 中止」。
///
/// **画面の下に置く。** 上に出すと、一覧が動くたびに位置が変わる。
class BulkDownloadBanner extends ConsumerWidget {
  const BulkDownloadBanner({super.key, required this.listId});

  final String listId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jobs = ref.watch(downloadJobsProvider);
    final bulk = jobs.bulk;
    if (bulk == null || bulk.listId != listId) return const SizedBox.shrink();

    final l10n = AppL10n.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final item = bulk.currentItemId == null
        ? null
        : jobs.items[bulk.currentItemId];

    return Material(
      color: scheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.downloadListProgress(bulk.position, bulk.total),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSecondaryContainer,
                    ),
                  ),
                  if (item != null) ...[
                    const SizedBox(height: 2),
                    // **「%」だけだと止まって見える**（4.1）。
                    Text(
                      l10n.downloadProgressBytes(
                        formatBytes(item.transferred),
                        formatBytes(item.total),
                      ),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSecondaryContainer,
                      ),
                    ),
                    const SizedBox(height: 4),
                    LinearProgressIndicator(value: item.ratio),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            // **いつでも中断できること**（論点 20）。押したら、いま落として
            // いる曲の `.part` だけ捨て、済んだぶんは残す（4.1）。
            TextButton(
              onPressed: () =>
                  ref.read(downloadJobsProvider.notifier).cancelBulk(),
              child: Text(l10n.downloadStop),
            ),
          ],
        ),
      ),
    );
  }
}

void _say(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}
