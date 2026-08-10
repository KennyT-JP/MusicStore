/// 認証画面の共通の外枠（仕様書 14.2）
///
/// ログイン・サインアップ・メール確認待ち・パスワード再設定で使う。
/// これらはナビゲーションを持たないため、AppShell の外に置いている。
library;

import 'package:flutter/material.dart';

import '../../env/app_environment.dart';
import '../../l10n/app_localizations.dart';
import 'brand_logo.dart';

class AuthScaffold extends StatelessWidget {
  const AuthScaffold({
    super.key,
    required this.title,
    required this.child,
    this.busy = false,
  });

  final String title;
  final Widget child;

  /// 処理中はローディングを重ねて二重送信を防ぐ。
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      body: Stack(
        children: [
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
