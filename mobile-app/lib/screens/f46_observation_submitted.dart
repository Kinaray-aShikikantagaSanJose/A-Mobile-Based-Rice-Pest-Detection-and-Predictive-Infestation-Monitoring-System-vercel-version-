import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../app_router.dart';
import '../controllers/auth_controller.dart';
import '../models/record.dart';
import '../services/local_store.dart';
import '../services/sync_service.dart';
import '../theme.dart';
import '../utils/formatters.dart';
import '../widgets/app_widgets.dart';
import '../widgets/motion.dart';
import '../widgets/shell_scope.dart';

/// An observation the user just confirmed, still being sent.
class PendingSubmission {
  final OutboxObservation draft;
  final Future<SubmitOutcome> result;
  const PendingSubmission(this.draft, this.result);
}

/// Opens as soon as the user confirms Submit (the upload runs meanwhile, so
/// nobody waits on the form). Then it shows what happened:
/// - Online pest report: the server's model result, clearly marked as not final.
/// - Offline: saved on the phone; nothing comes back until there is signal.
/// - Disease report: no model result at all; sent to a technician.
class F46ObservationSubmitted extends StatefulWidget {
  final SubmitOutcome? outcome;
  final PendingSubmission? pending;

  const F46ObservationSubmitted({super.key, this.outcome, this.pending})
      : assert(outcome != null || pending != null);

  @override
  State<F46ObservationSubmitted> createState() => _F46ObservationSubmittedState();
}

class _F46ObservationSubmittedState extends State<F46ObservationSubmitted> {
  SubmitOutcome? _outcome;

  @override
  void initState() {
    super.initState();
    _outcome = widget.outcome;
    widget.pending?.result.then((o) {
      if (mounted) setState(() => _outcome = o);
    });
  }

  Record get _record {
    final o = _outcome;
    if (o != null) return o.record;
    final d = widget.pending!.draft;
    return Record(pending: d, localPhoto: d.imagePath);
  }

  void _home() => ShellNav.open(context);

  @override
  Widget build(BuildContext context) {
    final o = _outcome;
    final rec = _record;
    final isTech = AuthControllerImpl.instance.role == AppRole.technician;
    final (String title, String subtitle) = switch (o) {
      null => ('Observation submitted', 'Thank you! We are sending it now. You can leave this screen at any time.'),
      SubmitOutcome(uploaded: false, error: null) => ('Saved on your phone', 'No signal right now. It goes out by itself when you are back in coverage.'),
      SubmitOutcome(uploaded: false) => ('Saved, but not sent', 'The server did not accept it. It is kept on this phone.'),
      _ when rec.isDisease => ('Picture sent and counted!', 'Your photo and description reached the agriculture office.'),
      _ => ('Picture sent and counted!', 'Your photo was checked for pests. A technician confirms the result.'),
    };
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _home();
      },
      child: Scaffold(
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(AppSpacing.hPad, AppSpacing.lg, AppSpacing.hPad, AppSpacing.xl),
            children: [
              FadeSlideIn(child: _Header(title: title, subtitle: subtitle, sending: o == null, ok: o?.uploaded ?? true)),
              const SizedBox(height: AppSpacing.xl),
              FadeSlideIn(index: 1, child: _PhotoCard(record: rec)),
              const SizedBox(height: AppSpacing.lg),
              AppSwitcher(
                child: KeyedSubtree(
                  key: ValueKey(o == null ? 'sending' : 'done:${o.uploaded}'),
                  child: o == null ? _Sending(isDisease: rec.isDisease) : _Result(outcome: o),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              _NextSteps(isDisease: rec.isDisease),
              const SizedBox(height: AppSpacing.xl),
              if (o != null && o.uploaded && isTech && rec.id != null) ...[
                // A technician's own observation is validated by the technician.
                AppPrimaryButton(
                  label: 'Validate it now',
                  icon: Icons.fact_check_rounded,
                  color: AppColors.orange,
                  onPressed: () => context.pushReplacement('${AppRouter.review}/${rec.id}'),
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              AppPrimaryButton(label: 'Back to dashboard', icon: Icons.home_rounded, onPressed: _home),
              const SizedBox(height: AppSpacing.md),
              AppSecondaryButton(
                label: 'Open the record',
                icon: Icons.open_in_new_rounded,
                onPressed: o == null ? null : () => context.pushReplacement(AppRouter.record, extra: rec),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool sending;
  final bool ok;
  const _Header({required this.title, required this.subtitle, required this.sending, required this.ok});

  @override
  Widget build(BuildContext context) {
    final Color color = ok ? AppColors.primary : AppColors.orange;
    return Column(
      children: [
        Container(
          width: 84,
          height: 84,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            boxShadow: [BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 24, offset: const Offset(0, 8))],
          ),
          child: PopIn(
            child: Icon(
              ok ? Icons.check_rounded : Icons.cloud_off_rounded,
              size: 44,
              color: AppColors.surface,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        AppSwitcher(
          alignment: Alignment.center,
          child: Text(
            title,
            key: ValueKey(title),
            textAlign: TextAlign.center,
            style: const TextStyle(fontFamily: AppFonts.display, fontSize: 25, fontWeight: FontWeight.w800),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 14.5, height: 1.45),
        ),
      ],
    );
  }
}

class _PhotoCard extends StatelessWidget {
  final Record record;
  const _PhotoCard({required this.record});

  @override
  Widget build(BuildContext context) {
    final r = record;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: AspectRatio(
        aspectRatio: 16 / 10,
        child: Stack(
          fit: StackFit.expand,
          children: [
            RecordPhoto(localPath: r.localPhoto, serverId: r.id, clientUuid: r.clientUuid),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Color(0xB30F2A1F)],
                  stops: [0.5, 1],
                ),
              ),
            ),
            Positioned(
              left: AppSpacing.md,
              right: AppSpacing.md,
              bottom: AppSpacing.md,
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _PhotoTag(icon: r.isDisease ? Icons.coronavirus_outlined : Icons.bug_report_outlined,
                      label: r.isDisease ? 'Disease' : 'Pest'),
                  if (r.cropStage.isNotEmpty) _PhotoTag(icon: Icons.grass_rounded, label: r.cropStage),
                  if (r.lat != null) const _PhotoTag(icon: Icons.location_on_rounded, label: 'Located'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PhotoTag extends StatelessWidget {
  final IconData icon;
  final String label;
  const _PhotoTag({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: Colors.white),
            const SizedBox(width: 4),
            Text(label, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        ),
      );
}

/// While the upload runs: a plain note, no spinner or progress bar.
class _Sending extends StatelessWidget {
  final bool isDisease;
  const _Sending({required this.isDisease});

  @override
  Widget build(BuildContext context) => AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.cloud_upload_outlined, color: AppColors.primary, size: 22),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    isDisease ? 'Sending your picture' : 'Sending your picture for the pest check',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              isDisease
                  ? 'It is already saved on your phone.'
                  : 'The app looks for the four rice pests and counts them when they can be told apart. '
                      'It is already saved on your phone.',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.4),
            ),
          ],
        ),
      );
}

/// What came back.
class _Result extends StatelessWidget {
  final SubmitOutcome outcome;
  const _Result({required this.outcome});

  @override
  Widget build(BuildContext context) {
    final rec = outcome.record;
    if (!outcome.uploaded) {
      return AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const StatusChip(state: RecordState.waiting),
            const SizedBox(height: AppSpacing.md),
            Text(
              outcome.error ??
                  'Your photo and details are safe on this phone and will be sent by themselves when you are back in coverage. '
                      '${rec.isDisease ? 'A technician will review it after it is sent.' : 'The pest check happens after it is sent, so there is no result yet. You will see it in My Records.'}',
              style: const TextStyle(fontSize: 14.5, height: 1.5),
            ),
          ],
        ),
      );
    }
    if (rec.isDisease) {
      return const AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            StatusChip(state: RecordState.sentForReview),
            SizedBox(height: AppSpacing.md),
            Text('Sent for review by an agricultural technician',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            SizedBox(height: 4),
            Text(
              'A technician will look at your photo and notes and send you a diagnosis and what to do. You will get a notification.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 14.5, height: 1.45),
            ),
          ],
        ),
      );
    }
    return AiResultCard(ai: rec.ai);
  }
}

/// The automatic pest check, marked as a suggestion until a technician confirms it.
class AiResultCard extends StatelessWidget {
  final AiResult? ai;
  const AiResultCard({super.key, required this.ai});

  @override
  Widget build(BuildContext context) {
    final a = ai;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _ValidationBadge(),
          const SizedBox(height: AppSpacing.md),
          if (a == null || !a.recognized) ...[
            const Text('No pest recognized automatically', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
            const SizedBox(height: AppSpacing.sm),
            Text(
              (a?.message.isNotEmpty ?? false) ? a!.message : 'A technician will look at your photo and identify the pest.',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 14.5, height: 1.4),
            ),
          ] else ...[
            Row(
              children: [
                const IconTile(icon: Icons.bug_report_rounded, color: AppColors.primary, size: 46),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(a.pestLabel, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                      Text('Model result', style: const TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
                    ],
                  ),
                ),
              ],
            ),
            if (a.confidence != null) ...[
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  const Text('Confidence', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                  const Spacer(),
                  Text(a.confidenceLabel, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                ],
              ),
              const SizedBox(height: 6),
              AnimatedProgressBar(value: a.confidence!, color: _confidenceColor(a.confidence!), height: 8),
            ],
            const SizedBox(height: AppSpacing.md),
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.surfaceMuted,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Row(
                children: [
                  Icon(a.count != null ? Icons.tag_rounded : Icons.blur_on_rounded, color: AppColors.primary, size: 22),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      a.count != null
                          ? '${plural(a.count!, 'insect')} counted'
                          : 'Not counted: the insects are too close together or unclear to count reliably.',
                      style: const TextStyle(fontSize: 14.5, height: 1.4, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          const Text(
            'This is not final. Your technician will confirm the pest and the infestation level.',
            style: TextStyle(color: AppColors.textMuted, fontSize: 12.5, height: 1.4),
          ),
        ],
      ),
    );
  }

  static Color _confidenceColor(double c) => c >= 0.7 ? AppColors.primary : (c >= 0.45 ? AppColors.orange : AppColors.danger);
}

/// "For technician validation": the model result is a suggestion, not final.
class _ValidationBadge extends StatelessWidget {
  const _ValidationBadge();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: AppColors.orangeLight,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: AppColors.orange.withValues(alpha: 0.4)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.hourglass_top_rounded, size: 16, color: AppColors.orange),
            SizedBox(width: 6),
            Text('For technician validation',
                style: TextStyle(color: AppColors.orange, fontWeight: FontWeight.bold, fontSize: 13.5)),
          ],
        ),
      );
}

/// What happens after sending, as three steps.
class _NextSteps extends StatelessWidget {
  final bool isDisease;
  const _NextSteps({required this.isDisease});

  @override
  Widget build(BuildContext context) {
    final steps = [
      (Icons.cloud_done_outlined, 'Sent', 'Your photo, location and notes reach the agriculture office.'),
      (Icons.fact_check_outlined, 'Checked by a technician',
          isDisease ? 'They diagnose it and set how serious it is.' : 'They confirm the pest, the count and the infestation level.'),
      (Icons.healing_outlined, 'Treatment options',
          'You get options for your crop stage, then a reminder to check the field again.'),
    ];
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('What happens next', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: AppSpacing.md),
          for (final (i, (icon, title, body)) in steps.indexed)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  children: [
                    IconTile(icon: icon, size: 36, color: i == 0 ? AppColors.primary : AppColors.textMuted),
                    if (i < steps.length - 1) Container(width: 2, height: 22, color: AppColors.border),
                  ],
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 2, bottom: AppSpacing.sm),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                        Text(body, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5, height: 1.35)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
