/// 共有リンクを開いた画面（仕様書 3.3 / 14.2）
///
/// **受け取った人がここで決める。**
///
/// - **参加する**：そのリストのメンバーになる。曲やコメントを追加できる
///   ようになり（役割による）、新しい曲が入ると通知が届く
/// - **参加せずに見る**：メンバーにはならない。中身は見られて音も聴けるが、
///   メンバー一覧には出ず、通知も届かない
///
/// **どちらを選んでも、その説明を画面に出す。** 押したあとで
/// 「そういうことだったのか」となる作りにしない。
///
/// リンクは無期限で、何度でも、複数人が使える。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/repositories/functions_repository.dart';
import '../../domain/share_link.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/app_providers.dart';
import '../routes.dart';
import '../widgets/error_message.dart';

class ShareLinkScreen extends ConsumerStatefulWidget {
  const ShareLinkScreen({super.key, required this.linkId});

  final String linkId;

  @override
  ConsumerState<ShareLinkScreen> createState() => _ShareLinkScreenState();
}

class _ShareLinkScreenState extends ConsumerState<ShareLinkScreen> {
  bool _busy = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    Icons.link,
                    size: 40,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    l10n.shareLinkReceived,
                    style: theme.textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.shareLinkChooseHint,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),

                  if (_error != null) ...[
                    ErrorMessage(_error!),
                    const SizedBox(height: 16),
                  ],

                  // **参加する。** 何が起きるかを添える。
                  _Choice(
                    icon: Icons.group_add_outlined,
                    title: l10n.shareLinkJoinTitle,
                    body: l10n.shareLinkJoinBody,
                    emphasized: true,
                    onPressed: _busy ? null : () => _accept(join: true),
                  ),
                  const SizedBox(height: 12),

                  // **参加せずに見る。** こちらも何が起きるかを添える。
                  _Choice(
                    icon: Icons.visibility_outlined,
                    title: l10n.shareLinkViewTitle,
                    body: l10n.shareLinkViewBody,
                    emphasized: false,
                    onPressed: _busy ? null : () => _accept(join: false),
                  ),

                  const SizedBox(height: 16),
                  Text(
                    l10n.shareLinkChangeLaterNote,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _busy ? null : () => context.go(AppRoutes.home),
                    child: Text(l10n.cancel),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _accept({required bool join}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await ref
          .read(functionsRepositoryProvider)
          .acceptShareLink(widget.linkId, join: join);
      if (!mounted) return;

      // 曲を指すリンクならその曲へ、そうでなければリストへ。
      context.go(
        result.itemId == null
            ? AppRoutes.list(result.listId)
            : AppRoutes.item(result.listId, result.itemId!),
      );
    } on ShareLinkRejectedException catch (e) {
      if (mounted) setState(() => _error = _messageFor(e.reason));
    } on FunctionsCallException catch (e) {
      if (mounted) {
        setState(() => _error = describeFunctionsError(context, e));
      }
    } catch (_) {
      if (mounted) setState(() => _error = AppL10n.of(context).errorGeneric);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 受け入れられなかった理由ごとに文言を出し分ける（仕様書 3.3）。
  String _messageFor(ShareLinkRejection reason) {
    final l10n = AppL10n.of(context);
    return switch (reason) {
      ShareLinkRejection.revoked => l10n.shareLinkRevoked,
      ShareLinkRejection.notFound => l10n.shareLinkNotFound,
    };
  }
}

/// 選択肢を 1 つ。**何が起きるかを本文で説明する。**
class _Choice extends StatelessWidget {
  const _Choice({
    required this.icon,
    required this.title,
    required this.body,
    required this.emphasized,
    required this.onPressed,
  });

  final IconData icon;
  final String title;
  final String body;
  final bool emphasized;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Card(
      margin: EdgeInsets.zero,
      color: emphasized ? scheme.primaryContainer : scheme.surfaceContainerHigh,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                icon,
                color: emphasized
                    ? scheme.onPrimaryContainer
                    : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: emphasized
                            ? scheme.onPrimaryContainer
                            : scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      body,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: emphasized
                            ? scheme.onPrimaryContainer
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
