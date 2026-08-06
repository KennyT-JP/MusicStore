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
import 'ui/app_router.dart';

/// アプリ全体で使うフォント。pubspec.yaml の `fonts:` と揃えること。
const String kAppFontFamily = 'NotoSansJP';

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
  );
});

/// 音楽リスト共有アプリ。
class MusicListApp extends ConsumerWidget {
  const MusicListApp({super.key, this.routerOverride});

  /// テストから差し替えるためのルーター。通常は null。
  final GoRouter? routerOverride;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = routerOverride ?? ref.watch(routerProvider);

    // 表示言語はユーザー設定に従う（仕様書 2 章）。
    // 未設定のうちは端末の言語に任せる。
    final locale = ref.watch(currentAppUserProvider).value?.locale;

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
      // フォントだけは同梱の Noto Sans JP を指定する。既定のままだと
      // 日本語のグリフを実行時に Google Fonts から取りに行くため、
      // それが遮断された環境で文字が出なくなる（pubspec.yaml 参照）。
      theme: ThemeData(
        colorScheme: appColorScheme(Brightness.light),
        fontFamily: kAppFontFamily,
      ),
      darkTheme: ThemeData(
        colorScheme: appColorScheme(Brightness.dark),
        fontFamily: kAppFontFamily,
      ),
    );
  }
}
