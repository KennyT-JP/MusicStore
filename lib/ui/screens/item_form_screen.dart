/// 項目の追加・編集（仕様書 14.4）
///
/// 1 つの画面で「ファイル」「URL」をタブ切替する。
/// 日付・曲名・アーティスト名・コメントの入力欄は共通で、タブを切り替えても
/// 入力内容は保持する。
library;

import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/list_item.dart';
import '../../data/repositories/item_repository.dart';
import '../../domain/local_date.dart';
import '../../domain/quota.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/app_providers.dart';
import '../routes.dart';
import '../widgets/async_view.dart';
import '../widgets/error_message.dart';

class ItemFormScreen extends ConsumerStatefulWidget {
  const ItemFormScreen({super.key, required this.listId, this.itemId});

  final String listId;

  /// null なら新規追加、値があれば編集。
  final String? itemId;

  @override
  ConsumerState<ItemFormScreen> createState() => _ItemFormScreenState();
}

class _ItemFormScreenState extends ConsumerState<ItemFormScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);

  final _url = TextEditingController();
  final _title = TextEditingController();
  final _artist = TextEditingController();
  final _comment = TextEditingController();

  LocalDate _date = LocalDate.today();
  PlatformFile? _picked;

  /// 編集時、既存のファイルを差し替えない場合はこれをそのまま残す。
  ItemFile? _existingFile;

  /// 編集画面を開いたときの updatedAt。同時編集の検出に使う（仕様書 6.3）。
  DateTime? _openedWith;
  bool _loaded = false;

  bool _busy = false;

  /// 進行中のアップロード。中止できるように保持する（仕様書 7.5）。
  UploadTask? _uploadTask;
  double? _uploadProgress;
  String? _error;

  bool get _isEditing => widget.itemId != null;

  /// いま保存できる状態か（仕様書 14.4）。
  ///
  /// **押せるのに押すと怒られる、をやめる。** 以前はファイルを選ばずに
  /// 保存を押せてしまい、一瞬エラーが出たあと画面が閉じていた
  /// （2026-08-09 の指摘）。何が足りないかは、押す前に分かるようにする。
  ///
  /// | タブ | 要るもの |
  /// | --- | --- |
  /// | ファイル | 選んだファイル。**編集中は、元のファイルがあればそれでよい** |
  /// | URL | 空でない URL |
  ///
  /// 曲名・アーティスト名・コメントは任意（14.4）。
  bool get _canSave {
    if (_tabs.index == 0) {
      return _picked?.bytes != null || (_isEditing && _existingFile != null);
    }
    return _url.text.trim().isNotEmpty;
  }

  @override
  void initState() {
    super.initState();
    // **保存ボタンの活性を、入力に追従させる。**
    // タブを切り替えると要るものが変わり、URL は 1 文字目で満たされる。
    // ここを繋がないと、条件を満たしても押せないままになる。
    _tabs.addListener(_refresh);
    _url.addListener(_refresh);
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _tabs.removeListener(_refresh);
    _url.removeListener(_refresh);
    _tabs.dispose();
    _url.dispose();
    _title.dispose();
    _artist.dispose();
    _comment.dispose();
    super.dispose();
  }

  /// 編集時に既存の値を読み込む。1 回だけ行う。
  void _loadOnce(ListItem item) {
    if (_loaded) return;
    _loaded = true;
    _title.text = item.title ?? '';
    _artist.text = item.artist ?? '';
    _url.text = item.url ?? '';
    _date = item.itemDate;
    _existingFile = item.file;
    _openedWith = item.updatedAt;
    if (item.kind == ItemKind.file) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _tabs.animateTo(0));
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _tabs.animateTo(1));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);

    if (_isEditing) {
      final item = ref.watch(
        itemProvider((listId: widget.listId, itemId: widget.itemId!)),
      );
      return AsyncView(
        value: item,
        builder: (data) {
          if (data == null) {
            return Scaffold(
              body: EmptyState(icon: Icons.search_off, title: l10n.notFound),
            );
          }
          _loadOnce(data);
          return _form(l10n);
        },
      );
    }
    return _form(l10n);
  }

  Widget _form(AppL10n l10n) {
    final stats = ref.watch(listStatsProvider(widget.listId)).value;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: _busy ? null : () => _close(),
        ),
        title: Text(_isEditing ? l10n.editItem : l10n.addItem),
        bottom: TabBar(
          controller: _tabs,
          tabs: [
            Tab(
              text: l10n.tabFile,
              icon: const Icon(Icons.audio_file_outlined),
            ),
            Tab(text: l10n.tabUrl, icon: const Icon(Icons.link)),
          ],
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error != null) ...[
                ErrorMessage(_error!),
                const SizedBox(height: 16),
              ],

              // タブによって変わる部分だけを切り替える。
              // 共通の入力欄はタブの外に置いてあるので、切り替えても消えない。
              SizedBox(
                height: 150,
                child: TabBarView(
                  controller: _tabs,
                  children: [_filePane(l10n, stats?.quota), _urlPane(l10n)],
                ),
              ),

              const Divider(height: 32),

              // ここから下はタブ共通（仕様書 14.4）。
              _dateField(l10n),
              const SizedBox(height: 12),
              TextField(
                controller: _title,
                decoration: InputDecoration(
                  labelText: l10n.titleLabel,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _artist,
                decoration: InputDecoration(
                  labelText: l10n.artistLabel,
                  border: const OutlineInputBorder(),
                ),
              ),
              if (!_isEditing) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _comment,
                  minLines: 2,
                  maxLines: 4,
                  decoration: InputDecoration(
                    labelText: l10n.commentLabel,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ],

              const SizedBox(height: 24),
              if (_uploadProgress != null) ...[
                LinearProgressIndicator(value: _uploadProgress),
                const SizedBox(height: 8),
                Text(
                  l10n.uploadProgress((_uploadProgress! * 100).round()),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                // **中止できるようにする（仕様書 7.5 / 14.4）。**
                // 進捗は出していたが止める手段が無く、大きな音源を選んで
                // しまうと完了まで待つしかなかった（監査 S16）。
                Center(
                  child: TextButton.icon(
                    onPressed: _uploadTask == null ? null : _cancelUpload,
                    icon: const Icon(Icons.stop_circle_outlined),
                    label: Text(l10n.cancelUpload),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              // **押せない理由を、押せない場所のそばに書く。**
              // ボタンが灰色なだけだと、何が足りないのか分からない。
              if (!_canSave)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    _tabs.index == 0 ? l10n.fileRequired : l10n.urlRequired,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              FilledButton(
                onPressed: (_busy || !_canSave) ? null : _save,
                child: Text(l10n.save),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _busy ? null : _close,
                child: Text(l10n.cancel),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _filePane(AppL10n l10n, QuotaStatus? quota) {
    final picked = _picked;
    final existing = _existingFile;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton.icon(
          onPressed: _busy ? null : _pickFile,
          icon: const Icon(Icons.upload_file),
          label: Text(l10n.chooseFile),
        ),
        const SizedBox(height: 8),
        if (picked != null)
          Text(l10n.fileWithSize(picked.name, formatBytes(picked.size)))
        else if (existing != null)
          Text(
            l10n.fileWithSize(existing.fileName, formatBytes(existing.sizeBytes)),
            style: TextStyle(color: Theme.of(context).colorScheme.outline),
          ),
        const Spacer(),
        // 残り容量を併せて示す（仕様書 14.4）。
        if (quota != null)
          Text(
            l10n.quotaRemaining(formatBytes(quota.remainingBytes)),
            style: Theme.of(context).textTheme.bodySmall,
          ),
      ],
    );
  }

  Widget _urlPane(AppL10n l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _url,
          keyboardType: TextInputType.url,
          decoration: InputDecoration(
            labelText: l10n.urlLabel,
            border: const OutlineInputBorder(),
            hintText: 'https://',
          ),
        ),
      ],
    );
  }

  Widget _dateField(AppL10n l10n) {
    return InkWell(
      onTap: _busy ? null : _pickDate,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: l10n.dateLabel,
          border: const OutlineInputBorder(),
          suffixIcon: const Icon(Icons.calendar_today, size: 18),
        ),
        child: Text(_date.toIso8601Date()),
      ),
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date.toDateTimeAtNoon(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    // タイムゾーンを持たない年月日として保持する（仕様書 6.2）。
    setState(() => _date = LocalDate(picked.year, picked.month, picked.day));
  }

  /// アップロードを中止する（仕様書 7.5 / 14.4）。
  Future<void> _cancelUpload() async {
    await _uploadTask?.cancel();
    if (mounted) {
      setState(() {
        _uploadTask = null;
        _uploadProgress = null;
      });
    }
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.pickFiles(withData: true);
    if (result == null || result.files.isEmpty) return;
    setState(() {
      _picked = result.files.first;
      _error = null;
    });
  }

  void _close() {
    if (_isEditing) {
      context.go(AppRoutes.item(widget.listId, widget.itemId!));
    } else {
      context.go(AppRoutes.list(widget.listId));
    }
  }

  Future<void> _save() async {
    final l10n = AppL10n.of(context);
    final uid = ref.read(firebaseUserProvider).value?.uid;
    if (uid == null) return;

    final isFileTab = _tabs.index == 0;
    final repo = ref.read(itemRepositoryProvider);

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      // **保存できたときだけ閉じる。**
      // 以前は _saveNew が「入力が足りない」ときに例外ではなく普通に
      // 戻っており、呼び出し側は成功と見分けられずに画面を閉じていた。
      // エラーが一瞬見えてから一覧へ戻る、という出方をする
      // （2026-08-09 の指摘）。**成否を返り値で受け取る。**
      final saved = _isEditing
          ? await _saveEdit(repo, uid, isFileTab, l10n)
          : await _saveNew(repo, uid, isFileTab, l10n);
      if (mounted && saved) _close();
    } on UploadCanceledException {
      // 中止は失敗ではないので、エラーとして見せない（仕様書 7.5）。
      if (mounted) setState(() => _error = null);
    } on QuotaExceededException {
      await _showError(l10n.quotaExceeded);
    } on ConcurrentEditException {
      await _showError(l10n.conflictBody);
    } catch (_) {
      await _showError(l10n.uploadFailed);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _uploadProgress = null;
          _uploadTask = null;
        });
      }
    }
  }

  /// 失敗を知らせる（仕様書 14.4）。
  ///
  /// **画面にとどまる。** 入力したものは残っているので、直して押し直せる。
  /// 一覧へ戻してしまうと、書いた内容ごと失われる（2026-08-09 の指摘）。
  ///
  /// 画面の中にも同じ文言を残す。ポップアップを閉じたあと、
  /// 何が起きたのかを見返せるようにするため。
  Future<void> _showError(String message) async {
    if (!mounted) return;
    setState(() => _error = message);

    final l10n = AppL10n.of(context);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.error_outline),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.close),
          ),
        ],
      ),
    );
  }

  /// 保存できたら true。**足りないものがあれば false**（画面は閉じない）。
  Future<bool> _saveNew(
    ItemRepository repo,
    String uid,
    bool isFileTab,
    AppL10n l10n,
  ) async {
    String itemId;

    if (isFileTab) {
      final picked = _picked;
      if (picked?.bytes == null) {
        await _showError(l10n.fileRequired);
        return false;
      }
      final stats = ref.read(listStatsProvider(widget.listId)).value;
      itemId = await repo.addFileItem(
        listId: widget.listId,
        uid: uid,
        bytes: picked!.bytes!,
        fileName: picked.name,
        contentType: _guessContentType(picked.name),
        date: _date,
        quota:
            stats?.quota ??
            const QuotaStatus(usedBytes: 0, quotaBytes: kDefaultQuotaBytes),
        title: _title.text,
        artist: _artist.text,
        onProgress: (fraction) {
          if (mounted) setState(() => _uploadProgress = fraction);
        },
        onTaskStarted: (task) {
          if (mounted) setState(() => _uploadTask = task);
        },
      );
    } else {
      if (_url.text.trim().isEmpty) {
        await _showError(l10n.urlRequired);
        return false;
      }
      itemId = await repo.addUrlItem(
        listId: widget.listId,
        uid: uid,
        url: _url.text,
        date: _date,
        title: _title.text,
        artist: _artist.text,
      );
    }

    // 追加時のコメントは独立したコメントとして作る（仕様書 13.3）。
    if (_comment.text.trim().isNotEmpty) {
      await repo.addComment(
        listId: widget.listId,
        itemId: itemId,
        uid: uid,
        body: _comment.text,
      );
    }
    return true;
  }

  /// 保存できたら true。**受け付けられない指定なら false**（画面は閉じない）。
  Future<bool> _saveEdit(
    ItemRepository repo,
    String uid,
    bool isFileTab,
    AppL10n l10n,
  ) async {
    // ファイルの差し替えは未実装。
    // 新しいファイルを別名で保存し、旧ファイルを猶予期間後に削除する必要があり
    // （仕様書 13.7 / 13.4）、Cloud Functions 側の対応と合わせて実装する。
    if (isFileTab && _picked != null) {
      await _showError(l10n.fileReplaceNotSupported);
      return false;
    }

    await repo.updateItem(
      listId: widget.listId,
      itemId: widget.itemId!,
      uid: uid,
      openedWith: _openedWith,
      date: _date,
      title: _title.text,
      artist: _artist.text,
      url: isFileTab ? null : _url.text,
      file: isFileTab ? _existingFile : null,
    );
    return true;
  }

  /// 拡張子から MIME タイプを推測する。
  ///
  /// ファイル種別は制限しない（仕様書 7.1）ので、分からないものは
  /// octet-stream にしておく。
  String _guessContentType(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    return switch (ext) {
      'mp3' => 'audio/mpeg',
      'm4a' => 'audio/mp4',
      'wav' => 'audio/wav',
      'flac' => 'audio/flac',
      'ogg' => 'audio/ogg',
      'aac' => 'audio/aac',
      'mp4' => 'video/mp4',
      'mov' => 'video/quicktime',
      _ => 'application/octet-stream',
    };
  }
}
