/// 項目詳細（仕様書 9 章 / 14.2）
///
/// 曲名・ファイル／URL と、無制限の入れ子になるコメントスレッドを表示する。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/models/app_user.dart';
import '../../data/models/list_item.dart';
import '../../domain/comment_tree.dart';
import '../../domain/display_name.dart';
import '../../data/repositories/functions_repository.dart';
import '../../domain/permissions.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/app_providers.dart';
import '../downloads/download_support.dart';
import '../format.dart';
import '../routes.dart';
import '../share_url.dart';
import '../widgets/async_view.dart';
import '../widgets/download_button.dart';
import '../widgets/error_message.dart';
import '../widgets/item_external_action.dart';
import '../widgets/web_download_notice.dart';

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
    // **削除は削除の判定を使う。** 編集と同じ条件だが、条件が分かれた
    // ときに画面だけ取り残される。判定関数はあるのに呼ばれていなかった
    // （監査 S8・第2回）。
    final canDelete = Permissions.canDeleteItem(
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
              // **この曲を指すリンクを配れる（仕様書 3.3）。**
              // 開いた人は、参加するか見るだけかをその場で選べる。
              if (Permissions.canCreateShareLink(access) && !item.isDeleted)
                _ItemShareLinkButton(listId: listId, itemId: item.id),
              if (canEdit)
                IconButton(
                  tooltip: l10n.editItem,
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () =>
                      context.go(AppRoutes.editItem(listId, item.id)),
                ),
              if (canDelete)
                IconButton(
                  tooltip: l10n.deleteItem,
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _confirmDelete(context, ref, graceDays),
                ),
              if (canRestore)
                TextButton.icon(
                  icon: const Icon(Icons.restore),
                  label: Text(l10n.restoreItem),
                  onPressed: () => _restore(context, ref, uid),
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
            // **登録者は改めて解決する。** itemProvider は 1 件だけを
            // 監視するため表示名を解決しておらず、空文字が入っている。
            // 一覧では出るのに詳細だけ常に空欄だった（監査 第2回）。
            _MetaRow(
              label: l10n.columnRegistrant,
              value: _registrantName(ref, listId, item.createdBy, l10n),
            ),
            const SizedBox(height: 16),
            _MediaAction(listId: listId, item: item),
          ],
        ],
      ),
    );
  }

  /// 削除した項目を復元する（仕様書 6.3）。
  ///
  /// **失敗を握りつぶさない。** 以前は await すらしておらず、オフラインや
  /// 権限拒否では押しても何も起きないように見えた（監査 第4回）。
  Future<void> _restore(BuildContext context, WidgetRef ref, String uid) async {
    try {
      await ref
          .read(itemRepositoryProvider)
          .restoreItem(listId: listId, itemId: item.id, uid: uid);
    } catch (error) {
      if (context.mounted) showWriteFailure(context, error);
    }
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
        content: Text(l10n.deleteItemBody(graceDays)),
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
    try {
      await ref
          .read(itemRepositoryProvider)
          .deleteItem(
            listId: listId,
            itemId: item.id,
            uid: uid,
            graceDays: graceDays,
          );
    } catch (error) {
      // 失敗したのに一覧から消えたように見える、を避ける（監査 第4回）。
      if (context.mounted) showWriteFailure(context, error);
    }
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
              // **書き方を揃える。** ここだけゼロ埋めが無く、
              // 同じアプリの中で 2026-8-6 と 2026/08/06 が混ざっていた
              // （監査 第2回）。
              l10n.restorableUntil(formatDateTime(purgeAt)),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}

/// 登録者・投稿者の表示名を解決する（仕様書 3.5 / 5.4）。
///
/// 退会・除外された人は本名を出さない。まだ読み込めていない人と
/// 区別できるよう、取得前は空文字を返す（「退会したユーザー」と
/// 表示してしまうと、在籍中の人が退会したように見える）。
String _registrantName(WidgetRef ref, String listId, String uid, AppL10n l10n) {
  final users = ref.watch(userDirectoryProvider(userDirectoryKey([uid])));
  final members = ref.watch(listMembersProvider(listId));

  // どちらかがまだ届いていないなら、決めつけずに空にする。
  if (!users.hasValue || !members.hasValue) return '';

  final user = users.requireValue[uid];
  return DisplayNameResolver.resolveInList(
    uid: uid,
    user: user == null
        ? null
        : UserNameSource(
            displayName: user.displayName,
            isWithdrawn: user.isWithdrawn,
          ),
    currentMemberUids: members.requireValue.map((m) => m.uid).toSet(),
    withdrawnLabel: l10n.withdrawnUser,
  ).text;
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

/// 再生・保存・リンクの挙動（仕様書 8 章／docs/DOWNLOAD-DESIGN.md 6.2 / 7.2）。
///
/// **「アプリ内蔵のプレーヤーは作らない」という以前の注記は、すでに事実と
/// 違っていた**（一覧に再生ボタンがある）。7.2 の指示どおり、ここで直す。
///
/// | 種類 | ここに出るもの |
/// | --- | --- |
/// | 音源ファイル | **端末に保存**（6.2）。ダウンロードのボタンは 7 節で外す |
/// | 音源以外のファイル（PDF・zip など） | **従来どおりダウンロードできる**（論点 2） |
/// | URL の項目 | 従来どおり外部サイトへ |
///
/// 一覧の行から鳴らす再生は `list_detail_screen.dart` にある。
class _MediaAction extends ConsumerWidget {
  const _MediaAction({required this.listId, required this.item});

  final String listId;
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

    // **音源のダウンロードだけを外す**（7.1）。判定は `isPlayableAudio` を
    // 通す `isAudioFileItem` に任せ、ここに 2 つ目の判定を書かない。
    final isAudio = isAudioFileItem(item);
    final showsLegacyDownload =
        !isAudio || ref.watch(legacyAudioDownloadProvider);

    final listName = ref.watch(listProvider(listId)).value?.name ?? '';

    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: const Icon(Icons.audio_file_outlined),
        title: Text(file.fileName, overflow: TextOverflow.ellipsis),
        subtitle: Text(formatBytes(file.sizeBytes)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 端末に保存（6.2）。**Web では出ない**（6.5）。
            ItemDownloadButton(listId: listId, listName: listName, item: item),
            if (showsLegacyDownload)
              const Icon(Icons.download_outlined)
            else
              // **空白にしない**（7.3）。消えた場所に何も無いと、
              // 壊れたようにしか見えない。
              const WebDownloadReplacement(),
          ],
        ),
        onTap: showsLegacyDownload
            ? () async {
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
              }
            : null,
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
      // **成功したときだけ消す。** 失敗時に消すと、書いた本文ごと失われる。
      _controller.clear();
      if (mounted) setState(() => _replyTo = null);
    } catch (error) {
      // オフライン・権限拒否で無反応に見えないようにする（監査 第4回）。
      if (mounted) showWriteFailure(context, error);
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
                    l10n.noCommentsYet,
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
                    l10n.replyingTo(_replyTo!.body),
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
    // 削除は削除の判定を使う（項目と同じ理由）。
    final canDelete = Permissions.canDeleteComment(
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
                  // **編集の導線（仕様書 9）。** updateComment は実装済み
                  // だったが、呼ぶ場所が無かった（監査 S16）。
                  if (canEdit)
                    TextButton(
                      onPressed: () => _editComment(context, ref),
                      child: Text(l10n.edit),
                    ),
                  if (canDelete)
                    TextButton(
                      onPressed: () => _deleteComment(context, ref),
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

extension _CommentEditing on _CommentTile {
  /// コメントを削除する（仕様書 9）。
  ///
  /// **失敗を握りつぶさない。** 以前は fire-and-forget で、オフラインや
  /// 権限拒否では押しても何も起きないように見えた（監査 第4回）。
  Future<void> _deleteComment(BuildContext context, WidgetRef ref) async {
    try {
      await ref
          .read(itemRepositoryProvider)
          .deleteComment(listId: listId, itemId: itemId, commentId: comment.id);
    } catch (error) {
      if (context.mounted) showWriteFailure(context, error);
    }
  }

  /// コメントを編集する（仕様書 9）。
  Future<void> _editComment(BuildContext context, WidgetRef ref) async {
    final l10n = AppL10n.of(context);
    final controller = TextEditingController(text: comment.body);

    final edited = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.edit),
        content: TextField(
          controller: controller,
          maxLines: 5,
          minLines: 1,
          autofocus: true,
          decoration: InputDecoration(labelText: l10n.commentLabel),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: Text(l10n.save),
          ),
        ],
      ),
    );

    if (edited == null || edited.isEmpty || edited == comment.body) return;

    try {
      await ref
          .read(itemRepositoryProvider)
          .updateComment(
            listId: listId,
            itemId: itemId,
            commentId: comment.id,
            body: edited,
            // 開いた時点の更新日時を渡し、その間に他の人が直していたら
            // 弾く（仕様書 6.3 と同じ扱い）。
            openedWith: comment.updatedAt,
          );
    } catch (error) {
      // **競合を黙って捨てない。** リポジトリは ConcurrentEditException を
      // 投げる設計なのに受け手が無く、競合時は編集が黙って消えていた
      // （監査 第4回）。項目編集（item_form_screen.dart）と同じく
      // conflictBody を出す。それ以外の失敗も無反応にしない。
      if (context.mounted) showWriteFailure(context, error);
    }
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
    final users = ref
        .watch(userDirectoryProvider(userDirectoryKey([uid])))
        .value;
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

/// この曲を指す共有リンクをコピーする（仕様書 3.3）。
///
/// **リストのリンクと同じ性質。** 無期限で、何度でも、複数人が使える。
/// 開いた人は「参加する」か「参加せずに見る」かを選ぶ。
class _ItemShareLinkButton extends ConsumerStatefulWidget {
  const _ItemShareLinkButton({required this.listId, required this.itemId});

  final String listId;
  final String itemId;

  @override
  ConsumerState<_ItemShareLinkButton> createState() =>
      _ItemShareLinkButtonState();
}

class _ItemShareLinkButtonState extends ConsumerState<_ItemShareLinkButton> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    return IconButton(
      tooltip: l10n.copyItemShareLink,
      icon: _busy
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.link),
      onPressed: _busy ? null : _copy,
    );
  }

  Future<void> _copy() async {
    final l10n = AppL10n.of(context);
    final messenger = ScaffoldMessenger.of(context);

    setState(() => _busy = true);
    try {
      // **リストから配るリンクと同じもの。** 曲を指すだけの違い。
      // 受け取った人が「参加する」か「参加せずに見る」かを選ぶ（3.3）。
      final linkId = await ref
          .read(functionsRepositoryProvider)
          .createShareLink(listId: widget.listId, itemId: widget.itemId);

      await Clipboard.setData(
        ClipboardData(text: buildShareUrl(AppRoutes.shareLink(linkId))),
      );
      if (!mounted) return;
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
