/// Firestore のコレクション・ドキュメントのパス（仕様書 13.2）
///
/// ```
/// users/{uid}                          ← 誰でも読める（表示名の解決のため）
///   ├ private/state                    ← **本人だけ**読める私的な情報
///   └ notifications/{notificationId}
///
/// lists/{listId}                       ← 公開可能な最小情報のみ
///   ├ meta/stats                       ← 容量・連番などの内部情報
///   ├ members/{uid}
///   ├ viewers/{uid}                    ← 参加せずに見るだけの人（3.3）
///   ├ joinRequests/{uid}
///   └ items/{itemId}
///       └ comments/{commentId}
///
/// listRequests/{requestId}
/// siteConfig/global
/// ```
///
/// パスを文字列で直書きせず、ここに集約する。
///
/// **クライアントが触らないパスは持たない。** リスト名の予約
/// （listNames）や共有リンク（shareLinks）はサーバーだけが読み書きし、
/// パスの正本は functions/src/config.ts にある。旧設計の invites も
/// そちらへ移して久しく、ここの定義は 0 参照の残骸だった（監査 第4回）。
library;

/// Firestore のパス。
class FirestorePaths {
  const FirestorePaths._();

  // --- トップレベルのコレクション ---

  static const String users = 'users';
  static const String lists = 'lists';
  static const String listRequests = 'listRequests';
  static const String siteConfig = 'siteConfig';

  // --- サブコレクション名 ---

  static const String notifications = 'notifications';

  /// 本人だけが読める私的な情報を入れる下位コレクション。
  ///
  /// **`users/{uid}` 本体には置かない。** 本体は表示名を解決するために
  /// ログイン済みなら誰でも読める設計で、メールアドレス・プレミアムの
  /// 期限・容量の使用量まで他の利用者に見えていた（2026-08-11）。
  static const String private = 'private';

  static const String meta = 'meta';
  static const String members = 'members';
  static const String joinRequests = 'joinRequests';
  static const String items = 'items';
  static const String comments = 'comments';

  // --- 固定のドキュメント ID ---

  /// `lists/{listId}/meta/stats`
  static const String statsDoc = 'stats';

  /// `siteConfig/global`
  static const String globalConfigDoc = 'global';

  /// `users/{uid}/private/state`
  static const String privateStateDoc = 'state';

  // --- パスの組み立て ---

  static String user(String uid) => '$users/$uid';

  static String userNotifications(String uid) => '${user(uid)}/$notifications';

  /// 本人だけが読める私的な情報（メールアドレス・表示言語・通知設定・
  /// プレミアムの期限・容量）。
  ///
  /// **他人のぶんは読めない。** 読もうとすると権限で断られるので、
  /// 自分の uid でしか呼ばないこと。
  static String userPrivate(String uid) =>
      '${user(uid)}/$private/$privateStateDoc';

  static String list(String listId) => '$lists/$listId';

  /// 容量・連番などの内部情報（メンバーのみ読める）。
  static String listStats(String listId) => '${list(listId)}/$meta/$statsDoc';

  static String listMembers(String listId) => '${list(listId)}/$members';

  /// 参加せずに見るだけの人（仕様書 3.3）。
  ///
  /// **メンバーとは別に持つ。** メンバー一覧にも人数にも通知の宛先にも
  /// 入れないため。書き込むのは Cloud Functions だけ。
  static String listViewers(String listId) => '${list(listId)}/viewers';

  /// 閲覧者 1 人分。**本人だけは自分の 1 件を読める**（firestore.rules）。
  static String listViewer(String listId, String uid) =>
      '${listViewers(listId)}/$uid';

  static String listMember(String listId, String uid) =>
      '${listMembers(listId)}/$uid';

  /// 参加申請。ドキュメント ID は申請者の uid（二重申請の防止／13.3）。
  static String listJoinRequests(String listId) =>
      '${list(listId)}/$joinRequests';

  static String listJoinRequest(String listId, String uid) =>
      '${listJoinRequests(listId)}/$uid';

  static String listItems(String listId) => '${list(listId)}/$items';

  static String listItem(String listId, String itemId) =>
      '${listItems(listId)}/$itemId';

  static String itemComments(String listId, String itemId) =>
      '${listItem(listId, itemId)}/$comments';

  static String itemComment(String listId, String itemId, String commentId) =>
      '${itemComments(listId, itemId)}/$commentId';

  static String get globalConfig => '$siteConfig/$globalConfigDoc';
}

/// Storage のファイル配置（仕様書 13.7）
///
/// ```
/// lists/{listId}/items/{itemId}/{元のファイル名}
/// ```
///
/// パスにリスト ID を含めることで、Storage 側のセキュリティルールを
/// リスト単位で書ける。
class StoragePaths {
  const StoragePaths._();

  static String itemFile({
    required String listId,
    required String itemId,
    required String fileName,
  }) => 'lists/$listId/items/$itemId/$fileName';

  // ディレクトリ単位の削除はサーバー側（Cloud Functions）だけが行うので、
  // ディレクトリのパスはここに持たない（正本は functions/src/config.ts）。
}

/// リスト名の正規化（仕様書 5.1 / 13.3）
///
/// 重複チェックのためにドキュメント ID として使うので、
/// 大文字小文字と前後の空白の違いを吸収する。
///
/// **スラッシュは `_` に置き換える。** Firestore のドキュメント ID に
/// スラッシュを入れると、そこでパスが区切られてしまう。`foo/bar` は
/// `listNames/foo` の下の階層になり、`listNames/foo` とは別の場所に
/// できるため重複チェックをすり抜ける。
///
/// **サーバー側（functions/src/domain/paths.ts）と同じ結果になること。**
/// 以前はこちらだけ置き換えを忘れており、同じ名前を別々に正規化していた
/// （監査 第2回）。そのうえ、揃っていることを確かめるはずのテストが
/// スラッシュを含まない入力しか渡しておらず、食い違いを隠していた。
String normalizeListName(String name) =>
    name.trim().toLowerCase().replaceAll('/', '_');
