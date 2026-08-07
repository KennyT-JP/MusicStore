/// ログイン画面（仕様書 3.1 / 14.2）
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

class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key, this.redirect});

  /// ログイン後に戻る先（仕様書 3.1.1）。
  final String? redirect;

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();

  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      // 成功したらルーターのリダイレクトが戻り先へ運ぶ（仕様書 3.1.1）。
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() => _error = describeAuthError(context, e));
    } catch (_) {
      if (mounted) setState(() => _error = AppL10n.of(context).errorGeneric);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final auth = ref.watch(authRepositoryProvider);

    return AuthScaffold(
      title: l10n.signIn,
      busy: _busy,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null) ...[
            ErrorMessage(_error!),
            const SizedBox(height: 16),
          ],
          FilledButton.tonalIcon(
            onPressed: _busy
                ? null
                : () => _run(
                    () => auth.signInWithGoogle(
                      // 登録時の表示言語を、その人の設定として残す（2 章）。
                      languageCode: Localizations.localeOf(context).languageCode,
                    ),
                  ),
            icon: const Icon(Icons.account_circle_outlined),
            label: Text(l10n.signInWithGoogle),
          ),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 16),
          Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  decoration: InputDecoration(
                    labelText: l10n.emailLabel,
                    border: const OutlineInputBorder(),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? l10n.emailRequired
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _password,
                  obscureText: true,
                  autofillHints: const [AutofillHints.password],
                  decoration: InputDecoration(
                    labelText: l10n.passwordLabel,
                    border: const OutlineInputBorder(),
                  ),
                  validator: (v) =>
                      (v == null || v.isEmpty) ? l10n.passwordRequired : null,
                  onFieldSubmitted: (_) => _submit(auth),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _busy ? null : () => _submit(auth),
                  child: Text(l10n.signIn),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: _busy ? null : () => context.go(AppRoutes.resetPassword),
            child: Text(l10n.forgotPassword),
          ),
          TextButton(
            onPressed: _busy
                ? null
                : () => context.go(_withRedirect(AppRoutes.signUp)),
            child: Text(l10n.signUp),
          ),
        ],
      ),
    );
  }

  /// 戻り先をサインアップ画面へ引き継ぐ（仕様書 3.1.1）。
  String _withRedirect(String base) {
    final redirect = widget.redirect;
    if (redirect == null || redirect.isEmpty) return base;
    return '$base?${AppRoutes.redirectQueryParam}='
        '${Uri.encodeQueryComponent(redirect)}';
  }

  void _submit(dynamic auth) {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    // 初回のログインで users を作るときに、表示言語として残す（2 章）。
    final languageCode = Localizations.localeOf(context).languageCode;
    _run(
      () => auth.signInWithEmail(
        _email.text,
        _password.text,
        languageCode: languageCode,
      ),
    );
  }
}
