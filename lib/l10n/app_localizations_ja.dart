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
  String get emailRequired => 'メールアドレスを入力してください';

  @override
  String get passwordRequired => 'パスワードを入力してください';

  @override
  String get passwordTooShort => 'パスワードは 6 文字以上で入力してください';

  @override
  String get urlRequired => 'URL を入力してください';

  @override
  String get fileRequired => 'ファイルを選択してください';

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
  String get verifyEmailAutoDetect => 'リンクを開くと、この画面も自動で次に進みます。';

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
  String get edit => '編集';

  @override
  String get cancelUpload => 'アップロードを中止';

  @override
  String get authInvalidEmail => 'メールアドレスの形式が正しくありません。';

  @override
  String get authUserDisabled => 'このアカウントは無効になっています。';

  @override
  String get authWrongCredential => 'メールアドレスまたはパスワードが違います。';

  @override
  String get authEmailInUse => 'このメールアドレスはすでに使われています。ログインしてください。';

  @override
  String get authWeakPassword => 'パスワードが短すぎます。6 文字以上にしてください。';

  @override
  String get authTooManyRequests => '試行回数が多すぎます。しばらく待ってからお試しください。';

  @override
  String get authPopupClosed => 'ログインがキャンセルされました。';

  @override
  String get authNetworkFailed => 'ネットワークに接続できませんでした。通信状況をご確認ください。';

  @override
  String get requestSubmitted => '申請しました。';

  @override
  String get requestSubmittedBody => 'サイト管理者が確認して承認するまでお待ちください。';

  @override
  String get listNameLabel => 'リスト名';

  @override
  String get listNameHelper => '既にあるリストと同じ名前は使えません';

  @override
  String get listNameRequired => 'リスト名を入力してください';

  @override
  String get estimatedTrackCountLabel => '概算の登録曲数';

  @override
  String get expectedUserCountLabel => '使用者数';

  @override
  String get purposeLabel => '作成目的';

  @override
  String get purposeRequired => '作成目的を入力してください';

  @override
  String get nonNegativeNumberRequired => '0 以上の数値を入力してください';

  @override
  String get openList => 'リストを開く';

  @override
  String get startPlayback => '再生';

  @override
  String get pausePlayback => '一時停止';

  @override
  String get stopPlayback => '停止';

  @override
  String get playbackFailed => '再生できませんでした。もう一度お試しください。';

  @override
  String get showDetails => '詳細';

  @override
  String get close => '閉じる';

  @override
  String get removeMemberBody =>
      'このメンバーをリストから外します。\n\n登録した項目やコメントは残りますが、表示名は「退会したユーザー」になります。あらためて参加申請することもできます。';

  @override
  String get leaveListBody =>
      'このリストから抜けます。\n\n登録した項目やコメントは残りますが、表示名は「退会したユーザー」になります。';

  @override
  String get noPendingRequests => '保留中の申請はありません。';

  @override
  String get chooseApprovalRole => '承認する役割を選んでください';

  @override
  String deleteListBody(String name) {
    return '「$name」を削除します。\n\nバックアップは取っていないため、削除した内容は元に戻せません。';
  }

  @override
  String get usedCapacity => '使用容量';

  @override
  String get quotaOver90 => '上限の 90% を超えています。上限の引き上げはサイト管理者に依頼してください。';

  @override
  String get quotaOver80 => '上限の 80% を超えています。';

  @override
  String get quotaGraceNote => '削除した項目のファイルは一定期間保持されるため、削除してもすぐには空きが増えません。';

  @override
  String get shareUrl => '共有 URL';

  @override
  String get shareUrlNote => 'この URL を渡すと、受け取った人は参加を申請できます。中身は承認するまで見えません。';

  @override
  String get noPendingListRequests => '保留中の申請はありません。';

  @override
  String get requesterLabel => '申請者';

  @override
  String get trackCountLabel => '登録曲数';

  @override
  String trackCountValue(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '約 $count 曲',
    );
    return '$_temp0';
  }

  @override
  String userCountValue(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 人',
    );
    return '$_temp0';
  }

  @override
  String get noListsYet => 'リストはまだありません。';

  @override
  String get changeQuota => '容量上限を変更';

  @override
  String changeQuotaBody(Object name) {
    return '「$name」の上限を MB 単位で入力してください。';
  }

  @override
  String siteAdminCountSummary(Object admins, Object total) {
    return 'サイト管理者 $admins 人 / 全 $total 人';
  }

  @override
  String memberCountHeading(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'メンバー（$count）',
    );
    return '$_temp0';
  }

  @override
  String changeRoleTo(String role) {
    return '役割を変更：$role';
  }

  @override
  String approveAs(String role) {
    return '承認：$role';
  }

  @override
  String get withdrawIrreversible => 'この操作は取り消せません。';

  @override
  String noItemsHint(String addItem) {
    return '右下の「$addItem」から音源や URL を登録できます。';
  }

  @override
  String get removeSiteAdmin => '管理者から外す';

  @override
  String get siteAdminGranted => 'サイト管理者にしました。反映には本人の再ログインが必要です。';

  @override
  String get siteAdminRevoked => 'サイト管理者から外しました。反映には本人の再ログインが必要です。';

  @override
  String get defaultQuotaLabel => '新規リストの容量上限';

  @override
  String get defaultQuotaHelp => '初期値 1024（1GB）。既存リストの上限は「リストと容量」から変更します。';

  @override
  String get purgeGraceLabel => '削除ファイルの保持日数';

  @override
  String get unitDays => '日';

  @override
  String get purgeGraceHelp => '初期値 30。この期間はリスト管理者が復元でき、容量も消費し続けます。';

  @override
  String get invalidNumber => '数値を正しく入力してください。';

  @override
  String get saved => '保存しました。';

  @override
  String get verificationResent => '確認メールを再送しました。';

  @override
  String get verificationNotYet => 'まだ確認が済んでいないようです。メール内のリンクを開いてください。';

  @override
  String get displayNameHelper => '後から変更できます';

  @override
  String get passwordHelper => '6 文字以上';

  @override
  String get noItemsYet => 'まだ項目がありません。';

  @override
  String get noSearchResults => '該当する項目が見つかりませんでした。';

  @override
  String deleteItemBody(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: 'この項目を削除します。\n\nファイル本体は $days 日間保持され、その間はリスト管理者以上が復元できます。',
    );
    return '$_temp0';
  }

  @override
  String restorableUntil(Object date) {
    return '$date まではリスト管理者が復元できます。';
  }

  @override
  String get noCommentsYet => 'まだコメントはありません。';

  @override
  String replyingTo(Object body) {
    return '「$body」への返信';
  }

  @override
  String get join => '参加する';

  @override
  String fileWithSize(Object name, Object size) {
    return '$name（$size）';
  }

  @override
  String get fileReplaceNotSupported =>
      'ファイルの差し替えはまだ実装されていません。曲名・アーティスト名・日付の変更は保存できます。';

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
  String get conflictBody => 'ほかの方がこの項目を更新しました。最新の内容を読み込み直してください。';

  @override
  String get reload => '読み込み直す';

  @override
  String get joinRequestBody => 'このリストの中身は、参加が承認されるまで表示されません。';

  @override
  String get joinRequestButton => '参加を申請';

  @override
  String get joinRequestSent => '参加を申請しました。承認されるまでお待ちください。';

  @override
  String get leaveList => 'このリストから抜ける';

  @override
  String get myRequestsEmpty => 'まだ申請はありません。';

  @override
  String get myJoinRequests => '自分の参加申請';

  @override
  String get open => '開く';

  @override
  String get requestStatusPending => '申請中';

  @override
  String get requestStatusApproved => '承認済み';

  @override
  String get requestStatusRejected => '却下済み';

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
  String get notifyItemAdded => '曲が追加された';

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
  String get notifyItemAddedDetail => '参加しているリストに曲が追加されたとき。管理しているリストも含みます。';

  @override
  String get notifyCommentAddedDetail => '自分が管理しているリスト、または自分の投稿にコメントが付いたとき。';

  @override
  String get notifyQuotaNoticeDetail => '管理しているリストの使用容量が上限の 80% を超えたとき。';

  @override
  String get notifyQuotaWarningDetail => '管理しているリストの使用容量が上限の 90% を超えたとき。';

  @override
  String get notifyListRequestedDetail => 'リスト作成の申請が出されたとき。サイト管理者だけが受け取ります。';

  @override
  String get notifyJoinRequestedDetail => '管理しているリストに参加を申し込まれたとき。';

  @override
  String get notifyRequestApprovedDetail => '自分が出した申請が承認されたとき。';

  @override
  String get notificationsEmpty => '通知はありません。';

  @override
  String get markAllAsRead => 'すべて既読にする';

  @override
  String get functionErrorSignInRequired => 'ログインが必要です。';

  @override
  String get functionErrorEmailNotVerified =>
      'メールアドレスの確認が済んでいません。確認メールのリンクを開いてください。';

  @override
  String get functionErrorSiteAdminOnly => 'この操作はサイト管理者のみ行えます。';

  @override
  String get functionErrorListAdminOnly => 'この操作はリスト管理者のみ行えます。';

  @override
  String get functionErrorListNotFound => 'リストが見つかりません。';

  @override
  String get functionErrorUserNotFound => 'ユーザーが見つかりません。';

  @override
  String get functionErrorRequestNotFound => '申請が見つかりません。';

  @override
  String get functionErrorRequestAlreadyHandled => 'この申請はすでに処理されています。';

  @override
  String get functionErrorListNameMissing => 'リスト名がありません。';

  @override
  String get functionErrorRequesterUnknown => '申請者が不明です。';

  @override
  String get functionErrorInvalidTrackCount => '登録曲数を正しく入力してください。';

  @override
  String get functionErrorInvalidUserCount => '使用者数を正しく入力してください。';

  @override
  String get functionErrorInvalidQuota => '上限は 1 バイト以上で指定してください。';

  @override
  String get functionErrorLastSiteAdmin =>
      'あなたは現在ただ 1 人のサイト管理者です。先に別の方をサイト管理者に指名してください。';

  @override
  String get functionErrorAlreadyMember => 'すでにこのリストに参加しています。';

  @override
  String get functionErrorRoleNotAllowed =>
      '役割は Super User か Read Only を指定してください。';

  @override
  String get functionErrorMissingField => '入力が足りません。';

  @override
  String get functionErrorFieldTooLong => '入力が長すぎます。';

  @override
  String functionErrorListNameTaken(String listName) {
    return '「$listName」は既に使われているか、申請中です。';
  }

  @override
  String get errorGeneric => 'エラーが発生しました。しばらくしてからもう一度お試しください。';

  @override
  String get errorNoPermission => 'この操作を行う権限がありません。';

  @override
  String get notFound => 'ページが見つかりません。';

  @override
  String get createShareLink => '共有リンクを作る';

  @override
  String get copyShareLink => 'リンクをコピー';

  @override
  String get shareLinkCopied => 'リンクをコピーしました。';

  @override
  String get shareLinkReusableNote =>
      '有効期限はありません。何人でも、何度でも使えます。止めるときは取り消してください。';

  @override
  String get shareLinkCopyFailed => 'リンクを作れませんでした。もう一度お試しください。';

  @override
  String get copyItemShareLink => 'この曲のリンクをコピー';

  @override
  String get revokeShareLink => 'リンクを取り消す';

  @override
  String get shareLinkRevokedDone => 'リンクを取り消しました。以降このリンクからは入れません。';

  @override
  String get shareLinkReceived => 'リンクが共有されました';

  @override
  String get shareLinkChooseHint => 'どちらかを選んでください。あとから変えられます。';

  @override
  String get shareLinkJoinTitle => '参加する';

  @override
  String get shareLinkJoinBody =>
      'メンバーになります。メンバー一覧に名前が出て、曲が追加されると通知が届きます。役割によっては曲やコメントを追加できます。';

  @override
  String get shareLinkViewTitle => '参加せずに見る';

  @override
  String get shareLinkViewBody =>
      'メンバーにはなりません。曲の一覧を見て、音を聴くことはできます。メンバー一覧には出ず、通知も届きません。書き込みもできません。';

  @override
  String get shareLinkChangeLaterNote =>
      '「参加せずに見る」を選んだあとで参加したくなったら、同じリンクをもう一度開いてください。';

  @override
  String get shareLinkNotFound => 'リンクが見つかりません。URL をご確認ください。';

  @override
  String get shareLinkRevoked => 'このリンクは取り消されています。共有した方に新しいリンクを依頼してください。';

  @override
  String get functionErrorShareLinkNotFound => 'リンクが見つかりません。URL をご確認ください。';

  @override
  String get functionErrorShareLinkRevoked => 'このリンクは取り消されています。';

  @override
  String get functionErrorItemNotFound => '曲が見つかりません。';

  @override
  String get viewersTitle => '参加せずに見ている人';

  @override
  String get viewersEmpty => 'まだいません。';
}
