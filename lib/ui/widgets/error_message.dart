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
  switch (e.code) {
    case 'invalid-email':
      return 'メールアドレスの形式が正しくありません。';
    case 'user-disabled':
      return 'このアカウントは無効になっています。';
    case 'user-not-found':
    case 'wrong-password':
    case 'invalid-credential':
      return 'メールアドレスまたはパスワードが違います。';
    case 'email-already-in-use':
      return 'このメールアドレスはすでに使われています。ログインしてください。';
    case 'weak-password':
      return 'パスワードが短すぎます。6 文字以上にしてください。';
    case 'too-many-requests':
      return '試行回数が多すぎます。しばらく待ってからお試しください。';
    case 'popup-closed-by-user':
    case 'cancelled-popup-request':
      return 'ログインがキャンセルされました。';
    case 'network-request-failed':
      return 'ネットワークに接続できませんでした。通信状況をご確認ください。';
    default:
      return l10n.errorGeneric;
  }
}
