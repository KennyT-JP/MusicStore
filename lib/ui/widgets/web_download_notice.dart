/// Web から音源のダウンロードを外すことの告知（docs/DOWNLOAD-DESIGN.md 7.3）
///
/// **既存利用者の機能削減にあたる**（AUDIT-CHECKLIST 観点 6）ので、
/// 外すより先に知らせる。順序は 7.3 のとおり。
///
/// ```
/// 1. 使い方ページと画面に告知を出す（ボタンはまだ外さない）
/// 2. iOS アプリを App Store で公開する
/// 3. Android アプリを Google Play で一般公開する   ← 引き金
/// 4. Web からボタンを外す
/// ```
///
/// ## 文面の決まり
///
/// - **「終了します」を先に、「できること」をすぐ後ろに書く。**
///   順序が逆だと、何が変わるのか読み取れない
/// - **「楽譜やその他のファイルは従来どおり」を必ず書く**（論点 2）。
///   これを書かないと、全部落とせなくなったと受け取られる
/// - **日付を書かない**（論点 17）。引き金は Android の一般公開で、
///   その日程は未定。**「〇月〇日に終了します」と告知して、その日に
///   Android が出ていないと、告知そのものを取り消すことになる**
/// - **日英の両方**（`lib/l10n/` と `docs/manual/{ja,en}.html`）
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../downloads/download_support.dart';

/// 帯を閉じたか。**セッションのあいだだけ覚える。**
///
/// 端末に覚えさせないのは、**まだ外していない**ため——外すまでのあいだ、
/// 別の日に開いた人にはもう一度知らせてよい。
/// 「1 回だけ」は 1 つの画面の中での話で、閉じたのに描き直しのたびに
/// 戻ってくるのを防ぐためにある（7.3）。
final webDownloadNoticeDismissedProvider =
    NotifierProvider<WebDownloadNoticeDismissed, bool>(
      WebDownloadNoticeDismissed.new,
    );

class WebDownloadNoticeDismissed extends Notifier<bool> {
  @override
  bool build() => false;

  void dismiss() => state = true;
}

/// リスト詳細の上に出す帯（7.3）。**閉じられるようにする。**
class WebDownloadNotice extends ConsumerWidget {
  const WebDownloadNotice({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(showsWebDownloadNoticeProvider)) {
      return const SizedBox.shrink();
    }
    if (ref.watch(webDownloadNoticeDismissedProvider)) {
      return const SizedBox.shrink();
    }

    final l10n = AppL10n.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      width: double.infinity,
      color: scheme.tertiaryContainer,
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.webDownloadNoticeTitle,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: scheme.onTertiaryContainer,
                  ),
                ),
                const SizedBox(height: 4),
                // **「終了します」が先、「できること」がすぐ後ろ**（7.3）。
                for (final line in [
                  l10n.webDownloadNoticeBody1,
                  l10n.webDownloadNoticeBody2,
                  l10n.webDownloadNoticeBody3,
                ])
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      line,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onTertiaryContainer,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: l10n.close,
            icon: Icon(Icons.close, color: scheme.onTertiaryContainer),
            onPressed: () =>
                ref.read(webDownloadNoticeDismissedProvider.notifier).dismiss(),
          ),
        ],
      ),
    );
  }
}

/// ボタンがあった場所に置く文（7.3）。
///
/// **空白にしない。** 消えた場所に何も無いと、壊れたようにしか見えない。
class WebDownloadReplacement extends ConsumerWidget {
  const WebDownloadReplacement({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // アプリ側では出さない。ここには「端末に保存」のボタンがある。
    if (ref.watch(audioDownloadSupportedProvider)) {
      return const SizedBox.shrink();
    }
    // 外す前は、これまでのボタンがまだ出ている。置き換える相手がいない。
    if (!ref.watch(webAudioDownloadRemovedProvider)) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Text(
        AppL10n.of(context).webDownloadReplacement,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
