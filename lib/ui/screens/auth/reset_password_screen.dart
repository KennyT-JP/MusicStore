/// パスワード再設定画面（仕様書 3.1 / 14.2）
library;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/app_localizations.dart';
import '../../../providers/app_providers.dart';
import '../../routes.dart';
import '../../widgets/auth_scaffold.dart';
import '../../widgets/error_message.dart';

class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  ConsumerState<ResetPasswordScreen> createState() =>
      _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();

  bool _busy = false;
  bool _sent = false;
  String? _error;

  /// 原因が 1 つに絞れないときだけ入る、技術的な内容。
  String? _errorDetail;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
      _errorDetail = null;
    });
    try {
      await ref
          .read(authRepositoryProvider)
          .sendPasswordResetEmail(
            _email.text,
            languageCode: Localizations.localeOf(context).languageCode,
          );
      if (mounted) setState(() => _sent = true);
    } on FirebaseAuthException catch (e) {
      // アカウントの有無を外部に漏らさないため、
      // 「そのメールアドレスは存在しない」は送信成功と同じ扱いにする。
      if (e.code == 'user-not-found') {
        if (mounted) setState(() => _sent = true);
      } else if (mounted) {
        setState(() {
          _error = describeAuthError(context, e);
          _errorDetail = authErrorDetail(e);
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = AppL10n.of(context).errorGeneric;
          _errorDetail = '$error';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);

    return AuthScaffold(
      title: l10n.resetPassword,
      busy: _busy,
      child: _sent
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(l10n.resetPasswordSent),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () => context.go(AppRoutes.signIn),
                  child: Text(l10n.signIn),
                ),
              ],
            )
          : Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_error != null) ...[
                    ErrorMessage(_error!, detail: _errorDetail),
                    const SizedBox(height: 16),
                  ],
                  TextFormField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      labelText: l10n.emailLabel,
                      border: const OutlineInputBorder(),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? l10n.emailRequired
                        : null,
                    onFieldSubmitted: (_) => _submit(),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: Text(l10n.resetPassword),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => context.go(AppRoutes.signIn),
                    child: Text(l10n.signIn),
                  ),
                ],
              ),
            ),
    );
  }
}
