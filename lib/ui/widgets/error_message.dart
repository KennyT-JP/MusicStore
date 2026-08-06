/// エラー表示の共通部品
library;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// 画面上部に出すエラー。
class ErrorMessage extends StatelessWidget {
  const ErrorMessage(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, color: scheme.onErrorContainer, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: scheme.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}

/// Firebase Auth のエラーを、利用者に伝わる文言に変換する。
///
/// 原因が分かるものだけ個別に訳し、それ以外は汎用の文言に倒す。
/// 「メールアドレスが存在しない」と「パスワードが違う」を区別すると
/// アカウントの有無を外部に漏らすため、まとめて同じ文言にする。
String describeAuthError(BuildContext context, FirebaseAuthException e) {
  final l10n = AppL10n.of(context);
  // **文言はすべて l10n を通す（監査 S20）。** ここは日本語を直書きして
  // おり、英語表示に切り替えてもログイン失敗時だけ日本語が出ていた。
  switch (e.code) {
    case 'invalid-email':
      return l10n.authInvalidEmail;
    case 'user-disabled':
      return l10n.authUserDisabled;
    case 'user-not-found':
    case 'wrong-password':
    case 'invalid-credential':
      return l10n.authWrongCredential;
    case 'email-already-in-use':
      return l10n.authEmailInUse;
    case 'weak-password':
      return l10n.authWeakPassword;
    case 'too-many-requests':
      return l10n.authTooManyRequests;
    case 'popup-closed-by-user':
    case 'cancelled-popup-request':
      return l10n.authPopupClosed;
    case 'network-request-failed':
      return l10n.authNetworkFailed;
    default:
      return l10n.errorGeneric;
  }
}
