/// 曲ごとのダウンロードボタン（docs/DOWNLOAD-DESIGN.md 6.2 / 6.5）
///
/// **状態は 4 つ。**
///
/// | 状態 | 見え方 |
/// | --- | --- |
/// | 未ダウンロード | ダウンロードのアイコン |
/// | ダウンロード中 | 進捗の輪＋押すと中止 |
/// | ダウンロード済み | チェックの付いたアイコン。押すと「端末から削除しますか」 |
/// | 使えない | 6.5 のとおり（薄く出す／出さない） |
///
/// **アイコンを流用しない**（6.2）。`Icons.download_outlined` は
/// `item_external_action.dart` が「URL を開く」の意味で使っている。
/// **同じ絵で違う動きをさせないこと。**
///
/// ## 出し分け（6.5）
///
/// | 相手 | 見せ方 |
/// | --- | --- |
/// | プレミアムでない人 | **薄く出す。** 押すと案内＋クーポン入力への導線（論点 19） |
/// | 閲覧者（viewer） | **出さない。** 契約しても使えないので、押せるものを見せない |
/// | サイト管理者でメンバーでない人 | **出さない**（論点 18）。落とせても次の起動で消える |
/// | 判定が届く前 | **どちらも出さない。** 一瞬「使えません」が見える |
/// | Web で開いている人 | **出さない。** 7 節の告知に置き換える |
///
/// **判定はここに書かない。** `canDownloadProvider` と
/// `showsDownloadButtonProvider`（`lib/providers/download_provider.dart`）が
/// `Permissions.canDownload` を呼んでいる。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/list_item.dart';
import '../../domain/download_target.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/download_provider.dart';
import '../downloads/download_jobs.dart';
import '../downloads/download_support.dart';
import '../routes.dart';
import 'async_view.dart';

/// この項目を端末に保存できる形か（3.3・論点 5）。
///
/// **判定を別に作らない**（2.3）。`downloadTargetKind` が
/// `playback.dart` の白リストを通している。
bool isDownloadableItem(ListItem item) {
  final file = item.file;
  if (item.kind != ItemKind.file || file == null) return false;
  if (item.isDeleted) return false;
  return downloadTargetKind(
        contentType: file.contentType,
        fileName: file.fileName,
      ) ==
      DownloadTargetKind.audio;
}

class ItemDownloadButton extends ConsumerWidget {
  const ItemDownloadButton({
    super.key,
    required this.listId,
    required this.listName,
    required this.item,
  });

  final String listId;

  /// オフラインで「どのリストのものか」を出すために端末へ持つ（論点 8）。
  final String listName;

  final ListItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);

    // **Web には保存先が無い**（6.5）。7 節の告知が代わりに出る。
    if (!ref.watch(audioDownloadSupportedProvider)) {
      return const SizedBox.shrink();
    }
    if (!isDownloadableItem(item)) return const SizedBox.shrink();

    // 閲覧者と、メンバーでないサイト管理者には出さない（6.5・論点 9 / 18）。
    if (!ref.watch(showsDownloadButtonProvider(listId))) {
      return const SizedBox.shrink();
    }

    final canDownload = ref.watch(canDownloadProvider(listId));

    // **届く前はどちらも出さない**（6.5）。読み込み中に「使えない」を
    // 確定表示すると、プレミアムの人に一瞬それが見える。
    // 読めなかったときも同じ扱いにする——分からないことを
    // 「使えない」と断定しない。
    if (canDownload.isLoading || canDownload.hasError) {
      return const SizedBox.shrink();
    }

    if (canDownload.value != true) {
      return _PremiumGateButton(l10n: l10n);
    }

    final job = ref.watch(downloadJobsProvider).items[item.id];
    if (job != null) {
      return _CancelButton(job: job, itemId: item.id, l10n: l10n);
    }

    final downloaded =
        ref
            .watch(downloadsProvider)
            .value
            ?.items
            .any((i) => i.itemId == item.id) ??
        false;

    return downloaded
        ? IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: l10n.downloadedToDevice,
            // **チェックの付いたアイコン**（6.2）。押すと端末から消す。
            icon: const Icon(Icons.offline_pin),
            onPressed: () => confirmRemoveDownload(
              context,
              ref,
              listId: listId,
              itemId: item.id,
              title: item.displayLabel(),
            ),
          )
        : IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: l10n.downloadToDevice,
            // **`Icons.download_outlined` は使わない**（6.2）。
            icon: const Icon(Icons.cloud_download_outlined),
            onPressed: () => startItemDownload(
              context,
              ref,
              listId: listId,
              listName: listName,
              item: item,
            ),
          );
  }
}

/// プレミアムでない人に見せるボタン（6.5・論点 19）。
///
/// **隠さない。** 存在を知らせないと、契約する理由も伝わらない。
/// **「壊れている」ではなく「門がある」と伝わる形にすること**——
/// 押せて、押すと何のための門かが分かる。
class _PremiumGateButton extends StatelessWidget {
  const _PremiumGateButton({required this.l10n});

  final AppL10n l10n;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IconButton(
      visualDensity: VisualDensity.compact,
      tooltip: l10n.downloadPremiumOnly,
      icon: Icon(Icons.cloud_download_outlined, color: scheme.outline),
      onPressed: () => showPremiumRequiredForDownload(context),
    );
  }
}

/// ダウンロード中（6.2）。進捗の輪を出し、押すと中止する。
class _CancelButton extends ConsumerWidget {
  const _CancelButton({
    required this.job,
    required this.itemId,
    required this.l10n,
  });

  final ItemDownloadJob job;
  final String itemId;
  final AppL10n l10n;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IconButton(
      visualDensity: VisualDensity.compact,
      tooltip: l10n.downloadCancel,
      icon: SizedBox(
        width: 24,
        height: 24,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // **全体の大きさが分かるまでは不定の輪。**
            CircularProgressIndicator(strokeWidth: 2, value: job.ratio),
            const Icon(Icons.close, size: 12),
          ],
        ),
      ),
      onPressed: () =>
          ref.read(downloadJobsProvider.notifier).cancelItem(itemId),
    );
  }
}

/// プレミアムの案内（6.5・論点 19）。**クーポン入力への導線を必ず置く。**
Future<void> showPremiumRequiredForDownload(BuildContext context) async {
  final l10n = AppL10n.of(context);
  final go = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.downloadPremiumOnly),
      content: Text(l10n.downloadPremiumOnlyBody),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(l10n.close),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(l10n.downloadPremiumOnlyCta),
        ),
      ],
    ),
  );
  if (go == true && context.mounted) context.go(AppRoutes.settings);
}

/// 端末から 1 曲消す（6.2・論点 6）。
///
/// **「曲もリストも消えません」を必ず書く**（2.1）。ダウンロードは
/// 「機能」であって「資産」ではない。
Future<void> confirmRemoveDownload(
  BuildContext context,
  WidgetRef ref, {
  required String listId,
  required String itemId,
  required String title,
}) async {
  final l10n = AppL10n.of(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.downloadRemove),
      content: Text(l10n.downloadRemoveBody(title)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(l10n.downloadRemove),
        ),
      ],
    ),
  );
  if (confirmed != true) return;

  try {
    await ref
        .read(downloadsProvider.notifier)
        .removeItem(listId: listId, itemId: itemId);
  } catch (_) {
    if (context.mounted) _say(context, l10n.errorGeneric);
  }
}

/// 1 曲を落とし始めて、結果を知らせる（4.1・6.2）。
///
/// **押した人に何が起きたかを伝える。** 黙って何も起きないのがいちばん困る。
/// **中止だけは知らせない**——押したとおりに止まっただけで、失敗ではない。
Future<void> startItemDownload(
  BuildContext context,
  WidgetRef ref, {
  required String listId,
  required String listName,
  required ListItem item,
}) async {
  final l10n = AppL10n.of(context);
  // **「アプリを開いたままに」を先に出す**（4.1 の B の代償）。
  // `DownloadTask` はアプリのプロセスと寿命を共にし、閉じると止まる。
  // **「再開」とは書かない**——できないことを言葉で約束しない。
  _say(context, l10n.downloadKeepAppOpen);

  final outcome = await ref
      .read(downloadJobsProvider.notifier)
      .downloadItem(
        listId: listId,
        listName: listName,
        item: item,
        withdrawnLabel: l10n.withdrawnUser,
      );

  if (!context.mounted) return;
  final message = messageForDownloadOutcome(l10n, outcome);
  if (message != null) _say(context, message);
}

/// 結果に対する文言（4.1 の「途中で失敗したとき」）。null なら黙る。
String? messageForDownloadOutcome(AppL10n l10n, DownloadOutcome outcome) =>
    switch (outcome) {
      DownloadOutcome.done => l10n.downloadDone,
      // **押したとおりに止まっただけ。** 失敗として知らせない。
      DownloadOutcome.canceled => null,
      // **「モバイルデータを使いません」とは書かない**（4.6）。
      DownloadOutcome.blockedByNetwork => l10n.downloadNeedsWifi,
      DownloadOutcome.notSupported => l10n.downloadNotSupportedFile,
      DownloadOutcome.permissionDenied => l10n.downloadPermissionLost,
      DownloadOutcome.unavailable => l10n.downloadUnavailableHere,
      DownloadOutcome.failed => l10n.downloadFailed,
    };

void _say(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

/// 端末に保存済みの合計（6.4 の使用量）を、決まった形で出す。
String formatDownloadUsage(
  AppL10n l10n, {
  required int bytes,
  required int count,
}) => l10n.downloadsUsage(formatBytes(bytes), count);
