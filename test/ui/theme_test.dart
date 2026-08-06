/// 配色のテスト（仕様書 12.5）
///
/// **回帰テスト。** Material 3 は基準色 1 つから配色を自動で作るが、
/// tertiary は色相を回して作られるため、青を指定しても桃色系になる。
/// 実際に検証環境のバナー（tertiaryContainer）が桃色になっていた。
///
/// 「寒色系で統一する」は目で見ないと分からない、と思われがちだが、
/// 色相は数値なので機械的に確かめられる。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_list_app/app.dart';

/// 寒色とみなす色相の範囲（度）。
///
/// 青緑（約 180）から青紫（約 280）まで。桃色（約 330）や
/// 橙（約 30）はこの外側に出る。
const double _coolestHue = 170;
const double _warmestHue = 285;

/// 彩度がごく低い色は、色相を見ても意味がないので対象から外す。
const double _minSaturation = 0.08;

void _expectCool(Color color, String name) {
  final hsl = HSLColor.fromColor(color);
  if (hsl.saturation < _minSaturation) return; // ほぼ無彩色

  expect(
    hsl.hue,
    inInclusiveRange(_coolestHue, _warmestHue),
    reason:
        '$name の色相が寒色の範囲から外れています'
        '（色相 ${hsl.hue.toStringAsFixed(0)}度、彩度 ${hsl.saturation.toStringAsFixed(2)}）',
  );
}

void main() {
  for (final brightness in Brightness.values) {
    group('配色（${brightness.name}）', () {
      final scheme = appColorScheme(brightness);

      test('主要な色がすべて寒色', () {
        _expectCool(scheme.primary, 'primary');
        _expectCool(scheme.primaryContainer, 'primaryContainer');
        _expectCool(scheme.secondary, 'secondary');
        _expectCool(scheme.secondaryContainer, 'secondaryContainer');
      });

      test('tertiary も寒色（検証環境のバナーに使う）', () {
        _expectCool(scheme.tertiary, 'tertiary');
        _expectCool(scheme.tertiaryContainer, 'tertiaryContainer');
      });

      test('背景も寒色に寄せる', () {
        _expectCool(scheme.surface, 'surface');
        _expectCool(scheme.surfaceContainerHighest, 'surfaceContainerHighest');
      });

      // エラーは赤のままにする。寒色に寄せると危険の伝わり方が弱くなるため。
      test('エラー色は赤のまま（あえて寒色にしない）', () {
        final hue = HSLColor.fromColor(scheme.error).hue;
        expect(hue < 40 || hue > 330, isTrue, reason: '色相 $hue 度');
      });

      test('文字と背景の明度差が確保されている', () {
        // 読めない配色になっていないことの最低限の確認。
        final onSurface = scheme.onSurface.computeLuminance();
        final surface = scheme.surface.computeLuminance();
        expect((onSurface - surface).abs(), greaterThan(0.4));
      });
    });
  }
}
