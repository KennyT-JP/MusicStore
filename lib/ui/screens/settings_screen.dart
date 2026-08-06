/// 設定（仕様書 3.4 / 3.5 / 10.3 / 14.2）
///
/// 表示名の変更、表示言語、通知設定、退会。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/app_user.dart';
import '../../data/repositories/functions_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/app_providers.dart';
import '../widgets/async_view.dart';
import '../widgets/error_message.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentAppUserProvider);

    return Scaffold(
      body: AsyncView(
        value: user,
        builder: (appUser) {
          if (appUser == null) {
            return const Center(child: CircularProgressIndicator());
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _DisplayNameSection(user: appUser),
              const Divider(height: 32),
              _LanguageSection(user: appUser),
              const Divider(height: 32),
              _NotificationSection(user: appUser),
              const Divider(height: 32),
              const _AccountSection(),
            ],
          );
        },
      ),
    );
  }
}

/// 表示名の変更（仕様書 3.4）。
class _DisplayNameSection extends ConsumerStatefulWidget {
  const _DisplayNameSection({required this.user});

  final AppUser user;

  @override
  ConsumerState<_DisplayNameSection> createState() =>
      _DisplayNameSectionState();
}

class _DisplayNameSectionState extends ConsumerState<_DisplayNameSection> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.user.displayName,
  );
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final changed = _controller.text.trim() != widget.user.displayName;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.displayName, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: (!changed || _busy) ? null : _save,
              child: Text(l10n.save),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _save() async {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(listRepositoryProvider)
          .updateDisplayName(widget.user.uid, name);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

/// 表示言語（仕様書 2 章）。
class _LanguageSection extends ConsumerWidget {
  const _LanguageSection({required this.user});

  final AppUser user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.language, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'ja', label: Text('日本語')),
            ButtonSegment(value: 'en', label: Text('English')),
          ],
          selected: {user.locale},
          onSelectionChanged: (selection) => ref
              .read(listRepositoryProvider)
              .updateLocale(user.uid, selection.first),
        ),
      ],
    );
  }
}

/// 通知設定（仕様書 10.3）。
///
/// プッシュ通知は初期リリースでは画面に出さない（仕様書 12.7）。
/// データとしては保持しているので、ここでは触らずそのまま残す。
class _NotificationSection extends ConsumerWidget {
  const _NotificationSection({required this.user});

  final AppUser user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final settings = user.notificationSettings;

    Future<void> save(NotificationSettings next) => ref
        .read(listRepositoryProvider)
        .updateNotificationSettings(user.uid, next);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.notificationSettings,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),

        // マスタースイッチ。オフにすると種別ごとの設定は効かなくなる。
        SwitchListTile(
          title: Text(l10n.notificationMaster),
          value: settings.master,
          onChanged: (value) => save(settings.copyWith(master: value)),
        ),
        const Divider(height: 1),

        for (final type in NotificationType.values)
          SwitchListTile(
            title: Text(_labelFor(l10n, type)),
            // どんなときに届くのかを書き添える。種別の名前だけでは
            // 「自分に届くのか」が分からず、切り替える判断ができない。
            subtitle: Text(
              _detailFor(l10n, type),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            isThreeLine: false,
            value: settings.settingFor(type).inApp,
            // マスターがオフなら個別の切り替えは意味がないので無効にする。
            onChanged: settings.master
                ? (value) => save(
                    settings.withType(
                      type,
                      settings.settingFor(type).copyWith(inApp: value),
                    ),
                  )
                : null,
          ),
      ],
    );
  }

  static String _labelFor(AppL10n l10n, NotificationType type) =>
      switch (type) {
        NotificationType.itemAdded => l10n.notifyItemAdded,
        NotificationType.commentAdded => l10n.notifyCommentAdded,
        NotificationType.quotaNotice => l10n.notifyQuotaNotice,
        NotificationType.quotaWarning => l10n.notifyQuotaWarning,
        NotificationType.listRequested => l10n.notifyListRequested,
        NotificationType.joinRequested => l10n.notifyJoinRequested,
        NotificationType.requestApproved => l10n.notifyRequestApproved,
      };

  /// その通知がどんなときに届くか（仕様書 10.2 の受信者）。
  static String _detailFor(AppL10n l10n, NotificationType type) =>
      switch (type) {
        NotificationType.itemAdded => l10n.notifyItemAddedDetail,
        NotificationType.commentAdded => l10n.notifyCommentAddedDetail,
        NotificationType.quotaNotice => l10n.notifyQuotaNoticeDetail,
        NotificationType.quotaWarning => l10n.notifyQuotaWarningDetail,
        NotificationType.listRequested => l10n.notifyListRequestedDetail,
        NotificationType.joinRequested => l10n.notifyJoinRequestedDetail,
        NotificationType.requestApproved => l10n.notifyRequestApprovedDetail,
      };
}

/// ログアウトと退会（仕様書 3.5 / 4.5）。
class _AccountSection extends ConsumerStatefulWidget {
  const _AccountSection();

  @override
  ConsumerState<_AccountSection> createState() => _AccountSectionState();
}

class _AccountSectionState extends ConsumerState<_AccountSection> {
  bool _busy = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_error != null) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              _error!,
              style: TextStyle(color: theme.colorScheme.onErrorContainer),
            ),
          ),
          const SizedBox(height: 16),
        ],
        OutlinedButton.icon(
          icon: const Icon(Icons.logout),
          label: Text(l10n.signOut),
          onPressed: _busy
              ? null
              : () => ref.read(authRepositoryProvider).signOut(),
        ),
        const SizedBox(height: 24),
        Text(
          l10n.withdraw,
          style: theme.textTheme.titleMedium?.copyWith(
            color: theme.colorScheme.error,
          ),
        ),
        const SizedBox(height: 8),
        Text(l10n.withdrawWarning, style: theme.textTheme.bodySmall),
        const SizedBox(height: 8),
        OutlinedButton(
          style: OutlinedButton.styleFrom(
            foregroundColor: theme.colorScheme.error,
          ),
          onPressed: _busy ? null : _confirmWithdraw,
          child: Text(l10n.withdraw),
        ),
      ],
    );
  }

  Future<void> _confirmWithdraw() async {
    final l10n = AppL10n.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.withdraw),
        content: Text('${l10n.withdrawWarning}\n\n${l10n.withdrawIrreversible}'),
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
            child: Text(l10n.withdraw),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(functionsRepositoryProvider).withdrawAccount();
      // 退会するとアカウントが消えるため、ルーターがログイン画面へ送る。
    } on FunctionsCallException catch (e) {
      // 最後のサイト管理者は退会できない（仕様書 4.5）。
      if (mounted) setState(() => _error = describeFunctionsError(context, e));
    } catch (_) {
      if (mounted) setState(() => _error = AppL10n.of(context).errorGeneric);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
