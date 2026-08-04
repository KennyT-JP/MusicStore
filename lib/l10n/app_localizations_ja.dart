// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Japanese (`ja`).
class AppL10nJa extends AppL10n {
  AppL10nJa([String locale = 'ja']) : super(locale);

  @override
  String get appTitle => '音楽リスト';

  @override
  String get navHome => 'ホーム';

  @override
  String get navNotifications => '通知';

  @override
  String get navSettings => '設定';

  @override
  String get navSiteAdmin => 'サイト管理';

  @override
  String get environmentBannerStaging => '検証環境';

  @override
  String get signIn => 'ログイン';

  @override
  String get signUp => 'アカウントを作成';

  @override
  String get signOut => 'ログアウト';

  @override
  String get signInWithGoogle => 'Google でログイン';

  @override
  String get signInWithEmail => 'メールアドレスでログイン';

  @override
  String get emailLabel => 'メールアドレス';

  @override
  String get passwordLabel => 'パスワード';

  @override
  String get forgotPassword => 'パスワードをお忘れですか';

  @override
  String get resetPassword => 'パスワードを再設定';

  @override
  String get resetPasswordSent => '再設定用のリンクを送信しました。メールをご確認ください。';

  @override
  String get verifyEmailTitle => '確認メールを送りました';

  @override
  String verifyEmailBody(String email) {
    return '$email 宛に確認メールを送りました。メール内のリンクを開くと、ご利用いただけます。';
  }

  @override
  String get verifyEmailResend => '確認メールを再送する';

  @override
  String get verifyEmailRecheck => '確認が済んだので次へ';

  @override
  String get homeTitle => '参加しているリスト';

  @override
  String get homeEmpty => 'まだどのリストにも参加していません。';

  @override
  String get homeEmptyHint =>
      'リストを作りたい場合は作成を申請してください。既にあるリストに入りたい場合は、参加している方から共有 URL を受け取ってください。';

  @override
  String get requestNewList => 'リスト作成を申請';

  @override
  String get myRequests => '自分の申請';

  @override
  String get roleListAdmin => 'リスト管理者';

  @override
  String get roleSuperUser => 'Super User';

  @override
  String get roleReadOnly => 'Read Only';

  @override
  String get roleSiteAdmin => 'サイト管理者';

  @override
  String itemCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count件',
    );
    return '$_temp0';
  }

  @override
  String quotaUsage(String used, String total) {
    return '$used / $total';
  }

  @override
  String get columnSeq => '連番';

  @override
  String get columnDate => '日付';

  @override
  String get columnTitle => '曲名';

  @override
  String get columnArtist => 'アーティスト名';

  @override
  String get columnRegistrant => '登録者';

  @override
  String get sortBy => '並び替え';

  @override
  String get searchHint => '曲名・アーティスト名・ファイル名で検索';

  @override
  String get showDeletedItems => '削除済みも表示';

  @override
  String get itemDeleted => '削除されました';

  @override
  String get withdrawnUser => '退会したユーザー';

  @override
  String get addItem => '追加';

  @override
  String get editItem => '編集';

  @override
  String get deleteItem => '削除';

  @override
  String get restoreItem => '復元';

  @override
  String get tabFile => 'ファイル';

  @override
  String get tabUrl => 'URL';

  @override
  String get chooseFile => 'ファイルを選択';

  @override
  String get urlLabel => 'URL';

  @override
  String get dateLabel => '日付';

  @override
  String get titleLabel => '曲名（任意）';

  @override
  String get artistLabel => 'アーティスト名（任意）';

  @override
  String get commentLabel => 'コメント（任意）';

  @override
  String get save => '保存';

  @override
  String get cancel => 'キャンセル';

  @override
  String uploadProgress(int percent) {
    return 'アップロード中… $percent%';
  }

  @override
  String get uploadFailed => 'アップロードに失敗しました。もう一度お試しください。';

  @override
  String get quotaExceeded => '上限を超えました。リスト管理者にご連絡ください。';

  @override
  String quotaRemaining(String remaining) {
    return '残り $remaining';
  }

  @override
  String get comments => 'コメント';

  @override
  String get writeComment => 'コメントを書く';

  @override
  String get reply => '返信';

  @override
  String get commentDeleted => '削除されました';

  @override
  String get conflictTitle => '保存できませんでした';

  @override
  String get conflictBody => 'ほかの方がこの項目を更新しました。最新の内容を読み込み直してください。';

  @override
  String get reload => '読み込み直す';

  @override
  String get joinRequestTitle => 'このリストに参加する';

  @override
  String get joinRequestBody => 'このリストの中身は、参加が承認されるまで表示されません。';

  @override
  String get joinRequestButton => '参加を申請';

  @override
  String get joinRequestSent => '参加を申請しました。承認されるまでお待ちください。';

  @override
  String get leaveList => 'このリストから抜ける';

  @override
  String get inviteAccepted => 'リストに参加しました。';

  @override
  String get inviteExpired => '招待の有効期限が切れています。招待した方に再発行を依頼してください。';

  @override
  String get inviteAlreadyUsed => 'この招待はすでに使用されています。招待した方に再発行を依頼してください。';

  @override
  String get inviteRevoked => 'この招待は取り消されています。';

  @override
  String get inviteNotFound => '招待が見つかりません。URL をご確認ください。';

  @override
  String get inviteAlreadyMember => 'すでにこのリストに参加しています。';

  @override
  String get createInvite => '招待 URL を発行';

  @override
  String get requestStatusPending => '申請中';

  @override
  String get requestStatusApproved => '承認';

  @override
  String get requestStatusRejected => '却下';

  @override
  String get requestAgain => 'もう一度申請する';

  @override
  String get approve => '承認';

  @override
  String get reject => '却下';

  @override
  String get members => 'メンバー';

  @override
  String get manageMembers => 'メンバー管理';

  @override
  String get joinRequests => '参加申請';

  @override
  String get removeMember => 'リストから外す';

  @override
  String get changeRole => '役割を変更';

  @override
  String get listSettings => 'リスト設定';

  @override
  String get deleteList => 'リストを削除';

  @override
  String get deleteListWarning =>
      'リストを削除すると、そのリストのファイル・コメントもすべて削除されます。この操作は取り消せません。';

  @override
  String get siteAdminListRequests => 'リスト作成申請';

  @override
  String get siteAdminLists => 'リストと容量';

  @override
  String get siteAdminUsers => 'ユーザー管理';

  @override
  String get siteAdminSettings => 'サイト設定';

  @override
  String get listsWithoutAdmin => '管理者不在のリスト';

  @override
  String get assignListAdmin => 'リスト管理者を指名';

  @override
  String get promoteToSiteAdmin => 'サイト管理者にする';

  @override
  String get lastSiteAdminBlocked =>
      'あなたは現在ただ 1 人のサイト管理者です。先に別の方をサイト管理者に指名してください。';

  @override
  String get displayName => '表示名';

  @override
  String get language => '表示言語';

  @override
  String get notificationSettings => '通知設定';

  @override
  String get notificationMaster => 'すべての通知';

  @override
  String get withdraw => '退会する';

  @override
  String get withdrawWarning => '退会しても、登録した項目やコメントは残ります。表示名は「退会したユーザー」になります。';

  @override
  String get notifyItemAdded => '項目が追加された';

  @override
  String get notifyCommentAdded => 'コメントが付いた';

  @override
  String get notifyQuotaNotice => '容量が 80% を超えた';

  @override
  String get notifyQuotaWarning => '容量が 90% を超えた';

  @override
  String get notifyListRequested => 'リスト作成の申請があった';

  @override
  String get notifyJoinRequested => '参加申請があった';

  @override
  String get notifyRequestApproved => '申請が承認された';

  @override
  String get notificationsEmpty => '通知はありません。';

  @override
  String get markAllAsRead => 'すべて既読にする';

  @override
  String get errorGeneric => 'エラーが発生しました。しばらくしてからもう一度お試しください。';

  @override
  String get errorNoPermission => 'この操作を行う権限がありません。';

  @override
  String get notFound => 'ページが見つかりません。';
}
