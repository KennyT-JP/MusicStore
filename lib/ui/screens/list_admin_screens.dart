/// リスト管理の画面（仕様書 5.2 / 5.4 / 5.5 / 7.4 / 11.2 / 14.2）
///
/// - メンバー管理（役割の変更・除外・招待 URL の発行）
/// - 参加申請の承認
/// - リスト設定（容量の表示・リスト削除）
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/app_user.dart';
import '../../data/models/music_list.dart';
import '../../data/models/requests.dart';
import '../../data/repositories/functions_repository.dart';
import '../../domain/display_name.dart';
import '../../domain/permissions.dart';
import '../../domain/quota.dart';
import '../../domain/role.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/app_providers.dart';
import '../routes.dart';
import '../widgets/async_view.dart';
import '../widgets/error_message.dart';
import '../widgets/role_chip.dart';

// ---------------------------------------------------------------------------
// メンバー管理（仕様書 5.4 / 11.2）
// ---------------------------------------------------------------------------

class ListMembersScreen extends ConsumerWidget {
  const ListMembersScreen({super.key, required this.listId});

  final String listId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final members = ref.watch(listMembersProvider(listId));
    final access = ref.watch(listAccessProvider(listId));
    final myUid = ref.watch(firebaseUserProvider).value?.uid ?? '';

    return Scaffold(
      body: AsyncView(
        value: members,
        onRetry: () => ref.invalidate(listMembersProvider(listId)),
        builder: (list) {
          final uids = list.map((m) => m.uid).toSet();
          final users =
              ref.watch(userDirectoryProvider(userDirectoryKey(uids))).value ?? const {};

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _AdminHeader(listId: listId, title: l10n.manageMembers),
              const SizedBox(height: 16),
              _InviteSection(listId: listId),
              const Divider(height: 32),
              Text(
                '${l10n.members}（${list.length}）',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              for (final member in list)
                _MemberTile(
                  listId: listId,
                  member: member,
                  user: users[member.uid],
                  canManage: Permissions.canManageMembers(access),
                  canRemove: Permissions.canRemoveMember(
                    access,
                    viewerUid: myUid,
                    targetUid: member.uid,
                  ),
                  isSelf: member.uid == myUid,
                ),
            ],
          );
        },
      ),
    );
  }
}

/// リスト管理画面の共通ヘッダ。
class _AdminHeader extends ConsumerWidget {
  const _AdminHeader({required this.listId, required this.title});

  final String listId;
  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = ref.watch(listProvider(listId)).value?.name ?? '';

    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go(AppRoutes.list(listId)),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              if (name.isNotEmpty)
                Text(name, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ],
    );
  }
}

/// 招待 URL の発行（仕様書 3.3）。
class _InviteSection extends ConsumerStatefulWidget {
  const _InviteSection({required this.listId});

  final String listId;

  @override
  ConsumerState<_InviteSection> createState() => _InviteSectionState();
}

class _InviteSectionState extends ConsumerState<_InviteSection> {
  ListRole _role = ListRole.superUser;
  bool _busy = false;
  String? _error;
  String? _inviteUrl;
  String? _inviteId;
  DateTime? _expiresAt;

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.createInvite, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (_error != null) ...[
          ErrorMessage(_error!),
          const SizedBox(height: 8),
        ],
        Row(
          children: [
            // 招待時に付与する役割をあらかじめ指定する（仕様書 3.3）。
            // リスト管理者は招待では付与できない。
            SegmentedButton<ListRole>(
              segments: [
                ButtonSegment(
                  value: ListRole.superUser,
                  label: Text(l10n.roleSuperUser),
                ),
                ButtonSegment(
                  value: ListRole.readOnly,
                  label: Text(l10n.roleReadOnly),
                ),
              ],
              selected: {_role},
              onSelectionChanged: (s) => setState(() => _role = s.first),
            ),
            const SizedBox(width: 12),
            FilledButton(
              onPressed: _busy ? null : _create,
              child: Text(l10n.createInvite),
            ),
          ],
        ),
        if (_inviteUrl != null) ...[
          const SizedBox(height: 12),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectableText(
                    _inviteUrl!,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    // 有効期限は受諾した時点で判定される（仕様書 3.3）。
                    l10n.inviteExpiryNote(_formatDateTime(_expiresAt!)),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 4),
                  // **取消の導線（仕様書 3.3）。** revokeInvite は実装済み
                  // だったが、画面から呼ぶ場所が無かった（監査 S16）。
                  // 誤って渡した URL を無効にできないと、取り消す手段が
                  // 「期限切れを待つ」しかなくなる。
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _busy ? null : _revoke,
                      icon: const Icon(Icons.link_off),
                      label: Text(l10n.revokeInvite),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// 発行した招待 URL を無効にする（仕様書 3.3）。
  Future<void> _revoke() async {
    final id = _inviteId;
    if (id == null) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(functionsRepositoryProvider).revokeInvite(id);
      if (mounted) {
        setState(() {
          _inviteUrl = null;
          _inviteId = null;
          _expiresAt = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppL10n.of(context).inviteRevoked)),
        );
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is FunctionsCallException
              ? error.message
              : AppL10n.of(context).errorGeneric,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _create() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await ref
          .read(functionsRepositoryProvider)
          .createInvite(listId: widget.listId, role: _role);

      if (mounted) {
        setState(() {
          _inviteUrl = buildShareUrl(AppRoutes.invite(result.inviteId));
          _inviteId = result.inviteId;
          _expiresAt = result.expiresAt;
        });
      }
    } on FunctionsCallException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = AppL10n.of(context).errorGeneric);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _MemberTile extends ConsumerWidget {
  const _MemberTile({
    required this.listId,
    required this.member,
    required this.user,
    required this.canManage,
    required this.canRemove,
    required this.isSelf,
  });

  final String listId;
  final ListMember member;
  final AppUser? user;
  final bool canManage;
  final bool canRemove;
  final bool isSelf;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);

    final resolved = DisplayNameResolver.resolveInList(
      uid: member.uid,
      user: user == null
          ? null
          : UserNameSource(
              displayName: user!.displayName,
              isWithdrawn: user!.isWithdrawn,
            ),
      // メンバー一覧なので、メンバー判定は不要（全員が現メンバー）。
      currentMemberUids: null,
      withdrawnLabel: l10n.withdrawnUser,
    );

    return ListTile(
      leading: const Icon(Icons.person_outline),
      title: Text(resolved.text),
      subtitle: user?.email.isNotEmpty == true ? Text(user!.email) : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          RoleChip(role: member.role),
          if (canManage && !isSelf)
            PopupMenuButton<String>(
              onSelected: (value) => _onSelected(context, ref, value),
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'listAdmin',
                  child: Text('${l10n.changeRole}：${l10n.roleListAdmin}'),
                ),
                PopupMenuItem(
                  value: 'superUser',
                  child: Text('${l10n.changeRole}：${l10n.roleSuperUser}'),
                ),
                PopupMenuItem(
                  value: 'readOnly',
                  child: Text('${l10n.changeRole}：${l10n.roleReadOnly}'),
                ),
                if (canRemove)
                  PopupMenuItem(
                    value: 'remove',
                    child: Text(l10n.removeMember),
                  ),
              ],
            ),
          // 自分からリストを抜ける（仕様書 5.4）。
          if (isSelf)
            TextButton(
              onPressed: () => _confirmLeave(context, ref),
              child: Text(l10n.leaveList),
            ),
        ],
      ),
    );
  }

  Future<void> _onSelected(
    BuildContext context,
    WidgetRef ref,
    String value,
  ) async {
    final repo = ref.read(listRepositoryProvider);
    if (value == 'remove') {
      final l10n = AppL10n.of(context);
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l10n.removeMember),
          // 除外しても投稿は残る（仕様書 5.4）。
          content: Text(
l10n.removeMemberBody,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(l10n.removeMember),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      await repo.removeMember(listId, member.uid);
    } else {
      await repo.updateMemberRole(listId, member.uid, value);
    }
  }

  Future<void> _confirmLeave(BuildContext context, WidgetRef ref) async {
    final l10n = AppL10n.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.leaveList),
        content: Text(
l10n.leaveListBody,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.leaveList),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(listRepositoryProvider).removeMember(listId, member.uid);
    if (context.mounted) context.go(AppRoutes.home);
  }
}

// ---------------------------------------------------------------------------
// 参加申請の承認（仕様書 5.2）
// ---------------------------------------------------------------------------

class ListJoinRequestsScreen extends ConsumerWidget {
  const ListJoinRequestsScreen({super.key, required this.listId});

  final String listId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final requests = ref.watch(pendingJoinRequestsProvider(listId));

    return Scaffold(
      body: AsyncView(
        value: requests,
        onRetry: () => ref.invalidate(pendingJoinRequestsProvider(listId)),
        builder: (items) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _AdminHeader(listId: listId, title: l10n.joinRequests),
              const SizedBox(height: 16),
              if (items.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Center(child: Text(l10n.noPendingRequests)),
                ),
              for (final request in items) _JoinRequestCard(request: request),
            ],
          );
        },
      ),
    );
  }
}

class _JoinRequestCard extends ConsumerWidget {
  const _JoinRequestCard({required this.request});

  final JoinRequest request;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final users = ref.watch(userDirectoryProvider(userDirectoryKey([request.uid]))).value;
    final user = users?[request.uid];

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              user?.displayName ?? request.uid,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (user?.email.isNotEmpty == true)
              Text(user!.email, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 16),
            // 承認時に役割を決める。申請者は選べない（仕様書 5.2）。
            Text(
              l10n.chooseApprovalRole,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                FilledButton(
                  onPressed: () => _approve(context, ref, ListRole.superUser),
                  child: Text('${l10n.approve}：${l10n.roleSuperUser}'),
                ),
                FilledButton.tonal(
                  onPressed: () => _approve(context, ref, ListRole.readOnly),
                  child: Text('${l10n.approve}：${l10n.roleReadOnly}'),
                ),
                TextButton(
                  onPressed: () => _reject(context, ref),
                  child: Text(l10n.reject),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _approve(
    BuildContext context,
    WidgetRef ref,
    ListRole role,
  ) async {
    try {
      await ref
          .read(functionsRepositoryProvider)
          .approveJoinRequest(
            listId: request.listId,
            uid: request.uid,
            role: role,
          );
    } on FunctionsCallException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  Future<void> _reject(BuildContext context, WidgetRef ref) async {
    // 却下しても申請者には通知しない（仕様書 5.2.1）。
    try {
      await ref
          .read(functionsRepositoryProvider)
          .rejectJoinRequest(listId: request.listId, uid: request.uid);
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
// リスト設定（仕様書 5.5 / 7.4）
// ---------------------------------------------------------------------------

class ListSettingsScreen extends ConsumerWidget {
  const ListSettingsScreen({super.key, required this.listId});

  final String listId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final stats = ref.watch(listStatsProvider(listId)).value;
    final access = ref.watch(listAccessProvider(listId));

    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _AdminHeader(listId: listId, title: l10n.listSettings),
          const SizedBox(height: 24),

          // 容量使用量（仕様書 7.4）。
          if (stats != null) _QuotaCard(stats: stats),

          const SizedBox(height: 24),
          _ShareUrlCard(listId: listId),

          if (Permissions.canDeleteList(access)) ...[
            const Divider(height: 48),
            Text(
              l10n.deleteList,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.deleteListWarning,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
              onPressed: () => _confirmDelete(context, ref),
              child: Text(l10n.deleteList),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final l10n = AppL10n.of(context);
    final name = ref.read(listProvider(listId)).value?.name ?? '';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.deleteList),
        // バックアップを持たないため、復旧できないことを明示する（仕様書 12.3）。
        content: Text(
          '${l10n.deleteListBody(name)}\n\n${l10n.deleteListWarning}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.deleteList),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await ref.read(listRepositoryProvider).deleteList(listId);
    if (context.mounted) context.go(AppRoutes.home);
  }
}

class _QuotaCard extends StatelessWidget {
  const _QuotaCard({required this.stats});

  final ListStats stats;

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final quota = stats.quota;
    final scheme = Theme.of(context).colorScheme;

    final color = switch (quota.level) {
      QuotaLevel.warning => scheme.error,
      QuotaLevel.notice => Colors.orange,
      QuotaLevel.normal => scheme.primary,
    };

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.usedCapacity, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: quota.ratio.clamp(0.0, 1.0),
              color: color,
              backgroundColor: scheme.surfaceContainerHighest,
            ),
            const SizedBox(height: 8),
            Text(
              l10n.quotaUsage(
                formatBytes(quota.usedBytes),
                formatBytes(quota.quotaBytes),
              ),
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: color),
            ),
            const SizedBox(height: 4),
            Text(
              l10n.quotaRemaining(formatBytes(quota.remainingBytes)),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (quota.level != QuotaLevel.normal) ...[
              const SizedBox(height: 12),
              Text(
                quota.level == QuotaLevel.warning
                    ? l10n.quotaOver90
                    : l10n.quotaOver80,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: color),
              ),
            ],
            const SizedBox(height: 12),
            Text(
              // 猶予期間中は容量が減らない（仕様書 6.3 / 13.4）。
              l10n.quotaGraceNote,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

/// 共有 URL（仕様書 5.3）。
class _ShareUrlCard extends StatelessWidget {
  const _ShareUrlCard({required this.listId});

  final String listId;

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final url = buildShareUrl(AppRoutes.list(listId));

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.shareUrl, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            SelectableText(url, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            Text(
              // 未参加者が開くと参加申請の画面になる（仕様書 5.3）。
              l10n.shareUrlNote,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

/// アプリ内のパスから、人に渡せる URL を組み立てる（仕様書 5.3 / 3.3）。
///
/// Flutter Web は既定でハッシュ方式の URL を使うため、`#` を挟む。
String buildShareUrl(String path) {
  final base = Uri.base;
  return '${base.origin}${base.path}#$path';
}

/// 投稿日時などのシステム日時は、見る人の現地時刻で表示する（仕様書 6.2）。
String _formatDateTime(DateTime value) {
  final local = value.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${local.year}/${two(local.month)}/${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}
