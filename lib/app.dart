/// アプリのルートウィジェット
///
/// テーマは Material 標準をそのまま使い、独自のデザインシステムは作らない
/// （仕様書 12.5）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';

import 'l10n/app_localizations.dart';
import 'ui/app_router.dart';

/// 音楽リスト共有アプリ。
class MusicListApp extends StatefulWidget {
  const MusicListApp({super.key, this.initialAuthState});

  /// 認証状態。実際の Firebase Auth につなぐまでの差し込み口。
  final AuthState? initialAuthState;

  @override
  State<MusicListApp> createState() => _MusicListAppState();
}

class _MusicListAppState extends State<MusicListApp> {
  late final GoRouter _router;
  late AuthState _authState;

  @override
  void initState() {
    super.initState();
    _authState = widget.initialAuthState ?? const AuthState.signedOut();
    _router = buildAppRouter(readAuthState: () => _authState);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      onGenerateTitle: (context) => AppL10n.of(context).appTitle,
      routerConfig: _router,

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
