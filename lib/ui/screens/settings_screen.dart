/// 設定（仕様書 3.4 / 3.5 / 10.3 / 14.2）
///
/// 表示名の変更、表示言語、通知設定、クーポンの入力、容量、退会。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:go_router/go_router.dart';

import '../../data/models/app_user.dart';
import '../../data/repositories/functions_repository.dart';
import '../../domain/premium.dart';
import '../../domain/quota.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/app_providers.dart';
import '../../providers/download_provider.dart';
import '../downloads/download_support.dart';
import '../format.dart';
import '../routes.dart';
import '../widgets/async_view.dart';
import '../widgets/download_button.dart';
import '../widgets/error_message.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentAppUserProvider);
    final private = ref.watch(currentUserPrivateProvider);

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
              // 表示言語・通知・プレミアム・容量は、本人だけが読める
              // `users/{uid}/private/state` にある（2026-08-11）。
              // **届く前に既定値で描かない。** 「日本語」「通知はすべてオン」
              // 「プレミアムではありません」を先に出すと、直後に別の値へ
              // 入れ替わり、その間に触った操作が消える
              // （docs/AUDIT-CHECKLIST.md 観点 2）。
              _PrivateSections(uid: appUser.uid, value: private),
              // 端末に保存した音源（docs/DOWNLOAD-DESIGN.md 6.4）。
              // **本人の private とは無関係**なので、その外に置く。
              // 目録は端末の中にあり、Firestore からは来ない。
              const _DownloadsSection(),
              const Divider(height: 32),
              const _AccountSection(),
            ],
          );
        },
      ),
    );
  }
}

/// 本人だけが読める設定のまとまり。
///
/// 届くまでは読み込み中のまま待たせる。1 つの購読なので、届くのは
/// 全部同時であり、section ごとに別々の読み込み表示を出す意味がない。
class _PrivateSections extends StatelessWidget {
  const _PrivateSections({required this.uid, required this.value});

  final String uid;
  final AsyncValue<UserPrivate?> value;

  @override
  Widget build(BuildContext context) {
    return AsyncView(
      value: value,
      builder: (private) {
        if (private == null) {
          // まだサーバーが作っていない。既定値を「その人の設定」として
          // 出すと、保存していないものが保存済みに見える。
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _LanguageSection(uid: uid, private: private),
            const Divider(height: 32),
            _NotificationSection(uid: uid, private: private),
            const Divider(height: 32),
            // **通知の下に置く。** 上に挟むと、通知の設定が画面の外へ
            // 押し出される。よく触る設定ほど上に残す。
            _PremiumSection(private: private),
            const Divider(height: 32),
            _StorageSection(private: private),
          ],
        );
      },
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
  const _LanguageSection({required this.uid, required this.private});

  final String uid;
  final UserPrivate private;

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
          selected: {private.locale},
          // 保存できなかったときに黙って戻らないようにする（監査 第4回）。
          // 切り替えたのに元へ戻る動きは、押し損ねたようにしか見えない。
          onSelectionChanged: (selection) async {
            try {
              await ref
                  .read(listRepositoryProvider)
                  .updateLocale(uid, selection.first);
            } catch (error) {
              if (context.mounted) showWriteFailure(context, error);
            }
          },
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
  const _PremiumSection({required this.private});

  final UserPrivate private;

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
    final until = widget.private.premiumUntil;
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
  const _StorageSection({required this.private});

  final UserPrivate private;

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final theme = Theme.of(context);
    final storage = private.storage;

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

/// 端末に保存した音源（docs/DOWNLOAD-DESIGN.md 6.4）。
///
/// | 出すもの | 中身 |
/// | --- | --- |
/// | 端末内の使用量 | **`localBytes` の合計**（3.5）。**サーバー側の `sizeBytes` を使わない**——落とし損ねたぶんが数字に出ない |
/// | リストごとの内訳 | 「バンド練習 2026 — 820 MB（28 曲）」 |
/// | すべて削除 | 確認ダイアログ。**「曲とリストは消えません」を必ず書く**（2.1） |
/// | モバイル通信でもダウンロードする | 既定 off（論点 11b） |
///
/// **端末の空き容量は出していない**（6.4 は「参考として」挙げている）。
/// 空き容量を読む手段がいまの依存に無く、そのためだけにプラグインを
/// 1 つ増やす代償に見合わない。**上限を置かない**（論点 6）方針は
/// 変わらないので、足りなくなったときは 4.1 の失敗として伝わる。
class _DownloadsSection extends ConsumerWidget {
  const _DownloadsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // **Web には保存先が無い**（論点 2）。設定に空の節を出さない。
    if (!ref.watch(audioDownloadSupportedProvider)) {
      return const SizedBox.shrink();
    }

    final l10n = AppL10n.of(context);
    final theme = Theme.of(context);
    final index = ref.watch(downloadsProvider).value;
    if (index == null) return const SizedBox.shrink();

    final byList = <String, ({int bytes, int count})>{};
    for (final item in index.items) {
      final current = byList[item.listName] ?? (bytes: 0, count: 0);
      byList[item.listName] = (
        bytes: current.bytes + item.localBytes,
        count: current.count + 1,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 32),
        Text(l10n.downloadsSettingsTitle, style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),

        if (index.items.isEmpty)
          Text(l10n.downloadsSettingsNone, style: theme.textTheme.bodySmall)
        else ...[
          Text(
            // **端末上の実測を合計する**（3.5・6.4）。
            formatDownloadUsage(
              l10n,
              bytes: index.localBytesTotal,
              count: index.items.length,
            ),
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 8),
          for (final entry in byList.entries)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                l10n.downloadsPerList(
                  entry.key,
                  formatBytes(entry.value.bytes),
                  entry.value.count,
                ),
                style: theme.textTheme.bodySmall,
              ),
            ),
        ],

        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            icon: const Icon(Icons.cloud_download_outlined),
            label: Text(l10n.downloadsSettingsOpen),
            onPressed: () => context.go(AppRoutes.downloads),
          ),
        ),

        // 通信条件（4.6・論点 11b）。**既定は Wi-Fi のときだけ。**
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.downloadsAllowMobileData),
          // **「モバイルデータを使いません」とは書かない**（4.6）。
          // ほかの端末のテザリングは Wi-Fi に見えるので、確かめられない。
          subtitle: Text(
            l10n.downloadsAllowMobileDataNote,
            style: theme.textTheme.bodySmall,
          ),
          value: index.allowMobileData,
          onChanged: (value) async {
            try {
              await ref
                  .read(downloadsProvider.notifier)
                  .setAllowMobileData(value);
            } catch (error) {
              if (context.mounted) showWriteFailure(context, error);
            }
          },
        ),

        if (index.items.isNotEmpty)
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: theme.colorScheme.error,
              ),
              onPressed: () => _confirmRemoveAll(context, ref),
              child: Text(l10n.downloadsRemoveAll),
            ),
          ),
      ],
    );
  }

  /// すべて削除（6.4）。
  ///
  /// **「曲とリストは消えません」を必ず書く**（2.1）。ダウンロードは
  /// 「機能」であって「資産」ではない。**「残っているもの」を先に、
  /// 具体的に書く**——「容量が減りました」とだけ出して誤解された
  /// （PREMIUM-DESIGN.md）のと同じ間違いを繰り返さない。
  Future<void> _confirmRemoveAll(BuildContext context, WidgetRef ref) async {
    final l10n = AppL10n.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.downloadsRemoveAll),
        content: Text(l10n.downloadsRemoveAllBody),
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
            child: Text(l10n.downloadsRemoveAll),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref.read(downloadsProvider.notifier).removeAll();
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.downloadsRemoveAllDone)));
      }
    } catch (error) {
      if (context.mounted) showWriteFailure(context, error);
    }
  }
}

/// 通知設定（仕様書 10.3）。
///
/// プッシュ通知は初期リリースでは画面に出さない（仕様書 12.7）。
/// データとしては保持しているので、ここでは触らずそのまま残す。
class _NotificationSection extends ConsumerWidget {
  const _NotificationSection({required this.uid, required this.private});

  final String uid;
  final UserPrivate private;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final settings = private.notificationSettings;

    // 切り替えたのに保存できていない、を黙って見逃さない（監査 第4回）。
    Future<void> save(NotificationSettings next) async {
      try {
        await ref
            .read(listRepositoryProvider)
            .updateNotificationSettings(uid, next);
      } catch (error) {
        if (context.mounted) showWriteFailure(context, error);
      }
    }

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
        content: Text(
          '${l10n.withdrawWarning}\n\n${l10n.withdrawIrreversible}',
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
