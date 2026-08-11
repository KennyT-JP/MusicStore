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
                  const _NewListButton(),
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
              // **Wrap にする。** 狭い画面でボタンを横に並べ続けると、
              // 文字が 1 文字ずつ折り返されて縦一列になる（2026-08-10 に
              // サイト管理の一覧で起きた形）。入りきらなければ折り返す。
              Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const _NewListButton(),
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

/// リストを増やす導線（docs/PREMIUM-DESIGN.md 4.3）。
///
/// - プレミアムの方 …… 「リストを作る」。その場で作れる
/// - それ以外 …… いままでどおり「リスト作成を申請」
///
/// **プレミアムかどうかが分かるまで、どちらも出さない。**
/// 既定を「プレミアムでない」に倒すと、開いた直後の一瞬だけ
/// 申請の導線が出て、直後に別のボタンへ入れ替わる。押そうとした先が
/// 変わるので、**押し間違いを誘う**（AUDIT-CHECKLIST 観点 2。
/// ホームの「0件」と同じ、届く前に確定を出す形）。
class _NewListButton extends ConsumerWidget {
  const _NewListButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final premium = ref.watch(isPremiumProvider);

    return premium.when(
      loading: () => const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      // 読めなかったときは、誰でも通れる申請の導線に倒す。
      // **「プレミアムでない」と断定はしない**（文言も変えない）。
      error: (_, _) => const _RequestButton(),
      data: (isPremium) => isPremium
          ? FilledButton.icon(
              onPressed: () => _createList(context, ref),
              icon: const Icon(Icons.add),
              label: Text(l10n.createList),
            )
          : const _RequestButton(),
    );
  }

  Future<void> _createList(BuildContext context, WidgetRef ref) async {
    final listId = await showDialog<String>(
      context: context,
      builder: (_) => const _CreateListDialog(),
    );
    if (listId == null || !context.mounted) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(AppL10n.of(context).listCreated)));
    // 作ったリストへ移る。作ったのに一覧が古いままだと、
    // 「できたのかどうか」が分からない。
    context.go(AppRoutes.list(listId));
  }
}

class _RequestButton extends StatelessWidget {
  const _RequestButton();

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    return OutlinedButton.icon(
      onPressed: () => context.go(AppRoutes.requestList),
      icon: const Icon(Icons.add),
      label: Text(l10n.requestNewList),
    );
  }
}

/// 申請なしでリストを作る（設計 4.2）。
///
/// 名前だけを入れて即作成する。**名前の重複はサーバーが断る**ので、
/// ここでは調べない（調べても、読んだ後に他の人が取れば食い違う）。
class _CreateListDialog extends ConsumerStatefulWidget {
  const _CreateListDialog();

  @override
  ConsumerState<_CreateListDialog> createState() => _CreateListDialogState();
}

class _CreateListDialogState extends ConsumerState<_CreateListDialog> {
  final _name = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);

    return AlertDialog(
      title: Text(l10n.createList),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.createListNote,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            if (_error case final error?) ...[
              ErrorMessage(error),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: _name,
              autofocus: true,
              decoration: InputDecoration(
                labelText: l10n.listNameLabel,
                helperText: l10n.listNameHelper,
                helperMaxLines: 2,
              ),
              onSubmitted: _busy ? null : (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: Text(l10n.createList),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    final l10n = AppL10n.of(context);
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = l10n.listNameRequired);
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final listId = await ref
          .read(functionsRepositoryProvider)
          .createListDirectly(name);
      if (mounted) Navigator.of(context).pop(listId);
    } on FunctionsCallException catch (e) {
      // 名前が使われている・プレミアムが切れた、を区別して出す。
      if (mounted) setState(() => _error = describeFunctionsError(context, e));
    } catch (_) {
      if (mounted) setState(() => _error = AppL10n.of(context).errorGeneric);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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

/// 容量の使用状況（仕様書 7.3 / 7.4、docs/PREMIUM-DESIGN.md D5 の補足）。
///
/// 80% 超で Notice、90% 超で警告の色に変える。
///
/// **出すのは「このリストの使用量」ではなく、リストを作った人の合計。**
/// 上限は人ごとの合計にかかるので、リストぶんだけを見せると
/// 「まだ空いているのに追加できない」ことになる。**どちらの数字かが
/// 分かるよう、必ず「作成者の合計」と添える。**
class _QuotaBar extends ConsumerWidget {
  const _QuotaBar({required this.listId});

  final String listId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final stats = ref.watch(listStatsProvider(listId)).value;
    if (stats == null) return const SizedBox.shrink();

    // **合計がまだ届いていないなら、何も出さない。**
    // リストぶんの数字で代用すると、「作成者の合計」と名乗ったまま
    // 別の量を出すことになる（AUDIT-CHECKLIST 観点 2）。
    final quota = stats.ownerQuota;
    if (quota == null) return const SizedBox.shrink();

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
          // **数字だけを出さない。** 誰の合計なのかを必ず添える。
          // 文の中に括弧を書き足すと、言語によって書き方が変わって
          // しまうので、行を分けて l10n の文言そのものを出す。
          Text(
            l10n.ownerQuotaCaption,
            style: Theme.of(context).textTheme.bodySmall,
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
