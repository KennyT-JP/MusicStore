/// 同期の結果を利用者に知らせる（docs/DOWNLOAD-DESIGN.md 4.4）
///
/// > **画面に何が起きたかを出します**——黙って消えると、
/// > 利用者は「アプリが勝手に消した」と受け取ります。
///
/// **判定はここに 1 つも書かない。** 何を消すか・落とし直すかは
/// `DownloadSyncPolicy.decide`（domain）が決め、
/// `DownloadsController.syncFromServer` が実行する。ここは**結果を文章に
/// するだけ**の純関数で、通信も端末のファイルも要らない形にしてある
/// （`lib/domain/playback.dart` の流儀）。
library;

import '../../data/repositories/download_repository.dart';
import '../../l10n/app_localizations.dart';

/// 同期で起きたことを 1 つの文章にする。**何も起きていなければ null。**
///
/// - **削除は必ず知らせる**（4.4）。消えたことに気づけないのがいちばん困る
/// - **1 曲なら曲名を出す。** 「1 曲を削除しました」では、どれが消えたのか
///   分からない。複数のときは件数にする——曲名を並べると通知に収まらない
/// - **落とし直し（差し替え）も知らせる。** 端末の中身が黙って変わっている
/// - **失敗（`failed`）は知らせない。** 古いほうが残っていて聴けるので、
///   利用者から見て何も変わっていない。次の起動でもう一度試される
String? describeDownloadSync(AppL10n l10n, DownloadSyncReport report) {
  final lines = <String>[];

  if (report.removed.length == 1) {
    final item = report.removed.first;
    lines.add(
      l10n.downloadSyncRemovedOne(
        item.title?.trim().isNotEmpty == true
            ? item.title!.trim()
            : item.fileName,
      ),
    );
  } else if (report.removed.length > 1) {
    lines.add(l10n.downloadSyncRemovedMany(report.removed.length));
  }

  if (report.replaced.isNotEmpty) {
    lines.add(l10n.downloadSyncReplaced(report.replaced.length));
  }

  return lines.isEmpty ? null : lines.join('\n');
}
