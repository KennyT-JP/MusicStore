/// サインアップ画面（仕様書 3.2 / 14.2）
///
/// メールで登録した場合は確認メールを送り、確認が済むまでアプリを使えない
/// （仕様書 3.1）。ルーターがメール確認待ち画面へ送る。
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

class SignUpScreen extends ConsumerStatefulWidget {
  const SignUpScreen({super.key, this.redirect});

  final String? redirect;

  @override
  ConsumerState<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends ConsumerState<SignUpScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();

  bool _busy = false;
  String? _error;

  /// 原因が 1 つに絞れないときだけ入る、技術的な内容。
  String? _errorDetail;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
      _errorDetail = null;
    });
    try {
      await action();
    } on FirebaseAuthException catch (e) {
      if (mounted) {
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
    final auth = ref.watch(authRepositoryProvider);

    return AuthScaffold(
      title: l10n.signUp,
      busy: _busy,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null) ...[
            ErrorMessage(_error!, detail: _errorDetail),
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
                  controller: _name,
                  decoration: InputDecoration(
                    labelText: l10n.displayName,
                    border: const OutlineInputBorder(),
                    helperText: l10n.displayNameHelper,
                  ),
                ),
                const SizedBox(height: 12),
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
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _password,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: l10n.passwordLabel,
                    border: const OutlineInputBorder(),
                    helperText: l10n.passwordHelper,
                  ),
                  validator: (v) => (v == null || v.length < 6)
                      ? l10n.passwordTooShort
                      : null,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: Text(l10n.signUp),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: _busy ? null : () => context.go(_withRedirect()),
            child: Text(l10n.signIn),
          ),
        ],
      ),
    );
  }

  String _withRedirect() {
    final redirect = widget.redirect;
    if (redirect == null || redirect.isEmpty) return AppRoutes.signIn;
    return '${AppRoutes.signIn}?${AppRoutes.redirectQueryParam}='
        '${Uri.encodeQueryComponent(redirect)}';
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final auth = ref.read(authRepositoryProvider);
    _run(
      () => auth.signUpWithEmail(
        email: _email.text,
        password: _password.text,
        displayName: _name.text,
        // いま画面に出ている言語で確認メールを送る（仕様書 2 章）。
        languageCode: Localizations.localeOf(context).languageCode,
      ),
    );
  }
}
