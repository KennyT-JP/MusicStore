/// 設定（仕様書 3.4 / 3.5 / 10.3 / 14.2）
///
/// 表示名の変更、表示言語、通知設定、クーポンの入力、容量、退会。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/app_user.dart';
import '../../data/repositories/functions_repository.dart';
import '../../domain/premium.dart';
import '../../domain/quota.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/app_providers.dart';
import '../format.dart';
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
              // **通知の下に置く。** 上に挟むと、通知の設定が画面の外へ
              // 押し出される。よく触る設定ほど上に残す。
              _PremiumSection(user: appUser),
              const Divider(height: 32),
              _StorageSection(user: appUser),
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

/// プレミアムとクーポン（docs/PREMIUM-DESIGN.md 5）。
///
/// **いつまでプレミアムかを、必ず出す。** 「プレミアムです」とだけ書くと、
/// 切れる日が分からず、切れたあとに「勝手に解約された」と読まれる。
///
/// クーポンの失敗は**原因ごとに文言を変える**（error_message.dart）。
/// 打ち直せば直るのか、配布元に聞くしかないのかが、利用者にとって別物
/// だからである。
class _PremiumSection extends ConsumerStatefulWidget {
  const _PremiumSection({required this.user});

  final AppUser user;

  @override
  ConsumerState<_PremiumSection> createState() => _PremiumSectionState();
}

class _PremiumSectionState extends ConsumerState<_PremiumSection> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;

  /// 引き換えに成功したときの期限。
  ///
  /// **ユーザー文書の更新を待たずに出す。** サーバーが書いた値が
  /// Firestore の購読で降りてくるまでには間があり、その間に
  /// 「適用できたのかどうか分からない」時間が生まれる。
  DateTime? _redeemedUntil;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final theme = Theme.of(context);
    final until = widget.user.premiumUntil;
    final isPremium = PremiumPolicy.isActive(until);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.premiumSection, style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),

        if (isPremium && until != null)
          Text(l10n.premiumActiveUntil(formatDateTime(until)))
        else ...[
          Text(l10n.premiumInactive),
          const SizedBox(height: 4),
          // 期限が切れても消えないことを、ここで書いておく（設計 D3）。
          Text(l10n.premiumInactiveNote, style: theme.textTheme.bodySmall),
        ],

        if (_redeemedUntil case final redeemed?) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              l10n.couponRedeemed(formatDateTime(redeemed)),
              style: TextStyle(color: theme.colorScheme.onPrimaryContainer),
            ),
          ),
        ],

        if (_error case final error?) ...[
          const SizedBox(height: 12),
          ErrorMessage(error),
        ],

        const SizedBox(height: 12),
        // **縦に積む。** コードは 24 文字あり、狭い画面で入力欄とボタンを
        // 横に並べると入力欄がほとんど残らない（サイト管理の一覧で
        // 同じ形の崩れが起きた／2026-08-10）。
        TextField(
          controller: _code,
          decoration: InputDecoration(
            labelText: l10n.couponCodeLabel,
            border: const OutlineInputBorder(),
            isDense: true,
          ),
          onSubmitted: _busy ? null : (_) => _redeem(),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton(
            onPressed: _busy ? null : _redeem,
            child: Text(l10n.couponRedeem),
          ),
        ),
      ],
    );
  }

  Future<void> _redeem() async {
    final l10n = AppL10n.of(context);
    final code = PremiumPolicy.normalizeCouponCode(_code.text);
    if (code.isEmpty) {
      setState(() {
        _error = l10n.couponCodeRequired;
        _redeemedUntil = null;
      });
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
      _redeemedUntil = null;
    });
    try {
      final until = await ref
          .read(functionsRepositoryProvider)
          .redeemCoupon(code);
      if (!mounted) return;
      setState(() {
        _redeemedUntil = until;
        _code.clear();
      });
    } on FunctionsCallException catch (e) {
      // **原因が分かる文言に変える。** 汎用の文言に落とすと、
      // 打ち間違いなのか止められたクーポンなのか区別できない。
      if (mounted) setState(() => _error = describeFunctionsError(context, e));
    } catch (_) {
      // 通信の失敗など。黙って何も起きないようにはしない（監査 第4回）。
      if (mounted) setState(() => _error = AppL10n.of(context).errorGeneric);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

/// 自分の合計の容量（設計 D5 の補足）。
///
/// **上限は人ごとの合計に対してかかる。** リストごとではないことを
/// 書き添えないと、リストを増やせば増えると誤解される。
class _StorageSection extends StatelessWidget {
  const _StorageSection({required this.user});

  final AppUser user;

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final theme = Theme.of(context);
    final storage = user.storage;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.myStorageTitle, style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),

        // **届く前に 0 と書かない。** まだ集計されていないことと、
        // 使っていないことは別（docs/AUDIT-CHECKLIST.md 観点 2）。
        if (storage == null)
          Text(l10n.myStorageUnknown, style: theme.textTheme.bodySmall)
        else ...[
          Builder(
            builder: (context) {
              final quota = storage.quota;
              final color = switch (quota.level) {
                QuotaLevel.warning => theme.colorScheme.error,
                QuotaLevel.notice => Colors.orange,
                QuotaLevel.normal => theme.colorScheme.primary,
              };
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LinearProgressIndicator(
                    value: quota.ratio.clamp(0.0, 1.0),
                    color: color,
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.quotaUsage(
                      formatBytes(quota.usedBytes),
                      formatBytes(quota.quotaBytes),
                    ),
                    style: theme.textTheme.bodyMedium?.copyWith(color: color),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l10n.quotaRemaining(formatBytes(quota.remainingBytes)),
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              );
            },
          ),
        ],
        const SizedBox(height: 8),
        Text(l10n.myStorageNote, style: theme.textTheme.bodySmall),
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
