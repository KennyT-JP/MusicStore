/// どこに何のダウンロードを出すか（docs/DOWNLOAD-DESIGN.md 6.5 / 7 節）
///
/// **「Web かどうか」を画面のあちこちで判定しないこと**（7.2）。
/// 判定はこの 2 つのプロバイダだけが持ち、画面はそれを見る。
///
/// | プロバイダ | 何を決めるか |
/// | --- | --- |
/// | [audioDownloadSupportedProvider] | **新しい**「端末に保存」を出すか（6.5） |
/// | [legacyAudioDownloadProvider] | **これまでの**「ファイルをダウンロード」を音源に出すか（7.1） |
///
/// 2 つに分けてあるのは、**性質が違う**ため。前者は新機能なので
/// 出さないことが誰の損にもならない。後者は**既存利用者の機能削減**で、
/// 外す時期が決まっている（7.3）。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../platform/downloads_supported.dart';

/// **Web から音源のダウンロードを外したか**（7.3・論点 17）。
///
/// **引き金は「Android の一般公開」です。日付では決めません。**
/// Google Play の一般公開が済んだことだけが条件で、期限も切りません。
///
/// ```
/// 1. 使い方ページと画面に告知を出す（ボタンはまだ外さない）  ← いまここ
/// 2. iOS アプリを App Store で公開する
/// 3. Android アプリを Google Play で一般公開する            ← 引き金
/// 4. ここを true にする
/// ```
///
/// **iOS が出ただけで true にしないこと**（10 節の危険 6）。
/// iOS だけ出た時点で外すと、**Android の利用者には代わりが 1 つも無い**まま
/// 機能が消えます。「アプリでできます」と書いたアプリが、その人の端末には
/// 存在しない状態です。
///
/// **日程が苦しいことは、決定を変える理由になりません。**
/// Google Play のクローズドテスト要件（12 人 × 14 日）が長引くと
/// 「iOS は出たのだから、そろそろ外してよいのでは」という判断が出てきます。
/// その代償は 7.3 に書いてあり、依頼者は承知のうえで待つと決めています。
///
/// **この期間中、Web からは誰でも無料で音源を落とせる状態が続きます。**
/// 「ダウンロードはプレミアム限定」が実質的に成立するのは iOS のアプリ内だけです。
/// 期間の長さは決まっていません。
const bool kWebAudioDownloadRemoved = false;

/// 引き金（7.3）。**テストから差し替えられるようにしてある。**
///
/// 外したあとの姿を、外す前に確かめられないと、
/// **引き金を引いた日に初めて動きを見ることになる。**
final webAudioDownloadRemovedProvider = Provider<bool>(
  (ref) => kWebAudioDownloadRemoved,
);

/// **新しい**「端末に保存」（オフライン用ダウンロード）を出せるか（6.5）。
///
/// **Web では出しません。** 保存先が無いので、押しても何も起きません。
/// 代わりに 7.3 の告知を置きます（`WebDownloadNotice`）。
final audioDownloadSupportedProvider = Provider<bool>(
  (ref) => kDownloadsSupported,
);

/// **これまでの**「ファイルをダウンロード」を、音源に出すか（7.1 / 7.2）。
///
/// - **アプリ（iOS / Android）では出しません。** 「端末に保存」がその役目を
///   継ぎます。同じ画面に似た操作が 2 つ並ぶと、どちらが端末に残るのかが
///   分からなくなります。**アプリには既存利用者がいない**ので、
///   ここに機能削減はありません
/// - **Web では、引き金が引かれるまで残します**（7.3）。代わりが無いまま
///   消すと、その日から困る人がいます
///
/// **音源以外のファイル（楽譜 PDF など）と URL の項目は、この判定の外**です。
/// 論点 2 のとおり、従来どおり開けます。
final legacyAudioDownloadProvider = Provider<bool>((ref) {
  if (ref.watch(audioDownloadSupportedProvider)) return false;
  return !ref.watch(webAudioDownloadRemovedProvider);
});

/// Web に 7.3 の告知を出すか。
///
/// **外したあとも出し続けない。** 外し終えたら、告知は「これから終了します」
/// ではなく事実に変わるので、画面からは下ろして使い方ページに残します。
final showsWebDownloadNoticeProvider = Provider<bool>((ref) {
  if (ref.watch(audioDownloadSupportedProvider)) return false;
  return !ref.watch(webAudioDownloadRemovedProvider);
});
