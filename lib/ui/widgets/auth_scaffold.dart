/// 認証画面の共通の外枠（仕様書 14.2）
///
/// ログイン・サインアップ・メール確認待ち・パスワード再設定で使う。
/// これらはナビゲーションを持たないため、AppShell の外に置いている。
library;

import 'package:flutter/material.dart';

import '../../domain/help_links.dart';
import '../../env/app_environment.dart';
import '../../l10n/app_localizations.dart';
import 'brand_logo.dart';
import 'help_button.dart';

class AuthScaffold extends StatelessWidget {
  const AuthScaffold({
    super.key,
    required this.title,
    required this.child,
    required this.helpTopic,
    this.busy = false,
  });

  final String title;
  final Widget child;

  /// 右上のヘルプが開く節（14.2）。
  final HelpTopic helpTopic;

  /// 処理中はローディングを重ねて二重送信を防ぐ。
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      body: Stack(
        children: [
          // **使い方への入口を、ここにも置く**（14.2）。
          // 登録や確認メールでつまずく人が最初に見る画面で、
          // ここに導線が無いと、どこにも聞きに行けない。
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: HelpButton(topic: helpTopic),
            ),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (AppEnvironment.current.showEnvironmentBanner) ...[
                        Align(
                          alignment: Alignment.center,
                          child: Chip(
                            label: Text(l10n.environmentBannerStaging),
                            backgroundColor:
                                theme.colorScheme.tertiaryContainer,
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      // **アプリ名は文字ではなくロゴで出す**
                      // （brand/README.md）。最初に目に入る画面なので、
                      // 何のアプリかがひと目で分かるようにする。
                      // 読み上げには、いま出ている言語のアプリ名を伝える。
                      Center(
                        child: BrandLogo.vertical(
                          semanticLabel: l10n.appTitle,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 32),
                      child,
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (busy)
            const ColoredBox(
              color: Color(0x33000000),
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }
}

/// 「または」を挟んだ区切り線。
///
/// メール＋パスワードと、外部サービスでのログインを分ける。
/// **どちらか一方でよい**ことが、線だけより伝わる。
class OrDivider extends StatelessWidget {
  const OrDivider({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        const Expanded(child: Divider()),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            AppL10n.of(context).orSeparator,
            style: TextStyle(color: scheme.outline, fontSize: 12),
          ),
        ),
        const Expanded(child: Divider()),
      ],
    );
  }
}

/// Google のボタンに置く「G」。
///
/// **画像を持ち込まない。** ロゴの画像は配布の条件が別にあるため、
/// 文字で代用する。色は Google の青に寄せてある。
class GoogleMark extends StatelessWidget {
  const GoogleMark({super.key});

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 18,
      height: 18,
      child: Center(
        child: Text(
          'G',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: Color(0xFF4285F4),
          ),
        ),
      ),
    );
  }
}
