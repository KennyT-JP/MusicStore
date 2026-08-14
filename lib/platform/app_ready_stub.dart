/// Web 以外での [notifyAppReady]（何もしない）
///
/// テストは Dart VM で走るため、こちらが使われます。
/// **消す相手（HTML の読み込み画面）が存在しない**ので、何もしないのが正しい。
library;

/// 何もしない。
void notifyAppReady() {}
