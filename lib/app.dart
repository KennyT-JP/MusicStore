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
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo,
          brightness: Brightness.dark,
        ),
      ),
    );
  }
}
