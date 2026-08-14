/// 一覧から、外部で開く・ダウンロードする（仕様書 6.4）
///
/// **文字ではなくボタンにする**（2026-08-14 の依頼者の判断）。
/// 一覧の行を押すと曲の詳細へ行くので、同じ行の文字にリンクを付けると
/// **押す場所によって違うことが起きる**。狭い画面では押し間違いが起きる。
/// 再生ボタンと同じく、専用のボタンを右に置く。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/models/list_item.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/app_providers.dart';

class ItemExternalAction extends ConsumerWidget {
  const ItemExternalAction({super.key, required this.item});

  final ListItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final isFile = item.kind == ItemKind.file;

    return IconButton(
      icon: Icon(isFile ? Icons.download_outlined : Icons.open_in_new),
      // **読み上げにも意味を持たせる。** アイコンだけだと何が起きるか
      // 分からない（英語の画面で日本語を読み上げないよう l10n から取る）。
      tooltip: isFile ? l10n.downloadFile : l10n.openLink,
      onPressed: () => _run(context, ref, l10n),
    );
  }

  Future<void> _run(BuildContext context, WidgetRef ref, AppL10n l10n) async {
    try {
      final target = item.kind == ItemKind.file
          ? await ref
                .read(itemRepositoryProvider)
                .downloadUrl(item.file!.storagePath)
          : item.url;

      final uri = Uri.tryParse(target ?? '');
      // **開けない指定は黙って無視しない。** 何も起きないと、
      // 押した人には壊れているのか分からない。
      if (uri == null || !context.mounted) {
        if (context.mounted) _warn(context, l10n);
        return;
      }

      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && context.mounted) _warn(context, l10n);
    } catch (_) {
      if (context.mounted) _warn(context, l10n);
    }
  }

  void _warn(BuildContext context, AppL10n l10n) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l10n.errorGeneric)));
  }
}
