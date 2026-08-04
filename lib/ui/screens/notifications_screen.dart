/// 通知一覧（仕様書 10 / 14.2）
///
/// アプリ内通知を新しい順に表示する。プッシュ通知は初期リリースでは扱わない
/// （仕様書 12.7）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/firestore_paths.dart';
import '../../data/models/app_user.dart';
import '../../data/models/requests.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/app_providers.dart';
import '../routes.dart';
import '../widgets/async_view.dart';

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final notifications = ref.watch(myNotificationsProvider);

    return Scaffold(
      body: AsyncView(
        value: notifications,
        onRetry: () => ref.invalidate(myNotificationsProvider),
        builder: (items) {
          if (items.isEmpty) {
            return EmptyState(
              icon: Icons.notifications_none,
              title: l10n.notificationsEmpty,
            );
          }

          final unread = items.where((n) => !n.isRead).toList();

          return ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              if (unread.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      icon: const Icon(Icons.done_all),
                      label: Text(l10n.markAllAsRead),
                      onPressed: () => _markAllAsRead(ref, unread),
                    ),
                  ),
                ),
              for (final notification in items)
                _NotificationTile(notification: notification),
            ],
          );
        },
      ),
    );
  }

  /// すべて既読にする。
  ///
  /// 件数が多いこともあるため、まとめ書きで 1 往復にする。
  Future<void> _markAllAsRead(
    WidgetRef ref,
    List<AppNotification> unread,
  ) async {
    final uid = ref.read(firebaseUserProvider).value?.uid;
    if (uid == null) return;
    final db = ref.read(firestoreProvider);

    // 1 回のバッチで書ける上限は 500 件。分割して送る。
    for (var i = 0; i < unread.length; i += 500) {
      final batch = db.batch();
      final chunk = unread.skip(i).take(500);
      for (final notification in chunk) {
        batch.update(
          db.doc('${FirestorePaths.userNotifications(uid)}/${notification.id}'),
          {'isRead': true},
        );
      }
      await batch.commit();
    }
  }
}

class _NotificationTile extends ConsumerWidget {
  const _NotificationTile({required this.notification});

  final AppNotification notification;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final theme = Theme.of(context);

    return ListTile(
      leading: Icon(
        _iconFor(notification.type),
        color: notification.isRead
            ? theme.colorScheme.outline
            : theme.colorScheme.primary,
      ),
      title: Text(
        _labelFor(l10n, notification.type),
        style: TextStyle(
          fontWeight: notification.isRead ? FontWeight.normal : FontWeight.bold,
        ),
      ),
      subtitle: notification.createdAt == null
          ? null
          : Text(_formatDateTime(notification.createdAt!)),
      trailing: notification.isRead
          ? null
          : Icon(Icons.circle, size: 8, color: theme.colorScheme.primary),
      onTap: () => _open(context, ref),
    );
  }

  /// 通知をタップしたら既読にして対象へ遷移する（仕様書 14.2）。
  Future<void> _open(BuildContext context, WidgetRef ref) async {
    final uid = ref.read(firebaseUserProvider).value?.uid;
    if (uid != null && !notification.isRead) {
      await ref
          .read(firestoreProvider)
          .doc('${FirestorePaths.userNotifications(uid)}/${notification.id}')
          .update({'isRead': true})
          // 既読にできなくても遷移は妨げない。
          .catchError((_) {});
    }
    if (!context.mounted) return;

    final destination = _destinationFor(notification);
    if (destination != null) context.go(destination);
  }

  /// 遷移先。特定できなければ null（その場に留まる）。
  static String? _destinationFor(AppNotification n) {
    final listId = n.listId;
    final itemId = n.itemId;

    switch (n.type) {
      case NotificationType.itemAdded:
      case NotificationType.commentAdded:
        if (listId != null && itemId != null) {
          return AppRoutes.item(listId, itemId);
        }
        return listId == null ? null : AppRoutes.list(listId);
      case NotificationType.quotaNotice:
      case NotificationType.quotaWarning:
        return listId == null ? null : AppRoutes.listSettings(listId);
      case NotificationType.listRequested:
        return AppRoutes.siteAdminListRequests;
      case NotificationType.joinRequested:
        return listId == null ? null : AppRoutes.listJoinRequests(listId);
      case NotificationType.requestApproved:
        return listId == null ? AppRoutes.myRequests : AppRoutes.list(listId);
      case null:
        return null;
    }
  }

  static IconData _iconFor(NotificationType? type) => switch (type) {
    NotificationType.itemAdded => Icons.library_music_outlined,
    NotificationType.commentAdded => Icons.comment_outlined,
    NotificationType.quotaNotice => Icons.info_outline,
    NotificationType.quotaWarning => Icons.warning_amber_outlined,
    NotificationType.listRequested => Icons.playlist_add_outlined,
    NotificationType.joinRequested => Icons.person_add_outlined,
    NotificationType.requestApproved => Icons.check_circle_outline,
    null => Icons.notifications_none,
  };

  static String _labelFor(AppL10n l10n, NotificationType? type) =>
      switch (type) {
        NotificationType.itemAdded => l10n.notifyItemAdded,
        NotificationType.commentAdded => l10n.notifyCommentAdded,
        NotificationType.quotaNotice => l10n.notifyQuotaNotice,
        NotificationType.quotaWarning => l10n.notifyQuotaWarning,
        NotificationType.listRequested => l10n.notifyListRequested,
        NotificationType.joinRequested => l10n.notifyJoinRequested,
        NotificationType.requestApproved => l10n.notifyRequestApproved,
        // 将来 Functions 側に種別が増えても画面が壊れないようにする。
        null => l10n.navNotifications,
      };
}

/// 投稿日時などのシステム日時は、見る人の現地時刻で表示する（仕様書 6.2）。
String _formatDateTime(DateTime utc) {
  final local = utc.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${local.year}/${two(local.month)}/${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}
