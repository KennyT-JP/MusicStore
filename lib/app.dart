/// アプリのルートウィジェット
///
/// テーマは Material 標準をそのまま使い、独自のデザインシステムは作らない
/// （仕様書 12.5）。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'data/repositories/download_repository.dart';
import 'l10n/app_localizations.dart';
import 'platform/app_ready.dart';
import 'platform/downloads_supported.dart';
import 'providers/app_providers.dart';
import 'providers/download_provider.dart';
import 'providers/font_provider.dart';
import 'ui/app_router.dart';
import 'ui/downloads/download_sync_notice.dart';
import 'ui/routes.dart';
import 'ui/widgets/startup_splash.dart';

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

/// 読み込み画面を消す合図を、1 度だけ送る。
///
/// 画面が作り直されるたびに呼ばれるので、印を持って 1 回に絞る。
/// **描画の途中で DOM を触らない**——最初のフレームを描き終えてから
/// 消す（描いている最中に外側を書き換えると、ちらつく）。
bool _appReadyNotified = false;

void _notifyAppReadyOnce() {
  if (_appReadyNotified) return;
  _appReadyNotified = true;
  WidgetsBinding.instance.addPostFrameCallback((_) => notifyAppReady());
}

/// 端末のダウンロードの起動処理を、1 回だけ走らせる印
/// （docs/DOWNLOAD-DESIGN.md 4.7 → 4.2 → 4.4）。
bool _downloadsStarted = false;

/// 起動時の知らせを出すための入口。
///
/// **画面より外側で起きることを、画面へ伝えるために要る。** 同期（4.4）は
/// 最初の描画の直後に走るので、どの画面が出ているか分からない。
final rootScaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

/// **掃除（4.7）→ 権限確認（4.2）→ 同期（4.4）を、起動ごとに 1 回。**
///
/// 順序は `DownloadsController.startup` が持っている。掃除を先にしないと、
/// `.part` の残骸や孤児が権限確認のあとまで残る。
/// **同期は権限確認のあと**——4.4 は「別のタイミングを増やさない」と決めている。
///
/// **ログインが済んでから呼ぶ。** `verifyDownloadAccess` は
/// `requireUid` を通るので、未ログインでは必ず失敗する。
/// **失敗しても何も起きない**（5.1）——圏外で 1 回失敗しただけで
/// 全曲が消える事故を避けるため、応答が無いときは「オフライン」として扱う。
///
/// **Web では呼ばない。** 保存先が無く、掃除するものも無い（論点 2）。
void _startDownloadsOnce(WidgetRef ref) {
  if (!kDownloadsSupported || _downloadsStarted) return;
  _downloadsStarted = true;
  WidgetsBinding.instance.addPostFrameCallback(
    // **待たない。** 画面はダウンロードの有無に関わらず動く。
    (_) => unawaited(_runDownloadsStartup(ref)),
  );
}

Future<void> _runDownloadsStartup(WidgetRef ref) async {
  final controller = ref.read(downloadsProvider.notifier);
  await controller.startup();

  // **元の削除・差し替えを端末へ反映する**（4.4・論点 11）。
  _tellWhatSyncDid(await controller.syncFromServer());
}

/// **黙って消さない**（4.4）。黙って消えると、利用者は
/// 「アプリが勝手に消した」と受け取る。
///
/// **同期を待ってから呼ばれるが、この関数自体は非同期にしない。**
/// `BuildContext` を await をまたいで持ち回らないため
/// （`use_build_context_synchronously`）。ここで取り直す。
void _tellWhatSyncDid(DownloadSyncReport report) {
  if (report.isEmpty) return;

  final context = rootScaffoldMessengerKey.currentContext;
  final messenger = rootScaffoldMessengerKey.currentState;
  if (context == null || messenger == null) return;

  final message = describeDownloadSync(AppL10n.of(context), report);
  if (message == null) return;
  messenger.showSnackBar(
    // **既定の 4 秒では読み切れない。** 端末の中身が変わったことを
    // 伝える知らせなので、消えるまでの時間を延ばす。
    SnackBar(content: Text(message), duration: const Duration(seconds: 10)),
  );
}

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
    final font = ref.watch(japaneseFontProvider);
    final fontReady = font.value ?? false;
    final fontFamily = fontReady ? kAppFontFamily : null;

    final authRestoring = ref.watch(firebaseUserProvider).isLoading;

    // **HTML の読み込み画面（ロゴ）を消してよいのは、ここが決まってから。**
    //
    // 待つのは 2 つ——ログイン状態の復元と、日本語フォントの読み込み。
    // フォントを待つのは、**読み終わる前に画面を出すと、端末に無い字が
    // □ で描かれる**ため（2026-08-08 の指摘）。
    //
    // **失敗も「決着」に数える。** フォントが読めなかったときは
    // `value == false` で返るので（font_provider.dart）、
    // `isLoading` が下りた時点で先へ進む。成功だけを待つと、
    // 読み込みに失敗した人の画面が永久にロゴのままになる。
    if (routerOverride == null && !authRestoring && !font.isLoading) {
      _notifyAppReadyOnce();
    }

    // ログインが済んだところで、端末のダウンロードの起動処理を 1 回だけ。
    if (routerOverride == null &&
        ref.watch(firebaseUserProvider).value != null) {
      _startDownloadsOnce(ref);
    }

    if (authRestoring && routerOverride == null) {
      return MaterialApp(
        // **この画面にも l10n を渡す。** ロゴの読み上げにアプリ名を使う。
        localizationsDelegates: const [
          AppL10n.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppL10n.supportedLocales,
        theme: ThemeData(
          colorScheme: appColorScheme(Brightness.light),
          fontFamily: fontFamily,
        ),
        darkTheme: ThemeData(
          colorScheme: appColorScheme(Brightness.dark),
          fontFamily: fontFamily,
        ),
        // **ロゴを出す。** ここが真っ白だと、HTML の読み込み画面から
        // 引き継いだ瞬間に「白くなった」と見える（2026-08-14）。
        home: const StartupSplash(),
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
      // 起動時の同期（4.4）が何をしたかを知らせるための入口。
      scaffoldMessengerKey: rootScaffoldMessengerKey,
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
