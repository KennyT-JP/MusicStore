/// 役割の表示（仕様書 4.1 / 14.2）
library;

import 'package:flutter/material.dart';

import '../../domain/role.dart';
import '../../l10n/app_localizations.dart';

/// 役割を色つきのチップで表示する。
class RoleChip extends StatelessWidget {
  const RoleChip({super.key, required this.role, this.isSiteAdmin = false});

  final ListRole role;

  /// サイト管理者として表示するか。
  final bool isSiteAdmin;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (label, background, foreground) = _appearance(context, scheme);

    return Chip(
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      label: Text(label),
      labelStyle: Theme.of(
        context,
      ).textTheme.labelSmall?.copyWith(color: foreground),
      backgroundColor: background,
      side: BorderSide.none,
    );
  }

  (String, Color, Color) _appearance(BuildContext context, ColorScheme scheme) {
    final l10n = AppL10n.of(context);
    if (isSiteAdmin) {
      return (l10n.roleSiteAdmin, scheme.primaryContainer, scheme.onPrimaryContainer);
    }
    return switch (role) {
      ListRole.listAdmin => (
        l10n.roleListAdmin,
        scheme.secondaryContainer,
        scheme.onSecondaryContainer,
      ),
      ListRole.superUser => (
        l10n.roleSuperUser,
        scheme.tertiaryContainer,
        scheme.onTertiaryContainer,
      ),
      ListRole.readOnly => (
        l10n.roleReadOnly,
        scheme.surfaceContainerHighest,
        scheme.onSurfaceVariant,
      ),
    };
  }
}
