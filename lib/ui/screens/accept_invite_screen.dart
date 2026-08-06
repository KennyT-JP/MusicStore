/// 招待の受諾（仕様書 3.3 / 14.2）
///
/// 有効期限は**受諾した時点**で判定される。URL を開いた時点ではなく、
/// サインアップやメール確認を終えて実際に参加処理が走る瞬間を見る。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/repositories/functions_repository.dart';
import '../../domain/invite.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/app_providers.dart';
import '../routes.dart';
import '../widgets/error_message.dart';

class AcceptInviteScreen extends ConsumerStatefulWidget {
  const AcceptInviteScreen({super.key, required this.inviteId});

  final String inviteId;

  @override
  ConsumerState<AcceptInviteScreen> createState() => _AcceptInviteScreenState();
}

class _AcceptInviteScreenState extends ConsumerState<AcceptInviteScreen> {
  bool _busy = false;
  String? _error;
  String? _joinedListId;

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(
                  _joinedListId != null
                      ? Icons.check_circle_outline
                      : Icons.mail_outline,
                  size: 40,
                  color: _joinedListId != null
                      ? theme.colorScheme.primary
                      : theme.colorScheme.outline,
                ),
                const SizedBox(height: 16),
                Text(
                  l10n.inviteReceived,
                  style: theme.textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),

                if (_error != null) ...[
                  ErrorMessage(_error!),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: () => context.go(AppRoutes.home),
                    child: Text(l10n.navHome),
                  ),
                ] else if (_joinedListId != null) ...[
                  Text(
                    l10n.inviteAccepted,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: theme.colorScheme.primary),
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: () => context.go(AppRoutes.list(_joinedListId!)),
                    child: Text(l10n.openList),
                  ),
                ] else ...[
                  Text(
                    l10n.joinThisList,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _busy ? null : _accept,
                    child: _busy
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(l10n.join),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _busy ? null : () => context.go(AppRoutes.home),
                    child: Text(l10n.cancel),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _accept() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final listId = await ref
          .read(functionsRepositoryProvider)
          .acceptInvite(widget.inviteId);
      if (mounted) setState(() => _joinedListId = listId);
    } on InviteRejectedException catch (e) {
      if (mounted) setState(() => _error = _messageFor(e.reason));
    } catch (_) {
      if (mounted) setState(() => _error = AppL10n.of(context).errorGeneric);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 受け入れられなかった理由ごとに文言を出し分ける（仕様書 3.3）。
  String _messageFor(InviteRejection reason) {
    final l10n = AppL10n.of(context);
    return switch (reason) {
      InviteRejection.expired => l10n.inviteExpired,
      InviteRejection.alreadyUsed => l10n.inviteAlreadyUsed,
      InviteRejection.revoked => l10n.inviteRevoked,
      InviteRejection.alreadyMember => l10n.inviteAlreadyMember,
      InviteRejection.notFound => l10n.inviteNotFound,
    };
  }
}
