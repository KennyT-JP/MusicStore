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
import '../../domain/permissions.dart';
import '../../domain/role.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/app_providers.dart';
import '../routes.dart';
import '../widgets/async_view.dart';
import '../widgets/error_message.dart';

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
        ).showSnackBar(SnackBar(content: Text(describeFunctionsError(context, e))));
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
        ).showSnackBar(SnackBar(content: Text(describeFunctionsError(context, e))));
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
        ).showSnackBar(SnackBar(content: Text(describeFunctionsError(context, e))));
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addUser(context, ref),
        icon: const Icon(Icons.person_add_outlined),
        label: Text(l10n.addUser),
      ),
    );
  }

  Future<void> _addUser(BuildContext context, WidgetRef ref) async {
    final added = await showDialog<bool>(
      context: context,
      builder: (_) => const _AddUserDialog(),
    );
    if (added != true) return;
    ref.invalidate(siteUsersProvider);
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(AppL10n.of(context).userAdded)));
    }
  }
}

/// ユーザーを追加する入力欄（仕様書 11.1）。
///
/// **パスワードはサイト管理者が決める**（2026-08-09 の依頼者指示）。
/// 決めた本人が知っている状態になるため、**渡したあとで本人に変えて
/// もらう**ことを画面に書いてある。
class _AddUserDialog extends ConsumerStatefulWidget {
  const _AddUserDialog();

  @override
  ConsumerState<_AddUserDialog> createState() => _AddUserDialogState();
}

class _AddUserDialogState extends ConsumerState<_AddUserDialog> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _displayName = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _displayName.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);

    return AlertDialog(
      title: Text(l10n.addUser),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.addUserBody,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              if (_error != null) ...[
                ErrorMessage(_error!),
                const SizedBox(height: 12),
              ],
              TextFormField(
                controller: _email,
                decoration: InputDecoration(labelText: l10n.emailLabel),
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? l10n.emailRequired : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _displayName,
                decoration: InputDecoration(
                  labelText: l10n.displayName,
                  helperText: l10n.displayNameHelper,
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? l10n.displayNameRequired
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _password,
                decoration: InputDecoration(
                  labelText: l10n.passwordLabel,
                  helperText: l10n.passwordHelper,
                ),
                obscureText: true,
                validator: (v) {
                  if (v == null || v.isEmpty) return l10n.passwordRequired;
                  if (v.length < 6) return l10n.passwordTooShort;
                  return null;
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: Text(l10n.addUserSubmit),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(functionsRepositoryProvider)
          .createSiteUser(
            email: _email.text.trim(),
            password: _password.text,
            displayName: _displayName.text.trim(),
          );
      if (mounted) Navigator.of(context).pop(true);
    } on FunctionsCallException catch (e) {
      // **理由を出す。** 「追加できませんでした」だけでは、
      // メールアドレスの重複なのか形式違いなのか分からない。
      if (mounted) {
        setState(() => _error = describeFunctionsError(context, e));
      }
    } catch (_) {
      if (mounted) setState(() => _error = AppL10n.of(context).errorGeneric);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
    // **判定は domain/permissions.dart に置いてある。**
    // 以前はここに同じ式を直接書いており、テストされている
    // canStepDownAsSiteAdmin は本番から呼ばれていなかった（監査 第2回）。
    final isLastAdmin = !Permissions.canStepDownAsSiteAdmin(
      isSiteAdmin: user.isSiteAdmin,
      siteAdminCount: siteAdminCount,
    );

    // **無効にされた人は、退会した人とは別に見せる。**
    // 退会は本人の意思、無効はサイト管理者の判断で、戻し方も違う。
    final isDisabled = user.isDisabled;

    return ListTile(
      leading: Icon(
        isDisabled
            ? Icons.block
            : (user.isWithdrawn
                  ? Icons.person_off_outlined
                  : Icons.person_outline),
        color: (isDisabled || user.isWithdrawn) ? scheme.outline : null,
      ),
      title: Text(
        (user.isWithdrawn && !isDisabled)
            ? l10n.withdrawnUser
            : (user.displayName.isEmpty ? user.email : user.displayName),
      ),
      subtitle: (user.isWithdrawn && !isDisabled) ? null : Text(user.email),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isDisabled)
            Chip(
              visualDensity: VisualDensity.compact,
              label: Text(l10n.userDisabledLabel),
              backgroundColor: scheme.surfaceContainerHighest,
              side: BorderSide.none,
            ),
          if (user.isSiteAdmin && !isDisabled)
            Chip(
              visualDensity: VisualDensity.compact,
              label: Text(l10n.roleSiteAdmin),
              backgroundColor: scheme.primaryContainer,
              side: BorderSide.none,
            ),
          const SizedBox(width: 8),
          if (!user.isWithdrawn && !isDisabled)
            (user.isSiteAdmin
                ? TextButton(
                    onPressed: isLastAdmin ? null : () => _revoke(context, ref),
                    child: Text(l10n.removeSiteAdmin),
                  )
                : TextButton(
                    onPressed: () => _grant(context, ref),
                    child: Text(l10n.promoteToSiteAdmin),
                  )),
          // 無効化・有効化・削除（仕様書 11.1）。
          //
          // **消す操作は、押しやすい場所に置かない。** 役割の変更と
          // 並べると押し間違える。メニューの中に入れ、確認も挟む。
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) => switch (value) {
              'addToList' => _addToList(context, ref),
              'disable' => _confirmDisable(context, ref),
              'enable' => _confirmEnable(context, ref),
              _ => _confirmDelete(context, ref),
            },
            itemBuilder: (_) => [
              // リストに加える（仕様書 5.7）。
              //
              // **退会した人と無効にした人には出さない。** サーバー側でも
              // 断るが、押せてしまうと「なぜ失敗したのか」を押した後に
              // 知ることになる。
              if (!user.isWithdrawn && !isDisabled)
                PopupMenuItem(
                  value: 'addToList',
                  child: Text(l10n.addToList),
                ),
              if (isDisabled)
                PopupMenuItem(value: 'enable', child: Text(l10n.enableUser))
              else
                PopupMenuItem(value: 'disable', child: Text(l10n.disableUser)),
              PopupMenuItem(
                value: 'delete',
                child: Text(
                  l10n.deleteUser,
                  style: TextStyle(color: scheme.error),
                ),
              ),
            ],
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

  /// 一覧に出している名前。確認の文に差し込む。
  String _name(AppL10n l10n) =>
      user.displayName.isEmpty ? user.email : user.displayName;

  /// 無効にする（仕様書 11.1）。**戻せる。**
  Future<void> _confirmDisable(BuildContext context, WidgetRef ref) async {
    final l10n = AppL10n.of(context);
    final ok = await _confirm(
      context,
      title: l10n.disableUser,
      body: l10n.disableUserBody(_name(l10n)),
      danger: false,
    );
    if (!ok || !context.mounted) return;
    await _run(context, ref, () async {
      await ref.read(functionsRepositoryProvider).disableSiteUser(user.uid);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppL10n.of(context).userDisabled)),
        );
      }
    });
  }

  /// 有効に戻す（仕様書 11.1）。
  Future<void> _confirmEnable(BuildContext context, WidgetRef ref) async {
    final l10n = AppL10n.of(context);
    final ok = await _confirm(
      context,
      title: l10n.enableUser,
      body: l10n.enableUserBody(_name(l10n)),
      danger: false,
    );
    if (!ok || !context.mounted) return;
    await _run(context, ref, () async {
      await ref.read(functionsRepositoryProvider).enableSiteUser(user.uid);
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(AppL10n.of(context).userEnabled)));
      }
    });
  }

  /// 削除する（仕様書 11.1）。**戻せない。**
  ///
  /// 何が消えて何が残るかを、押す前に全部書く。
  /// 「無効にするだけならデータは残る」ことも併せて示し、
  /// **取り返しのつく道があることを、選べるようにしておく。**
  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final l10n = AppL10n.of(context);
    final ok = await _confirm(
      context,
      title: l10n.deleteUser,
      body: l10n.deleteUserBody(_name(l10n)),
      danger: true,
    );
    if (!ok || !context.mounted) return;
    await _run(context, ref, () async {
      await ref.read(functionsRepositoryProvider).deleteSiteUser(user.uid);
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(AppL10n.of(context).userDeleted)));
      }
    });
  }

  Future<bool> _confirm(
    BuildContext context, {
    required String title,
    required String body,
    required bool danger,
  }) async {
    final l10n = AppL10n.of(context);
    final scheme = Theme.of(context).colorScheme;
    final answer = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(child: Text(body)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            style: danger
                ? FilledButton.styleFrom(
                    backgroundColor: scheme.error,
                    foregroundColor: scheme.onError,
                  )
                : null,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(title),
          ),
        ],
      ),
    );
    return answer ?? false;
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

  /// リストに加える（仕様書 5.7）。
  ///
  /// **リストを選ぶ → 役割を選ぶ**の2段。役割を既定にしないのは、
  /// 加える人が曲を足せるのか見るだけなのかを、こちらが推測しては
  /// いけないため（承認のとき・5.2 と同じ考え方）。
  ///
  /// **すでにメンバーかどうかは、ここでは調べない。** 調べるには
  /// リストの数だけ読み取りが要るうえ、読んだ後に他の人が入れれば
  /// どのみち食い違う。**サーバーが断り、その理由をここで出す。**
  Future<void> _addToList(BuildContext context, WidgetRef ref) async {
    final l10n = AppL10n.of(context);
    final lists = ref.read(allListsProvider).value ?? const <MusicList>[];

    if (lists.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.addToListEmpty)));
      return;
    }

    final listId = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(l10n.addToListTitle(_name(l10n))),
        children: [
          // 数が増えても選べるように、高さを決めて中でスクロールさせる。
          SizedBox(
            width: 360,
            height: 320,
            child: ListView.builder(
              itemCount: lists.length,
              itemBuilder: (_, i) => ListTile(
                title: Text(lists[i].name),
                onTap: () => Navigator.of(dialogContext).pop(lists[i].id),
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(right: 8, top: 4),
              child: TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text(l10n.cancel),
              ),
            ),
          ),
        ],
      ),
    );
    if (listId == null || !context.mounted) return;

    final role = await showDialog<ListRole>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(lists.firstWhere((l) => l.id == listId).name),
        content: Text(l10n.chooseApprovalRole),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.cancel),
          ),
          FilledButton.tonal(
            onPressed: () =>
                Navigator.of(dialogContext).pop(ListRole.readOnly),
            child: Text(l10n.addAs(l10n.roleReadOnly)),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(ListRole.superUser),
            child: Text(l10n.addAs(l10n.roleSuperUser)),
          ),
        ],
      ),
    );
    if (role == null || !context.mounted) return;

    final name = lists.firstWhere((l) => l.id == listId).name;
    await _run(context, ref, () async {
      await ref
          .read(functionsRepositoryProvider)
          .addListMember(listId: listId, uid: user.uid, role: role);
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.addToListDone(name))));
      }
    });
  }

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
        ).showSnackBar(SnackBar(content: Text(describeFunctionsError(context, e))));
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
  final _quotaMb = TextEditingController();
  final _graceDays = TextEditingController();
  bool _loaded = false;
  bool _busy = false;

  @override
  void dispose() {
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
    final quotaMb = int.tryParse(_quotaMb.text.trim());
    final grace = int.tryParse(_graceDays.text.trim());

    if (quotaMb == null ||
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
