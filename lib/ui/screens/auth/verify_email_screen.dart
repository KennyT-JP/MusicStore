/// メール確認待ち画面（仕様書 3.1 / 14.2）
///
/// メール＋パスワードで登録した場合、リンクを押すまでアプリを使えない。
/// Google 連携での登録は確認不要のため、この画面を通らない。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../../providers/app_providers.dart';
import '../../widgets/auth_scaffold.dart';
import '../../widgets/error_message.dart';

class VerifyEmailScreen extends ConsumerStatefulWidget {
  const VerifyEmailScreen({super.key});

  @override
  ConsumerState<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends ConsumerState<VerifyEmailScreen> {
  bool _busy = false;
  String? _message;
  String? _error;

  Future<void> _resend() async {
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    try {
      await ref.read(authRepositoryProvider).resendVerificationEmail();
      if (mounted) setState(() => _message = '確認メールを再送しました。');
    } catch (_) {
      if (mounted) setState(() => _error = AppL10n.of(context).errorGeneric);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _recheck() async {
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    try {
      final verified = await ref
          .read(authRepositoryProvider)
          .reloadEmailVerification();
      if (!mounted) return;
      if (verified) {
        // ユーザー情報が更新されると authStateProvider が変わり、
        // ルーターのリダイレクトが本来の画面へ運ぶ（仕様書 14.3）。
        ref.invalidate(firebaseUserProvider);
      } else {
        setState(() => _message = 'まだ確認が済んでいないようです。メール内のリンクを開いてください。');
      }
    } catch (_) {
      if (mounted) setState(() => _error = AppL10n.of(context).errorGeneric);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final email = ref.watch(firebaseUserProvider).value?.email ?? '';

    return AuthScaffold(
      title: l10n.verifyEmailTitle,
      busy: _busy,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null) ...[
            ErrorMessage(_error!),
            const SizedBox(height: 16),
          ],
          Text(l10n.verifyEmailBody(email)),
          if (_message != null) ...[
            const SizedBox(height: 16),
            Text(
              _message!,
              style: TextStyle(color: Theme.of(context).colorScheme.primary),
            ),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _busy ? null : _recheck,
            child: Text(l10n.verifyEmailRecheck),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _busy ? null : _resend,
            child: Text(l10n.verifyEmailResend),
          ),
          const Divider(height: 32),
          TextButton(
            onPressed: _busy
                ? null
                : () => ref.read(authRepositoryProvider).signOut(),
            child: Text(l10n.signOut),
          ),
        ],
      ),
    );
  }
}
