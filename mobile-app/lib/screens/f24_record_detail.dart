import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../app_router.dart';
import '../models/record.dart';
import '../services/api_client.dart';
import '../services/sync_service.dart';
import '../theme.dart';
import '../utils/formatters.dart';
import '../widgets/app_widgets.dart';
import '../widgets/motion.dart';
import '../widgets/scan_map.dart';
import 'f30_new_observation.dart' show ObserveArgs;
import 'f46_observation_submitted.dart' show AiResultCard;
import 'f47_submission_done.dart';

/// One record in full. Once validated it shows the confirmed pest, the
/// infestation level and the treatment options approved by the agriculture
/// office, lets the farmer log what they applied, and prompts the follow-up.
class F24RecordDetail extends StatefulWidget {
  final Record? initial;
  final int? serverId;
  const F24RecordDetail({super.key, this.initial, this.serverId});

  @override
  State<F24RecordDetail> createState() => _F24RecordDetailState();
}

class _F24RecordDetailState extends State<F24RecordDetail> {
  Record? _record;
  List<TreatmentInfo> _pendingTreatments = const [];
  String? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _record = widget.initial;
    _load();
  }

  Future<void> _load() async {
    final id = widget.serverId ?? _record?.id;
    if (id == null) return; // still on the phone; nothing on the server yet
    setState(() => _loading = true);
    try {
      final r = await SyncService.record(id);
      final pending = await SyncService.pendingTreatmentsFor(id);
      if (!mounted) return;
      setState(() {
        _record = r ?? _record;
        _pendingTreatments = pending;
        _error = null;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _sendNow() async {
    setState(() => _loading = true);
    await SyncService.syncAll();
    if (!mounted) return;
    final records = await SyncService.records();
    final uuid = _record?.clientUuid;
    final updated = records.where((r) => r.clientUuid == uuid).firstOrNull;
    if (!mounted) return;
    setState(() {
      _record = updated ?? _record;
      _loading = false;
    });
    if (updated?.uploaded == true) {
      _load();
    } else {
      _snack('Still no connection. It will be sent automatically.');
    }
  }

  Future<void> _discard(Record r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard this observation?'),
        content: const Text('It will be removed from this phone and not sent.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep it')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Discard')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await SyncService.discard(r.clientUuid);
    if (mounted) context.pop();
  }

  void _snack(String msg) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));

  /// Pick what was applied, confirm, then the result screen saves it (on the
  /// phone first, then sent) and leads back to the dashboard.
  Future<void> _logTreatment(Record r) async {
    final draft = await showModalBottomSheet<_TreatmentDraft>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _TreatmentSheet(record: r),
    );
    if (draft == null || !mounted) return;
    final ok = await confirmAction(
      context,
      title: 'Log this treatment?',
      message: 'In about a week the app will remind you to check the field, so your technician can see if it worked.',
      confirmLabel: 'Yes, log it',
      icon: Icons.task_alt_rounded,
      summary: [
        ('Treatment', draft.label),
        ('Date applied', formatShortDate(draft.appliedAt.toIso8601String())),
        ('For', r.title),
      ],
    );
    if (!ok || !mounted) return;

    Future<DoneResult> work() async {
      try {
        final sent = await SyncService.logTreatment(
          scanId: r.id!,
          libraryId: draft.libraryId,
          label: draft.label,
          customText: draft.customText,
          appliedAt: draft.appliedAt,
        );
        return sent
            ? const DoneResult.success('Treatment logged',
                'We will remind you to check the field in about a week.', icon: Icons.task_alt_rounded)
            : const DoneResult.success('Saved on your phone',
                'No signal right now. It will be sent by itself when you are back in coverage.',
                icon: Icons.cloud_done_outlined, color: AppColors.orange);
      } on ApiException catch (e) {
        return DoneResult.failure('Not saved', e.message);
      }
    }

    await context.push(
      AppRouter.done,
      extra: DoneArgs(
        workingTitle: 'Saving your treatment…',
        workingMessage: 'It is kept on your phone first, then sent.',
        work: work(),
        backLabel: 'View the record',
      ),
    );
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final r = _record;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            AppHeader(
              title: r?.title ?? 'Record',
              subtitle: r == null ? null : formatDateTime(r.createdAt),
              actions: [
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.all(8),
                    child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
              ],
            ),
            Expanded(
              child: r == null
                  ? (_error == null
                      ? const Center(child: CircularProgressIndicator())
                      : AppEmptyState(
                          icon: Icons.cloud_off_rounded,
                          title: 'Can\'t open this record',
                          message: _error!,
                          actionLabel: 'Try again',
                          onAction: _load,
                          color: AppColors.danger,
                        ))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(AppSpacing.hPad, AppSpacing.sm, AppSpacing.hPad, AppSpacing.xl),
                        children: [
                          _photo(r),
                          const SizedBox(height: AppSpacing.lg),
                          ..._statusSection(r),
                          const SizedBox(height: AppSpacing.lg),
                          _details(r),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _photo(Record r) => GestureDetector(
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => Scaffold(
            backgroundColor: Colors.black,
            appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white),
            body: InteractiveViewer(
              maxScale: 5,
              child: Center(
                child: RecordPhoto(
                  localPath: r.localPhoto,
                  serverId: r.id,
                  clientUuid: r.clientUuid,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
        )),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: AspectRatio(
            aspectRatio: 4 / 3,
            child: Stack(
              fit: StackFit.expand,
              children: [
                RecordPhoto(localPath: r.localPhoto, serverId: r.id, clientUuid: r.clientUuid),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x660F2A1F), Colors.transparent, Colors.transparent, Color(0x990F2A1F)],
                      stops: [0, 0.25, 0.6, 1],
                    ),
                  ),
                ),
                Positioned(
                  top: AppSpacing.md,
                  left: AppSpacing.md,
                  child: _Pill(
                    icon: r.isDisease ? Icons.coronavirus_outlined : Icons.bug_report_outlined,
                    label: r.isDisease ? 'Disease report' : 'Pest report',
                  ),
                ),
                const Positioned(
                  top: AppSpacing.md,
                  right: AppSpacing.md,
                  child: _Pill(icon: Icons.zoom_in_rounded, label: 'Tap to zoom'),
                ),
                Positioned(
                  left: AppSpacing.md,
                  bottom: AppSpacing.md,
                  right: AppSpacing.md,
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      if (r.cropStage.isNotEmpty) _Pill(icon: Icons.grass_rounded, label: r.cropStage),
                      if (r.barangay.isNotEmpty || r.municipality.isNotEmpty)
                        _Pill(
                          icon: Icons.location_on_rounded,
                          label: [r.barangay, r.municipality].where((x) => x.isNotEmpty).join(', '),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );

  List<Widget> _statusSection(Record r) {
    final state = r.state;
    final chip = Align(alignment: Alignment.centerLeft, child: StatusChip(state: state));
    switch (state) {
      case RecordState.waiting:
        return [
          chip,
          const SizedBox(height: AppSpacing.md),
          _Note(
            icon: Icons.signal_cellular_connected_no_internet_0_bar_rounded,
            color: r.uploadError.isNotEmpty ? AppColors.danger : AppColors.textSecondary,
            text: r.uploadError.isNotEmpty
                ? 'It could not be sent: ${r.uploadError}'
                : 'This observation is saved on your phone and will be sent when you are back in signal. '
                    '${r.isDisease ? '' : 'The pest check happens after it is sent, so there is no result yet.'}',
          ),
          const SizedBox(height: AppSpacing.md),
          AppPrimaryButton(label: 'Try sending now', icon: Icons.cloud_upload_outlined, loading: _loading, onPressed: _sendNow),
          if (r.uploadError.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            AppSecondaryButton(
              label: 'Discard this observation',
              icon: Icons.delete_outline_rounded,
              color: AppColors.danger,
              onPressed: () => _discard(r),
            ),
          ],
        ];
      case RecordState.sentForReview:
        return [
          chip,
          const SizedBox(height: AppSpacing.md),
          const _Note(
            icon: Icons.mark_email_read_rounded,
            text: 'Sent for review by an agricultural technician. You will get a notification with the diagnosis and what to do.',
          ),
        ];
      case RecordState.forValidation:
        return [chip, const SizedBox(height: AppSpacing.md), AiResultCard(ai: r.ai)];
      case RecordState.withAgriculturist:
        return [
          chip,
          const SizedBox(height: AppSpacing.md),
          const _Note(
            icon: Icons.forward_to_inbox_rounded,
            color: AppColors.purple,
            text: 'Your technician asked an agriculturist to take a closer look. You will get a notification when there is an answer.',
          ),
          if (!r.isDisease) ...[const SizedBox(height: AppSpacing.md), AiResultCard(ai: r.ai)],
        ];
      case RecordState.returned:
        return [
          chip,
          const SizedBox(height: AppSpacing.md),
          AppCard(
            borderColor: AppColors.danger.withValues(alpha: 0.4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const IconTile(icon: Icons.replay_rounded, color: AppColors.danger, size: 40),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Your technician says:', style: TextStyle(color: AppColors.textSecondary)),
                      const SizedBox(height: 4),
                      Text(r.returnReason.isEmpty ? 'Please take the photo again.' : r.returnReason,
                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, height: 1.35)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          if (r.resubmittedAs != null) ...[
            const _Note(
              icon: Icons.check_circle_outline_rounded,
              text: 'You already sent a new photo. It goes through the check again.',
            ),
            const SizedBox(height: AppSpacing.md),
            AppSecondaryButton(
              label: 'Open the new photo',
              icon: Icons.open_in_new_rounded,
              onPressed: () => context.push(AppRouter.record, extra: r.resubmittedAs),
            ),
          ] else
            AppPrimaryButton(
              label: 'Retake the photo',
              icon: Icons.photo_camera_rounded,
              onPressed: r.id == null || !r.isMine ? null : () => _retake(r),
            ),
        ];
      case RecordState.validated:
        return r.isDisease ? _validatedDisease(r, chip) : _validatedPest(r, chip);
    }
  }

  /// The technician returned it (photo unclear): take a new one. The retake
  /// reuses this observation's details and is linked to it.
  Future<void> _retake(Record r) async {
    await context.push(AppRouter.observe, extra: ObserveArgs(retakeOf: r));
    if (mounted) _load();
  }

  List<Widget> _validatedDisease(Record r, Widget chip) => [
        chip,
        const SizedBox(height: AppSpacing.md),
        _ConfirmedCard(level: r.level ?? r.confirmed?.level, title: 'Disease report'),
        if (r.diagnosis.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          _Section(
            icon: Icons.medical_information_outlined,
            title: 'Diagnosis',
            child: Text(r.diagnosis, style: const TextStyle(fontSize: 15.5, height: 1.45)),
          ),
        ],
        if (r.guidance.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          _Section(
            icon: Icons.tips_and_updates_outlined,
            title: 'What to do',
            child: Text(r.guidance, style: const TextStyle(fontSize: 15.5, height: 1.45)),
          ),
        ],
      ];

  List<Widget> _validatedPest(Record r, Widget chip) {
    final c = r.confirmed!;
    final recs = r.recommendations;
    final treatments = [...r.treatments, ..._pendingTreatments];
    return [
      chip,
      const SizedBox(height: AppSpacing.md),
      _ConfirmedCard(
        level: c.level,
        title: c.pestLabel,
        count: c.count == null ? 'Not countable' : plural(c.count!, 'insect'),
        guidance: r.guidance,
      ),
      for (final t in treatments.where((t) => t.followUpIsDue)) ...[
        const SizedBox(height: AppSpacing.md),
        _FollowUpPrompt(treatment: t),
      ],
      const SizedBox(height: AppSpacing.lg),
      _Section(
        icon: Icons.healing_rounded,
        title: 'Treatment options',
        subtitle: r.cropStage.isEmpty ? null : 'For the ${r.cropStage.toLowerCase()} stage',
        child: recs == null
            ? const Text('Open this record with signal to see the options.')
            : recs.isEmpty
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'No approved options for this case yet. Ask your agricultural technician what to do.',
                            style: TextStyle(height: 1.45),
                          ),
                          if (recs.alreadyTried.isNotEmpty) ...[
                            const SizedBox(height: AppSpacing.sm),
                            _AlreadyTried(titles: recs.alreadyTried),
                          ],
                        ],
                      )
                    : _Options(recs: recs),
      ),
      if (r.isMine) ...[
        const SizedBox(height: AppSpacing.md),
        AppPrimaryButton(
          label: 'I applied a treatment',
          icon: Icons.task_alt_rounded,
          onPressed: r.id == null ? null : () => _logTreatment(r),
        ),
      ],
      if (treatments.isNotEmpty) ...[
        const SizedBox(height: AppSpacing.lg),
        _Section(
          icon: Icons.history_rounded,
          title: r.isMine ? 'What you applied' : 'Applied treatments',
          child: Column(children: [for (final t in treatments) _TreatmentRow(treatment: t)]),
        ),
      ],
    ];
  }

  Widget _details(Record r) {
    final trap = r.monitoringMethod == 'Trap-based';
    return _Section(
      icon: Icons.info_outline_rounded,
      title: 'Details',
      child: Column(
        children: [
          _Detail('Report', r.isDisease ? 'Disease report' : 'Pest report'),
          if (r.resubmissionOf != null) _Detail('Retake', 'New photo for report #${r.resubmissionOf}'),
          _Detail('Crop stage', r.cropStage),
          _Detail('Land type', landTypeLabel(r.landType)),
          if (!r.isDisease) _Detail('Checked by', r.monitoringMethod),
          if (trap && r.trapType.isNotEmpty) _Detail('Trap or lure', r.trapType),
          if (trap && r.targetPest.isNotEmpty) _Detail('Target pest', r.targetPest),
          if (trap && r.targetSex.isNotEmpty) _Detail('Target sex', r.targetSex),
          if (r.notes.isNotEmpty) _Detail(r.isDisease ? 'Symptoms' : 'Your notes', r.notes),
          if (r.followUpOf != null) const _Detail('Follow-up', 'Checks on a treatment you applied'),
          if (r.barangay.isNotEmpty || r.municipality.isNotEmpty)
            _Detail('Area', [r.barangay, r.municipality].where((x) => x.isNotEmpty).join(', ')),
          if (r.lat != null && r.lng != null) ...[
            const SizedBox(height: AppSpacing.sm),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: ScanMap(markers: [ScanMarker(lat: r.lat!, lng: r.lng!)], height: 160, zoom: 15),
            ),
          ],
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final IconData icon;
  final String label;
  const _Pill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.38),
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: Colors.white),
            const SizedBox(width: 4),
            Flexible(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      );
}

/// What the technician confirmed: pest (or disease), level, count, guidance.
class _ConfirmedCard extends StatelessWidget {
  final String? level;
  final String title;
  final String? count;
  final String guidance;

  const _ConfirmedCard({required this.level, required this.title, this.count, this.guidance = ''});

  @override
  Widget build(BuildContext context) {
    final color = levelColor(level);
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.1)),
            child: Row(
              children: [
                IconTile(icon: Icons.verified_rounded, color: color, size: 46, filled: true),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Confirmed by your technician',
                          style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5)),
                      Text(title, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    LevelChip(level: level),
                    if (count != null) AppChip(label: count!, color: AppColors.textSecondary, icon: Icons.tag_rounded),
                  ],
                ),
                if (guidance.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text(guidance, style: const TextStyle(fontSize: 15, height: 1.45)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

const Map<String, Color> _optionColors = {
  'cultural': AppColors.primary,
  'biological': AppColors.sky,
  'ecological': AppColors.brandLeaf,
  'chemical': AppColors.orange,
};

/// Approved options grouped by type. Listed, never chosen for the farmer.
class _Options extends StatelessWidget {
  final Recommendations recs;
  const _Options({required this.recs});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Approved by your agriculture office for this pest, crop stage and level. '
          'Choose what fits your farm; your technician can help.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13.5, height: 1.4),
        ),
        if (recs.alreadyTried.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          _AlreadyTried(titles: recs.alreadyTried),
        ],
        for (final type in ['cultural', 'biological', 'ecological', 'chemical'])
          if ((recs.groups[type] ?? const []).isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                IconTile(icon: kOptionTypeIcons[type]!, color: _optionColors[type]!, size: 30),
                const SizedBox(width: AppSpacing.sm),
                Text(kOptionTypeNames[type]!, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                const SizedBox(width: 6),
                Text('${recs.groups[type]!.length}', style: const TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w700)),
              ],
            ),
            if (type == 'chemical') ...[
              const SizedBox(height: AppSpacing.sm),
              InfoBanner(icon: Icons.warning_amber_rounded, message: recs.chemicalNote),
            ],
            for (final o in recs.groups[type]!)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceMuted,
                    border: Border(left: BorderSide(color: _optionColors[type]!, width: 3)),
                    borderRadius: BorderRadius.circular(AppRadius.xs),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(o.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                      const SizedBox(height: 4),
                      Text(o.description, style: const TextStyle(fontSize: 14, height: 1.45)),
                      if (o.sourceReference.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text('Source: ${o.sourceReference}',
                            style: const TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
                      ],
                    ],
                  ),
                ),
              ),
          ],
      ],
    );
  }
}

/// Options left out because the farmer already applied them and sent feedback.
class _AlreadyTried extends StatelessWidget {
  final List<String> titles;
  const _AlreadyTried({required this.titles});

  @override
  Widget build(BuildContext context) => Text(
        'Not shown again because you already tried ${titles.length == 1 ? 'it' : 'them'} and sent feedback: '
        '${titles.join(', ')}. Your technician can recommend ${titles.length == 1 ? 'it' : 'them'} again.',
        style: const TextStyle(color: AppColors.textMuted, fontSize: 12.5, height: 1.4),
      );
}

class _FollowUpPrompt extends StatelessWidget {
  final TreatmentInfo treatment;
  const _FollowUpPrompt({required this.treatment});

  @override
  Widget build(BuildContext context) => AppCard(
        tinted: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                IconTile(icon: Icons.alarm_rounded, size: 38),
                SizedBox(width: AppSpacing.md),
                Expanded(child: Text('How is the field now?', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'It has been a while since you applied "${treatment.treatment}". Take a photo so your '
              'technician can see if it worked.',
              style: const TextStyle(height: 1.4),
            ),
            const SizedBox(height: AppSpacing.md),
            AppPrimaryButton(
              label: 'Check the field',
              icon: Icons.photo_camera_rounded,
              onPressed: () => context.push(
                AppRouter.observe,
                extra: ObserveArgs(followUpOf: treatment.id, followUpLabel: treatment.treatment),
              ),
            ),
          ],
        ),
      );
}

class _TreatmentRow extends StatelessWidget {
  final TreatmentInfo treatment;
  const _TreatmentRow({required this.treatment});

  @override
  Widget build(BuildContext context) {
    final t = treatment;
    final (String status, Color color) = t.pending
        ? ('Waiting for signal', AppColors.textMuted)
        : t.followUpScanId != null
            ? ('Follow-up sent', AppColors.primary)
            : t.followUpIsDue
                ? ('Follow-up due now', AppColors.danger)
                : ('Follow-up on ${formatShortDate(t.followUpDue)}', AppColors.orange);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          IconTile(icon: kOptionTypeIcons[t.optionType] ?? Icons.task_alt_rounded, size: 38),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t.treatment, style: const TextStyle(fontWeight: FontWeight.w800)),
                Text('Applied ${formatShortDate(t.appliedAt)}',
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
                if (t.followUpSetBy != null && t.followUpScanId == null)
                  const Text('Follow-up date set by your technician',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
              ],
            ),
          ),
          AppChip(label: status, color: color),
        ],
      ),
    );
  }
}

/// What the farmer picked in the treatment sheet (not saved yet).
class _TreatmentDraft {
  final int? libraryId;
  final String label;
  final String customText;
  final DateTime appliedAt;
  const _TreatmentDraft(this.libraryId, this.label, this.customText, this.appliedAt);
}

/// "I applied a treatment": pick an approved option (or describe your own)
/// and the date. Pops the choice; saving happens after the confirmation.
class _TreatmentSheet extends StatefulWidget {
  final Record record;
  const _TreatmentSheet({required this.record});

  @override
  State<_TreatmentSheet> createState() => _TreatmentSheetState();
}

class _TreatmentSheetState extends State<_TreatmentSheet> {
  static const int _own = -1;
  int? _choice;
  DateTime _date = DateUtils.dateOnly(DateTime.now());
  final TextEditingController _ownText = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _ownText.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final today = DateUtils.dateOnly(DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: today.subtract(const Duration(days: 60)),
      lastDate: today,
    );
    if (picked != null) setState(() => _date = picked);
  }

  void _next() {
    final options = widget.record.recommendations?.all ?? const <TreatmentOption>[];
    final picked = options.where((o) => o.id == _choice).firstOrNull;
    final own = _ownText.text.trim();
    if (_choice == null || (_choice == _own && own.isEmpty)) {
      setState(() => _error = 'Pick what you used, or describe it.');
      return;
    }
    Navigator.of(context).pop(_TreatmentDraft(picked?.id, picked?.title ?? own, picked == null ? own : '', _date));
  }

  @override
  Widget build(BuildContext context) {
    final options = widget.record.recommendations?.all ?? const <TreatmentOption>[];
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(AppSpacing.hPad, 0, AppSpacing.hPad, AppSpacing.lg),
          children: [
            const Text('What did you use?', style: TextStyle(fontFamily: AppFonts.display, fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: AppSpacing.md),
            RadioGroup<int>(
              groupValue: _choice,
              onChanged: (v) => setState(() {
                _choice = v;
                _error = null;
              }),
              child: Column(
                children: [
                  for (final o in options)
                    RadioListTile<int>(
                      value: o.id,
                      contentPadding: EdgeInsets.zero,
                      title: Text(o.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(kOptionTypeNames[o.type] ?? o.type),
                      secondary: IconTile(
                        icon: kOptionTypeIcons[o.type] ?? Icons.task_alt_rounded,
                        color: _optionColors[o.type] ?? AppColors.primary,
                        size: 36,
                      ),
                    ),
                  const RadioListTile<int>(
                    value: _own,
                    contentPadding: EdgeInsets.zero,
                    title: Text('Something else', style: TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text('Describe what you did'),
                    secondary: IconTile(icon: Icons.edit_note_rounded, color: AppColors.textSecondary, size: 36),
                  ),
                ],
              ),
            ),
            if (_choice == _own)
              TextField(
                controller: _ownText,
                maxLength: 200,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(hintText: 'e.g. Removed weeds around the field'),
              ),
            const SizedBox(height: AppSpacing.sm),
            Material(
              color: AppColors.surfaceMuted,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
                leading: const Icon(Icons.event_rounded, color: AppColors.primary),
                title: const Text('Date applied'),
                subtitle: Text(formatShortDate(_date.toIso8601String()), style: const TextStyle(fontWeight: FontWeight.w700)),
                trailing: const Text('Change', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
                onTap: _pickDate,
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(_error!, style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600)),
            ],
            const SizedBox(height: AppSpacing.lg),
            AppPrimaryButton(label: 'Continue', icon: Icons.arrow_forward_rounded, onPressed: _next),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget child;
  const _Section({required this.icon, required this.title, this.subtitle, required this.child});

  @override
  Widget build(BuildContext context) => FadeSlideIn(
        child: AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 20, color: AppColors.primary),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
                  if (subtitle != null)
                    Text(subtitle!, style: const TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              child,
            ],
          ),
        ),
      );
}

class _Note extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;
  const _Note({required this.icon, required this.text, this.color = AppColors.primary});

  @override
  Widget build(BuildContext context) => AppCard(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IconTile(icon: icon, color: color, size: 38),
            const SizedBox(width: AppSpacing.md),
            Expanded(child: Text(text, style: const TextStyle(fontSize: 14.5, height: 1.45))),
          ],
        ),
      );
}

class _Detail extends StatelessWidget {
  final String label;
  final String value;
  const _Detail(this.label, this.value);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 110, child: Text(label, style: const TextStyle(color: AppColors.textMuted))),
            Expanded(child: Text(value.isEmpty ? '—' : value, style: const TextStyle(height: 1.35, fontWeight: FontWeight.w600))),
          ],
        ),
      );
}
