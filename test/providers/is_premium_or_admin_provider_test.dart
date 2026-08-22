/// 実効プレミアム `isPremiumOrAdminProvider` の合成（仕様書 4.1）
///
/// **実効プレミアム＝プレミアム有効（[isPremiumProvider]）OR
/// サイト管理者（[isSiteAdminProvider]）。** サイト管理者はプレミアム機能を
/// すべて持つ（仕様書 4.1）。ここで固定するのは合成の規約：
///
/// - どちらかが読み込み中なら**読み込み中**（届く前に false へ倒さない）
/// - どちらかがエラーなら**エラー**（安全側の扱いは呼び出し側に委ねる）
/// - 両方そろって初めて `premium || admin` を返す
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_list_app/providers/app_providers.dart';

void main() {
  group('isPremiumOrAdminProvider（実効プレミアム／仕様書 4.1）', () {
    /// premium は `Provider<AsyncValue<bool>>`、admin は `FutureProvider<bool>`。
    ProviderContainer make({
      required AsyncValue<bool> premium,
      required FutureOr<bool> Function() admin,
    }) {
      final container = ProviderContainer(
        overrides: [
          isPremiumProvider.overrideWithValue(premium),
          isSiteAdminProvider.overrideWith((ref) => admin()),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('両方 data のとき premium || admin', () async {
      for (final c in [
        (p: false, a: false, want: false),
        (p: true, a: false, want: true),
        (p: false, a: true, want: true), // ← サイト管理者は実効プレミアム
        (p: true, a: true, want: true),
      ]) {
        final container = make(premium: AsyncData(c.p), admin: () => c.a);
        // admin（FutureProvider）を解決させてから合成を読む。
        await container.read(isSiteAdminProvider.future);
        expect(
          container.read(isPremiumOrAdminProvider).value,
          c.want,
          reason: 'premium=${c.p} admin=${c.a}',
        );
      }
    });

    test('premium が読み込み中なら読み込み中（届く前に false へ倒さない）', () async {
      final container = make(premium: const AsyncLoading(), admin: () => true);
      await container.read(isSiteAdminProvider.future);
      expect(container.read(isPremiumOrAdminProvider).isLoading, isTrue);
    });

    test('admin が読み込み中なら読み込み中', () {
      // admin をずっと未完了にする。premium は data。
      final container = ProviderContainer(
        overrides: [
          isPremiumProvider.overrideWithValue(const AsyncData(false)),
          isSiteAdminProvider.overrideWith((ref) => Completer<bool>().future),
        ],
      );
      addTearDown(container.dispose);
      expect(container.read(isPremiumOrAdminProvider).isLoading, isTrue);
    });

    test('premium がエラーならエラー', () async {
      final container = make(
        premium: AsyncError<bool>(Exception('boom'), StackTrace.empty),
        admin: () => true,
      );
      await container.read(isSiteAdminProvider.future);
      expect(container.read(isPremiumOrAdminProvider).hasError, isTrue);
    });
  });
}
