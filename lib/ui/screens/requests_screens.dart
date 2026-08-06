/// 申請まわりの画面（仕様書 5.1 / 5.2 / 5.2.1 / 5.3 / 14.2）
///
/// - リスト作成の申請
/// - 自分の申請一覧
/// - リスト参加申請（共有 URL を開いた未参加者向け）
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/requests.dart';
import '../../data/repositories/functions_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/app_providers.dart';
import '../routes.dart';
import '../widgets/async_view.dart';
import '../widgets/error_message.dart';

// ---------------------------------------------------------------------------
// リスト作成の申請（仕様書 5.1）
// ---------------------------------------------------------------------------

class RequestListScreen extends ConsumerStatefulWidget {
  const RequestListScreen({super.key});

  @override
  ConsumerState<RequestListScreen> createState() => _RequestListScreenState();
}

class _RequestListScreenState extends ConsumerState<RequestListScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _tracks = TextEditingController();
  final _users = TextEditingController();
  final _purpose = TextEditingController();

  bool _busy = false;
  bool _sent = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _tracks.dispose();
    _users.dispose();
    _purpose.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);

    if (_sent) {
      return Scaffold(
        body: EmptyState(
          icon: Icons.check_circle_outline,
          title: l10n.requestSubmitted,
          description:
              '${l10n.requestSubmittedBody}\n${l10n.myRequests}',
          action: FilledButton(
            onPressed: () => context.go(AppRoutes.myRequests),
            child: Text(l10n.myRequests),
          ),
        ),
      );
    }

    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    l10n.requestNewList,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  if (_error != null) ...[
                    ErrorMessage(_error!),
                    const SizedBox(height: 16),
                  ],
                  TextFormField(
                    controller: _name,
                    decoration: InputDecoration(
                      labelText: l10n.listNameLabel,
                      border: OutlineInputBorder(),
                      helperText: l10n.listNameHelper,
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? l10n.listNameRequired
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _tracks,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: l10n.estimatedTrackCountLabel,
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) => _positiveNumber(l10n, v),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _users,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: l10n.expectedUserCountLabel,
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) => _positiveNumber(l10n, v),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _purpose,
                    minLines: 3,
                    maxLines: 6,
                    decoration: InputDecoration(
                      labelText: l10n.purposeLabel,
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? l10n.purposeRequired
                        : null,
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: Text(l10n.requestNewList),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _busy ? null : () => context.go(AppRoutes.home),
                    child: Text(l10n.cancel),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String? _positiveNumber(AppL10n l10n, String? value) {
    final n = int.tryParse((value ?? '').trim());
    if (n == null || n < 0) return l10n.nonNegativeNumberRequired;
    return null;
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(functionsRepositoryProvider)
          .submitListRequest(
            listName: _name.text,
            purpose: _purpose.text,
            estimatedTrackCount: int.parse(_tracks.text.trim()),
            expectedUserCount: int.parse(_users.text.trim()),
          );
      if (mounted) setState(() => _sent = true);
    } on FunctionsCallException catch (e) {
      // リスト名の重複チェックはサーバー側で行う（仕様書 5.1）。
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = AppL10n.of(context).errorGeneric);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

// ---------------------------------------------------------------------------
// 自分の申請一覧（仕様書 5.2.1）
// ---------------------------------------------------------------------------

/// 却下されても通知は届かないが、ここで状態を確認でき、再申請もできる。
class MyRequestsScreen extends ConsumerWidget {
  const MyRequestsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final requests = ref.watch(myListRequestsProvider);
    // **参加申請も並べる（仕様書 5.2.1）。** リスト作成申請しか出ておらず、
    // 参加申請の状態をどこからも確認できなかった（監査 S17）。
    final joinRequests = ref.watch(myJoinRequestsProvider).value ?? const [];

    return Scaffold(
      body: AsyncView(
        value: requests,
        onRetry: () => ref.invalidate(myListRequestsProvider),
        builder: (items) {
          if (items.isEmpty && joinRequests.isEmpty) {
            return EmptyState(
              icon: Icons.inbox_outlined,
              title: l10n.myRequestsEmpty,
              action: FilledButton.icon(
                onPressed: () => context.go(AppRoutes.requestList),
                icon: const Icon(Icons.add),
                label: Text(l10n.requestNewList),
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                l10n.myRequests,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              for (final request in items) _RequestCard(request: request),
              if (joinRequests.isNotEmpty) ...[
                const SizedBox(height: 24),
                Text(
                  l10n.myJoinRequests,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                for (final request in joinRequests)
                  _JoinRequestCard(request: request),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({required this.request});

  final ListRequest request;

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    request.listName,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                RequestStatusChip(status: request.status),
              ],
            ),
            const SizedBox(height: 8),
            Text(request.purpose, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
            if (request.status == RequestStatus.approved &&
                request.createdListId != null)
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.tonal(
                  onPressed: () =>
                      context.go(AppRoutes.list(request.createdListId!)),
                  child: Text(l10n.openList),
                ),
              )
            else if (request.status == RequestStatus.rejected)
              // 却下されても、同じ内容でもう一度申請できる（仕様書 5.2.1）。
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton(
                  onPressed: () => context.go(AppRoutes.requestList),
                  child: Text(l10n.requestAgain),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 申請の状態を表すチップ。
class RequestStatusChip extends StatelessWidget {
  const RequestStatusChip({super.key, required this.status});

  final RequestStatus status;

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final scheme = Theme.of(context).colorScheme;

    final (label, background, foreground) = switch (status) {
      RequestStatus.pending => (
        l10n.requestStatusPending,
        scheme.surfaceContainerHighest,
        scheme.onSurfaceVariant,
      ),
      RequestStatus.approved => (
        l10n.requestStatusApproved,
        scheme.primaryContainer,
        scheme.onPrimaryContainer,
      ),
      RequestStatus.rejected => (
        l10n.requestStatusRejected,
        scheme.errorContainer,
        scheme.onErrorContainer,
      ),
    };

    return Chip(
      visualDensity: VisualDensity.compact,
      label: Text(label),
      labelStyle: Theme.of(
        context,
      ).textTheme.labelSmall?.copyWith(color: foreground),
      backgroundColor: background,
      side: BorderSide.none,
    );
  }
}

// ---------------------------------------------------------------------------
// リスト参加申請（仕様書 5.3）
// ---------------------------------------------------------------------------

/// 共有 URL を開いた未参加者に見せる画面。
///
/// リスト名など最低限の情報と「参加申請」ボタンだけを表示し、
/// 中身（曲・コメント）は承認されるまで見せない。
class JoinRequestScreen extends ConsumerStatefulWidget {
  const JoinRequestScreen({super.key, required this.listId});

  final String listId;

  @override
  ConsumerState<JoinRequestScreen> createState() => _JoinRequestScreenState();
}

class _JoinRequestScreenState extends ConsumerState<JoinRequestScreen> {
  bool _busy = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final list = ref.watch(listProvider(widget.listId));
    final myRequest = ref.watch(myJoinRequestProvider(widget.listId)).value;

    return Scaffold(
      body: AsyncView(
        value: list,
        builder: (musicList) {
          if (musicList == null) {
            return EmptyState(icon: Icons.search_off, title: l10n.notFound);
          }

          // 申請中なら待ってもらう。却下されていれば再申請できる（仕様書 5.2.1）。
          final pending = myRequest?.status == RequestStatus.pending;

          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(
                      Icons.lock_outline,
                      size: 40,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      musicList.name,
                      style: Theme.of(context).textTheme.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l10n.joinRequestBody,
                      style: Theme.of(context).textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    if (_error != null) ...[
                      ErrorMessage(_error!),
                      const SizedBox(height: 16),
                    ],
                    if (pending)
                      Text(
                        l10n.joinRequestSent,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      )
                    else
                      FilledButton(
                        onPressed: _busy ? null : _submit,
                        child: Text(
                          myRequest?.status == RequestStatus.rejected
                              ? l10n.requestAgain
                              : l10n.joinRequestButton,
                        ),
                      ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () => context.go(AppRoutes.home),
                      child: Text(l10n.navHome),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(functionsRepositoryProvider)
          .submitJoinRequest(widget.listId);
    } on FunctionsCallException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = AppL10n.of(context).errorGeneric);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}


/// 自分が出した参加申請の 1 行（仕様書 5.2.1）。
class _JoinRequestCard extends ConsumerWidget {
  const _JoinRequestCard({required this.request});

  final JoinRequest request;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final list = ref.watch(listProvider(request.listId)).value;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        title: Text(list?.name ?? request.listId),
        subtitle: Text(_statusLabel(l10n, request.status)),
        trailing: request.status == RequestStatus.approved
            ? TextButton(
                onPressed: () => context.go(AppRoutes.list(request.listId)),
                child: Text(l10n.open),
              )
            : null,
      ),
    );
  }

  String _statusLabel(AppL10n l10n, RequestStatus status) => switch (status) {
    RequestStatus.pending => l10n.requestStatusPending,
    RequestStatus.approved => l10n.requestStatusApproved,
    RequestStatus.rejected => l10n.requestStatusRejected,
  };
}
