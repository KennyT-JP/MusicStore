/// 通知設定の画面（仕様書 10.2 / 10.3）
///
/// **回帰テスト。** 通知の種別は Cloud Functions 側と対で増えていくため、
/// 種別を足したのに設定画面へ出し忘れる、説明を書き忘れる、という抜けが起きる。
/// 出し忘れると「届くのに止められない通知」になってしまう。
///
/// ここでは種別の一覧をそのまま回して、どの種別も
/// 「名前」と「どんなときに届くか」の両方が画面に出ることを確かめる。
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_list_app/data/models/app_user.dart';
import 'package:music_list_app/l10n/app_localizations.dart';
import 'package:music_list_app/providers/app_providers.dart';
import 'package:music_list_app/ui/screens/settings_screen.dart';

Widget _app(Widget child, {Locale locale = const Locale('ja')}) => MaterialApp(
  localizationsDelegates: const [
    AppL10n.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: AppL10n.supportedLocales,
  locale: locale,
  home: child,
);

AppUser _user({NotificationSettings? settings}) => AppUser(
  uid: 'u1',
  displayName: '太郎',
  email: 'taro@example.com',
  locale: 'ja',
  isWithdrawn: false,
  notificationSettings: settings ?? const NotificationSettings(),
);

Future<void> _pumpSettings(
  WidgetTester tester, {
  AppUser? user,
  Locale locale = const Locale('ja'),
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentAppUserProvider.overrideWith(
          (ref) => Stream.value(user ?? _user()),
        ),
      ],
      child: _app(const SettingsScreen(), locale: locale),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('すべての通知種別を個別に切り替えられる（10.3）', (tester) async {
    await _pumpSettings(tester);

    // マスタースイッチ 1 つ ＋ 種別ごとに 1 つ。
    expect(
      find.byType(SwitchListTile),
      findsNWidgets(NotificationType.values.length + 1),
    );
  });

  for (final locale in const [Locale('ja'), Locale('en')]) {
    testWidgets('どの種別にも名前と説明がある（${locale.languageCode}）', (tester) async {
      await _pumpSettings(tester, locale: locale);

      final l10n = await AppL10n.delegate.load(locale);
      final labels = <String>{};

      for (final type in NotificationType.values) {
        final tile = find.ancestor(
          of: find.text(_labelFor(l10n, type)),
          matching: find.byType(SwitchListTile),
        );
        expect(tile, findsOneWidget, reason: '${type.name} の行が無い');

        final detail = _detailFor(l10n, type);
        expect(detail.trim(), isNotEmpty, reason: '${type.name} の説明が空');
        expect(
          find.descendant(of: tile, matching: find.text(detail)),
          findsOneWidget,
          reason: '${type.name} の説明が画面に出ていない',
        );

        // 説明が使い回されていると、どれを切っているのか分からなくなる。
        expect(labels.add(detail), isTrue, reason: '${type.name} の説明が他と同じ');
      }
    });
  }

  testWidgets('曲の追加は参加しているリストが対象だと分かる（10.2）', (tester) async {
    // **受信者を「リスト管理者」から「メンバー全員」に広げた。**
    // 画面の説明が古いままだと、参加しているだけの人は
    // 「自分には関係ない設定」と読んでしまう。
    await _pumpSettings(tester);

    final l10n = await AppL10n.delegate.load(const Locale('ja'));
    expect(l10n.notifyItemAddedDetail, contains('参加しているリスト'));
    expect(find.text(l10n.notifyItemAddedDetail), findsOneWidget);
  });

  testWidgets('マスタースイッチがオフなら種別の切り替えは無効になる', (tester) async {
    await _pumpSettings(
      tester,
      user: _user(settings: const NotificationSettings(master: false)),
    );

    final tiles = tester
        .widgetList<SwitchListTile>(find.byType(SwitchListTile))
        .toList();

    // 先頭がマスター。残りは種別ごとの切り替え。
    expect(tiles.first.onChanged, isNotNull);
    for (final tile in tiles.skip(1)) {
      expect(tile.onChanged, isNull);
    }
  });

  testWidgets('曲の通知だけを切っても他の通知は残る（10.3）', (tester) async {
    const settings = NotificationSettings();
    final off = settings.withType(
      NotificationType.itemAdded,
      settings.settingFor(NotificationType.itemAdded).copyWith(inApp: false),
    );

    expect(off.settingFor(NotificationType.itemAdded).inApp, isFalse);
    expect(off.settingFor(NotificationType.commentAdded).inApp, isTrue);

    await _pumpSettings(tester, user: _user(settings: off));

    final l10n = await AppL10n.delegate.load(const Locale('ja'));
    final tile = tester.widget<SwitchListTile>(
      find
          .ancestor(
            of: find.text(l10n.notifyItemAdded),
            matching: find.byType(SwitchListTile),
          )
          .first,
    );
    expect(tile.value, isFalse);
  });
}

/// 画面と同じ対応表。画面側は private なのでここに写している。
/// 種別が増えたときに、こちらも switch の網羅で気づけるようにする。
String _labelFor(AppL10n l10n, NotificationType type) => switch (type) {
  NotificationType.itemAdded => l10n.notifyItemAdded,
  NotificationType.commentAdded => l10n.notifyCommentAdded,
  NotificationType.quotaNotice => l10n.notifyQuotaNotice,
  NotificationType.quotaWarning => l10n.notifyQuotaWarning,
  NotificationType.listRequested => l10n.notifyListRequested,
  NotificationType.joinRequested => l10n.notifyJoinRequested,
  NotificationType.requestApproved => l10n.notifyRequestApproved,
};

String _detailFor(AppL10n l10n, NotificationType type) => switch (type) {
  NotificationType.itemAdded => l10n.notifyItemAddedDetail,
  NotificationType.commentAdded => l10n.notifyCommentAddedDetail,
  NotificationType.quotaNotice => l10n.notifyQuotaNoticeDetail,
  NotificationType.quotaWarning => l10n.notifyQuotaWarningDetail,
  NotificationType.listRequested => l10n.notifyListRequestedDetail,
  NotificationType.joinRequested => l10n.notifyJoinRequestedDetail,
  NotificationType.requestApproved => l10n.notifyRequestApprovedDetail,
};
