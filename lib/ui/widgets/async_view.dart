/// 非同期データの表示（読み込み中・エラー・空）の共通部品
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';

/// [AsyncValue] を、読み込み中とエラーの扱いを揃えて描画する。
class AsyncView<T> extends StatelessWidget {
  const AsyncView({
    super.key,
    required this.value,
    required this.builder,
    this.onRetry,
  });

  final AsyncValue<T> value;
  final Widget Function(T data) builder;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return value.when(
      data: builder,
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _ErrorState(error: error, onRetry: onRetry),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.error, this.onRetry});

  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final theme = Theme.of(context);

    // 権限がない場合は、原因が分かる文言に変える。
    final isPermissionDenied = error.toString().contains('permission-denied');

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isPermissionDenied ? Icons.lock_outline : Icons.error_outline,
              size: 40,
              color: theme.colorScheme.error,
            ),
            const SizedBox(height: 12),
            Text(
              isPermissionDenied ? l10n.errorNoPermission : l10n.errorGeneric,
              textAlign: TextAlign.center,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              OutlinedButton(onPressed: onRetry, child: Text(l10n.reload)),
            ],
          ],
        ),
      ),
    );
  }
}

/// 何もないときの表示。
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.description,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? description;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 48, color: theme.colorScheme.outline),
              const SizedBox(height: 16),
              Text(
                title,
                style: theme.textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              if (description != null) ...[
                const SizedBox(height: 8),
                Text(
                  description!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
              if (action != null) ...[const SizedBox(height: 24), action!],
            ],
          ),
        ),
      ),
    );
  }
}

/// バイト数を読みやすく整える。
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB', 'TB'];
  var value = bytes / 1024;
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final text = value >= 100
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(1);
  return '$text ${units[unit]}';
}
