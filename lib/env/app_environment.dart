/// 環境の切り替え（仕様書 12.2）
///
/// 本番と検証（ステージング）を別々の Firebase プロジェクトとして分離する。
/// Flutter 側はビルド時に接続先を切り替える。
///
/// ```sh
/// # 検証環境（既定）
/// flutter run -d chrome
///
/// # 本番環境
/// flutter run -d chrome --dart-define=APP_ENV=prod
/// flutter build web --dart-define=APP_ENV=prod
/// ```
library;

/// 接続先の環境。
enum AppEnvironment {
  /// 検証（ステージング）。既定値。
  ///
  /// 誤って本番へ繋ぐ事故を避けるため、指定がないときはこちらに倒す。
  staging('staging', '検証環境', 'https://music-storage-dev.web.app'),

  /// 本番。
  production('prod', '本番環境', 'https://music-storage-d79b2.web.app');

  const AppEnvironment(this.key, this.label, this.shareOrigin);

  /// `--dart-define=APP_ENV=` に渡す値。
  final String key;

  /// 画面に出すラベル。
  final String label;

  /// 共有・招待リンクに使うオリジン（末尾に `/` は付けない）。
  ///
  /// **ネイティブ（iOS / Android）には「いま表示しているドメイン」が無い。**
  /// `Uri.base` は実行時のカレントディレクトリを指す `file:` 形式になり、
  /// `origin` を読むと `StateError` を投げる。そこで環境ごとの固定値を
  /// 使う（`lib/ui/share_url.dart` の `defaultShareBase` を参照）。
  ///
  /// **置き場所をここにしてあるのは、本番／検証の切り替えがこの enum に
  /// 一本化されているため。** 別の場所に持つと、接続先の Firebase は検証
  /// なのに招待 URL だけ本番、という食い違いが起きる。**配られた人は本番の
  /// リストに入ろうとして入れない。**
  final String shareOrigin;

  /// ビルド時に指定された環境。
  static final AppEnvironment current = _resolve();

  /// 本番環境か。
  bool get isProduction => this == AppEnvironment.production;

  /// 画面上に環境バナーを出すか。
  ///
  /// 検証環境で作業していることを見失わないようにする。
  bool get showEnvironmentBanner => !isProduction;

  static AppEnvironment _resolve() {
    const raw = String.fromEnvironment('APP_ENV', defaultValue: 'staging');
    for (final env in AppEnvironment.values) {
      if (env.key == raw) return env;
    }
    return AppEnvironment.staging;
  }
}
