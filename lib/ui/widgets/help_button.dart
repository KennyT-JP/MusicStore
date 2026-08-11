/// 使い方を開くボタン（仕様書 14.2）
library;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../domain/help_links.dart';
import '../../l10n/app_localizations.dart';

/// いま出ている画面に対応する説明を、別のタブで開く。
///
/// **別のタブで開く。** 同じタブで出ると、書きかけの入力が消える。
///
/// 開く言語は**アプリの表示言語**に従う（`domain/help_links.dart`）。
class HelpButton extends StatelessWidget {
  const HelpButton({required this.topic, super.key});

  final HelpTopic topic;

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    return IconButton(
      icon: const Icon(Icons.help_outline),
      tooltip: l10n.help,
      onPressed: () {
        final url = helpUrlFor(
          topic,
          Localizations.localeOf(context).languageCode,
        );
        // 失敗しても画面は壊さない。開けないときは何も起きない。
        launchUrl(Uri.parse(url), webOnlyWindowName: '_blank');
      },
    );
  }
}
