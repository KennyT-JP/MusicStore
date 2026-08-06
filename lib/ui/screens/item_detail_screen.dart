/// 項目詳細（仕様書 9 章 / 14.2）
///
/// 曲名・ファイル／URL と、無制限の入れ子になるコメントスレッドを表示する。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/models/app_user.dart';
import '../../data/models/list_item.dart';
import '../../domain/comment_tree.dart';
import '../../domain/display_name.dart';
import '../../domain/permissions.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/app_providers.dart';
import '../routes.dart';
import '../widgets/async_view.dart';

class ItemDetailScreen extends ConsumerWidget {
  const ItemDetailScreen({
    super.key,
    required this.listId,
    required this.itemId,
  });

  final String listId;
  final String itemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final item = ref.watch(itemProvider((listId: listId, itemId: itemId)));

    return Scaffold(
      body: AsyncView(
        value: item,
        builder: (data) {
          if (data == null) {
            return EmptyState(icon: Icons.search_off, title: l10n.notFound);
          }
          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: _ItemHeader(listId: listId, item: data),
              ),
              const SliverToBoxAdapter(child: Divider(height: 1)),
              SliverToBoxAdapter(
                child: _CommentSection(listId: listId, itemId: itemId),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ItemHeader extends ConsumerWidget {
  const _ItemHeader({required this.listId, required this.item});

  final String listId;
  final ListItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final theme = Theme.of(context);
    final access = ref.watch(listAccessProvider(listId));
    final uid = ref.watch(firebaseUserProvider).value?.uid ?? '';
    final graceDays =
        ref.watch(siteConfigProvider).value?.itemPurgeGraceDays ?? 30;

    final canEdit = Permissions.canEditItem(
      access,
      viewerUid: uid,
      itemCreatedBy: item.createdBy,
      itemIsDeleted: item.isDeleted,
    );
    final canRestore = Permissions.canRestoreItem(
      access,
      itemIsDeleted: item.isDeleted,
      withinGracePeriod: item.withinGracePeriod(DateTime.now()),
    );

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                onPressed: () => context.go(AppRoutes.list(listId)),
                icon: const Icon(Icons.arrow_back),
              ),
              Text('#${item.seq}', style: theme.textTheme.titleMedium),
              const Spacer(),
              if (canEdit)
                IconButton(
                  tooltip: l10n.editItem,
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () =>
                      context.go(AppRoutes.editItem(listId, item.id)),
                ),
              if (canEdit)
                IconButton(
                  tooltip: l10n.deleteItem,
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _confirmDelete(context, ref, graceDays),
                ),
              if (canRestore)
                TextButton.icon(
                  icon: const Icon(Icons.restore),
                  label: Text(l10n.restoreItem),
                  onPressed: () => ref
                      .read(itemRepositoryProvider)
                      .restoreItem(listId: listId, itemId: item.id, uid: uid),
                ),
            ],
          ),
          const SizedBox(height: 8),

          if (item.isDeleted)
            _DeletedNotice(item: item)
          else ...[
            Text(item.displayLabel(), style: theme.textTheme.headlineSmall),
            if (item.artist?.trim().isNotEmpty == true) ...[
              const SizedBox(height: 4),
              Text(
                item.artist!.trim(),
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 16),
            _MetaRow(label: l10n.columnDate, value: item.date),
            _MetaRow(
              label: l10n.columnRegistrant,
              value: item.registrantDisplayName,
            ),
            const SizedBox(height: 16),
            _MediaAction(item: item),
          ],
        ],
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    int graceDays,
  ) async {
    final l10n = AppL10n.of(context);
    final uid = ref.read(firebaseUserProvider).value?.uid ?? '';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.deleteItem),
        // 猶予期間があることを伝える（仕様書 6.3）。
        content: Text(
          'この項目を削除します。\n\n'
          '一覧には「${l10n.itemDeleted}」と表示され、連番は欠番として残ります。\n'
          'ファイル本体は $graceDays 日間保持され、その間はリスト管理者以上が復元できます。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.deleteItem),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    await ref
        .read(itemRepositoryProvider)
        .deleteItem(
          listId: listId,
          itemId: item.id,
          uid: uid,
          graceDays: graceDays,
        );
  }
}

class _DeletedNotice extends StatelessWidget {
  const _DeletedNotice({required this.item});

  final ListItem item;

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final scheme = Theme.of(context).colorScheme;
    final purgeAt = item.purgeAt;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.itemDeleted,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (purgeAt != null) ...[
            const SizedBox(height: 8),
            Text(
              '${purgeAt.year}年${purgeAt.month}月${purgeAt.day}日 まではリスト管理者が復元できます。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.label, required this.value});

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
            width: 96,
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

/// 再生・リンクの挙動（仕様書 8 章）。
///
/// アプリ内蔵のプレーヤーは作らない。ファイルはダウンロード URL を開き、
/// どう再生するかは端末側に委ねる。URL は外部サイトへ遷移する。
class _MediaAction extends ConsumerWidget {
  const _MediaAction({required this.item});

  final ListItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (item.kind == ItemKind.url) {
      final url = item.url ?? '';
      return Card(
        margin: EdgeInsets.zero,
        child: ListTile(
          leading: const Icon(Icons.link),
          // URL はそのまま表示してリンクを付ける（仕様書 6.4）。
          title: Text(url, overflow: TextOverflow.ellipsis),
          trailing: const Icon(Icons.open_in_new),
          onTap: () => _open(context, url),
        ),
      );
    }

    final file = item.file;
    if (file == null) return const SizedBox.shrink();

    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: const Icon(Icons.audio_file_outlined),
        title: Text(file.fileName, overflow: TextOverflow.ellipsis),
        subtitle: Text(formatBytes(file.sizeBytes)),
        trailing: const Icon(Icons.download_outlined),
        onTap: () async {
          try {
            final url = await ref
                .read(itemRepositoryProvider)
                .downloadUrl(file.storagePath);
            if (context.mounted) await _open(context, url);
          } catch (_) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(AppL10n.of(context).errorGeneric)),
              );
            }
          }
        },
      ),
    );
  }

  Future<void> _open(BuildContext context, String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(AppL10n.of(context).errorGeneric)));
    }
  }
}

/// コメントスレッド（仕様書 9 章）。
class _CommentSection extends ConsumerStatefulWidget {
  const _CommentSection({required this.listId, required this.itemId});

  final String listId;
  final String itemId;

  @override
  ConsumerState<_CommentSection> createState() => _CommentSectionState();
}

class _CommentSectionState extends ConsumerState<_CommentSection> {
  final _controller = TextEditingController();

  /// 返信先。null ならルートコメント。
  ItemComment? _replyTo;
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _post() async {
    final body = _controller.text.trim();
    if (body.isEmpty) return;
    final uid = ref.read(firebaseUserProvider).value?.uid;
    if (uid == null) return;

    setState(() => _busy = true);
    try {
      await ref
          .read(itemRepositoryProvider)
          .addComment(
            listId: widget.listId,
            itemId: widget.itemId,
            uid: uid,
            body: body,
            parent: _replyTo,
          );
      _controller.clear();
      if (mounted) setState(() => _replyTo = null);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final args = (listId: widget.listId, itemId: widget.itemId);
    final comments = ref.watch(itemCommentsProvider(args));
    final access = ref.watch(listAccessProvider(widget.listId));
    final canPost = Permissions.canPostComment(access);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.comments, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          AsyncView(
            value: comments,
            builder: (list) {
              if (list.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    'まだコメントはありません。',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                );
              }
              // フラットに保存されたコメントをツリーへ組み直す（仕様書 13.3）。
              final flattened = CommentTree.flatten(CommentTree.build(list));
              return Column(
                children: [
                  for (final node in flattened)
                    _CommentTile(
                      listId: widget.listId,
                      itemId: widget.itemId,
                      comment: node.value,
                      depth: node.depth,
                      onReply: canPost
                          ? () => setState(() => _replyTo = node.value)
                          : null,
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          // Read Only は入力欄そのものを出さない（仕様書 14.5）。
          if (canPost) _composer(l10n),
        ],
      ),
    );
  }

  Widget _composer(AppL10n l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_replyTo != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                const Icon(Icons.reply, size: 16),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    '「${_replyTo!.body}」への返信',
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 16),
                  onPressed: () => setState(() => _replyTo = null),
                ),
              ],
            ),
          ),
        TextField(
          controller: _controller,
          minLines: 2,
          maxLines: 6,
          decoration: InputDecoration(
            hintText: l10n.writeComment,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
            onPressed: _busy ? null : _post,
            child: Text(_replyTo == null ? l10n.writeComment : l10n.reply),
          ),
        ),
      ],
    );
  }
}

class _CommentTile extends ConsumerWidget {
  const _CommentTile({
    required this.listId,
    required this.itemId,
    required this.comment,
    required this.depth,
    this.onReply,
  });

  final String listId;
  final String itemId;
  final ItemComment comment;
  final int depth;
  final VoidCallback? onReply;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final theme = Theme.of(context);
    final uid = ref.watch(firebaseUserProvider).value?.uid ?? '';
    final access = ref.watch(listAccessProvider(listId));

    final canEdit = Permissions.canEditComment(
      access,
      viewerUid: uid,
      commentCreatedBy: comment.createdBy,
      commentIsDeleted: comment.isDeleted,
    );

    // 深い階層でも横に押し出されないよう、字下げに上限を設ける。
    final indent = (depth.clamp(0, 6)) * 20.0;

    return Padding(
      padding: EdgeInsets.only(left: indent, bottom: 8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(8),
          border: depth > 0
              ? Border(
                  left: BorderSide(
                    color: theme.colorScheme.outlineVariant,
                    width: 2,
                  ),
                )
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _AuthorLine(listId: listId, uid: comment.createdBy),
            const SizedBox(height: 4),
            if (comment.isDeleted)
              Text(
                l10n.commentDeleted,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.outline,
                  fontStyle: FontStyle.italic,
                ),
              )
            else
              Text(comment.body),
            if (!comment.isDeleted)
              Row(
                children: [
                  if (onReply != null)
                    TextButton(onPressed: onReply, child: Text(l10n.reply)),
                  if (canEdit)
                    TextButton(
                      onPressed: () => ref
                          .read(itemRepositoryProvider)
                          .deleteComment(
                            listId: listId,
                            itemId: itemId,
                            commentId: comment.id,
                          ),
                      child: Text(l10n.deleteItem),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// コメントの投稿者名。
///
/// uid から解決し、退会・除外された人は「退会したユーザー」と表示する
/// （仕様書 3.5 / 5.4 / 13.3）。
class _AuthorLine extends ConsumerWidget {
  const _AuthorLine({required this.listId, required this.uid});

  final String listId;
  final String uid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final theme = Theme.of(context);
    final users = ref.watch(userDirectoryProvider(userDirectoryKey([uid]))).value;
    final members = ref.watch(listMembersProvider(listId)).value;

    final AppUser? user = users?[uid];
    final resolved = DisplayNameResolver.resolveInList(
      uid: uid,
      user: user == null
          ? null
          : UserNameSource(
              displayName: user.displayName,
              isWithdrawn: user.isWithdrawn,
            ),
      currentMemberUids: members?.map((m) => m.uid).toSet(),
      withdrawnLabel: l10n.withdrawnUser,
    );

    return Text(
      resolved.text,
      style: theme.textTheme.labelMedium?.copyWith(
        color: resolved.isAnonymized
            ? theme.colorScheme.outline
            : theme.colorScheme.primary,
      ),
    );
  }
}
