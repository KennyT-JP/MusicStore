/// サイト管理の画面（仕様書 11.1 / 14.2）
///
/// サイト管理者のみが開ける。ルーターでも URL 直打ちを塞いでいる（14.5）。
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/music_list.dart';
import '../../data/models/requests.dart';
import '../../data/repositories/functions_repository.dart';
import '../../domain/quota.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/app_providers.dart';
import '../routes.dart';
import '../widgets/async_view.dart';

// ---------------------------------------------------------------------------
// サイト管理のトップ
// ---------------------------------------------------------------------------

class SiteAdminHomeScreen extends ConsumerWidget {
  const SiteAdminHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final pending = ref.watch(pendingListRequestsProvider).value ?? const [];
    final lists = ref.watch(allListsProvider).value ?? const [];
    final orphaned = lists.where((l) => l.hasNoAdmin).length;

    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            l10n.navSiteAdmin,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          _AdminEntry(
            icon: Icons.playlist_add_check,
            title: l10n.siteAdminListRequests,
            // 未処理の件数を出し、放置に気づけるようにする。
            badge: pending.isEmpty ? null : '${pending.length}',
            route: AppRoutes.siteAdminListRequests,
          ),
          _AdminEntry(
            icon: Icons.storage_outlined,
            title: l10n.siteAdminLists,
            badge: orphaned == 0 ? null : '$orphaned',
            badgeIsWarning: true,
            route: AppRoutes.siteAdminLists,
          ),
          _AdminEntry(
            icon: Icons.people_outline,
            title: l10n.siteAdminUsers,
            route: AppRoutes.siteAdminUsers,
          ),
          _AdminEntry(
            icon: Icons.tune,
            title: l10n.siteAdminSettings,
            route: AppRoutes.siteAdminSettings,
          ),
        ],
      ),
    );
  }
}

class _AdminEntry extends StatelessWidget {
  const _AdminEntry({
    required this.icon,
    required this.title,
    required this.route,
    this.badge,
    this.badgeIsWarning = false,
  });

  final IconData icon;
  final String title;
  final String route;
  final String? badge;
  final bool badgeIsWarning;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (badge != null)
              Chip(
                visualDensity: VisualDensity.compact,
                label: Text(badge!),
                backgroundColor: badgeIsWarning
                    ? scheme.errorContainer
                    : scheme.primaryContainer,
                side: BorderSide.none,
              ),
            const Icon(Icons.chevron_right),
          ],
        ),
        onTap: () => context.go(route),
      ),
    );
  }
}

/// サイト管理の各画面で使う共通ヘッダ。
class _SiteAdminHeader extends StatelessWidget {
  const _SiteAdminHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go(AppRoutes.siteAdmin),
        ),
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// リスト作成申請の承認（仕様書 5.1 / 11.1）
// ---------------------------------------------------------------------------

class SiteAdminListRequestsScreen extends ConsumerWidget {
  const SiteAdminListRequestsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final requests = ref.watch(pendingListRequestsProvider);

    return Scaffold(
      body: AsyncView(
        value: requests,
        onRetry: () => ref.invalidate(pendingListRequestsProvider),
        builder: (items) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _SiteAdminHeader(title: l10n.siteAdminListRequests),
            const SizedBox(height: 16),
            if (items.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Center(child: Text(l10n.noPendingListRequests)),
              ),
            for (final request in items) _ListRequestCard(request: request),
          ],
        ),
      ),
    );
  }
}

class _ListRequestCard extends ConsumerStatefulWidget {
  const _ListRequestCard({required this.request});

  final ListRequest request;

  @override
  ConsumerState<_ListRequestCard> createState() => _ListRequestCardState();
}

class _ListRequestCardState extends ConsumerState<_ListRequestCard> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final request = widget.request;
    final users = ref.watch(userDirectoryProvider(userDirectoryKey([request.requestedBy]))).value;
    final requester = users?[request.requestedBy];

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              request.listName,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            _Field(
              label: l10n.requesterLabel,
              value: requester?.displayName ?? request.requestedBy,
            ),
            _Field(label: l10n.trackCountLabel, value: l10n.trackCountValue(request.estimatedTrackCount)),
            _Field(label: l10n.expectedUserCountLabel, value: l10n.userCountValue(request.expectedUserCount)),
            _Field(label: l10n.purposeLabel, value: request.purpose),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _busy ? null : _reject,
                  child: Text(l10n.reject),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _busy ? null : _approve,
                  child: Text(l10n.approve),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _approve() => _run(
    () => ref
        .read(functionsRepositoryProvider)
        .approveListRequest(widget.request.id),
  );

  /// 却下しても申請者には通知しない（仕様書 5.2.1）。
  /// 名前の予約はサーバー側で解放される。
  Future<void> _reject() => _run(
    () => ref
        .read(functionsRepositoryProvider)
        .rejectListRequest(widget.request.id),
  );

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } on FunctionsCallException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.value});

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
            width: 88,
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

// ---------------------------------------------------------------------------
// リスト一覧・容量（仕様書 5.6 / 7.2 / 11.1）
// ---------------------------------------------------------------------------

class SiteAdminListsScreen extends ConsumerWidget {
  const SiteAdminListsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final lists = ref.watch(allListsProvider);

    return Scaffold(
      body: AsyncView(
        value: lists,
        onRetry: () => ref.invalidate(allListsProvider),
        builder: (items) {
          // 管理者不在のリストを先に出す（仕様書 5.6）。
          final orphaned = items.where((l) => l.hasNoAdmin).toList();
          final normal = items.where((l) => !l.hasNoAdmin).toList();

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _SiteAdminHeader(title: l10n.siteAdminLists),
              const SizedBox(height: 16),
              if (orphaned.isNotEmpty) ...[
                Text(
                  l10n.listsWithoutAdmin,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
                const SizedBox(height: 8),
                for (final list in orphaned)
                  _SiteListCard(list: list, needsAdmin: true),
                const Divider(height: 32),
              ],
              for (final list in normal) _SiteListCard(list: list),
              if (items.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Center(child: Text(l10n.noListsYet)),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _SiteListCard extends ConsumerWidget {
  const _SiteListCard({required this.list, this.needsAdmin = false});

  final MusicList list;
  final bool needsAdmin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final stats = ref.watch(listStatsProvider(list.id)).value;
    final scheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    list.name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Text(
                  l10n.userCountValue(list.memberCount),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            if (stats != null) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: stats.quota.ratio.clamp(0.0, 1.0),
                color: switch (stats.quota.level) {
                  QuotaLevel.warning => scheme.error,
                  QuotaLevel.notice => Colors.orange,
                  QuotaLevel.normal => scheme.primary,
                },
                backgroundColor: scheme.surfaceContainerHighest,
              ),
              const SizedBox(height: 4),
              Text(
                l10n.quotaUsage(
                  formatBytes(stats.usedBytes),
                  formatBytes(stats.quotaBytes),
                ),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton(
                  onPressed: () => context.go(AppRoutes.list(list.id)),
                  child: Text(l10n.open),
                ),
                OutlinedButton(
                  onPressed: () => _editQuota(context, ref, stats),
                  child: Text(l10n.changeQuota),
                ),
                if (needsAdmin)
                  FilledButton(
                    onPressed: () => _assignAdmin(context, ref),
                    child: Text(l10n.assignListAdmin),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 容量上限を変更する（仕様書 7.2）。
  Future<void> _editQuota(
    BuildContext context,
    WidgetRef ref,
    ListStats? stats,
  ) async {
    final l10n = AppL10n.of(context);
    final current = (stats?.quotaBytes ?? kDefaultQuotaBytes) ~/ (1024 * 1024);
    final controller = TextEditingController(text: '$current');

    final value = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.changeQuota),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.changeQuotaBody(list.name)),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                suffixText: 'MB',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () {
              final mb = int.tryParse(controller.text.trim());
              Navigator.pop(context, (mb != null && mb > 0) ? mb : null);
            },
            child: Text(l10n.save),
          ),
        ],
      ),
    );
    if (value == null) return;

    try {
      await ref
          .read(functionsRepositoryProvider)
          .setListQuota(listId: list.id, quotaBytes: value * 1024 * 1024);
    } on FunctionsCallException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  /// 管理者不在のリストにリスト管理者を指名する（仕様書 5.6）。
  Future<void> _assignAdmin(BuildContext context, WidgetRef ref) async {
    final l10n = AppL10n.of(context);
    final users = await ref.read(siteUsersProvider.future);
    if (!context.mounted) return;

    final candidates = users.where((u) => !u.isWithdrawn).toList();

    final uid = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(l10n.assignListAdmin),
        children: [
          for (final user in candidates)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, user.uid),
              child: Text(
                user.displayName.isEmpty ? user.email : user.displayName,
              ),
            ),
        ],
      ),
    );
    if (uid == null) return;

    try {
      await ref
          .read(functionsRepositoryProvider)
          .assignListAdmin(listId: list.id, uid: uid);
    } on FunctionsCallException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }
}

// ---------------------------------------------------------------------------
// ユーザー管理（仕様書 4.4 / 4.5 / 11.1）
// ---------------------------------------------------------------------------

class SiteAdminUsersScreen extends ConsumerWidget {
  const SiteAdminUsersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final users = ref.watch(siteUsersProvider);

    return Scaffold(
      body: AsyncView(
        value: users,
        onRetry: () => ref.invalidate(siteUsersProvider),
        builder: (items) {
          final adminCount = items.where((u) => u.isSiteAdmin).length;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _SiteAdminHeader(title: l10n.siteAdminUsers),
              const SizedBox(height: 8),
              Text(
                l10n.siteAdminCountSummary(adminCount, items.length),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              for (final user in items)
                _SiteUserTile(user: user, siteAdminCount: adminCount),
            ],
          );
        },
      ),
    );
  }
}

class _SiteUserTile extends ConsumerWidget {
  const _SiteUserTile({required this.user, required this.siteAdminCount});

  final SiteUser user;
  final int siteAdminCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final scheme = Theme.of(context).colorScheme;

    // 最後の 1 人は降格できない（仕様書 4.5）。
    final isLastAdmin = user.isSiteAdmin && siteAdminCount <= 1;

    return ListTile(
      leading: Icon(
        user.isWithdrawn ? Icons.person_off_outlined : Icons.person_outline,
        color: user.isWithdrawn ? scheme.outline : null,
      ),
      title: Text(
        user.isWithdrawn
            ? l10n.withdrawnUser
            : (user.displayName.isEmpty ? user.email : user.displayName),
      ),
      subtitle: user.isWithdrawn ? null : Text(user.email),
      trailing: user.isWithdrawn
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (user.isSiteAdmin)
                  Chip(
                    visualDensity: VisualDensity.compact,
                    label: Text(l10n.roleSiteAdmin),
                    backgroundColor: scheme.primaryContainer,
                    side: BorderSide.none,
                  ),
                const SizedBox(width: 8),
                if (user.isSiteAdmin)
                  TextButton(
                    onPressed: isLastAdmin ? null : () => _revoke(context, ref),
                    child: Text(l10n.removeSiteAdmin),
                  )
                else
                  TextButton(
                    onPressed: () => _grant(context, ref),
                    child: Text(l10n.promoteToSiteAdmin),
                  ),
              ],
            ),
      // 最後の 1 人であることを、押せない理由として示す。
      isThreeLine: false,
      onTap: isLastAdmin
          ? () => ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(l10n.lastSiteAdminBlocked)))
          : null,
    );
  }

  Future<void> _grant(BuildContext context, WidgetRef ref) =>
      _run(context, ref, () async {
        await ref.read(functionsRepositoryProvider).grantSiteAdmin(user.uid);
        // 反映には対象ユーザーの再ログインが必要（仕様書 13.5）。
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(AppL10n.of(context).siteAdminGranted)),
          );
        }
      });

  Future<void> _revoke(BuildContext context, WidgetRef ref) =>
      _run(context, ref, () async {
        await ref.read(functionsRepositoryProvider).revokeSiteAdmin(user.uid);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(AppL10n.of(context).siteAdminRevoked)),
          );
        }
      });

  Future<void> _run(
    BuildContext context,
    WidgetRef ref,
    Future<void> Function() action,
  ) async {
    try {
      await action();
      ref.invalidate(siteUsersProvider);
    } on FunctionsCallException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }
}

// ---------------------------------------------------------------------------
// サイト設定（仕様書 11.1 / 13.3）
// ---------------------------------------------------------------------------

class SiteAdminSettingsScreen extends ConsumerStatefulWidget {
  const SiteAdminSettingsScreen({super.key});

  @override
  ConsumerState<SiteAdminSettingsScreen> createState() =>
      _SiteAdminSettingsScreenState();
}

class _SiteAdminSettingsScreenState
    extends ConsumerState<SiteAdminSettingsScreen> {
  final _inviteHours = TextEditingController();
  final _quotaMb = TextEditingController();
  final _graceDays = TextEditingController();
  bool _loaded = false;
  bool _busy = false;

  @override
  void dispose() {
    _inviteHours.dispose();
    _quotaMb.dispose();
    _graceDays.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final config = ref.watch(siteConfigProvider);

    return Scaffold(
      body: AsyncView(
        value: config,
        builder: (site) {
          if (!_loaded) {
            _loaded = true;
            _inviteHours.text = '${site.inviteExpiryHours}';
            _graceDays.text = '${site.itemPurgeGraceDays}';
            // **定数ではなく設定から読む。** 定数で埋めていたため、
            // 別の項目を直して保存するたびに容量上限が 1GB へ戻っていた
            // （監査 S10）。
            _quotaMb.text = '${site.defaultQuotaBytes ~/ (1024 * 1024)}';
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _SiteAdminHeader(title: l10n.siteAdminSettings),
              const SizedBox(height: 24),
              _SettingField(
                controller: _inviteHours,
                label: l10n.inviteExpiryLabel,
                suffix: l10n.unitHours,
                help: l10n.inviteExpiryHelp,
              ),
              _SettingField(
                controller: _quotaMb,
                label: l10n.defaultQuotaLabel,
                suffix: 'MB',
                help: l10n.defaultQuotaHelp,
              ),
              _SettingField(
                controller: _graceDays,
                label: l10n.purgeGraceLabel,
                suffix: l10n.unitDays,
                help: l10n.purgeGraceHelp,
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _busy ? null : _save,
                child: Text(l10n.save),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _save() async {
    final invite = int.tryParse(_inviteHours.text.trim());
    final quotaMb = int.tryParse(_quotaMb.text.trim());
    final grace = int.tryParse(_graceDays.text.trim());

    if (invite == null ||
        invite <= 0 ||
        quotaMb == null ||
        quotaMb <= 0 ||
        grace == null ||
        grace < 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(AppL10n.of(context).invalidNumber)));
      return;
    }

    setState(() => _busy = true);
    try {
      // siteAdminCount は Functions が持つため、ここでは触らない（仕様書 4.5）。
      await ref.read(firestoreProvider).doc('siteConfig/global').set({
        'inviteExpiryHours': invite,
        'defaultQuotaBytes': quotaMb * 1024 * 1024,
        'itemPurgeGraceDays': grace,
      }, SetOptions(merge: true));
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(AppL10n.of(context).saved)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppL10n.of(context).errorGeneric)),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _SettingField extends StatelessWidget {
  const _SettingField({
    required this.controller,
    required this.label,
    required this.suffix,
    required this.help,
  });

  final TextEditingController controller;
  final String label;
  final String suffix;
  final String help;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          labelText: label,
          suffixText: suffix,
          helperText: help,
          helperMaxLines: 3,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}
