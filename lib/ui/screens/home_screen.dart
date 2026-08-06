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
import '../../domain/role.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/app_providers.dart';
import '../format.dart';
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
                  // **招待の導線をここにも置く（仕様書 3.3）。**
                  // 以前はメンバー管理画面まで行かないと招待できず、
                  // 人を呼ぶたびに 3 画面ぶん移動する必要があった。
                  //
                  // 付与する役割は選んだ時点で決まる。あとから
                  // 「どちらで招待したか」を思い出せるようにするため、
                  // 役割を項目名に出す。
                  if (Permissions.canCreateInvite(access))
                    _InviteMenu(listId: entry.list.id),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 16,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    // 削除済みは件数に含めない。
                    l10n.itemCount(stats.value?.itemCount ?? 0),
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

/// 招待 URL をコピーするメニュー（仕様書 3.3）。
///
/// 発行した URL は**1 回しか使えず、既定 24 時間で切れる**。
/// 押した時点で招待が作られるので、配る直前に押してもらう。
class _InviteMenu extends ConsumerStatefulWidget {
  const _InviteMenu({required this.listId});

  final String listId;

  @override
  ConsumerState<_InviteMenu> createState() => _InviteMenuState();
}

class _InviteMenuState extends ConsumerState<_InviteMenu> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);

    return PopupMenuButton<ListRole>(
      enabled: !_busy,
      icon: _busy
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.more_vert),
      tooltip: l10n.createInvite,
      onSelected: _copyInviteUrl,
      itemBuilder: (context) => [
        // 招待で付与できるのは Super User と Read Only だけ（仕様書 3.3）。
        PopupMenuItem(
          value: ListRole.superUser,
          child: Text(l10n.copyInviteUrlAs(l10n.roleSuperUser)),
        ),
        PopupMenuItem(
          value: ListRole.readOnly,
          child: Text(l10n.copyInviteUrlAs(l10n.roleReadOnly)),
        ),
      ],
    );
  }

  Future<void> _copyInviteUrl(ListRole role) async {
    final l10n = AppL10n.of(context);
    final messenger = ScaffoldMessenger.of(context);

    setState(() => _busy = true);
    try {
      final invite = await ref
          .read(functionsRepositoryProvider)
          .createInvite(listId: widget.listId, role: role);

      final url = buildShareUrl(AppRoutes.invite(invite.inviteId));
      await Clipboard.setData(ClipboardData(text: url));
      if (!mounted) return;

      // **有効期限と 1 回限りであることを必ず添える。**
      // URL だけ渡されると、あとで使おうとして切れていることに気づけない。
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '${l10n.inviteUrlCopied}\n'
            '${l10n.inviteExpiryNote(formatDateTime(invite.expiresAt))}',
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
      messenger.showSnackBar(SnackBar(content: Text(l10n.inviteUrlCopyFailed)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
