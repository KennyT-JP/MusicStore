/// ホーム（参加リスト一覧）（仕様書 14.2）
///
/// 全リストの一覧を公開する画面は作らない（仕様書 5.3）。
/// 自分が参加しているリストだけを並べる。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/repositories/functions_repository.dart';
import '../../domain/permissions.dart';
import '../../domain/quota.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/app_providers.dart';
import '../routes.dart';
import '../share_url.dart';
import '../widgets/async_view.dart';
import '../widgets/error_message.dart';
import '../widgets/role_chip.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final lists = ref.watch(myListsProvider);

    return Scaffold(
      body: AsyncView(
        value: lists,
        onRetry: () => ref.invalidate(myMembershipsProvider),
        builder: (entries) {
          if (entries.isEmpty) {
            return EmptyState(
              icon: Icons.queue_music_outlined,
              title: l10n.homeEmpty,
              description: l10n.homeEmptyHint,
              // **申請一覧への導線をここにも置く。**
              // 申請を出した直後はまだ参加リストが 0 件なので、この画面から
              // 動けないと申請の状態を確認する手段がなくなる。
              action: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FilledButton.icon(
                    onPressed: () => context.go(AppRoutes.requestList),
                    icon: const Icon(Icons.add),
                    label: Text(l10n.requestNewList),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => context.go(AppRoutes.myRequests),
                    child: Text(l10n.myRequests),
                  ),
                ],
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  l10n.homeTitle,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              for (final entry in entries) _ListCard(entry: entry),
              const SizedBox(height: 24),
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: () => context.go(AppRoutes.requestList),
                    icon: const Icon(Icons.add),
                    label: Text(l10n.requestNewList),
                  ),
                  const SizedBox(width: 12),
                  TextButton(
                    onPressed: () => context.go(AppRoutes.myRequests),
                    child: Text(l10n.myRequests),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ListCard extends ConsumerWidget {
  const _ListCard({required this.entry});

  final MyListEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    // **項目数はサーバーが持つ値を使う（監査 S6）。**
    // 以前は listItemsProvider（全項目の常時購読）を件数表示のためだけに
    // 張っていた。参加リスト M 件 × 平均項目 N 件で、画面を開くだけで
    // M 本の接続と M×N 件の読み取りが発生していた。
    final stats = ref.watch(listStatsProvider(entry.list.id));
    final access = ref.watch(listAccessProvider(entry.list.id));

    // 容量はリスト管理者以上にのみ見せる（仕様書 7.4）。
    final showQuota = Permissions.canViewQuota(access);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => context.go(AppRoutes.list(entry.list.id)),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      entry.list.name,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  RoleChip(role: entry.role),
                  // **共有リンクの導線をここにも置く（仕様書 3.3）。**
                  // 以前はメンバー管理画面まで行かないと招待できず、
                  // 人を呼ぶたびに 3 画面ぶん移動する必要があった。
                  if (Permissions.canCreateShareLink(access))
                    _ShareLinkMenu(listId: entry.list.id),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 16,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  // **届くまで件数を出さない（2026-08-11）。**
                  //
                  // 以前は `?? 0` で既定に倒しており、開いた直後の数秒は
                  // **中身があるのに「0件」と言い切って**いた。
                  // 「空である」と「まだ取れていない」は別のことで、
                  // 0 と書くと前者にしか読めない
                  // （docs/AUDIT-CHECKLIST.md 観点 2）。
                  if (stats.value case final s?)
                    Text(
                      // 削除済みは件数に含めない。
                      l10n.itemCount(s.itemCount),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  if (entry.list.hasNoAdmin)
                    Chip(
                      visualDensity: VisualDensity.compact,
                      label: Text(l10n.listsWithoutAdmin),
                      backgroundColor: Theme.of(
                        context,
                      ).colorScheme.errorContainer,
                    ),
                ],
              ),
              if (showQuota) _QuotaBar(listId: entry.list.id),
            ],
          ),
        ),
      ),
    );
  }
}

/// 容量の使用状況（仕様書 7.3 / 7.4）。
///
/// 80% 超で Notice、90% 超で警告の色に変える。
class _QuotaBar extends ConsumerWidget {
  const _QuotaBar({required this.listId});

  final String listId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final stats = ref.watch(listStatsProvider(listId)).value;
    if (stats == null) return const SizedBox.shrink();

    final quota = stats.quota;
    final scheme = Theme.of(context).colorScheme;
    final color = switch (quota.level) {
      QuotaLevel.warning => scheme.error,
      QuotaLevel.notice => Colors.orange,
      QuotaLevel.normal => scheme.primary,
    };

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LinearProgressIndicator(
            value: quota.ratio.clamp(0.0, 1.0),
            color: color,
            backgroundColor: scheme.surfaceContainerHighest,
          ),
          const SizedBox(height: 4),
          Text(
            l10n.quotaUsage(
              formatBytes(quota.usedBytes),
              formatBytes(quota.quotaBytes),
            ),
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

/// 共有リンクをコピーするボタン（仕様書 3.3）。
///
/// **押すと 1 種類のリンクができる。** 受け取った人が「参加する」か
/// 「参加せずに見る」かを選ぶので、**配る側は相手の種類を選ばない。**
/// リンクは無期限で、何度でも、複数人が使える。
class _ShareLinkMenu extends ConsumerStatefulWidget {
  const _ShareLinkMenu({required this.listId});

  final String listId;

  @override
  ConsumerState<_ShareLinkMenu> createState() => _ShareLinkMenuState();
}

class _ShareLinkMenuState extends ConsumerState<_ShareLinkMenu> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);

    // **選ばせない。** 以前はここで相手の役割（Super User / Read Only）を
    // 選ぶ形にしていたが、配る側は相手が参加するかどうかも知らない。
    // 押したらリンクが 1 本できるだけにしてある。
    return IconButton(
      onPressed: _busy ? null : _copyShareLink,
      icon: _busy
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.link),
      tooltip: l10n.copyShareLink,
    );
  }

  Future<void> _copyShareLink() async {
    final l10n = AppL10n.of(context);
    final messenger = ScaffoldMessenger.of(context);

    setState(() => _busy = true);
    try {
      final linkId = await ref
          .read(functionsRepositoryProvider)
          .createShareLink(listId: widget.listId);

      final url = buildShareUrl(AppRoutes.shareLink(linkId));
      await Clipboard.setData(ClipboardData(text: url));
      if (!mounted) return;

      // **何度でも使えることを添える。** 以前は期限と 1 回限りを
      // 伝えていた。いまはその逆で、配ったあとも生き続けることと、
      // 止めるには取り消しが要ることを伝える必要がある。
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '${l10n.shareLinkCopied}\n${l10n.shareLinkReusableNote}',
          ),
        ),
      );
    } on FunctionsCallException catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(describeFunctionsError(context, e))),
      );
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(l10n.shareLinkCopyFailed)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
