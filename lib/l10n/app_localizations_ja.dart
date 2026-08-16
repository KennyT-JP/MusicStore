// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Japanese (`ja`).
class AppL10nJa extends AppL10n {
  AppL10nJa([String locale = 'ja']) : super(locale);

  @override
  String get appTitle => '音源創庫';

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
  String get forgotPassword => 'パスワードをお忘れですか？';

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
  String get verifyEmailRecheck => '確認を済ませたら次へ';

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
  String get signUpPrompt => 'はじめての方はこちら（新規登録）';

  @override
  String get orSeparator => 'または';

  @override
  String get continueWithGoogle => 'Google で続ける';

  @override
  String get continueWithApple => 'Apple で続ける';

  @override
  String get showPassword => 'パスワードを表示';

  @override
  String get hidePassword => 'パスワードを隠す';

  @override
  String get authPopupBlocked =>
      'ログイン用のウィンドウがブラウザにブロックされました。このサイトのポップアップを許可してから、もう一度お試しください。';

  @override
  String get authProviderDisabled => 'この方法でのログインは、いま利用できません。管理者にお問い合わせください。';

  @override
  String get authUnauthorizedDomain =>
      'このアドレスからはログインできない設定になっています。管理者にお問い合わせください。';

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
  String get help => '使い方';

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
  String get orphanGraceLabel => '行き場を失ったファイルの保持時間';

  @override
  String get unitHours => '時間';

  @override
  String get orphanGraceHelp =>
      '初期値 24。アップロードは終わったのに曲として登録されなかったファイルを、この時間が過ぎてから消します。短くしすぎると、登録の直前のファイルまで巻き添えで消えます。';

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
  String fileWithSize(Object name, Object size) {
    return '$name（$size）';
  }

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
  String get stopViewing => 'このリストを見るのをやめる';

  @override
  String get stopViewingBody =>
      'このリストの閲覧をやめます。\n\n中身は見られなくなりますが、同じ共有リンクからまた入れます。あなたが書いたコメントは残ります。';

  @override
  String get myRequestsEmpty => 'まだ申請はありません。';

  @override
  String get myJoinRequests => '自分の参加申請';

  @override
  String get open => '開く';

  @override
  String get openLink => 'リンクを開く';

  @override
  String get downloadFile => 'ファイルをダウンロード';

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
  String get notifyItemAdded => '曲が追加されました';

  @override
  String get notifyCommentAdded => 'コメントが付きました';

  @override
  String get notifyQuotaNotice => '容量が 80% を超えました';

  @override
  String get notifyQuotaWarning => '容量が 90% を超えました';

  @override
  String get notifyListRequested => 'リスト作成の申請がありました';

  @override
  String get notifyJoinRequested => '参加申請がありました';

  @override
  String get notifyRequestApproved => '申請が承認されました';

  @override
  String get notifyItemAddedDetail =>
      '参加しているリストに曲が追加されたときに届きます。管理しているリストも含みます。';

  @override
  String get notifyCommentAddedDetail =>
      '自分が管理しているリスト、または自分の投稿にコメントが付いたときに届きます。';

  @override
  String get notifyQuotaNoticeDetail => '管理しているリストの使用容量が上限の 80% を超えたときに届きます。';

  @override
  String get notifyQuotaWarningDetail => '管理しているリストの使用容量が上限の 90% を超えたときに届きます。';

  @override
  String get notifyListRequestedDetail =>
      'リスト作成の申請が出されたときに届きます。サイト管理者だけが受け取ります。';

  @override
  String get notifyJoinRequestedDetail => '管理しているリストに参加を申し込まれたときに届きます。';

  @override
  String get notifyRequestApprovedDetail => '自分が出した申請が承認されたときに届きます。';

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
  String get functionErrorSelfNotAllowed => 'ご自身に対しては行えません。退会される場合は設定からお願いします。';

  @override
  String get functionErrorEmailInvalid => 'メールアドレスの形式が正しくありません。';

  @override
  String get functionErrorPasswordTooShort => 'パスワードは 6 文字以上で入力してください。';

  @override
  String get functionErrorEmailAlreadyInUse => 'このメールアドレスはすでに使われています。';

  @override
  String get addUser => 'ユーザーを追加';

  @override
  String get addUserBody => 'サイト管理者がパスワードを決めます。お渡ししたあとで、ご本人に変更していただいてください。';

  @override
  String get addUserSubmit => '追加する';

  @override
  String get displayNameRequired => '表示名を入力してください';

  @override
  String get userAdded => 'ユーザーを追加しました。';

  @override
  String get disableUser => '無効にする';

  @override
  String get enableUser => '有効に戻す';

  @override
  String get deleteUser => '削除する';

  @override
  String get userDisabledLabel => '無効';

  @override
  String disableUserBody(String name) {
    return '「$name」を無効にします。\n\nログインできなくなり、参加中のリストからも外れます。登録した曲・音源ファイル・コメントは残ります。\n\nあとから有効に戻せます。';
  }

  @override
  String enableUserBody(String name) {
    return '「$name」を有効に戻します。\n\nまたログインできるようになります。参加していたリストには戻らないため、必要であれば改めてご案内ください。';
  }

  @override
  String deleteUserBody(String name) {
    return '「$name」を削除します。\n\nアカウントと、その方が登録した曲・音源ファイルを消します。書かれたコメントは残り、表示名が「退会したユーザー」になります。\n\nバックアップは取っていないため、削除した内容は元に戻せません。無効にするだけであれば、データは残ります。';
  }

  @override
  String get userDisabled => '無効にしました。';

  @override
  String get userEnabled => '有効に戻しました。';

  @override
  String get userDeleted => '削除しました。';

  @override
  String functionErrorListNameTaken(String listName) {
    return '「$listName」は既に使われているか、申請中です。';
  }

  @override
  String get errorGeneric => 'エラーが発生しました。しばらくしてからもう一度お試しください。';

  @override
  String get errorNoPermission => 'この操作を行う権限がありません。';

  @override
  String get operationFailed => '操作を完了できませんでした。通信状況をご確認のうえ、もう一度お試しください。';

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
  String get shareLinkCopyFailed => 'リンクをコピーできませんでした。もう一度お試しください。';

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
  String get shareLinkJoinTitle => 'リストのメンバーになる';

  @override
  String get shareLinkJoinBody =>
      'メンバーになります。曲やコメントを追加できます。メンバー一覧に名前が出て、曲が追加されると通知が届きます。';

  @override
  String get shareLinkViewTitle => 'リストのメンバーにならずに見る';

  @override
  String get shareLinkViewBody =>
      'メンバーにはなりません。曲の一覧を見て、音を聴くことはできます。メンバー一覧には出ず、通知も届きません。書き込みもできません。';

  @override
  String get shareLinkChangeLaterNote =>
      '「リストのメンバーにならずに見る」を選んだあとでメンバーになりたくなったら、同じリンクをもう一度開いてください。';

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
  String get functionErrorItemDeleted => '削除済みの曲は差し替えられません。先に復元してください。';

  @override
  String get functionErrorCannotEditItem => 'この曲を編集する権限がありません。';

  @override
  String get functionErrorFileNotInThisItem =>
      'ファイルの置き場所が正しくありません。もう一度やり直してください。';

  @override
  String get functionErrorUploadNotFound =>
      'アップロードしたファイルが見つかりません。通信の状態を確かめて、もう一度お試しください。';

  @override
  String get functionErrorSameStoragePath =>
      '同じ場所へ上書きされています。もう一度ファイルを選び直してください。';

  @override
  String get viewersTitle => '参加せずに見ている人';

  @override
  String get viewersEmpty => 'まだいません。';

  @override
  String get addToList => 'リストに追加';

  @override
  String addToListTitle(String name) {
    return '$name をリストに追加';
  }

  @override
  String get addToListEmpty => 'リストがまだありません。';

  @override
  String addAs(String role) {
    return '追加：$role';
  }

  @override
  String addToListDone(String list) {
    return '$list に追加しました';
  }

  @override
  String get functionErrorUserDisabled => 'この利用者は無効にされています。先に有効に戻してください。';

  @override
  String get functionErrorUserWithdrawn => 'この利用者は退会しています。';

  @override
  String get premiumSection => 'プレミアム';

  @override
  String premiumActiveUntil(String date) {
    return '$date までプレミアムをご利用いただけます。';
  }

  @override
  String get premiumInactive => '現在はプレミアムではありません。';

  @override
  String get premiumInactiveNote =>
      'プレミアムでない間も、これまでに保存した音源やリストはそのまま残ります。新しいリストを申請なしで作れないだけです。';

  @override
  String get couponCodeLabel => 'クーポンコード';

  @override
  String get couponCodeRequired => 'クーポンコードを入力してください';

  @override
  String get couponRedeem => 'クーポンを適用';

  @override
  String couponRedeemed(String date) {
    return 'クーポンを適用しました。$date までプレミアムをご利用いただけます。';
  }

  @override
  String get createList => 'リストを作る';

  @override
  String get createListNote => 'プレミアムの方は、申請せずにその場でリストを作成できます。';

  @override
  String get listCreated => 'リストを作成しました。';

  @override
  String get myStorageTitle => '使用中の容量（あなたの合計）';

  @override
  String get myStorageNote =>
      'あなたが作成したすべてのリストの合計です。上限はリストごとではなく、この合計に対してかかります。';

  @override
  String get myStorageUnknown => '使用量はまだ集計されていません。音源を追加すると表示されます。';

  @override
  String get ownerQuotaTitle => '使用中の容量（作成者の合計）';

  @override
  String get ownerQuotaCaption => '作成者の合計';

  @override
  String get ownerQuotaNote =>
      'このリストを作成した方が持つ、すべてのリストの合計です。このリスト 1 つ分の量ではありません。どなたが音源を追加しても、作成した方の容量から引かれます。';

  @override
  String get ownerQuotaUnknown => '作成者の合計容量は、まだ集計されていません。しばらくしてからご確認ください。';

  @override
  String get siteAdminCoupons => 'クーポン';

  @override
  String get couponListEmpty => 'まだクーポンはありません。';

  @override
  String get couponCreate => 'クーポンを発行';

  @override
  String get couponMonthsLabel => '付与する月数';

  @override
  String get couponMaxUsesLabel => '使える人数';

  @override
  String get couponExpiresLabel => 'クーポンの有効期限';

  @override
  String get couponNoExpiry => '期限なし';

  @override
  String get couponChooseExpiry => '期限を決める';

  @override
  String get couponClearExpiry => '期限を外す';

  @override
  String get couponCodeAuto => '自動で作る';

  @override
  String get couponCodeManual => '文字列を指定';

  @override
  String get couponCodeManualLabel => '指定するコード';

  @override
  String get couponCodeManualWarning =>
      '指定した文字列は覚えやすいぶん、推測もされやすくなります。使える人数と有効期限を必ず決めてください。';

  @override
  String couponMonthsValue(int months) {
    return '$months か月';
  }

  @override
  String couponUsesValue(int used, int max) {
    return '$used / $max 人';
  }

  @override
  String couponExpiresOn(String date) {
    return '期限 $date';
  }

  @override
  String get couponDisabledLabel => '停止中';

  @override
  String get couponUsedUpLabel => '上限に達しました';

  @override
  String get couponExpiredLabel => '期限切れ';

  @override
  String get couponDisable => '停止する';

  @override
  String get couponEnable => '停止を解除';

  @override
  String get couponChangeMaxUses => '人数を変える';

  @override
  String couponChangeMaxUsesBody(String code) {
    return '「$code」を使える人数を入力してください。すでに使った方より少ない人数にもできます。その場合、これ以上は使えなくなるだけで、すでに使った方のプレミアムは取り消されません。';
  }

  @override
  String get couponViewRedemptions => '使った人を見る';

  @override
  String couponRedemptionsTitle(String code) {
    return '「$code」を使った方';
  }

  @override
  String get couponRedemptionsEmpty => 'まだどなたも使っていません。';

  @override
  String couponCreated(String code) {
    return 'クーポンを発行しました：$code';
  }

  @override
  String get couponCopyCode => 'コードをコピー';

  @override
  String get couponCodeCopied => 'コードをコピーしました。';

  @override
  String get extendPremium => 'プレミアムを延長';

  @override
  String extendPremiumBody(String name) {
    return '$name のプレミアムを延長します。すでに期限がある場合は、その後ろに足されます。';
  }

  @override
  String get extendPremiumMonthsLabel => '延長する月数';

  @override
  String extendPremiumDone(String date) {
    return '$date まで延長しました。';
  }

  @override
  String get setUserQuotaTitle => '利用者の容量上限を変更';

  @override
  String setUserQuotaBody(String name) {
    return '$name の容量上限を MB 単位で入力してください。リストごとではなく、その方が作成したすべてのリストの合計に効きます。';
  }

  @override
  String get setUserQuotaDone => '容量上限を変更しました。';

  @override
  String get functionErrorPremiumRequired =>
      'この操作にはプレミアムが必要です。設定画面でクーポンコードを入力してください。';

  @override
  String get functionErrorCouponNotFound => 'そのクーポンコードは見つかりません。入力した文字をご確認ください。';

  @override
  String get functionErrorCouponDisabled => 'このクーポンは停止されています。配布元にお問い合わせください。';

  @override
  String get functionErrorCouponExpired => 'このクーポンは有効期限が切れています。';

  @override
  String get functionErrorCouponUsedUp => 'このクーポンは、使える人数の上限に達しています。';

  @override
  String get functionErrorCouponAlreadyUsed =>
      'このクーポンはすでにお使いです。同じクーポンは一度だけ使えます。';

  @override
  String get functionErrorCouponCodeTaken => 'そのコードはすでに使われています。別の文字列を指定してください。';

  @override
  String get functionErrorMonthsInvalid => '月数は 1 以上の整数で指定してください。';

  @override
  String get functionErrorMaxUsesInvalid => '使える人数は 1 以上の整数で指定してください。';

  @override
  String get functionErrorTooManyLists =>
      '一度に確認できるリストは 50 件までです。オフラインに保存するリストを減らしてから、もう一度お試しください。';

  @override
  String get navDownloads => 'ダウンロード済み';

  @override
  String get downloadsListLabel => 'リスト';

  @override
  String get downloadsTitle => 'ダウンロード済み';

  @override
  String get downloadsEmpty => '端末に保存した曲はまだありません。';

  @override
  String get downloadsEmptyHint =>
      '曲の一覧やリストのメニューから、端末に保存できます。インターネットに繋がっていなくても聴けるようになります（プレミアムの機能です）。';

  @override
  String downloadsUsage(String size, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 曲',
    );
    return '$size（$_temp0）';
  }

  @override
  String downloadsPerList(String name, String size, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 曲',
    );
    return '$name — $size（$_temp0）';
  }

  @override
  String offlineNoticeExpiring(int days) {
    return 'あと $days 日でオフライン再生が止まります。一度インターネットに接続してください。';
  }

  @override
  String get offlineNoticeStopped =>
      'オフラインで聴ける期間（30 日）が過ぎました。一度インターネットに接続すると、また聴けるようになります。端末のファイルは残っています。';

  @override
  String get offlineComments => 'コメント';

  @override
  String get offlineCommentsEmpty => 'この曲にコメントはありません。';

  @override
  String get offlineCommentsReadOnly => '端末に保存した写しです。オフラインでは書き込めません。';

  @override
  String get downloadToDevice => '端末に保存';

  @override
  String get downloadedToDevice => '端末に保存済み';

  @override
  String get downloadCancel => 'ダウンロードを中止';

  @override
  String get downloadKeepAppOpen => 'アプリを開いたままにしてください。閉じるとダウンロードは止まります。';

  @override
  String downloadProgressBytes(String done, String total) {
    return '$done / $total';
  }

  @override
  String get downloadDone => '端末に保存しました。';

  @override
  String get downloadFailed => 'ダウンロードできませんでした。もう一度お試しください。';

  @override
  String get downloadNeedsWifi =>
      'Wi-Fi に接続しているあいだだけダウンロードします。設定でモバイル通信も許可できます。';

  @override
  String get downloadNotSupportedFile => 'このファイルは端末に保存できません。音源だけが対象です。';

  @override
  String get downloadPermissionLost => 'このリストの音源を端末に保存する権限がありません。';

  @override
  String get downloadUnavailableHere => 'この環境では端末に保存できません。';

  @override
  String get downloadRemove => '端末から削除';

  @override
  String downloadRemoveBody(String title) {
    return '「$title」を端末から削除します。曲もリストも消えません。もう一度ダウンロードできます。';
  }

  @override
  String get downloadPremiumOnly => 'オフライン保存はプレミアムの機能です';

  @override
  String get downloadPremiumOnlyBody =>
      '端末に保存してオフラインで聴く機能は、プレミアムをご利用の方の機能です。設定でクーポンコードを入力すると、お使いいただけます。';

  @override
  String get downloadPremiumOnlyCta => 'クーポンを入力';

  @override
  String get downloadList => 'このリストを端末に保存';

  @override
  String downloadListEstimate(int total, int done, int count, String size) {
    return '$total 曲中 $done 曲は保存済みです。残り $count 曲・約 $size をダウンロードします。';
  }

  @override
  String get downloadListNothing => 'このリストの曲は、すべて端末に保存済みです。';

  @override
  String get downloadListStart => 'ダウンロードを始める';

  @override
  String downloadListProgress(int position, int total) {
    return '$position / $total 曲目';
  }

  @override
  String downloadListDone(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 曲',
    );
    return '$_temp0を端末に保存しました。';
  }

  @override
  String downloadListFailed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 曲',
    );
    return '$_temp0を保存できませんでした。';
  }

  @override
  String get downloadListStopped => 'ダウンロードを中止しました。保存が済んだぶんは端末に残っています。';

  @override
  String get downloadStop => '中止';

  @override
  String get downloadsSettingsTitle => '端末に保存した音源';

  @override
  String get downloadsSettingsNone => '端末に保存した音源はありません。';

  @override
  String get downloadsSettingsOpen => 'ダウンロード済みを見る';

  @override
  String get downloadsRemoveAll => '端末の保存をすべて削除';

  @override
  String get downloadsRemoveAllBody =>
      '端末に保存した音源をすべて削除します。曲もリストも、アップロードしたファイルも消えません。これまでどおりオンラインで再生でき、もう一度ダウンロードできます。';

  @override
  String get downloadsRemoveAllDone => '端末に保存した音源を削除しました。曲もリストも残っています。';

  @override
  String get downloadsAllowMobileData => 'モバイル通信でもダウンロードする';

  @override
  String get downloadsAllowMobileDataNote =>
      'オフのときは Wi-Fi に接続しているあいだだけダウンロードします。';

  @override
  String downloadSyncRemovedOne(String title) {
    return '「$title」は元が削除されたため、端末からも削除しました。';
  }

  @override
  String downloadSyncRemovedMany(int count) {
    return '元が削除された $count 曲を、端末からも削除しました。';
  }

  @override
  String downloadSyncReplaced(int count) {
    return '差し替えられた $count 曲を、端末に落とし直しました。';
  }

  @override
  String get webDownloadNoticeTitle => 'ブラウザからの音源のダウンロードについて';

  @override
  String get webDownloadNoticeBody1 =>
      'Web ブラウザからの音源のダウンロードを、今後終了します。Android アプリの公開に合わせて実施します。';

  @override
  String get webDownloadNoticeBody2 =>
      'これまでどおり、ブラウザでそのまま再生できます。楽譜やその他のファイルは、これまでどおりダウンロードできます。';

  @override
  String get webDownloadNoticeBody3 =>
      '端末に保存してオフラインで聴く機能は、iOS / Android アプリでご利用いただけます（プレミアムの機能です）。';

  @override
  String get webDownloadReplacement => 'オフラインで聴くには、アプリをお使いください。';
}
