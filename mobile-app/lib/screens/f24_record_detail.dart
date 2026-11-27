import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../app_router.dart';
import '../controllers/auth_controller.dart';
import '../l10n/app_language.dart';
import '../models/record.dart';
import '../services/api_client.dart';
import '../services/sync_service.dart';
import '../theme.dart';
import '../utils/formatters.dart';
import '../widgets/app_widgets.dart';
import '../widgets/land_type_sheet.dart';
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

  /// The record shown is the copy saved on the phone (the refresh failed or
  /// is still running); [_savedAt] is when it was saved, if known.
  bool _fromCache = false;
  DateTime? _savedAt;

  bool get _isTech => AuthControllerImpl.instance.role == AppRole.technician;

  @override
  void initState() {
    super.initState();
    _record = widget.initial;
    _load();
  }

  /// Cache first: the copy on the phone shows at once, then the server's
  /// copy replaces it. Without signal the saved copy stays, with a note.
  Future<void> _load() async {
    final id = widget.serverId ?? _record?.id;
    if (id == null) return; // still on the phone; nothing on the server yet
    setState(() => _loading = true);
    if (_record == null) {
      try {
        final cached = await SyncService.cachedRecord(id);
        final pending = await SyncService.pendingTreatmentsFor(id);
        if (cached != null && mounted && _record == null) {
          setState(() {
            _record = cached.data;
            _pendingTreatments = pending;
            _fromCache = true;
            _savedAt = cached.savedAt;
          });
        }
      } catch (e) {
        debugPrint('[Record] no saved copy: $e');
      }
    }
    try {
      final r = await SyncService.record(id);
      final pending = await SyncService.pendingTreatmentsFor(id);
      if (!mounted) return;
      setState(() {
        _record = r ?? _record;
        _pendingTreatments = pending;
        _error = null;
        _fromCache = false;
        _savedAt = null;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.statusCode == 410) {
        // Deleted on the server (e.g. by a technician): it is gone from the phone too.
        _snack(context.tr('This observation was deleted.'));
        popOrGoHome(context);
        return;
      }
      setState(() {
        _error = e.isOffline ? 'No signal, and this record is not saved on this phone yet.' : e.message;
        if (_record != null) _fromCache = true;
      });
    } catch (e) {
      // e.g. no local database: keep what is shown, offer a retry otherwise.
      debugPrint('[Record] could not load: $e');
      if (mounted) setState(() => _error = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Owner (before review) or technician: correct the land type.
  Future<void> _changeLandType(Record r) async {
    final updated = await showLandTypeChange(context, r, askReason: !r.isMine);
    if (updated == null || !mounted) return;
    setState(() {
      _record = updated;
      _fromCache = false;
    });
    _snack(context.tr('Land type saved.'));
  }

  Future<void> _retryTreatment(TreatmentInfo t) async {
    final result = await SyncService.retryTreatment(t.clientUuid);
    if (!mounted) return;
    if (result == null) {
      _snack(context.tr('Still no connection. It will be sent automatically.'));
    } else if (result.isNotEmpty) {
      _snack(context.tr('It could not be sent: {error}', {'error': context.tr(result)}));
    }
    _load();
  }

  Future<void> _discardTreatment(TreatmentInfo t) async {
    final ok = await confirmAction(
      context,
      title: context.tr('Remove this treatment?'),
      message: context.tr('It will be removed from this phone and not sent.'),
      confirmLabel: context.tr('Remove'),
      icon: Icons.delete_outline_rounded,
      color: AppColors.danger,
      summary: [(context.tr('Treatment'), t.treatment)],
    );
    if (!ok || !mounted) return;
    await SyncService.discardTreatment(t.clientUuid);
    if (mounted) _load();
  }

  /// Technicians: delete this observation for everyone, then leave.
  Future<void> _delete() async {
    final id = _record?.id;
    if (id == null) return;
    if (await confirmDeleteRecord(context, id) && mounted) popOrGoHome(context);
  }

  /// "Try sending now": sends this observation once more, even one the
  /// server refused before (the automatic sync skips those).
  Future<void> _sendNow() async {
    final pending = _record?.pending;
    if (pending == null) return;
    setState(() => _loading = true);
    final outcome = await SyncService.retryObservation(pending);
    if (!mounted) return;
    final records = await SyncService.records();
    final uuid = _record?.clientUuid;
    final updated = records.where((r) => r.clientUuid == uuid).firstOrNull;
    if (!mounted) return;
    setState(() {
      _record = outcome.uploaded ? outcome.record : (updated ?? _record);
      _loading = false;
    });
    if (outcome.uploaded) {
      _load();
    } else if (outcome.error != null) {
      _snack(context.tr('It could not be sent: {error}', {'error': context.tr(outcome.error!)}));
    } else {
      _snack(context.tr('Still no connection. It will be sent automatically.'));
    }
  }

  Future<void> _discard(Record r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('Discard this observation?')),
        content: Text(ctx.tr('It will be removed from this phone and not sent.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.tr('Keep it'))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ctx.tr('Discard'))),
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
      title: context.tr('Log this treatment?'),
      message: context.tr(
          'In about a week the app will remind you to check the field, so your technician can see if it worked.'),
      confirmLabel: context.tr('Yes, log it'),
      icon: Icons.task_alt_rounded,
      summary: [
        (context.tr('Treatment'), draft.label),
        (context.tr('Date applied'), formatShortDate(draft.appliedAt.toIso8601String())),
        (context.tr('For'), r.title),
      ],
    );
    if (!ok || !mounted) return;

    // The result screen translates these titles and messages.
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
              title: r?.title ?? context.tr('Record'),
              subtitle: r == null ? null : formatDateTime(r.createdAt),
              actions: [
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.all(8),
                    child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
                if (_isTech && r?.id != null)
                  AppCircleButton(
                    icon: Icons.delete_outline_rounded,
                    tooltip: context.tr('Delete record'),
                    color: AppColors.danger,
                    onTap: _delete,
                  ),
              ],
            ),
            Expanded(
              child: r == null
                  ? (_error == null
                      ? const Center(child: CircularProgressIndicator())
                      : ListView(children: [LoadErrorState(message: _error!, onRetry: _load)]))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(AppSpacing.hPad, AppSpacing.sm, AppSpacing.hPad, AppSpacing.xl),
                        children: [
                          MaxContentWidth(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (_fromCache && r.uploaded)
                                  _savedAt == null
                                      ? Padding(
                                          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                                          child: Text(
                                            context.tr(_loading
                                                ? 'Showing the copy saved on this phone while it refreshes.'
                                                : 'Showing the copy saved on this phone.'),
                                            style: const TextStyle(color: AppColors.textMuted, fontSize: 12.5),
                                          ),
                                        )
                                      : SavedDataNote(savedAt: _savedAt!, refreshing: _loading),
                                _photo(r),
                                const SizedBox(height: AppSpacing.lg),
                                ..._statusSection(r),
                                const SizedBox(height: AppSpacing.lg),
                                _details(r),
                              ],
                            ),
                          ),
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
                    label: context.tr(r.isDisease ? 'Disease report' : 'Pest report'),
                  ),
                ),
                Positioned(
                  top: AppSpacing.md,
                  right: AppSpacing.md,
                  child: _Pill(icon: Icons.zoom_in_rounded, label: context.tr('Tap to zoom')),
                ),
                Positioned(
                  left: AppSpacing.md,
                  bottom: AppSpacing.md,
                  right: AppSpacing.md,
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      if (r.cropStage.isNotEmpty) _Pill(icon: Icons.grass_rounded, label: context.tr(r.cropStage)),
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
    final chip = Align(alignment: Alignment.centerLeft, child: StatusChip(state: state, staff: _isTech && !r.isMine));
    switch (state) {
      case RecordState.waiting:
        return [
          chip,
          const SizedBox(height: AppSpacing.md),
          _Note(
            icon: Icons.signal_cellular_connected_no_internet_0_bar_rounded,
            color: r.uploadError.isNotEmpty ? AppColors.danger : AppColors.textSecondary,
            text: r.uploadError.isNotEmpty
                ? context.tr('It could not be sent: {error}', {'error': context.tr(r.uploadError)})
                : [
                    context.tr(
                        'This observation is saved on your phone and will be sent when you are back in signal.'),
                    if (!r.isDisease)
                      context.tr('The pest check happens after it is sent, so there is no result yet.'),
                  ].join(' '),
          ),
          if (r.uploadError.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              context.tr('It is not sent again automatically. Fix the problem if you can, then try again.'),
              style: const TextStyle(color: AppColors.textMuted, fontSize: 12.5, height: 1.4),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          AppPrimaryButton(
            label: context.tr('Try sending now'),
            icon: Icons.cloud_upload_outlined,
            loading: _loading,
            onPressed: _sendNow,
          ),
          if (r.uploadError.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            AppSecondaryButton(
              label: context.tr('Discard this observation'),
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
          _Note(
            icon: Icons.mark_email_read_rounded,
            text: context.tr(
                'Sent for review by an agricultural technician. You will get a notification with the diagnosis and what to do.'),
          ),
        ];
      case RecordState.forValidation:
        return [chip, const SizedBox(height: AppSpacing.md), AiResultCard(ai: r.ai)];
      case RecordState.withAgriculturist:
        return [
          chip,
          const SizedBox(height: AppSpacing.md),
          _Note(
            icon: Icons.forward_to_inbox_rounded,
            color: AppColors.purple,
            text: context.tr(
                'Your technician asked an agriculturist to take a closer look. You will get a notification when there is an answer.'),
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
                      Text(context.tr('Your technician says:'), style: const TextStyle(color: AppColors.textSecondary)),
                      const SizedBox(height: 4),
                      // Quick reasons arrive in English and are shown in the farmer's language.
                      Text(
                          r.returnReason.isEmpty
                              ? context.tr('Please take the photo again.')
                              : context.tr(r.returnReason),
                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, height: 1.35)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          if (r.resubmittedAs != null) ...[
            _Note(
              icon: Icons.check_circle_outline_rounded,
              text: context.tr('You already sent a new photo. It goes through the check again.'),
            ),
            const SizedBox(height: AppSpacing.md),
            AppSecondaryButton(
              label: context.tr('Open the new photo'),
              icon: Icons.open_in_new_rounded,
              onPressed: () => context.push(AppRouter.record, extra: r.resubmittedAs),
            ),
          ] else
            AppPrimaryButton(
              label: context.tr('Retake the photo'),
              icon: Icons.photo_camera_rounded,
              onPressed: r.id == null || !r.isMine ? null : () => _retake(r),
            ),
        ];
      case RecordState.validated:
        return r.isDisease ? _validatedDisease(r, chip) : _validatedPest(r, chip);
      case RecordState.noPests:
        // Closed without review; nothing to treat.
        return [
          chip,
          const SizedBox(height: AppSpacing.md),
          AppCard(
            tinted: true,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const IconTile(icon: Icons.eco_rounded, color: AppColors.primary, size: 40),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(context.tr('No pests found'),
                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, height: 1.35)),
                      const SizedBox(height: 4),
                      Text(
                        context.tr('The photo was clear and no pests were seen, so this observation was closed '
                            'without review. The photo was removed from the server to save space. Keep checking '
                            'your field and send a new photo anytime.'),
                        style: const TextStyle(fontSize: 14.5, height: 1.45),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ];
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
        _ConfirmedCard(level: r.level ?? r.confirmed?.level, title: context.tr('Disease report')),
        if (r.diagnosis.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          _Section(
            icon: Icons.medical_information_outlined,
            title: context.tr('Diagnosis'),
            child: Text(r.diagnosis, style: const TextStyle(fontSize: 15.5, height: 1.45)),
          ),
        ],
        if (r.guidance.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          _Section(
            icon: Icons.tips_and_updates_outlined,
            title: context.tr('What to do'),
            child: Text(r.guidance, style: const TextStyle(fontSize: 15.5, height: 1.45)),
          ),
        ],
      ];

  List<Widget> _validatedPest(Record r, Widget chip) {
    final c = r.confirmed!;
    final recs = r.recommendations;
    final treatments = [...r.treatments, ..._pendingTreatments];
    final recommended = r.recommended;
    return [
      chip,
      const SizedBox(height: AppSpacing.md),
      _ConfirmedCard(
        level: c.level,
        title: c.pestLabel,
        count: c.count == null ? context.tr('Not countable') : plural(c.count!, 'insect'),
        guidance: r.guidance,
      ),
      for (final t in treatments.where((t) => t.followUpIsDue)) ...[
        const SizedBox(height: AppSpacing.md),
        _FollowUpPrompt(treatment: t),
      ],
      if (recommended.isNotEmpty) ...[
        const SizedBox(height: AppSpacing.lg),
        _Section(
          icon: Icons.recommend_rounded,
          title: context.tr(r.isMine ? 'Recommended by your technician' : 'Recommended by the reviewer'),
          child: _Recommended(options: recommended),
        ),
      ],
      const SizedBox(height: AppSpacing.lg),
      _Section(
        icon: Icons.healing_rounded,
        title: context.tr('Treatment options'),
        subtitle: r.cropStage.isEmpty
            ? null
            : context.tr('For the {stage} stage', {'stage': context.tr(r.cropStage).toLowerCase()}),
        child: recs == null
            ? Text(context.tr('Open this record with signal to see the options.'))
            : recs.isEmpty
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.tr(
                                'No approved options for this case yet. Ask your agricultural technician what to do.'),
                            style: const TextStyle(height: 1.45),
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
          label: context.tr('I applied a treatment'),
          icon: Icons.task_alt_rounded,
          onPressed: r.id == null ? null : () => _logTreatment(r),
        ),
      ],
      if (treatments.isNotEmpty) ...[
        const SizedBox(height: AppSpacing.lg),
        _Section(
          icon: Icons.history_rounded,
          title: context.tr(r.isMine ? 'What you applied' : 'Applied treatments'),
          child: Column(children: [
            for (final t in treatments)
              _TreatmentRow(
                treatment: t,
                before: r,
                onRetry: t.pending && t.error.isNotEmpty ? () => _retryTreatment(t) : null,
                onDiscard: t.pending && t.error.isNotEmpty ? () => _discardTreatment(t) : null,
              ),
          ]),
        ),
      ],
    ];
  }

  Widget _details(Record r) {
    final trap = r.monitoringMethod == 'Trap-based';
    // Stored values (crop stage, method, trap, target) stay English; shown translated.
    return _Section(
      icon: Icons.info_outline_rounded,
      title: context.tr('Details'),
      child: Column(
        children: [
          _Detail(context.tr('Report'), context.tr(r.isDisease ? 'Disease report' : 'Pest report')),
          if (r.resubmissionOf != null)
            _Detail(context.tr('Retake'), context.tr('New photo for report #{id}', {'id': r.resubmissionOf})),
          _Detail(context.tr('Crop stage'), context.tr(r.cropStage)),
          _Detail(
            context.tr('Land type'),
            landTypeLabel(r.landType),
            action: r.id != null && (r.landTypeEditableByOwner || _isTech)
                ? TextButton(
                    key: const ValueKey('change-land-type'),
                    onPressed: () => _changeLandType(r),
                    style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                    child: Text(context.tr('Change')),
                  )
                : null,
          ),
          if (r.landTypeUpdatedAt.isNotEmpty)
            _Detail(
              context.tr('Land type changed'),
              [
                formatDateTime(r.landTypeUpdatedAt),
                if (r.landTypeUpdatedBy.isNotEmpty) r.landTypeUpdatedBy,
              ].join(' · '),
            ),
          if (!r.isDisease) _Detail(context.tr('Checked by'), context.tr(r.monitoringMethod)),
          if (trap && r.trapType.isNotEmpty) _Detail(context.tr('Trap or lure'), context.tr(r.trapType)),
          if (trap && r.targetPest.isNotEmpty) _Detail(context.tr('Target pest'), context.tr(r.targetPest)),
          if (trap && r.targetSex.isNotEmpty) _Detail(context.tr('Target sex'), context.tr(r.targetSex)),
          if (r.notes.isNotEmpty) _Detail(context.tr(r.isDisease ? 'Symptoms' : 'Your notes'), r.notes),
          if (r.followUpOf != null)
            _Detail(context.tr('Follow-up'), context.tr('Checks on a treatment you applied')),
          if (r.barangay.isNotEmpty || r.municipality.isNotEmpty)
            _Detail(context.tr('Area'), [r.barangay, r.municipality].where((x) => x.isNotEmpty).join(', ')),
          if (r.locationStatus == 'outside_antique')
            Padding(
              padding: const EdgeInsets.only(top: 2, bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline_rounded, size: 15, color: AppColors.textMuted),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      context.tr('The GPS point was outside Antique, so this was filed under your saved barangay.'),
                      style: const TextStyle(color: AppColors.textMuted, fontSize: 12.5, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
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

/// Technicians: asks before deleting an observation (with an optional reason
/// the farmer sees), deletes it on the server and this phone while the sheet
/// shows it is busy, then shows the outcome. Returns true once the record is
/// gone, so the caller can leave its screen. Also used by the review screen.
Future<bool> confirmDeleteRecord(BuildContext context, int scanId) async {
  final outcome = await showModalBottomSheet<Object>(
    context: context,
    isScrollControlled: true,
    enableDrag: false,
    builder: (_) => _DeleteSheet(scanId: scanId),
  );
  if (outcome == null || !context.mounted) return false;
  final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
  void show(String text) => messenger.showSnackBar(SnackBar(content: Text(text)));
  if (outcome is ApiException) {
    show(outcome.isOffline
        ? context.tr('No signal. Deleting needs a connection; try again with signal.')
        : context.tr(outcome.message));
    return outcome.statusCode == 410; // already deleted: nothing left to show
  }
  show(context.tr('Observation deleted.'));
  return true;
}

/// Pops true once deleted, or the ApiException to show.
class _DeleteSheet extends StatefulWidget {
  final int scanId;
  const _DeleteSheet({required this.scanId});

  @override
  State<_DeleteSheet> createState() => _DeleteSheetState();
}

class _DeleteSheetState extends State<_DeleteSheet> {
  final TextEditingController _reason = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    Object result = true;
    try {
      await SyncService.deleteRecord(widget.scanId, reason: _reason.text.trim());
    } on ApiException catch (e) {
      result = e;
      if (e.statusCode == 410) {
        // Someone already deleted it: loading it drops the phone's copy too.
        try {
          await SyncService.record(widget.scanId);
        } on ApiException catch (_) {
          // Gone either way; the next list refresh tidies up.
        }
      }
    }
    if (mounted) Navigator.pop(context, result);
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !_busy,
        child: Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(AppSpacing.hPad, 0, AppSpacing.hPad, AppSpacing.lg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(child: IconTile(icon: Icons.delete_outline_rounded, color: AppColors.danger, size: 56)),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    context.tr('Delete this observation?'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontFamily: AppFonts.display, fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    context.tr('This removes the record, its photo, treatments and review history for everyone. '
                        'The farmer is told in the app. This can\'t be undone.'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 14, height: 1.45),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  TextField(
                    controller: _reason,
                    enabled: !_busy,
                    maxLines: 2,
                    maxLength: 300,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(labelText: context.tr('Reason (optional, shown to the farmer)')),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AppPrimaryButton(
                    label: context.tr('Delete'),
                    icon: Icons.delete_outline_rounded,
                    color: AppColors.danger,
                    loading: _busy,
                    onPressed: _delete,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextButton(
                    onPressed: _busy ? null : () => Navigator.pop(context),
                    child: Text(context.tr('Cancel'), style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
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
                      Text(context.tr('Confirmed by your technician'),
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5)),
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
        Text(
          context.tr('Approved by your agriculture office for this pest, crop stage and level. '
              'Choose what fits your farm; your technician can help.'),
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13.5, height: 1.4),
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
                Flexible(
                  child: Text(kOptionTypeNames[type]!, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                ),
                const SizedBox(width: 6),
                Text('${recs.groups[type]!.length}', style: const TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w700)),
              ],
            ),
            if (type == 'chemical') ...[
              const SizedBox(height: AppSpacing.sm),
              InfoBanner(icon: Icons.warning_amber_rounded, message: context.tr(recs.chemicalNote)),
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
                      if (o.recommended) ...[
                        AppChip(
                          label: context.tr('Recommended by your technician'),
                          color: AppColors.primary,
                          icon: Icons.recommend_rounded,
                        ),
                        const SizedBox(height: 6),
                      ],
                      Text(o.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                      const SizedBox(height: 4),
                      Text(o.description, style: const TextStyle(fontSize: 14, height: 1.45)),
                      if (o.sourceReference.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(context.tr('Source: {source}', {'source': o.sourceReference}),
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
        context.tr(
          titles.length == 1
              ? 'Not shown again because you already tried it and sent feedback: {titles}. '
                  'Your technician can recommend it again.'
              : 'Not shown again because you already tried them and sent feedback: {titles}. '
                  'Your technician can recommend them again.',
          {'titles': titles.join(', ')},
        ),
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
            Row(
              children: [
                const IconTile(icon: Icons.alarm_rounded, size: 38),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(context.tr('How is the field now?'),
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              context.tr(
                'It has been a while since you applied "{treatment}". Take a photo so your '
                'technician can see if it worked.',
                {'treatment': treatment.treatment},
              ),
              style: const TextStyle(height: 1.4),
            ),
            const SizedBox(height: AppSpacing.md),
            AppPrimaryButton(
              label: context.tr('Check the field'),
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

/// Options the reviewer recommended from the approved library. They are
/// recommendations, not treatments the farmer applied.
class _Recommended extends StatelessWidget {
  final List<RecommendedOption> options;
  const _Recommended({required this.options});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.tr('Picked for this case from the approved options. These are recommendations, not treatments '
              'you applied.'),
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13.5, height: 1.4),
        ),
        for (final o in options)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.surfaceMuted,
                border: Border(left: BorderSide(color: _optionColors[o.optionType] ?? AppColors.primary, width: 3)),
                borderRadius: BorderRadius.circular(AppRadius.xs),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      if (o.optionType.isNotEmpty)
                        AppChip(
                          label: kOptionTypeNames[o.optionType] ?? o.optionType,
                          color: _optionColors[o.optionType] ?? AppColors.primary,
                          icon: kOptionTypeIcons[o.optionType],
                        ),
                      if (!o.stillApproved)
                        AppChip(label: context.tr('No longer approved'), color: AppColors.danger),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(o.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                  if (o.description.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(o.description, style: const TextStyle(fontSize: 14, height: 1.45)),
                  ],
                  if (o.recommendedByName.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(context.tr('Recommended by {name}', {'name': o.recommendedByName}),
                        style: const TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
                  ],
                  if (o.sourceReference.isNotEmpty)
                    Text(context.tr('Source: {source}', {'source': o.sourceReference}),
                        style: const TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _TreatmentRow extends StatelessWidget {
  final TreatmentInfo treatment;

  /// The observation the treatment was applied for ("before").
  final Record before;
  final VoidCallback? onRetry;
  final VoidCallback? onDiscard;
  const _TreatmentRow({required this.treatment, required this.before, this.onRetry, this.onDiscard});

  @override
  Widget build(BuildContext context) {
    final t = treatment;
    final (String status, Color color) = t.pending
        ? (t.error.isNotEmpty
            ? (context.tr('Not sent'), AppColors.danger)
            : (context.tr('Waiting for signal'), AppColors.textMuted))
        : t.followUpScanId != null
            ? (context.tr('Follow-up sent'), AppColors.primary)
            : t.followUpIsDue
                ? (context.tr('Follow-up due now'), AppColors.danger)
                : (context.tr('Follow-up on {date}', {'date': formatShortDate(t.followUpDue)}), AppColors.orange);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconTile(icon: kOptionTypeIcons[t.optionType] ?? Icons.task_alt_rounded, size: 38),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.treatment, style: const TextStyle(fontWeight: FontWeight.w800)),
                    Text(context.tr('Applied {date}', {'date': formatShortDate(t.appliedAt)}),
                        style: const TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
                    if (t.followUpSetBy != null && t.followUpScanId == null)
                      Text(context.tr('Follow-up date set by your technician'),
                          style: const TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
                    const SizedBox(height: 4),
                    AppChip(label: status, color: color),
                  ],
                ),
              ),
            ],
          ),
          if (t.pending && t.error.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              context.tr('It could not be sent: {error}', {'error': context.tr(t.error)}),
              style: const TextStyle(color: AppColors.danger, fontSize: 13, height: 1.4),
            ),
            Wrap(
              spacing: AppSpacing.sm,
              children: [
                if (onRetry != null)
                  TextButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: Text(context.tr('Try again')),
                  ),
                if (onDiscard != null)
                  TextButton.icon(
                    onPressed: onDiscard,
                    style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                    label: Text(context.tr('Remove')),
                  ),
              ],
            ),
          ],
          if (!t.pending) ...[
            const SizedBox(height: AppSpacing.sm),
            _BeforeAfter(before: before, treatment: t),
          ],
        ],
      ),
    );
  }
}

/// Before = the observation the treatment was for; after = the follow-up
/// photo, if one was sent. Never says "improved": a follow-up without pests
/// is not confirmed until a technician reviews it.
class _BeforeAfter extends StatefulWidget {
  final Record before;
  final TreatmentInfo treatment;
  const _BeforeAfter({required this.before, required this.treatment});

  @override
  State<_BeforeAfter> createState() => _BeforeAfterState();
}

class _BeforeAfterState extends State<_BeforeAfter> {
  Record? _after;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadAfter();
  }

  @override
  void didUpdateWidget(covariant _BeforeAfter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.treatment.followUpScanId != widget.treatment.followUpScanId) _loadAfter();
  }

  Future<void> _loadAfter() async {
    final id = widget.treatment.followUpScanId;
    if (id == null) return;
    setState(() => _loading = true);
    try {
      final cached = await SyncService.cachedRecord(id);
      if (cached != null && mounted) setState(() => _after = cached.data);
    } catch (_) {}
    try {
      final fresh = await SyncService.record(id);
      if (fresh != null && mounted) setState(() => _after = fresh);
    } catch (_) {
      // offline or gone: keep the saved copy, if any
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  static String _summary(BuildContext context, Record r) {
    final c = r.confirmed;
    final ai = r.ai;
    final pest = c?.pestLabel ?? (ai != null && ai.recognized ? ai.pestLabel : null);
    final count = c != null
        ? (c.count == null ? context.tr('Not countable') : plural(c.count!, 'insect'))
        : (ai != null && ai.recognized ? (ai.count == null ? context.tr('Not countable') : plural(ai.count!, 'insect')) : null);
    final level = c?.level ?? r.level;
    return [
      formatShortDate(r.createdAt),
      ?pest,
      ?count,
      if (level != null) context.tr('{level} infestation', {'level': levelLabel(level)}),
    ].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.treatment;
    final after = _after;
    final String afterText;
    Color afterColor = AppColors.textSecondary;
    if (t.followUpScanId == null) {
      afterText = t.followUpIsDue
          ? context.tr('No follow-up photo yet. It is due now.')
          : context.tr('No follow-up photo yet.');
    } else if (after == null) {
      afterText = _loading ? context.tr('Loading…') : context.tr('Open the follow-up with signal to see it.');
    } else if (after.status == 'no_pests') {
      afterText = '${formatShortDate(after.createdAt)} · '
          '${context.tr('No pests detected on the follow-up photo — not yet confirmed by a technician')}';
      afterColor = AppColors.sky;
    } else if (after.status == 'validated') {
      afterText = '${_summary(context, after)} · ${context.tr('Validated')}';
      afterColor = AppColors.primary;
    } else if (after.status == 'returned') {
      afterText = '${formatShortDate(after.createdAt)} · ${recordStateLabel(after.state)}';
      afterColor = AppColors.danger;
    } else {
      afterText = '${formatShortDate(after.createdAt)} · ${context.tr('Follow-up waiting for review')}';
      afterColor = AppColors.orange;
    }
    Widget line(String label, String text, Color color) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Text.rich(
            TextSpan(children: [
              TextSpan(text: '$label: ', style: const TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w700)),
              TextSpan(text: text, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
            ]),
            style: const TextStyle(fontSize: 13, height: 1.4),
          ),
        );
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(AppRadius.xs),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          line(context.tr('Before'), _summary(context, widget.before), AppColors.textPrimary),
          line(context.tr('After'), afterText, afterColor),
          if (t.followUpScanId != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => context.push(AppRouter.record, extra: t.followUpScanId),
                style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                icon: const Icon(Icons.open_in_new_rounded, size: 16),
                label: Text(context.tr('Open the follow-up')),
              ),
            ),
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
  String? _error; // English; shown translated

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
            Text(context.tr('What did you use?'),
                style: const TextStyle(fontFamily: AppFonts.display, fontSize: 20, fontWeight: FontWeight.w800)),
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
                  RadioListTile<int>(
                    value: _own,
                    contentPadding: EdgeInsets.zero,
                    title: Text(context.tr('Something else'), style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(context.tr('Describe what you did')),
                    secondary: const IconTile(icon: Icons.edit_note_rounded, color: AppColors.textSecondary, size: 36),
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
                decoration: InputDecoration(hintText: context.tr('e.g. Removed weeds around the field')),
              ),
            const SizedBox(height: AppSpacing.sm),
            Material(
              color: AppColors.surfaceMuted,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
                leading: const Icon(Icons.event_rounded, color: AppColors.primary),
                title: Text(context.tr('Date applied')),
                subtitle: Text(formatShortDate(_date.toIso8601String()), style: const TextStyle(fontWeight: FontWeight.w700)),
                trailing: Text(context.tr('Change'),
                    style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
                onTap: _pickDate,
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(context.tr(_error!), style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600)),
            ],
            const SizedBox(height: AppSpacing.lg),
            AppPrimaryButton(label: context.tr('Continue'), icon: Icons.arrow_forward_rounded, onPressed: _next),
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
                    Flexible(
                      child: Text(subtitle!,
                          textAlign: TextAlign.end,
                          style: const TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
                    ),
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
  final Widget? action;
  const _Detail(this.label, this.value, {this.action});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          crossAxisAlignment: action == null ? CrossAxisAlignment.start : CrossAxisAlignment.center,
          children: [
            // Label and value share the row (2:3) so long words wrap
            // instead of overflowing on narrow phones or large text.
            Expanded(flex: 2, child: Text(label, style: const TextStyle(color: AppColors.textMuted))),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              flex: 3,
              child: Text(value.isEmpty ? '—' : value, style: const TextStyle(height: 1.35, fontWeight: FontWeight.w600)),
            ),
            ?action,
          ],
        ),
      );
}
