import Flutter
import UIKit

/// iOS のバックアップ除外（docs/DOWNLOAD-DESIGN.md 3.2）の受け口。
///
/// **再取得できるデータを iCloud バックアップに載せない。** 理由は 2 つ。
///
/// 1. Apple の iOS Data Storage Guidelines。再ダウンロードできるものを
///    バックアップに入れると、審査でリジェクトの理由になる
/// 2. **消したはずのものが復元で戻る。** 論点 12 で「プレミアム失効時に
///    端末のファイルを削除する」と決めた以上、バックアップに残っていると
///    機種変更するだけで復活し、**削除の決定が意味を失う**
///
/// **ディレクトリに付ければ配下に効く**（3.2）。ただしディレクトリを
/// 作り直すと印が消えるので、Dart 側は起動のたびに冪等に呼び直す
/// （`lib/data/repositories/download_repository.dart` の `load()`）。
private enum BackupExclusion {
  /// **`lib/data/downloads/backup_exclusion.dart` の `_defaultChannel` と
  /// 一字一句同じでなければならない。**
  ///
  /// ずれても Swift はビルドが通り、**Dart 側は `MissingPluginException` を
  /// 握りつぶす**ので、除外が静かに効かなくなる。付いていないことに
  /// 気づく手段が無い、というのがこの機能でいちばん悪い壊れ方。
  /// **両側の一致は `test/domain/ios_backup_exclusion_test.dart` が見張る。**
  static let channelName = "jp.sessionconcierge.trackcabinet/backup_exclusion"

  /// Dart 側の `exclude(path)`。
  static let excludeMethod = "exclude"

  /// Dart 側の `isExcluded(path)`。
  static let isExcludedMethod = "isExcluded"

  /// 引数のキー。Dart 側は `{'path': absolutePath}` を渡す。
  static let pathArgument = "path"

  /// method channel の呼び出しを捌く。
  ///
  /// **失敗を握りつぶさない**（3.2）。付けたつもりで付いていないのが
  /// 最悪なので、失敗はすべて `FlutterError` にして Dart へ返す。
  static func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    switch call.method {
    case excludeMethod:
      guard let path = path(from: call) else {
        result(missingPathError(call))
        return
      }
      result(setExcluded(path))

    case isExcludedMethod:
      guard let path = path(from: call) else {
        result(missingPathError(call))
        return
      }
      result(readExcluded(path))

    default:
      // **知らない method を黙って成功にしない。** Dart 側で名前を
      // 打ち間違えたときに、ここで気づけるようにする。
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - 実処理

  /// 印を付ける。**冪等**（何度呼んでも同じ結果）。
  ///
  /// 成功なら `nil`（Dart 側は `invokeMethod<void>` で受ける）。
  private static func setExcluded(_ path: String) -> Any? {
    var url = URL(fileURLWithPath: path)
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    do {
      try url.setResourceValues(values)
      return nil
    } catch {
      return FlutterError(
        code: "excludeFailed",
        message: "バックアップ除外の設定に失敗しました: \(error.localizedDescription)",
        details: path
      )
    }
  }

  /// いま印が付いているか（3.2 の「確かめる手段」）。
  ///
  /// **必ずファイルシステムから読み直す。** 「`exclude` を呼んだから
  /// 付いているはず」で返すと、**確かめられない保証**になる。
  /// `URL` の resource value は URL の実体ごとにキャッシュされるので、
  /// **毎回ここで新しく作る**ことで前回の値を持ち越さない。
  ///
  /// 属性がそもそも付いていないときは `isExcludedFromBackup` が
  /// `nil` になり得るので、**`false`（付いていない）に倒す。**
  private static func readExcluded(_ path: String) -> Any? {
    let url = URL(fileURLWithPath: path)
    do {
      let values = try url.resourceValues(forKeys: [.isExcludedFromBackupKey])
      return values.isExcludedFromBackup ?? false
    } catch {
      return FlutterError(
        code: "isExcludedFailed",
        message: "バックアップ除外の読み取りに失敗しました: \(error.localizedDescription)",
        details: path
      )
    }
  }

  // MARK: - 引数

  private static func path(from call: FlutterMethodCall) -> String? {
    guard let arguments = call.arguments as? [String: Any],
      let path = arguments[pathArgument] as? String,
      !path.isEmpty
    else {
      return nil
    }
    return path
  }

  private static func missingPathError(_ call: FlutterMethodCall) -> FlutterError {
    FlutterError(
      code: "missingPath",
      message: "\(call.method) に \(pathArgument)（空でない文字列）が渡されていません",
      details: nil
    )
  }
}

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  /// **チャンネルを保持する。** ローカル変数のままだと登録直後に解放され、
  /// 呼んでも誰も答えない——**`MissingPluginException` と同じ見え方**になる。
  private var backupExclusionChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // **`applicationRegistrar` から messenger を取る。**
    // このテンプレートは `FlutterImplicitEngineDelegate` の形なので、
    // `window?.rootViewController as! FlutterViewController` は使えない
    // （UISceneDelegate 化されており、ここでは window がまだ無い）。
    // engine bridge が渡す 2 つのうち、`pluginRegistry` はプラグインへ
    // registrar を配るためのもので、**アプリ自身の method channel は
    // `applicationRegistrar`** が受け持つ（FlutterEngine.h の
    // `FlutterImplicitEngineBridge` の宣言どおり）。
    let channel = FlutterMethodChannel(
      name: BackupExclusion.channelName,
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    channel.setMethodCallHandler { call, result in
      BackupExclusion.handle(call, result)
    }
    backupExclusionChannel = channel
  }
}
