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
  staging('staging', '検証環境'),

  /// 本番。
  production('prod', '本番環境');

  const AppEnvironment(this.key, this.label);

  /// `--dart-define=APP_ENV=` に渡す値。
  final String key;

  /// 画面に出すラベル。
  final String label;

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
