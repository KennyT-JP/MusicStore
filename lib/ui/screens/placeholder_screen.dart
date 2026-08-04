/// 未実装画面の土台
///
/// 14.2 で洗い出した画面を、ルーティングが通る状態で先に置いておくための
/// ウィジェット。各画面を実装するときに中身を差し替える。
///
/// 何が未実装かを画面上に明示し、「実装済みに見えるが動かない」状態を
/// 作らないようにする。
library;

import 'package:flutter/material.dart';

/// 未実装であることを明示する画面。
class PlaceholderScreen extends StatelessWidget {
  const PlaceholderScreen({
    super.key,
    required this.title,
    required this.specReference,
    this.description,
  });

  /// 画面名（14.2 の一覧に合わせる）。
  final String title;

  /// 対応する仕様書の章番号。実装時に参照する場所。
  final String specReference;

  /// この画面で何をするか。
  final String? description;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(
                '仕様書 $specReference',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
              if (description != null) ...[
                const SizedBox(height: 16),
                Text(description!, style: theme.textTheme.bodyMedium),
              ],
              const SizedBox(height: 24),
              Card(
                color: theme.colorScheme.surfaceContainerHighest,
                child: const Padding(
                  padding: EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(Icons.construction_outlined),
                      SizedBox(width: 12),
                      Expanded(child: Text('この画面はまだ実装されていません。')),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
