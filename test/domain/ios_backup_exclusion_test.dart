/// iOS のバックアップ除外の受け口の見張り（docs/DOWNLOAD-DESIGN.md 3.2）
///
/// **Swift はこの開発機（Windows・Xcode 無し）ではビルドできない。**
/// 確かめられるのは Dart 側と Swift 側の**静的な一致**だけで、
/// 実際に印が付くかどうかは実機か CI でしか分からない
/// （`test/domain/manual_test_cases_test.dart` の手動テストへ回す）。
///
/// **それでもここで止める価値がある。** この受け口の壊れ方は、
/// どれも**静かに壊れる**から。
///
/// | 破れると | 何が起きるか |
/// | --- | --- |
/// | チャンネル名がずれる | Swift はビルドが通る。Dart は `MissingPluginException` を**握りつぶす**（`backup_exclusion.dart:79-81`）。**除外が一度も効かないまま、誰も気づかない** |
/// | method 名がずれる | 同上。`FlutterMethodNotImplemented` は Dart 側で `MissingPluginException` になる |
/// | 引数のキーがずれる | Swift が `missingPath` を返す。`PlatformException` も握りつぶされる |
/// | `isExcludedFromBackup` を実際に読まなくなる | 「`exclude` を呼んだから付いているはず」を返す口ができる。**確かめられない保証**は、確かめる手段が無いのと同じ（3.2 が読み取り口を要求した理由そのもの） |
///
/// **どちらか片方に値を書き写さない。** この見張りが Dart か Swift の
/// どちらかの値を持ってしまうと、**「見張りと片側」が一致するだけ**になり、
/// もう片側がずれても緑のままになる。**両方のソースから読み取って突き合わせる。**
///
/// **コメントは取り除いてから当てる。** 両方のファイルとも説明のコメントが
/// 本文より長く、しかも**コメントの中に `isExcludedFromBackup` や
/// `exclude` がそのまま出てくる**。素の `contains` だと、実装を丸ごと
/// 消しても説明文に当たって緑のままになる
/// （`test/domain/ios_platform_config_test.dart:15-20` と同じ形の空振り）。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _dartPath = 'lib/data/downloads/backup_exclusion.dart';
const _swiftPath = 'ios/Runner/AppDelegate.swift';

String _read(String path) {
  final file = File(path);
  expect(file.existsSync(), isTrue, reason: '$path が見つかりません');
  return file.readAsStringSync();
}

/// `//`（`///` を含む）と `/* */` を取り除く。
///
/// **チャンネル名に `//` は入らない**（`jp.…/backup_exclusion` のスラッシュは
/// 1 本）ので、文字列リテラルを巻き込む心配はない。
String _stripComments(String source) => source
    .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
    .replaceAll(RegExp(r'//[^\n]*'), '');

/// Dart 側の `MethodChannel('…')` の名前。
String _dartChannelName(String source) {
  final match = RegExp(r"MethodChannel\(\s*'([^']+)'").firstMatch(source);
  expect(
    match,
    isNotNull,
    reason:
        "$_dartPath に MethodChannel('…') が見つかりません。\n"
        '書き方が変わったなら、この見張りも直してください。\n'
        '**見張りが空振りしたまま緑になるのがいちばん困ります**',
  );
  return match!.group(1)!;
}

/// Swift 側の `static let channelName = "…"` の名前。
String _swiftChannelName(String source) {
  final match = RegExp(r'channelName\s*=\s*"([^"]+)"').firstMatch(source);
  expect(
    match,
    isNotNull,
    reason:
        '$_swiftPath に channelName = "…" が見つかりません。\n'
        '受け口を消したか、書き方を変えたかのどちらかです',
  );
  return match!.group(1)!;
}

/// Dart 側が `invokeMethod<…>('名前', …)` で呼んでいる method 名。
List<String> _dartMethodNames(String source) => RegExp(
  r"invokeMethod<[^>]*>\(\s*'([^']+)'",
).allMatches(source).map((m) => m.group(1)!).toList();

/// Dart 側が渡している引数のキー（`invokeMethod('…', {'キー': …})`）。
Set<String> _dartArgumentKeys(String source) => RegExp(
  r"invokeMethod<[^>]*>\(\s*'[^']+',\s*\{\s*'([^']+)'",
).allMatches(source).map((m) => m.group(1)!).toSet();

/// Swift のソースに現れる文字列リテラル。
Set<String> _swiftStringLiterals(String source) =>
    RegExp(r'"([^"\\]*)"').allMatches(source).map((m) => m.group(1)!).toSet();

void main() {
  group('見張り自身の健全性', () {
    // **ここが壊れると、下の見張りが全部素通りする。**
    // コメントの中の `isExcludedFromBackup` を拾って緑になるのがその形。
    test('コメントの中身は見えなくなる', () {
      expect(
        _stripComments('/// values.isExcludedFromBackup = true\nlet a = 1'),
        contains('let a = 1'),
      );
      expect(
        _stripComments('/// values.isExcludedFromBackup = true'),
        isNot(contains('isExcludedFromBackup')),
      );
      // **契約の値そのものは、この見張りのどこにも書かない。**
      // ここは剥がし器の動作確認なので、実在しない語を使う。
      expect(_stripComments('/* setResourceValues */'), isEmpty);
    });

    test('チャンネル名の取り出しが空振りしていない', () {
      // 両側とも「取れた値が空でなく、それらしい形をしている」ことを見る。
      // **値そのものは書かない**（書いた時点で片側の写しになる）。
      for (final name in [
        _dartChannelName(_stripComments(_read(_dartPath))),
        _swiftChannelName(_stripComments(_read(_swiftPath))),
      ]) {
        expect(name, isNotEmpty);
        expect(
          name,
          contains('/'),
          reason:
              'MethodChannel の名前は「アプリ ID/用途」の形にしています。\n'
              '取り出せた値: $name',
        );
      }
    });
  });

  group('Dart 側と Swift 側の一致（3.2）', () {
    test('チャンネル名が一字一句同じ', () {
      final dart = _dartChannelName(_stripComments(_read(_dartPath)));
      final swift = _swiftChannelName(_stripComments(_read(_swiftPath)));

      expect(
        swift,
        dart,
        reason:
            'MethodChannel の名前が食い違っています。\n'
            '  $_dartPath : $dart\n'
            '  $_swiftPath : $swift\n'
            '**Swift はビルドが通り、Dart は MissingPluginException を\n'
            '握りつぶします**（backup_exclusion.dart:79-81）。\n'
            '**除外が一度も効かないまま、誰も気づけません**',
      );
    });

    test('Dart が呼ぶ method 名が Swift 側に揃っている', () {
      final dartMethods = _dartMethodNames(_stripComments(_read(_dartPath)));

      // **数えてから中身を見る。** 0 件でも「全部ある」は成り立つ。
      expect(
        dartMethods.toSet(),
        hasLength(2),
        reason:
            '$_dartPath が呼ぶ method が 2 つではありません: $dartMethods\n'
            '3.2 で決めたのは「外す」と「付いているか読む」の 2 つです。\n'
            '増減させたなら、この見張りも Swift 側も直してください',
      );

      final swiftLiterals = _swiftStringLiterals(
        _stripComments(_read(_swiftPath)),
      );
      for (final method in dartMethods) {
        expect(
          swiftLiterals,
          contains(method),
          reason:
              "Dart が呼ぶ '$method' を $_swiftPath が受けていません。\n"
              '**Swift 側は FlutterMethodNotImplemented を返し、\n'
              'Dart 側ではそれが MissingPluginException になって\n'
              '握りつぶされます**（＝静かに効かなくなる）',
        );
      }
    });

    test('引数のキーが Swift 側に揃っている', () {
      final keys = _dartArgumentKeys(_stripComments(_read(_dartPath)));
      expect(
        keys,
        isNotEmpty,
        reason: "$_dartPath の invokeMethod('…', {'キー': …}) を読めませんでした",
      );

      final swiftLiterals = _swiftStringLiterals(
        _stripComments(_read(_swiftPath)),
      );
      for (final key in keys) {
        expect(
          swiftLiterals,
          contains(key),
          reason:
              "Dart が渡すキー '$key' を $_swiftPath が読んでいません。\n"
              '**Swift 側は引数を取り出せず FlutterError を返しますが、\n'
              'Dart 側は PlatformException も握りつぶします**\n'
              '（backup_exclusion.dart:82-84）',
        );
      }
    });
  });

  group('Swift 側が実際に属性を触っている（3.2）', () {
    test('isExcludedFromBackup を書き込んでいる', () {
      final swift = _stripComments(_read(_swiftPath));
      expect(
        swift,
        contains('isExcludedFromBackup = true'),
        reason:
            '$_swiftPath が isExcludedFromBackup を立てていません。\n'
            '**これを書かないと、受け口はあるのに何もしません。**\n'
            'Dart 側から見ると成功に見えます（3.2）',
      );
      expect(
        swift,
        contains('setResourceValues'),
        reason:
            'setResourceValues の呼び出しがありません。\n'
            'URLResourceValues を組み立てても、書き戻さなければ効きません',
      );
    });

    test('isExcluded はファイルシステムから読み直している', () {
      final swift = _stripComments(_read(_swiftPath));

      expect(
        swift,
        contains('isExcludedFromBackupKey'),
        reason:
            '$_swiftPath が .isExcludedFromBackupKey を読んでいません。\n'
            '**「exclude を呼んだから付いているはず」で返してはいけません**——\n'
            'それは確かめられない保証で、3.2 が読み取り口を要求した理由\n'
            '（付けたつもりで付いていないのが最悪）を満たしません',
      );
      expect(
        swift,
        contains('resourceValues(forKeys:'),
        reason:
            'resourceValues(forKeys:) の呼び出しがありません。\n'
            '属性は実際に読み出してください',
      );
    });

    test('どの catch も握りつぶさず FlutterError を返している', () {
      final swift = _stripComments(_read(_swiftPath));

      // **数を数えるだけでは足りない。** `FlutterError` は引数不足の
      // 応答にも使うので、総数を見ると **catch を 1 つ空にしても
      // 総数が閾値を超えたまま緑になる。**
      // **catch ごとに中身を見る。**
      final bodies = RegExp(
        r'catch\s*\{([^{}]*)\}',
      ).allMatches(swift).map((m) => m.group(1)!).toList();

      expect(
        bodies,
        hasLength(2),
        reason:
            'catch が ${bodies.length} 個です。\n'
            '**exclude（書き込み）と isExcluded（読み取り）の 2 つとも\n'
            '失敗し得ます。**両方で受けてください',
      );

      for (final body in bodies) {
        expect(
          body,
          contains('FlutterError('),
          reason:
              '失敗を握りつぶしている catch があります:\n$body\n'
              '**Swift 側で握りつぶすと、Dart 側は「効いている」と\n'
              '区別がつきません**（3.2「付けたつもりで付いていないのが最悪」）',
        );
      }
    });
  });
}
