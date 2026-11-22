import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../app_router.dart';
import '../l10n/app_language.dart';
import '../platform/local_files.dart';
import '../theme.dart';
import '../services/api_client.dart';
import '../services/local_store.dart';
import '../utils/formatters.dart';
import 'motion.dart';
import 'shell_scope.dart';

/// Shared building blocks: shadowed 18px cards on the sage canvas, pill
/// buttons, circular header buttons, tinted icon tiles.

/// Header for pushed screens: circular back button, title, optional subtitle
/// and trailing actions. Falls back to Home when there is nothing to pop
/// (deep link / restored route). Inside the tab shell the back button is
/// hidden, since the bottom bar is the navigation there.
class AppHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final VoidCallback? onBack;
  final bool showBack;

  const AppHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
    this.onBack,
    this.showBack = true,
  });

  @override
  Widget build(BuildContext context) {
    final bool back = showBack && (onBack != null || ShellScope.maybeOf(context) == null);
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.hPad, AppSpacing.sm, AppSpacing.hPad, AppSpacing.sm),
      child: Row(
        children: [
          if (back) ...[
            AppCircleButton(
              icon: Icons.arrow_back_rounded,
              tooltip: context.tr('Back'),
              onTap: onBack ?? () => popOrGoHome(context),
            ),
            const SizedBox(width: AppSpacing.md),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: AppFonts.display,
                    color: AppColors.textPrimary,
                    fontSize: back ? 18 : 24,
                    fontWeight: FontWeight.w800,
                    height: 1.25,
                  ),
                ),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
                  ),
                ],
              ],
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}

/// Pops when possible, otherwise goes Home (avoids go_router's
/// "There is nothing to pop" error on single-route stacks).
void popOrGoHome(BuildContext context, [Object? result]) {
  if (context.canPop()) {
    context.pop(result);
  } else {
    context.go(AppRouter.home);
  }
}

/// 42px circular icon button (header back/actions). [dark] is for use on
/// the green hero headers.
class AppCircleButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final Color? color;
  final bool dark;

  const AppCircleButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.color,
    this.dark = false,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: PressScale(
        enabled: onTap != null,
        scale: 0.92,
        child: Material(
          color: dark ? Colors.white.withValues(alpha: 0.12) : AppColors.surface,
          shape: CircleBorder(
            side: BorderSide(color: dark ? Colors.white.withValues(alpha: 0.18) : AppColors.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: SizedBox(
              width: 42,
              height: 42,
              child: Icon(icon, size: 21, color: color ?? (dark ? AppColors.surface : AppColors.textPrimary)),
            ),
          ),
        ),
      ),
    );
  }
}

/// White rounded card with a soft shadow; optional tap and tinted variant.
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final bool tinted;
  final Color? borderColor;
  final Color? color;

  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.onTap,
    this.tinted = false,
    this.borderColor,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppRadius.md);
    final Color bg = color ?? (tinted ? const Color(0xFFE3F5EC) : AppColors.surface);
    return PressScale(
      enabled: onTap != null,
      scale: 0.985,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: tinted ? null : AppShadows.card,
        ),
        child: Material(
          color: bg,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: radius,
            side: borderColor != null
                ? BorderSide(color: borderColor!, width: 1.2)
                : tinted
                    ? BorderSide(color: AppColors.primary.withValues(alpha: 0.18))
                    : BorderSide(color: AppColors.border.withValues(alpha: 0.6)),
          ),
          child: InkWell(
            onTap: onTap,
            child: Padding(padding: padding, child: child),
          ),
        ),
      ),
    );
  }
}

/// Rounded square with a tinted background and an icon (card leading art).
class IconTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;
  final bool filled;

  const IconTile({super.key, required this.icon, this.color = AppColors.primary, this.size = 44, this.filled = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: filled ? null : color.withValues(alpha: 0.13),
        gradient: filled
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [color, Color.lerp(color, AppColors.teal, 0.45)!],
              )
            : null,
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      child: Icon(icon, size: size * 0.52, color: filled ? AppColors.surface : color),
    );
  }
}

/// Section title with an optional trailing text action ("See all").
class AppSectionHeader extends StatelessWidget {
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Widget? trailing;

  const AppSectionHeader({
    super.key,
    required this.title,
    this.actionLabel,
    this.onAction,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontFamily: AppFonts.display,
              color: AppColors.textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        ?trailing,
        if (actionLabel != null && onAction != null)
          InkWell(
            onTap: onAction,
            borderRadius: BorderRadius.circular(AppRadius.xs),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.sm, AppSpacing.xs, 0, AppSpacing.xs),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    actionLabel!,
                    style: const TextStyle(color: AppColors.primary, fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                  const Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.primary),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Primary pill button. [loading] shows a spinner and disables taps.
class AppPrimaryButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool loading;
  final bool expanded;
  final bool compact;
  final Color? color;
  final Color? foreground;

  const AppPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.loading = false,
    this.expanded = true,
    this.compact = false,
    this.color,
    this.foreground,
  });

  @override
  Widget build(BuildContext context) {
    final bool enabled = onPressed != null && !loading;
    final Color bg = color ?? AppColors.primary;
    final Color fg = foreground ?? AppColors.surface;
    // The default button uses the brand gradient; a given colour stays solid.
    final Gradient? gradient = color == null ? kPrimaryGradient : null;
    final Widget content = Row(
      mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (loading)
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: fg),
          )
        else if (icon != null)
          Icon(icon, size: compact ? 16 : 19, color: fg),
        if (loading || icon != null) const SizedBox(width: AppSpacing.sm),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: fg,
              fontSize: compact ? 13 : 15.5,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
    return AnimatedOpacity(
      opacity: enabled || loading ? 1 : 0.5,
      duration: AppMotion.fast,
      child: PressScale(
        enabled: enabled,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            gradient: gradient,
            color: gradient == null ? bg : null,
            boxShadow: enabled && !compact
                ? [BoxShadow(color: bg.withValues(alpha: 0.28), blurRadius: 14, offset: const Offset(0, 6))]
                : null,
          ),
          child: Material(
            type: MaterialType.transparency,
            shape: const StadiumBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: enabled ? onPressed : null,
              child: Padding(
                padding: compact
                    ? const EdgeInsets.symmetric(horizontal: 16, vertical: 10)
                    : const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: AnimatedSwitcher(
                  duration: AppMotion.fast,
                  child: KeyedSubtree(key: ValueKey(loading), child: content),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Outlined pill button (secondary action).
class AppSecondaryButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool expanded;
  final bool compact;
  final Color? color;

  const AppSecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.expanded = true,
    this.compact = false,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final Color fg = color ?? AppColors.primary;
    return AnimatedOpacity(
      opacity: onPressed == null ? 0.5 : 1,
      duration: AppMotion.fast,
      child: PressScale(
        enabled: onPressed != null,
        child: Material(
          color: AppColors.surface,
          shape: StadiumBorder(side: BorderSide(color: fg.withValues(alpha: 0.55), width: 1.4)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            child: Padding(
              padding: compact
                  ? const EdgeInsets.symmetric(horizontal: 16, vertical: 10)
                  : const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
              child: Row(
                mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: compact ? 16 : 18, color: fg),
                    const SizedBox(width: AppSpacing.sm),
                  ],
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: fg,
                        fontSize: compact ? 13 : 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Centered empty/error state with icon, title, message and optional action.
class AppEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Color color;

  const AppEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.color = AppColors.primary,
  });

  @override
  Widget build(BuildContext context) {
    return FadeSlideIn(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.surface,
                shape: BoxShape.circle,
                boxShadow: AppShadows.card,
              ),
              child: Icon(icon, size: 32, color: color),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: AppFonts.display,
                color: AppColors.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13.5, height: 1.45),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: AppSpacing.lg),
              AppPrimaryButton(label: actionLabel!, onPressed: onAction, expanded: false, compact: true),
            ],
          ],
        ),
      ),
    );
  }
}

/// Tinted banner with an icon, a message and an optional action button
/// (offline notices, sync status, warnings).
class InfoBanner extends StatelessWidget {
  final IconData icon;
  final String message;
  final Color color;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool busy;

  const InfoBanner({
    super.key,
    required this.icon,
    required this.message,
    this.color = AppColors.orange,
    this.actionLabel,
    this.onAction,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, 10, AppSpacing.sm, 10),
      decoration: BoxDecoration(
        color: Color.alphaBlend(color.withValues(alpha: 0.12), AppColors.surface),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(message, style: const TextStyle(fontSize: 13.5, height: 1.35, color: AppColors.textPrimary)),
          ),
          if (actionLabel != null && onAction != null)
            busy
                ? Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: color)),
                  )
                : TextButton(
                    onPressed: onAction,
                    style: TextButton.styleFrom(foregroundColor: color, visualDensity: VisualDensity.compact),
                    child: Text(actionLabel!, style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
        ],
      ),
    );
  }
}

/// Asks before an action that sends something. Returns true to go ahead.
Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  IconData icon = Icons.send_rounded,
  Color color = AppColors.primary,
  List<(String, String)> summary = const [],
}) async {
  HapticFeedback.selectionClick();
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.hPad, 0, AppSpacing.hPad, AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(child: IconTile(icon: icon, color: color, size: 56)),
            const SizedBox(height: AppSpacing.md),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontFamily: AppFonts.display, fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 14, height: 1.45),
            ),
            if (summary.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.lg),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                decoration: BoxDecoration(
                  color: AppColors.surfaceMuted,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Column(
                  children: [
                    for (final (k, v) in summary)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 104,
                              child: Text(k, style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
                            ),
                            Expanded(
                              child: Text(v, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.xl),
            AppPrimaryButton(label: confirmLabel, icon: icon, color: color, onPressed: () => Navigator.pop(ctx, true)),
            const SizedBox(height: AppSpacing.sm),
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(ctx.tr('Not yet, go back'), style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    ),
  );
  return ok == true;
}

/// Tinted pill label.
class AppChip extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;

  const AppChip({
    super.key,
    required this.label,
    required this.color,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: AppMotion.medium,
      curve: AppMotion.curve,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}

/// Low / Medium / High chip in the level colour (the reviewer's confirmed level).
class LevelChip extends StatelessWidget {
  final String? level;
  const LevelChip({super.key, required this.level});

  @override
  Widget build(BuildContext context) => AppChip(
        label: context.tr('{level} infestation', {'level': levelLabel(level)}),
        color: levelColor(level),
      );
}

/// Where a record stands: Waiting for signal / For technician validation /
/// Sent for review / With an agriculturist / Please send a new photo / Validated.
class StatusChip extends StatelessWidget {
  final RecordState state;
  const StatusChip({super.key, required this.state});

  @override
  Widget build(BuildContext context) => AppChip(
        label: recordStateLabel(state),
        color: recordStateColor(state),
        icon: recordStateIcon(state),
      );
}

/// Large tappable tile with an icon, used for the few big choices farmers make
/// (report type, crop stage). Selected tiles are filled.
class ChoiceTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;
  final Color color;

  const ChoiceTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.selected = false,
    required this.onTap,
    this.color = AppColors.primary,
  });

  @override
  Widget build(BuildContext context) {
    final Color fg = selected ? AppColors.surface : AppColors.textPrimary;
    final radius = BorderRadius.circular(AppRadius.md);
    return Semantics(
      button: true,
      selected: selected,
      child: PressScale(
        child: AnimatedContainer(
          duration: AppMotion.fast,
          decoration: BoxDecoration(
            borderRadius: radius,
            boxShadow: selected
                ? [BoxShadow(color: color.withValues(alpha: 0.3), blurRadius: 16, offset: const Offset(0, 6))]
                : AppShadows.card,
          ),
          child: Material(
            color: selected ? color : AppColors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: radius,
              side: BorderSide(color: selected ? color : AppColors.border.withValues(alpha: 0.6), width: 1.5),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () {
                HapticFeedback.selectionClick();
                onTap();
              },
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 84),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
                  child: Row(
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: selected ? AppColors.surface.withValues(alpha: 0.18) : color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(icon, size: 28, color: selected ? AppColors.surface : color),
                      ),
                      const SizedBox(width: AppSpacing.lg),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(title, style: TextStyle(color: fg, fontSize: 17.5, fontWeight: FontWeight.bold)),
                            if (subtitle != null) ...[
                              const SizedBox(height: 2),
                              Text(
                                subtitle!,
                                style: TextStyle(
                                  color: selected ? AppColors.surface.withValues(alpha: 0.85) : AppColors.textSecondary,
                                  fontSize: 13.5,
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      AnimatedSwitcher(
                        duration: AppMotion.fast,
                        child: selected
                            ? const Icon(Icons.check_circle_rounded, key: ValueKey(1), color: AppColors.surface, size: 26)
                            : const Icon(Icons.chevron_right_rounded, key: ValueKey(0), color: AppColors.textMuted),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Photo of an observation: the copy on this phone if there is one, otherwise
/// the server's (which needs the sign-in token).
class RecordPhoto extends StatefulWidget {
  final String? localPath;
  final int? serverId;
  final String? clientUuid;
  final BoxFit fit;
  final int? cacheWidth;

  const RecordPhoto({super.key, this.localPath, this.serverId, this.clientUuid, this.fit = BoxFit.cover, this.cacheWidth});

  @override
  State<RecordPhoto> createState() => _RecordPhotoState();
}

class _RecordPhotoState extends State<RecordPhoto> {
  late Future<String?> _photo;

  @override
  void initState() {
    super.initState();
    _photo = _resolvePhoto();
  }

  @override
  void didUpdateWidget(covariant RecordPhoto oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.localPath != oldWidget.localPath ||
        widget.serverId != oldWidget.serverId ||
        widget.clientUuid != oldWidget.clientUuid) {
      _photo = _resolvePhoto();
    }
  }

  Future<String?> _resolvePhoto() async {
    if (widget.localPath != null) return widget.localPath!;
    final id = widget.serverId;
    if (id == null) return null;
    final uuid = widget.clientUuid ?? 'server_$id';
    final cached = await LocalStore.instance.localPhoto(uuid);
    if (cached != null) return cached;
    final bytes = await ApiClient.downloadImage('/sync/scans/$id/image');
    return LocalStore.instance.cacheServerPhoto(uuid, id, bytes);
  }

  static Widget _placeholder() => const ColoredBox(
        color: AppColors.accentLight,
        child: Center(child: Icon(Icons.image_outlined, color: AppColors.primary, size: 28)),
      );

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _photo,
      builder: (context, snap) {
        final photo = snap.data;
        if (photo == null) return _placeholder();
        return localImage(photo, fit: widget.fit, cacheWidth: widget.cacheWidth, errorBuilder: (_, _, _) => _placeholder());
      },
    );
  }
}
