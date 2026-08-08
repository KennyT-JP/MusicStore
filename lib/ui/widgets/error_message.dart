/// エラー表示の共通部品
library;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../data/repositories/functions_repository.dart';
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

/// Cloud Functions のエラーを、利用者に伝わる文言に変換する。
///
/// **サーバーが返す文をそのまま出さない。** 以前は `e.message` を無加工で
/// 表示しており、呼び出し口 15 本のうち 14 本がこの形だった。そのため
/// 英語表示にしていても、申請・承認・招待・退会・容量変更のエラーは
/// すべて日本語で出ていた（監査 第2回）。しかも
/// 「あなたは現在ただ 1 人のサイト管理者です」のように、**同じ文が
/// l10n に用意されているのに使われていない**ものが複数あった。
///
/// サーバーは `details.code` に符号を載せる（functions/src/errors.ts）。
/// ここでその符号から文言を引き、知らない符号のときだけサーバーの文に倒す。
String describeFunctionsError(
  BuildContext context,
  FunctionsCallException e,
) {
  final l10n = AppL10n.of(context);
  return switch (e.reason) {
    'signInRequired' => l10n.functionErrorSignInRequired,
    'emailNotVerified' => l10n.functionErrorEmailNotVerified,
    'siteAdminOnly' => l10n.functionErrorSiteAdminOnly,
    'listAdminOnly' => l10n.functionErrorListAdminOnly,
    'listNotFound' => l10n.functionErrorListNotFound,
    'userNotFound' => l10n.functionErrorUserNotFound,
    'requestNotFound' => l10n.functionErrorRequestNotFound,
    'requestAlreadyHandled' => l10n.functionErrorRequestAlreadyHandled,
    'listNameMissing' => l10n.functionErrorListNameMissing,
    'requesterUnknown' => l10n.functionErrorRequesterUnknown,
    'invalidTrackCount' => l10n.functionErrorInvalidTrackCount,
    'invalidUserCount' => l10n.functionErrorInvalidUserCount,
    'invalidQuota' => l10n.functionErrorInvalidQuota,
    'lastSiteAdmin' => l10n.functionErrorLastSiteAdmin,
    'alreadyMember' => l10n.functionErrorAlreadyMember,
    'shareLinkNotFound' => l10n.functionErrorShareLinkNotFound,
    'shareLinkRevoked' => l10n.functionErrorShareLinkRevoked,
    'itemNotFound' => l10n.functionErrorItemNotFound,
    'roleNotAllowed' => l10n.functionErrorRoleNotAllowed,
    'missingField' => l10n.functionErrorMissingField,
    'fieldTooLong' => l10n.functionErrorFieldTooLong,
    'selfNotAllowed' => l10n.functionErrorSelfNotAllowed,
    'emailInvalid' => l10n.functionErrorEmailInvalid,
    'passwordTooShort' => l10n.functionErrorPasswordTooShort,
    'emailAlreadyInUse' => l10n.functionErrorEmailAlreadyInUse,
    'listNameTaken' => l10n.functionErrorListNameTaken(
      e.params['listName'] ?? '',
    ),
    // まだ翻訳を用意していない符号。サーバーの文を出す。
    // サーバーが文を返さなかったときは、一般的な文言に倒す。
    // ここで日本語を書き足すと、英語表示でも日本語が出る。
    _ => e.message.isEmpty ? l10n.errorGeneric : e.message,
  };
}
