import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_language.dart';
import '../theme.dart';
import '../widgets/app_widgets.dart';
import '../widgets/motion.dart';
import '../widgets/shell_scope.dart';

/// How a confirmed submission ended.
class DoneResult {
  final bool ok;
  final String title;
  final String message;
  final IconData icon;
  final Color color;

  const DoneResult.success(this.title, this.message, {this.icon = Icons.check_rounded, this.color = AppColors.primary})
      : ok = true;
  const DoneResult.failure(this.title, this.message)
      : ok = false,
        icon = Icons.error_outline_rounded,
        color = AppColors.danger;
}

class DoneArgs {
  /// Shown while [work] runs.
  final String workingTitle;
  final String workingMessage;
  final Future<DoneResult> work;

  /// Main action after success: opens this tab (e.g. "Next in queue").
  /// Without it, "Back to dashboard" is the main action.
  final String? nextLabel;
  final IconData? nextIcon;
  final String? nextTab;

  /// Secondary action after success that returns to the previous screen
  /// (e.g. "View the record"). On failure that screen is where to try again.
  final String? backLabel;

  const DoneArgs({
    required this.workingTitle,
    required this.workingMessage,
    required this.work,
    this.nextLabel,
    this.nextIcon,
    this.nextTab,
    this.backLabel,
  });
}

/// Shown right after the user confirms a submission (a treatment log, a
/// validation decision): they are not left waiting on the form. It shows the
/// work finishing, then the outcome, and leads back to the dashboard.
class F47SubmissionDone extends StatefulWidget {
  final DoneArgs args;
  const F47SubmissionDone({super.key, required this.args});

  @override
  State<F47SubmissionDone> createState() => _F47SubmissionDoneState();
}

class _F47SubmissionDoneState extends State<F47SubmissionDone> {
  DoneResult? _result;

  @override
  void initState() {
    super.initState();
    widget.args.work
        .catchError((Object e) => DoneResult.failure('Something went wrong', '$e'))
        .then((r) {
      if (!mounted) return;
      r.ok ? HapticFeedback.mediumImpact() : HapticFeedback.heavyImpact();
      setState(() => _result = r);
    });
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.args;
    final r = _result;
    final working = r == null;
    return PopScope(
      canPop: !working,
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.hPad),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Spacer(),
                AppSwitcher(
                  alignment: Alignment.center,
                  child: working
                      ? _Status(
                          key: const ValueKey('working'),
                          badge: const SizedBox(
                            width: 44,
                            height: 44,
                            child: CircularProgressIndicator(strokeWidth: 4, color: AppColors.primary),
                          ),
                          color: AppColors.primary,
                          title: a.workingTitle,
                          message: a.workingMessage,
                        )
                      : _Status(
                          key: ValueKey('done:${r.ok}'),
                          badge: PopIn(child: Icon(r.icon, size: 48, color: AppColors.surface)),
                          color: r.color,
                          filled: true,
                          title: r.title,
                          message: r.message,
                        ),
                ),
                const Spacer(flex: 2),
                if (!working) ...[
                  FadeSlideIn(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: _actions(r))),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _actions(DoneResult r) {
    final a = widget.args;
    if (!r.ok) {
      return [
        AppPrimaryButton(
          label: context.tr('Go back and try again'),
          icon: Icons.arrow_back_rounded,
          onPressed: () => Navigator.of(context).pop(),
        ),
        const SizedBox(height: AppSpacing.md),
        AppSecondaryButton(
          label: context.tr('Back to dashboard'),
          icon: Icons.home_rounded,
          onPressed: () => ShellNav.open(context),
        ),
      ];
    }
    return [
      if (a.nextLabel != null && a.nextTab != null) ...[
        AppPrimaryButton(
          label: context.tr(a.nextLabel!),
          icon: a.nextIcon ?? Icons.arrow_forward_rounded,
          onPressed: () => ShellNav.open(context, a.nextTab!),
        ),
        const SizedBox(height: AppSpacing.md),
        AppSecondaryButton(
          label: context.tr('Back to dashboard'),
          icon: Icons.home_rounded,
          onPressed: () => ShellNav.open(context),
        ),
      ] else
        AppPrimaryButton(
          label: context.tr('Back to dashboard'),
          icon: Icons.home_rounded,
          onPressed: () => ShellNav.open(context),
        ),
      if (a.backLabel != null) ...[
        const SizedBox(height: AppSpacing.sm),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.tr(a.backLabel!), style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
      ],
    ];
  }
}

class _Status extends StatelessWidget {
  final Widget badge;
  final Color color;
  final bool filled;
  final String title;
  final String message;

  const _Status({
    super.key,
    required this.badge,
    required this.color,
    this.filled = false,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 108,
          height: 108,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: filled ? color : color.withValues(alpha: 0.1),
            boxShadow: filled
                ? [BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 28, offset: const Offset(0, 10))]
                : null,
          ),
          alignment: Alignment.center,
          child: badge,
        ),
        const SizedBox(height: AppSpacing.xl),
        Text(
          context.tr(title),
          textAlign: TextAlign.center,
          style: const TextStyle(fontFamily: AppFonts.display, fontSize: 24, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          context.tr(message),
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 15, height: 1.5),
        ),
      ],
    );
  }
}
