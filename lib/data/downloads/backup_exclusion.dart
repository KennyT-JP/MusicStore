/// iOS のバックアップ除外（docs/DOWNLOAD-DESIGN.md 3.2）
///
/// **再取得できるデータをバックアップに載せてはいけない。** 理由は 2 つ。
///
/// 1. **Apple の iOS Data Storage Guidelines。** 再ダウンロードできるものを
///    iCloud バックアップに入れると、審査でリジェクトの理由になる
/// 2. **消したはずのものが復元で戻る。** 論点 12 で「プレミアム失効時に
///    端末のファイルを削除する」と決めた以上、バックアップに残っていると
///    機種変更するだけで復活し、**削除の決定が意味を失う**
///
/// `Library/Application Support` は**既定でバックアップ対象**なので、
/// `downloads/` に「バックアップから除外」の印を付ける。
///
/// ## MethodChannel を 1 本足す（3.2）
///
/// **既存のパッケージにこれを行うものは無い。** `path_provider` にも無い。
/// iOS 側の受け口は `ios/Runner/AppDelegate.swift` に足す。
///
/// ```swift
/// var url = URL(fileURLWithPath: path)
/// var values = URLResourceValues()
/// values.isExcludedFromBackup = true
/// try url.setResourceValues(&values)
/// ```
///
/// - **ディレクトリに 1 回付ければ配下も対象になる。** ただし
///   **ディレクトリを作り直すと消える**ので、起動時に毎回、冪等に設定する
/// - **確かめる手段を用意する**（3.2）。付けたつもりで付いていないのが
///   最悪なので、同じ channel に [isExcluded] を置いた
///
/// ## Android 側はここに書かない（3.2）
///
/// `android/app/src/main/res/xml/data_extraction_rules.xml` と
/// `AndroidManifest.xml` の `allowBackup="false"` で済んでいる。
/// **あのファイルの所有は docs/MOBILE-APP-DESIGN.md 側**で、
/// 主目的は Firebase Auth のリフレッシュトークンの持ち出し防止である。
/// **落ちていないことは `test/domain/android_platform_test.dart` が見張る。**
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// iOS 側とのやり取り（3.2）。
///
/// **iOS 以外では何もしない。** Android はマニフェスト側で済んでおり、
/// Web と Dart VM（テスト）には相手が居ない。
class BackupExclusion {
  /// 引数は**テストのためだけ**にある。本番は引数なしで作る。
  ///
  /// **名前付きにしていない。** private なフィールドは名前付き引数の
  /// 初期化仮引数（`this._channel`）にできず、初期化子で書き写すことに
  /// なって `prefer_initializing_formals` に当たる。
  const BackupExclusion([
    this._channel = _defaultChannel,
    this._platformOverride,
  ]);

  /// アプリ ID（docs/MOBILE-APP-DESIGN.md 3-3）に揃えた名前。
  static const MethodChannel _defaultChannel = MethodChannel(
    'jp.sessionconcierge.trackcabinet/backup_exclusion',
  );

  final MethodChannel _channel;

  /// テストのためだけにある。本番では null。
  final TargetPlatform? _platformOverride;

  TargetPlatform get _platform => _platformOverride ?? defaultTargetPlatform;

  /// バックアップから外す。**起動のたびに呼んでよい**（冪等）。
  ///
  /// **失敗しても落とさない。** 受け口がまだ無い端末（iOS 側の
  /// `AppDelegate.swift` を足す前）でも、アプリは動き続けられる。
  /// 付いているかどうかは [isExcluded] で確かめる。
  Future<void> exclude(String absolutePath) async {
    if (_platform != TargetPlatform.iOS) return;
    try {
      await _channel.invokeMethod<void>('exclude', {'path': absolutePath});
    } on MissingPluginException {
      // iOS 側の受け口がまだ無い。**握りつぶすのはここだけ**——
      // 付いているかは isExcluded が別に答える。
    } on PlatformException {
      // 端末側の都合。次の起動でもう一度試す。
    }
  }

  /// いま印が付いているか（3.2 の「確かめる手段」）。
  ///
  /// - iOS 以外 → **null**（「そもそも要らない」を false と混ぜない）
  /// - 受け口が無い・失敗した → **null**（「付いていない」と断定しない）
  Future<bool?> isExcluded(String absolutePath) async {
    if (_platform != TargetPlatform.iOS) return null;
    try {
      return await _channel.invokeMethod<bool>('isExcluded', {
        'path': absolutePath,
      });
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }
}
