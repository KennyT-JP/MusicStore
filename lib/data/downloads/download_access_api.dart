/// `verifyDownloadAccess` の呼び出し（docs/DOWNLOAD-DESIGN.md 4.2 / 5.1）
///
/// サーバー側は `functions/src/callable/downloads.ts` に実装済み。
///
/// ```
/// 入力  { listIds: string[] }
/// 出力  { premiumActive: boolean,
///         verifiedAt: number,
///         lists: { [listId: string]: 'member' | 'notMember' } }
/// ```
///
/// ## **プレミアムでないことは例外で来ない**（5.1 / 10 節の危険 4）
///
/// サーバーは `premiumRequired` を投げない。**投げられると、呼び出し側は
/// 「呼び出しが失敗した」と「プレミアムでない」を区別できなくなる。**
/// 圏外・タイムアウト・コールドスタートの失敗も同じ「失敗」として届く。
///
/// そして**この呼び出しの結果は端末のファイル削除**である。
/// **電波の悪い場所で 1 回失敗しただけで全曲が消える**という事故になる。
///
/// **クライアント側もその形に合わせる。**
///
/// ```
/// 呼び出しが失敗した      → 何もしない。オフラインとして扱う
///                           （30 日の時計は動かさない）
/// premiumActive: false    → 削除する
/// lists[X] == 'notMember' → X のぶんだけ削除する
/// ```
///
/// つまり [DownloadAccessApi.verify] は
/// **「答えが返った」ことだけを成功として返し、中身では投げない。**
/// 呼び出せなかったときだけ [DownloadAccessUnavailableException] を投げる。
///
/// **`FunctionsRepository` を使わない理由。** あちらの `_call` は失敗を
/// `FunctionsCallException` にまとめて画面に文言を出させる作りで、
/// ここが要るのは逆——**失敗を画面に出さず、静かに「何もしない」に倒す**
/// ことである。混ぜると、圏外のたびに「エラー」が出る。
library;

import 'package:cloud_functions/cloud_functions.dart';

/// 呼び出せなかった（圏外・タイムアウト・サーバーの失敗）。
///
/// **これを受けたら何もしないこと**（5.1）。削除の判断材料にしない。
class DownloadAccessUnavailableException implements Exception {
  const DownloadAccessUnavailableException(this.cause);

  final Object cause;

  @override
  String toString() => 'DownloadAccessUnavailableException($cause)';
}

/// `verifyDownloadAccess` が返したもの（5.1）。
class DownloadAccessResult {
  const DownloadAccessResult({
    required this.premiumActive,
    required this.verifiedAt,
    required this.members,
  });

  /// **false は正常な答えである。** 例外ではない（5.1）。
  final bool premiumActive;

  /// **サーバーの時刻。** 端末はこれを `lastVerifiedAt` として持つ（4.2）。
  /// 端末の時計で決めると、時計を進めるだけで確認を偽装できる。
  final DateTime verifiedAt;

  /// リストごとに、いまメンバーであるか。
  ///
  /// **問い合わせに含めなかったリストは入っていない。**
  /// 入っていないことを「メンバーでない」と読まないこと（消すことになる）。
  final Map<String, bool> members;

  /// そのリストのぶんを消すべきか（論点 13）。
  ///
  /// **答えが返っていないリストは消さない。** 安全側は「残すほう」。
  bool lostAccessTo(String listId) => members[listId] == false;
}

/// `verifyDownloadAccess` の呼び出し口。
class DownloadAccessApi {
  /// **`FirebaseFunctions` そのものではなく、取り出し方を受け取る。**
  ///
  /// 目録を読むだけの用（設定画面の使用量表示、オフラインでの一覧）で
  /// Firebase の初期化を要求しないため。オフラインで開く画面が
  /// 「Firebase が初期化されていない」で真っ白になるのは割に合わない
  /// （6.1 の「この画面は Firestore を一切読まないこと」と同じ考え）。
  const DownloadAccessApi(this._functions);

  final FirebaseFunctions Function() _functions;

  /// 1 回の確認で渡せるリストの上限（5.1）。
  ///
  /// **サーバーも 50 で断る。** 超えると `invalid-argument` が返るだけで、
  /// それは「権限が無い」ではないので、ここで先に分けて呼ぶ。
  static const int maxListIdsPerCall = 50;

  /// 権限を確かめる（4.2）。
  ///
  /// **上限を超える件数は分けて呼び、結果をまとめる。** 論点 6 で
  /// 端末側の上限を置かないと決めた以上、リストの数が 50 を超えることは
  /// 起こり得る。1 回でも失敗したら**全体を失敗にする**——
  /// 半分だけの答えで削除を判断すると、答えの無いリストが
  /// 「メンバーでない」に見える。
  Future<DownloadAccessResult> verify(List<String> listIds) async {
    final unique = listIds.where((id) => id.isNotEmpty).toSet().toList();

    var premiumActive = false;
    DateTime? verifiedAt;
    final members = <String, bool>{};

    // **1 件も無くても 1 回は呼ぶ。** プレミアムの有無は、曲を 1 つも
    // 持っていなくても知る必要がある（設定画面の出し分け）。
    for (
      var start = 0;
      start == 0 || start < unique.length;
      start += maxListIdsPerCall
    ) {
      final chunk = unique.skip(start).take(maxListIdsPerCall).toList();
      final result = await _callOnce(chunk);
      premiumActive = result.premiumActive;
      verifiedAt = result.verifiedAt;
      members.addAll(result.members);
    }

    return DownloadAccessResult(
      premiumActive: premiumActive,
      verifiedAt: verifiedAt!,
      members: members,
    );
  }

  Future<DownloadAccessResult> _callOnce(List<String> listIds) async {
    final Map<String, dynamic> data;
    try {
      final response = await _functions()
          .httpsCallable('verifyDownloadAccess')
          .call<Object?>({'listIds': listIds});
      final value = response.data;
      if (value is! Map) {
        throw const DownloadAccessUnavailableException('unexpected response');
      }
      data = Map<String, dynamic>.from(value);
    } on DownloadAccessUnavailableException {
      rethrow;
    } on Object catch (error) {
      // **符号を見て分岐しない。** どんな失敗であっても答えは
      // 「何もしない」で同じである（5.1）。`premiumRequired` は
      // そもそも返らない。
      throw DownloadAccessUnavailableException(error);
    }

    final verifiedAt = data['verifiedAt'];
    if (verifiedAt is! num) {
      // **サーバーの時刻が無ければ確認が取れたことにしない。**
      // 端末の時計で埋めると、30 日の時計を端末側で作れてしまう（4.2）。
      throw const DownloadAccessUnavailableException('missing verifiedAt');
    }

    final rawLists = data['lists'];
    final members = <String, bool>{};
    if (rawLists is Map) {
      for (final entry in rawLists.entries) {
        members['${entry.key}'] = entry.value == 'member';
      }
    }

    return DownloadAccessResult(
      premiumActive: data['premiumActive'] == true,
      verifiedAt: DateTime.fromMillisecondsSinceEpoch(verifiedAt.toInt()),
      members: members,
    );
  }
}
