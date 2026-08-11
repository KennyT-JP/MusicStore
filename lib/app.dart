/// アプリのルートウィジェット
///
/// テーマは Material 標準をそのまま使い、独自のデザインシステムは作らない
/// （仕様書 12.5）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'l10n/app_localizations.dart';
import 'providers/app_providers.dart';
import 'providers/font_provider.dart';
import 'ui/app_router.dart';
import 'ui/routes.dart';

/// 配色の基準色（仕様書 12.5）。**寒色系で統一する。**
const Color kSeedColor = Color(0xFF1B5E9E);

/// 3 番目の色。青緑にそろえる。
///
/// **Material 3 は基準色から自動で配色を作るが、tertiary は色相を回して
/// 作られるため、青を指定しても桃色系になる。** 実際、検証環境のバナーが
/// 桃色になっていた。ここだけ別の基準色から作って寒色に固定する。
const Color kTertiarySeedColor = Color(0xFF0E7C86);

/// アプリの配色。
///
/// 明るい配色と暗い配色で同じ作り方をする。片方だけ手で調整すると、
/// もう片方で色が合わなくなるため。
ColorScheme appColorScheme(Brightness brightness) {
  final base = ColorScheme.fromSeed(
    seedColor: kSeedColor,
    brightness: brightness,
  );
  // tertiary の一群だけ、青緑の基準色から作り直して差し替える。
  final cool = ColorScheme.fromSeed(
    seedColor: kTertiarySeedColor,
    brightness: brightness,
  );
  return base.copyWith(
    tertiary: cool.primary,
    onTertiary: cool.onPrimary,
    tertiaryContainer: cool.primaryContainer,
    onTertiaryContainer: cool.onPrimaryContainer,
  );
}

/// アプリを開いたときの URL（main.dart が起動直後に控える）。
///
/// **ルーターより先に読み込み画面を出すと、開いた URL が失われる**ため。
/// ログイン状態の復元を待つあいだに最初の描画が挟まると、そのあとで
/// 作ったルーターには元の URL（例：共有リンク /s/…）が渡らず、
/// ホーム扱いで始まってしまう。起動時に控えておき、ルーターの
/// 開始地点として渡す（2026-08-08。検証環境の実機で発覚）。
final launchLocationProvider = Provider<String>((_) => AppRoutes.home);

/// ルーターを 1 度だけ組み立てて保持する。
///
/// 画面を作り直すたびにルーターを作ると履歴が失われるため、
/// プロバイダに持たせる。認証状態が変わったときは [Listenable] 経由で
/// ルーターにリダイレクトの再評価を促す。
final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref.onDispose(refresh.dispose);

  ref.listen<AuthState>(authStateProvider, (_, _) => refresh.value++);

  return buildAppRouter(
    readAuthState: () => ref.read(authStateProvider),
    authListenable: refresh,
    initialLocation: ref.read(launchLocationProvider),
  );
});

/// 音源創庫（Track Cabinet） — 音源を持ち寄って共有するアプリ。
class MusicListApp extends ConsumerWidget {
  const MusicListApp({super.key, this.routerOverride});

  /// テストから差し替えるためのルーター。通常は null。
  final GoRouter? routerOverride;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // **ログイン状態の復元が終わるまで、画面遷移の判定を始めない。**
    //
    // Firebase は起動直後、前回のログインを復元するまでのあいだ
    // 「未ログイン」に見える。その状態でルーターを動かすと、ログイン済みの
    // 人が URL を開いても一度ログイン画面へ送られ、復元後に戻される
    // （画面がちらつき、復元が遅いとログイン画面のまま止まって見える）。
    // 最初の判定が出るまでは読み込み表示だけを出す（2026-08-08 の指摘）。
    // **日本語フォントは画面を止めずに読み込む**（providers/font_provider.dart）。
    // 読み終わるまでは端末のフォントで描き、終わったらここが作り直されて
    // 差し替わる。`fontFamily` に未登録の名前を渡すと字が出ないので、
    // 読み終わるまでは既定（null）にしておく。
    final fontReady = ref.watch(japaneseFontProvider).value ?? false;
    final fontFamily = fontReady ? kAppFontFamily : null;

    final authRestoring = ref.watch(firebaseUserProvider).isLoading;
    if (authRestoring && routerOverride == null) {
      return MaterialApp(
        theme: ThemeData(
          colorScheme: appColorScheme(Brightness.light),
          fontFamily: fontFamily,
        ),
        darkTheme: ThemeData(
          colorScheme: appColorScheme(Brightness.dark),
          fontFamily: fontFamily,
        ),
        home: const Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }

    final router = routerOverride ?? ref.watch(routerProvider);

    // 表示言語はユーザー設定に従う（仕様書 2 章）。
    // 未設定のうちは端末の言語に任せる。
    // **本人だけが読める側にある**（`users/{uid}/private/state`）。
    final locale = ref.watch(currentUserPrivateProvider).value?.locale;

    return MaterialApp.router(
      onGenerateTitle: (context) => AppL10n.of(context).appTitle,
      routerConfig: router,
      locale: locale == null ? null : Locale(locale),

      // 多言語対応（仕様書 2 章）。初期対応は日本語・英語。
      localizationsDelegates: const [
        AppL10n.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppL10n.supportedLocales,

      // Material 標準のテーマ（仕様書 12.5）。
      // フォントだけは同梱の Noto Sans JP を使う。既定のままだと
      // 日本語のグリフを実行時に Google Fonts から取りに行くため、
      // それが遮断された環境で文字が出なくなる（pubspec.yaml 参照）。
      theme: ThemeData(
        colorScheme: appColorScheme(Brightness.light),
        fontFamily: fontFamily,
      ),
      darkTheme: ThemeData(
        colorScheme: appColorScheme(Brightness.dark),
        fontFamily: fontFamily,
      ),
    );
  }
}
