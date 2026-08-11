/// メール確認待ち画面（仕様書 3.1 / 14.2）
///
/// メール＋パスワードで登録した場合、リンクを押すまでアプリを使えない。
/// Google 連携での登録は確認不要のため、この画面を通らない。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/help_links.dart';
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

  /// 確認が済んだかを繰り返し確かめるためのもの。
  ///
  /// **メールのリンクは別のタブ（別の端末のこともある）で開かれる。**
  /// 開いた側で確認が済んでも、この画面は何も知らない。以前は利用者が
  /// 「確認が済んだので次へ」を押すまで待ち続けていた。
  ///
  /// リンクを踏んだら、こちら側も気づいて自動で先へ進めるようにする。
  Timer? _poll;

  /// 自動で確かめる間隔。
  ///
  /// 短くしすぎると Auth への問い合わせが増える。リンクを踏んでから
  /// 数秒で進めば、待たされている感じはしない。
  static const _pollInterval = Duration(seconds: 3);

  /// 自動で確かめるのをやめるまでの回数（3 秒 × 200 = 10 分）。
  ///
  /// **止めどきを決めておく（監査 第3回）。** 以前は画面を開いている間
  /// ずっと 3 秒ごとに問い合わせ続けていた。この画面は「メールを見に
  /// 行っている間」開きっぱなしになりやすく、そのまま忘れられることも
  /// ある。1 時間で 1,200 回になり、**Auth の回数制限に当たって
  /// `too-many-requests` で確認そのものができなくなる**恐れがあった。
  ///
  /// 止まったあとも、画面の「確認」を押せばいつでも確かめられる。
  static const _pollLimit = 200;

  int _polls = 0;

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(_pollInterval, (timer) {
      if (_polls++ >= _pollLimit) {
        timer.cancel();
        return;
      }
      _checkQuietly();
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  /// 裏で確かめる。まだなら何も言わない。
  ///
  /// 押したときの確認（_recheck）と違い、**済んでいないことを画面に
  /// 出さない**。3 秒ごとに「まだです」と出ると落ち着かないため。
  Future<void> _checkQuietly() async {
    if (_busy) return;
    try {
      final verified = await ref
          .read(authRepositoryProvider)
          .reloadEmailVerification();
      if (!mounted || !verified) return;
      _poll?.cancel();
      // ユーザー情報が更新されると authStateProvider が変わり、
      // ルーターのリダイレクトが本来の画面へ運ぶ（仕様書 14.3）。
      ref.invalidate(firebaseUserProvider);
    } catch (_) {
      // 通信が一時的に切れただけかもしれない。次の周期で試す。
    }
  }

  Future<void> _resend() async {
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    try {
      await ref
          .read(authRepositoryProvider)
          .resendVerificationEmail(
            languageCode: Localizations.localeOf(context).languageCode,
          );
      if (mounted) setState(() => _message = AppL10n.of(context).verificationResent);
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
        setState(() => _message = AppL10n.of(context).verificationNotYet);
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
      helpTopic: HelpTopic.account,
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
          const SizedBox(height: 8),
          Text(
            l10n.verifyEmailAutoDetect,
            style: Theme.of(context).textTheme.bodySmall,
          ),
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
