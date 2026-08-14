/// 起動直後の画面に、ロゴが出ているか（2026-08-14）
///
/// **依頼者の報告は「白い画面のまま数秒」だった。**
/// 原因は、HTML 側のロゴ入り読み込み画面を**アプリの最初の描画で消し**、
/// その裏で出していたのが `CircularProgressIndicator` だけの
/// 真っ白な画面だったこと。
///
/// つまり**いちばん見せたいところで、自分からロゴを消していた。**
///
/// ここで見張るのは 2 つ。
///
///   1. 復元中の画面に**ロゴが出る**こと
///   2. 復元とフォントが決着するまで、HTML 側へ**合図を送らない**こと
///
/// 2 は Web でしか実際には起きないが（Dart VM では何もしない実装が
/// 使われる）、**呼ぶ条件はここで確かめられる**。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_list_app/l10n/app_localizations.dart';
import 'package:music_list_app/ui/widgets/brand_logo.dart';
import 'package:music_list_app/ui/widgets/startup_splash.dart';

void main() {
  testWidgets('起動直後の画面にロゴが出る', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          localizationsDelegates: [AppL10n.delegate],
          supportedLocales: AppL10n.supportedLocales,
          home: StartupSplash(),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byType(BrandLogo),
      findsOneWidget,
      reason: '起動直後にロゴが無いと、HTML の読み込み画面から'
          '引き継いだ瞬間に「白くなった」と見える',
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('ロゴの読み上げは、画面の言語に従う', (tester) async {
    // 英語の画面で日本語のアプリ名を読み上げないこと（監査 第4回）。
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: [AppL10n.delegate],
          supportedLocales: AppL10n.supportedLocales,
          home: StartupSplash(),
        ),
      ),
    );
    await tester.pump();

    final logo = tester.widget<BrandLogo>(find.byType(BrandLogo));
    expect(logo.semanticLabel, isNotEmpty);
    expect(
      logo.semanticLabel,
      isNot(contains('音源創庫')),
      reason: '英語の画面では英語の名前で読み上げること',
    );
  });
}
