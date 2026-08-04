/// 見つからないパスの表示
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/app_localizations.dart';
import '../routes.dart';
import '../widgets/async_view.dart';

class NotFoundScreen extends StatelessWidget {
  const NotFoundScreen({super.key, this.location});

  /// 開こうとしたパス。原因の切り分けに使えるよう表示する。
  final String? location;

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    return Scaffold(
      body: EmptyState(
        icon: Icons.search_off,
        title: l10n.notFound,
        description: location,
        action: FilledButton(
          onPressed: () => context.go(AppRoutes.home),
          child: Text(l10n.navHome),
        ),
      ),
    );
  }
}
