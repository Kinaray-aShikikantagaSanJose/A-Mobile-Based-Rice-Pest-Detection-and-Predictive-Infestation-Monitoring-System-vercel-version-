import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../app_router.dart';
import '../controllers/auth_controller.dart';
import '../l10n/app_language.dart';
import '../models/record.dart';
import '../services/api_client.dart';
import '../services/sync_service.dart';
import '../theme.dart';
import '../utils/formatters.dart';
import '../utils/review_rules.dart';
import '../widgets/app_widgets.dart';
import '../widgets/detection_photo.dart';
import '../widgets/land_type_sheet.dart';
import '../widgets/scan_map.dart';
import '../widgets/shell_scope.dart';
import 'f24_record_detail.dart' show confirmDeleteRecord;
import 'f47_submission_done.dart';

/// Reviewing one observation, in the order of the process flow:
/// 1 Check the result: pest reports show the model result's pest and count, which the
///   technician confirms or corrects; disease reports have no model result, so the
///   technician checks the photo and the farmer's description.
/// 2 Decide: Return (photo unclear, the farmer retakes it) · Validate (confirm
///   or override the infestation level) · Escalate (refer the case to an
///   agriculturist).
class F61ReviewObservation extends StatefulWidget {
  final int scanId;

  /// Shows this record (with [previewSuggestion] and [previewLibrary])
  /// without loading anything: for widget tests and previews only.
  @visibleForTesting
  final Record? preview;
  @visibleForTesting
  final LevelSuggestion? previewSuggestion;
  @visibleForTesting
  final List<LibraryOption>? previewLibrary;

  const F61ReviewObservation({
    super.key,
    required this.scanId,
    this.preview,
    this.previewSuggestion,
    this.previewLibrary,
  });

  @override
  State<F61ReviewObservation> createState() => _F61ReviewObservationState();
}

enum _Decision { returnPhoto, validate, escalate }

class _F61ReviewObservationState extends State<F61ReviewObservation> {
  Record? _r;
  String? _error;
  bool _loading = false;

  /// Shown from the copy saved on the phone (refresh failed or running).
  bool _fromCache = false;
  DateTime? _savedAt;

  // Step 1: the result being confirmed (starts as the model result's).
  String? _pest;
  int? _count;
  bool _countable = true;

  // Step 2
  _Decision? _decision;
  final Set<String> _indicators = {};
  LevelSuggestion? _suggestion;
  String? _level;
  bool _levelTouched = false;
  Timer? _debounce;
  final TextEditingController _reason = TextEditingController();
  final TextEditingController _diagnosis = TextEditingController();
  final TextEditingController _guidance = TextEditingController();

  /// The reviewer's own note (required to validate). Kept in the review
  /// history; the farmer reads the guidance, not this.
  final TextEditingController _note = TextEditingController();

  /// Approved library options (technicians) and the ones recommended here.
  List<LibraryOption> _library = const [];
  bool _libraryLoaded = false;
  final Set<int> _recommendedIds = {};

  bool get _isTech => AuthControllerImpl.instance.role == AppRole.technician;

  @override
  void initState() {
    super.initState();
    final preview = widget.preview;
    if (preview != null) {
      _library = widget.previewLibrary ?? const [];
      _libraryLoaded = true;
      _show(preview);
      return;
    }
    _load();
    _loadLibrary();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _reason.dispose();
    _diagnosis.dispose();
    _guidance.dispose();
    _note.dispose();
    super.dispose();
  }

  void _show(Record r, {bool fromCache = false, DateTime? savedAt}) {
    final ai = r.ai;
    final first = _r == null;
    setState(() {
      _r = r;
      _fromCache = fromCache;
      _savedAt = savedAt;
      // Keep what the reviewer already changed when the fresh copy arrives.
      if (first) {
        _pest = ai?.pest;
        _count = ai?.count;
        // No pest named: the reviewer names it and enters the count.
        _countable = ai?.count != null || ai?.pest == null;
      }
    });
    if (first && !r.isDisease) _refreshSuggestion(immediate: true);
  }

  /// Cache first (a copy opened before shows at once), then the server's.
  Future<void> _load() async {
    setState(() {
      _error = null;
      _loading = true;
    });
    if (_r == null) {
      try {
        final cached = await SyncService.cachedRecord(widget.scanId);
        if (cached != null && mounted && _r == null) _show(cached.data, fromCache: true, savedAt: cached.savedAt);
      } catch (e) {
        debugPrint('[Review] no saved copy: $e');
      }
    }
    try {
      final r = await SyncService.record(widget.scanId);
      if (!mounted || r == null) return;
      _show(r);
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.statusCode == 410) {
        // Deleted on the server meanwhile: back to the queue, which reloads.
        _snack(context.tr('This observation was deleted.'));
        popOrGoHome(context, true);
        return;
      }
      setState(() {
        _error = e.isOffline ? 'No signal, and this report is not saved on this phone yet.' : e.message;
        if (_r != null) _fromCache = true;
      });
    } catch (e) {
      debugPrint('[Review] could not load: $e');
      if (mounted) setState(() => _error = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadLibrary() async {
    if (!_isTech) return;
    try {
      final lib = await SyncService.library();
      if (mounted) {
        setState(() {
          _library = lib;
          _libraryLoaded = true;
        });
      }
    } catch (e) {
      debugPrint('[Review] library unavailable: $e');
      if (mounted) setState(() => _libraryLoaded = true);
    }
  }

  /// Approved options for the pest being confirmed.
  List<LibraryOption> get _options => approvedOptionsFor(_library, _pest);

  Future<void> _changeLandType(Record r) async {
    final updated = await showLandTypeChange(context, r, askReason: true);
    if (updated == null || !mounted) return;
    setState(() => _r = updated);
    _snack(context.tr('Land type saved.'));
  }

  /// Technicians: delete this observation for everyone, then back to the queue.
  Future<void> _delete() async {
    if (await confirmDeleteRecord(context, widget.scanId) && mounted) popOrGoHome(context, true);
  }

  bool get _canAct => _r?.status == 'pending';

  /// True while the reviewer's result is still the model result's.
  bool get _sameAsAi {
    final ai = _r?.ai;
    return ai != null && ai.pest != null && _pest == ai.pest && _count == ai.count && _countable == (ai.count != null);
  }

  void _snack(String msg) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));

  /// The server's reasons for the suggested level come in English; shown in
  /// the app language.
  String _reasonLabel(String reason) {
    if (context.lang == AppLang.en) return reason;
    const bump = '+1 level: ';
    if (reason.startsWith(bump)) {
      return context.tr('+1 level: {damage}', {'damage': context.tr(reason.substring(bump.length))});
    }
    final m = RegExp(r'^Count (\d+): (LOW|MEDIUM|HIGH) for (.+) \(MEDIUM from ([\d.]+), HIGH from ([\d.]+)\)$')
        .firstMatch(reason);
    if (m != null) {
      return context.tr('Count {n}: {level} for {stage} (MEDIUM from {medium}, HIGH from {high})', {
        'n': m[1],
        'level': levelLabel(m[2]),
        'stage': context.tr(m[3]!),
        'medium': m[4],
        'high': m[5],
      });
    }
    return context.tr(reason);
  }

  // ---------------------------------------------------------------- step 1: confirm or correct

  Future<void> _correctPest() async {
    final pest = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(AppSpacing.hPad, 0, AppSpacing.hPad, AppSpacing.lg),
          children: [
            Text(ctx.tr('Which pest is it?'), style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
            const SizedBox(height: AppSpacing.sm),
            for (final k in kPestKeys)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: IconTile(
                  icon: k == 'other' ? Icons.help_outline_rounded : Icons.bug_report_outlined,
                  size: 38,
                  color: k == 'other' ? AppColors.textMuted : AppColors.primary,
                ),
                title: Text(pestName(k), style: const TextStyle(fontWeight: FontWeight.w600)),
                trailing: k == _pest ? const Icon(Icons.check_circle_rounded, color: AppColors.primary) : null,
                onTap: () => Navigator.pop(ctx, k),
              ),
          ],
        ),
      ),
    );
    if (pest == null || !mounted) return;
    setState(() {
      _pest = pest;
      _levelTouched = false;
      // Recommendations must be approved options for the confirmed pest.
      final allowed = {for (final o in _options) o.id};
      _recommendedIds.retainWhere(allowed.contains);
    });
    _refreshSuggestion(immediate: true);
  }

  Future<void> _correctCount() async {
    final ctrl = TextEditingController(text: '${_count ?? ''}');
    final result = await showModalBottomSheet<(int?, bool)>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.hPad, 0, AppSpacing.hPad, AppSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(ctx.tr('How many insects?'), style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(
                  ctx.tr('Count only when the insects can be told apart. Otherwise mark it not countable.'),
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: ctrl,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(labelText: ctx.tr('Count'), prefixIcon: const Icon(Icons.tag_rounded)),
                ),
                const SizedBox(height: AppSpacing.md),
                AppPrimaryButton(
                  label: ctx.tr('Use this count'),
                  onPressed: () {
                    final n = int.tryParse(ctrl.text);
                    if (n != null) Navigator.pop(ctx, (n, true));
                  },
                ),
                const SizedBox(height: AppSpacing.sm),
                AppSecondaryButton(label: ctx.tr('Not countable'), onPressed: () => Navigator.pop(ctx, (null, false))),
              ],
            ),
          ),
        ),
      ),
    );
    ctrl.dispose();
    if (result == null || !mounted) return;
    setState(() {
      _count = result.$1;
      _countable = result.$2;
      _levelTouched = false;
    });
    _refreshSuggestion(immediate: true);
  }

  void _resetToAi() {
    final ai = _r!.ai;
    setState(() {
      _pest = ai?.pest;
      _count = ai?.count;
      _countable = ai?.count != null || ai?.pest == null;
      _levelTouched = false;
      final allowed = {for (final o in _options) o.id};
      _recommendedIds.retainWhere(allowed.contains);
    });
    _refreshSuggestion(immediate: true);
  }

  void _refreshSuggestion({bool immediate = false}) {
    if (widget.preview != null) {
      final s = widget.previewSuggestion;
      if (s != null) {
        setState(() {
          _suggestion = s;
          if (!_levelTouched) _level = s.level;
        });
      }
      return;
    }
    _debounce?.cancel();
    _debounce = Timer(immediate ? Duration.zero : const Duration(milliseconds: 300), () async {
      final pest = _pest;
      if (pest == null || _r == null) return;
      try {
        final s = await SyncService.suggestLevel(
          pest: pest,
          cropStage: _r!.cropStage,
          count: _countable ? _count : null,
          indicators: _indicators.toList(),
        );
        if (!mounted || pest != _pest) return;
        setState(() {
          _suggestion = s;
          _indicators.retainWhere(s.availableIndicators.contains);
          if (!_levelTouched) _level = s.level;
        });
      } on ApiException catch (e) {
        if (mounted) _snack(context.tr(e.message));
      }
    });
  }

  // ---------------------------------------------------------------- step 2: decide

  void _choose(_Decision d) {
    if (_decision == d) return;
    setState(() {
      _decision = d;
      _reason.clear();
    });
  }

  /// Why Validate can't be sent yet (English; shown translated).
  String? get _validateBlocker {
    final r = _r!;
    if (!r.isDisease) {
      if (_pest == null) return 'Name the pest in step 1 first.';
      if (_countable && _count == null) return 'Enter the count in step 1, or mark it not countable.';
    }
    if (_level == null) return 'Pick the infestation level.';
    return reviewerNoteProblem(_note.text, diagnosis: _diagnosis.text, guidance: _guidance.text);
  }

  /// Why a Return or Escalate reason can't be sent yet (English), or null.
  String? get _reasonBlocker =>
      decisionReasonProblem(_reason.text, escalate: _decision == _Decision.escalate);

  bool get _overridden => _suggestion != null && _level != null && _level != _suggestion!.level;

  /// Confirm, then open the result screen while the decision is sent.
  Future<void> _submit() async {
    final r = _r!;
    final Map<String, dynamic> body;
    // Done titles/messages are translated by the result screen; the rest here.
    final String confirmTitle, confirmMessage, doneTitle, doneMessage;
    final IconData icon;
    final Color color;
    final summary = <(String, String)>[];
    switch (_decision) {
      case _Decision.returnPhoto:
        body = {'action': 'return', 'reason': _reason.text.trim()};
        confirmTitle = context.tr('Return to the farmer?');
        confirmMessage = context.tr('They will be asked to take the photo again.');
        doneTitle = 'Returned to the farmer';
        doneMessage = 'They will see your note and send a new photo.';
        icon = Icons.replay_rounded;
        color = AppColors.danger;
        summary.add((context.tr('Reason'), context.tr(_reason.text.trim())));
      case _Decision.escalate:
        body = {'action': 'escalate', 'reason': _reason.text.trim()};
        confirmTitle = context.tr('Refer to an agriculturist?');
        confirmMessage = context.tr('The case leaves your queue and goes to an agriculturist.');
        doneTitle = 'Sent to an agriculturist';
        doneMessage = 'An agriculturist will diagnose it and guide the farmer.';
        icon = Icons.forward_to_inbox_rounded;
        color = AppColors.purple;
        summary.add((context.tr('Reason'), context.tr(_reason.text.trim())));
      case _Decision.validate:
        final blocker = _validateBlocker;
        if (blocker != null) {
          _snack(context.tr(blocker));
          return;
        }
        body = {
          'action': 'validate',
          if (!r.isDisease) ...{
            'pest': _pest,
            'count': _countable ? _count : null,
            'countable': _countable,
            'damage_indicators': _indicators.toList(),
          },
          'level': _level,
          'diagnosis': _diagnosis.text.trim(),
          'guidance': _guidance.text.trim(),
          'reviewer_note': _note.text.trim(),
          if (!r.isDisease && _recommendedIds.isNotEmpty) 'recommended_library_ids': _recommendedIds.toList(),
        };
        confirmTitle = context.tr('Validate this report?');
        confirmMessage = context.tr('The farmer gets the result and the treatment options for their crop stage.');
        doneTitle = 'Validated';
        doneMessage = 'The farmer has been notified and can now see the treatment options.';
        icon = Icons.verified_rounded;
        color = AppColors.primary;
        if (!r.isDisease) {
          summary.add((context.tr('Pest'), pestName(_pest)));
          summary.add((context.tr('Count'), _countable ? '$_count' : context.tr('Not countable')));
        }
        summary.add((
          context.tr('Level'),
          _overridden ? context.tr('{level} (overridden)', {'level': levelLabel(_level)}) : levelLabel(_level),
        ));
        if (_recommendedIds.isNotEmpty) {
          summary.add((
            context.tr('Recommendations'),
            [for (final o in _options) if (_recommendedIds.contains(o.id)) o.title].join(', '),
          ));
        }
      case null:
        return;
    }
    if (_decision != _Decision.validate && _reasonBlocker != null) {
      _snack(context.tr(_reasonBlocker!));
      return;
    }
    final ok = await confirmAction(
      context,
      title: confirmTitle,
      message: confirmMessage,
      confirmLabel: context.tr('Yes, send'),
      icon: icon,
      color: color,
      summary: summary,
    );
    if (!ok || !mounted) return;
    Future<DoneResult> work() async {
      try {
        await SyncService.review(widget.scanId, body);
        return DoneResult.success(doneTitle, doneMessage, icon: icon, color: color);
      } on ApiException catch (e) {
        return DoneResult.failure(e.isOffline ? 'Not sent: no signal' : 'Not sent', e.message);
      }
    }

    // On success the result screen leads to the queue or the dashboard; after
    // a failure its back button returns here with the form as it was.
    context.push(
      AppRouter.done,
      extra: DoneArgs(
        workingTitle: 'Sending your decision…',
        workingMessage: 'This takes a moment.',
        work: work(),
        nextLabel: 'Next in queue',
        nextIcon: Icons.fact_check_rounded,
        nextTab: AppTab.queue,
      ),
    );
  }

  // ---------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final r = _r;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            AppHeader(
              title: context.tr(r == null ? 'Review' : (r.isDisease ? 'Disease report' : 'Pest report')),
              subtitle: r == null
                  ? null
                  : context.tr('Waiting {time} · #{id}', {'time': waitingLabel(r.createdAt), 'id': r.id}),
              onBack: () => context.pop(false),
              actions: [
                if (r != null && _isTech)
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
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(AppSpacing.hPad, AppSpacing.sm, AppSpacing.hPad, AppSpacing.xl),
                      children: [
                        MaxContentWidth(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                        if (_fromCache)
                          _savedAt == null
                              ? Padding(
                                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                                  child: Text(context.tr('Showing the copy saved on this phone.'),
                                      style: const TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
                                )
                              : SavedDataNote(savedAt: _savedAt!, refreshing: _loading),
                        if (_fromCache && !_loading && _error != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                            child: InfoBanner(
                              icon: Icons.cloud_off_rounded,
                              color: AppColors.textSecondary,
                              message: context.tr('Reviewing needs a connection. Your decision is sent when you tap send with signal.'),
                              actionLabel: context.tr('Retry'),
                              onAction: _load,
                            ),
                          ),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          child: DetectionPhoto(
                            scanId: r.id!,
                            clientUuid: r.clientUuid,
                            boxes: r.isDisease ? const [] : (r.ai?.detections ?? const []),
                            mainPest: r.ai?.pest,
                          ),
                        ),
                        ..._notices(r),
                        const SizedBox(height: AppSpacing.md),
                        _infoCard(r),
                        const SizedBox(height: AppSpacing.xl),
                        if (!_canAct)
                          AppCard(
                            child: Row(
                              children: [
                                StatusChip(state: r.state, staff: true),
                                const SizedBox(width: AppSpacing.md),
                                Expanded(child: Text(context.tr('Already handled.'))),
                              ],
                            ),
                          )
                        else ...[
                          _StepTitle(
                            number: 1,
                            title: context.tr(r.isDisease ? 'Check the symptoms' : 'Check the model result'),
                          ),
                          r.isDisease ? _diseaseCheck(r) : _pestCheck(r),
                          const SizedBox(height: AppSpacing.xl),
                          _StepTitle(number: 2, title: context.tr('Your decision')),
                          ..._decisions(),
                          if (_decision != null) ...[
                            const SizedBox(height: AppSpacing.lg),
                            ..._decisionForm(r),
                          ],
                        ],
                            ],
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _notices(Record r) => [
        if (r.possiblyUnrelated)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.md),
            child: InfoBanner(
              key: const ValueKey('possibly-unrelated'),
              icon: Icons.image_not_supported_outlined,
              color: AppColors.danger,
              message: context.tr(
                'This photo may not show a rice plant or field. Check it before validating; return it if it is not a field photo.',
              ),
            ),
          ),
        if (r.resubmissionOf != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.md),
            child: InfoBanner(
              icon: Icons.replay_rounded,
              color: AppColors.primary,
              message: context.tr(
                'New photo for report #{id}, which was returned because the photo was unclear.',
                {'id': r.resubmissionOf},
              ),
            ),
          ),
        if (r.followUpOf != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.md),
            child: InfoBanner(
              icon: Icons.healing_rounded,
              color: AppColors.sky,
              message: context.tr('Follow-up check: this photo shows the field after a treatment.'),
            ),
          ),
      ];

  Widget _infoCard(Record r) {
    final trap = r.monitoringMethod == 'Trap-based';
    Widget row(IconData icon, String k, String v, {Widget? action}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            crossAxisAlignment: action == null ? CrossAxisAlignment.start : CrossAxisAlignment.center,
            children: [
              Icon(icon, size: 17, color: AppColors.textMuted),
              const SizedBox(width: AppSpacing.sm),
              // Label and value share the row so long words wrap on narrow phones.
              Expanded(flex: 2, child: Text(k, style: const TextStyle(color: AppColors.textMuted, fontSize: 13.5))),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                flex: 3,
                child: SelectableText(v.isEmpty ? '—' : v, style: const TextStyle(height: 1.35, fontWeight: FontWeight.w600)),
              ),
              ?action,
            ],
          ),
        );
    // Stored values (crop stage, method, trap, target) stay English; shown translated.
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          row(
            Icons.person_outline_rounded,
            context.tr('Submitted by'),
            r.submitterRole == 'technician'
                ? context.tr('{name} (technician)', {'name': r.submitterName})
                : r.submitterName,
          ),
          if (r.submitterPhone.isNotEmpty) row(Icons.phone_outlined, context.tr('Phone'), r.submitterPhone),
          row(Icons.location_on_outlined, context.tr('Area'),
              [r.barangay, r.municipality].where((x) => x.isNotEmpty).join(', ')),
          row(Icons.schedule_rounded, context.tr('Sent'), formatDateTime(r.createdAt)),
          row(Icons.grass_rounded, context.tr('Crop stage'), context.tr(r.cropStage)),
          row(
            Icons.terrain_rounded,
            context.tr('Land type'),
            landTypeLabel(r.landType),
            action: _isTech && r.id != null
                ? TextButton(
                    key: const ValueKey('change-land-type'),
                    onPressed: () => _changeLandType(r),
                    style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                    child: Text(context.tr('Change')),
                  )
                : null,
          ),
          if (!r.isDisease) row(Icons.visibility_outlined, context.tr('Method'), context.tr(r.monitoringMethod)),
          if (trap) row(Icons.lightbulb_outline_rounded, context.tr('Trap or lure'), context.tr(r.trapType)),
          if (trap) row(Icons.bug_report_outlined, context.tr('Target pest'), context.tr(r.targetPest)),
          if (trap) row(Icons.wc_rounded, context.tr('Target sex'), context.tr(r.targetSex)),
          if (!r.isDisease) row(Icons.notes_rounded, context.tr('Farmer notes'), r.notes),
          if (r.lat != null && r.lng != null) ...[
            const SizedBox(height: AppSpacing.sm),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: ScanMap(markers: [ScanMarker(lat: r.lat!, lng: r.lng!)], height: 150, zoom: 15),
            ),
          ],
        ],
      ),
    );
  }

  Widget _pestCheck(Record r) {
    final ai = r.ai;
    final aiNamed = ai?.pest != null;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(color: AppColors.orangeLight, borderRadius: BorderRadius.circular(AppRadius.sm)),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.auto_awesome_rounded, size: 18, color: AppColors.orange),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    !aiNamed
                        ? (ai?.message.isNotEmpty == true
                            ? context.tr(ai!.message)
                            : context.tr('The model result names no pest.'))
                        : context.tr('Model result: {pest} · {sure} · {count}', {
                            'pest': ai!.pestLabel,
                            'sure': context.tr('{n}% sure', {'n': ((ai.confidence ?? 0) * 100).round()}),
                            'count': ai.count != null ? plural(ai.count!, 'insect') : context.tr('not countable'),
                          }),
                    style: const TextStyle(height: 1.35, fontWeight: FontWeight.w600, fontSize: 13.5),
                  ),
                ),
              ],
            ),
          ),
          if (ai != null && aiNamed && ai.count == null && ai.message.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(context.tr(ai.message),
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 13, height: 1.35)),
            ),
          const SizedBox(height: AppSpacing.md),
          _editRow(context.tr('Pest'), _pest == null ? context.tr('Not named yet') : pestName(_pest), _correctPest,
              action: context.tr(_pest == null ? 'Name it' : 'Correct')),
          const Divider(height: 1),
          _editRow(
              context.tr('Count'),
              _countable
                  ? (_count == null ? context.tr('Not entered yet') : '$_count')
                  : context.tr('Not countable'),
              _correctCount,
              action: context.tr(_countable && _count == null ? 'Enter' : 'Correct')),
          const SizedBox(height: AppSpacing.sm),
          if (_sameAsAi)
            AppChip(
              label: context.tr('Confirming the model result'),
              color: AppColors.primary,
              icon: Icons.check_circle_rounded,
            )
          else if (_pest != null)
            // Wraps onto two lines on narrow phones or with large text.
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: AppSpacing.sm,
              runSpacing: 4,
              children: [
                AppChip(label: context.tr('Corrected by you'), color: AppColors.orange, icon: Icons.edit_rounded),
                if (aiNamed) TextButton(onPressed: _resetToAi, child: Text(context.tr('Use the model result'))),
              ],
            ),
        ],
      ),
    );
  }

  Widget _diseaseCheck(Record r) => AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                context.tr(
                    'There is no model result for disease reports. Look at the photo and what the farmer describes.'),
                style: const TextStyle(color: AppColors.textMuted, fontSize: 13, height: 1.4)),
            const SizedBox(height: AppSpacing.md),
            Text(context.tr('Symptoms'),
                style: const TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            SelectableText(r.notes.isEmpty ? '—' : r.notes,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, height: 1.4)),
          ],
        ),
      );

  List<Widget> _decisions() => [
        ChoiceTile(
          icon: Icons.replay_rounded,
          title: context.tr('Return'),
          subtitle: context.tr('The photo is unclear. The farmer retakes it.'),
          selected: _decision == _Decision.returnPhoto,
          color: AppColors.danger,
          onTap: () => _choose(_Decision.returnPhoto),
        ),
        const SizedBox(height: AppSpacing.sm),
        ChoiceTile(
          icon: Icons.verified_rounded,
          title: context.tr('Validate'),
          subtitle: context.tr('Confirm or override the infestation level.'),
          selected: _decision == _Decision.validate,
          onTap: () => _choose(_Decision.validate),
        ),
        const SizedBox(height: AppSpacing.sm),
        ChoiceTile(
          icon: Icons.forward_to_inbox_rounded,
          title: context.tr('Escalate'),
          subtitle: context.tr('Complex case. Refer it to an agriculturist.'),
          selected: _decision == _Decision.escalate,
          color: AppColors.purple,
          onTap: () => _choose(_Decision.escalate),
        ),
      ];

  List<Widget> _decisionForm(Record r) => switch (_decision!) {
        _Decision.returnPhoto => _reasonForm(
            quick: const ['Photo too blurry', 'Too far away, move closer', 'Too dark', 'Insects not visible', 'Wrong photo'],
            hint: context.tr('What should the farmer fix? They will see this.'),
            button: context.tr('Return to the farmer'),
            icon: Icons.replay_rounded,
            color: AppColors.danger,
          ),
        _Decision.escalate => _reasonForm(
            quick: const ['Unclear what pest this is', 'Unusual damage', 'Possible outbreak', 'Not one of the four pests'],
            hint: context.tr('Why does it need an agriculturist?'),
            button: context.tr('Refer to an agriculturist'),
            icon: Icons.forward_to_inbox_rounded,
            color: AppColors.purple,
          ),
        _Decision.validate => _validateForm(r),
      };

  /// [quick] reasons are English: the chip shows them translated, but the
  /// English text goes in the field and to the server, so the farmer's app
  /// can show it in the farmer's language.
  List<Widget> _reasonForm({
    required List<String> quick,
    required String hint,
    required String button,
    required IconData icon,
    required Color color,
  }) =>
      [
        Text(context.tr('Quick reasons'),
            style: const TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final q in quick)
              ChoiceChip(
                label: Text(context.tr(q)),
                selected: _reason.text == q,
                showCheckmark: false,
                selectedColor: color.withValues(alpha: 0.15),
                onSelected: (_) => setState(() => _reason.text = q),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        TextField(
          controller: _reason,
          maxLines: 3,
          maxLength: 300,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            hintText: hint,
            // Same rule as the server: shown once the reviewer starts typing.
            errorText: _reason.text.trim().isEmpty || _reasonBlocker == null ? null : context.tr(_reasonBlocker!),
            errorMaxLines: 3,
          ),
          onChanged: (_) => setState(() {}),
        ),
        AppPrimaryButton(
          label: button,
          icon: icon,
          color: color,
          onPressed: _reasonBlocker != null ? null : _submit,
        ),
      ];

  List<Widget> _validateForm(Record r) {
    final s = _suggestion;
    return [
      if (!r.isDisease && _pest != null) ...[
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(context.tr('Damage you can see'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              if (s == null)
                const Padding(padding: EdgeInsets.all(AppSpacing.md), child: LinearProgressIndicator())
              else if (s.availableIndicators.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(context.tr('None listed for this pest.'), style: const TextStyle(color: AppColors.textMuted)),
                )
              else
                // Indicators stay English in what is sent; shown translated.
                for (final i in s.availableIndicators)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    dense: true,
                    value: _indicators.contains(i),
                    // The server's label in the app language; the English value is sent.
                    title: Text(s.labelFor(i), style: const TextStyle(fontSize: 14.5)),
                    onChanged: (v) {
                      setState(() => v == true ? _indicators.add(i) : _indicators.remove(i));
                      _refreshSuggestion();
                    },
                  ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
      ],
      AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Wraps the chip under the title on narrow phones or with large text.
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(context.tr(r.isDisease ? 'How bad is it in the field?' : 'Infestation level'),
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                if (_level != null && s != null)
                  AppChip(
                    label: context.tr(_overridden ? 'Overridden' : 'Suggested level'),
                    color: _overridden ? AppColors.orange : AppColors.primary,
                    icon: _overridden ? Icons.edit_rounded : Icons.check_rounded,
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              context.tr(s == null
                  ? 'Pick the level you see in the field.'
                  : 'Keep the suggested level to confirm it, or pick another to override it.'),
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            if (s != null && s.provisional) ...[
              const SizedBox(height: AppSpacing.sm),
              InfoBanner(
                key: const ValueKey('provisional-thresholds'),
                icon: Icons.rule_rounded,
                color: AppColors.orange,
                message: context.tr(
                  'Provisional thresholds: an agriculturist has not confirmed them yet. Use your own judgement for the level.',
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                for (final (i, lv) in const ['LOW', 'MEDIUM', 'HIGH'].indexed) ...[
                  if (i > 0) const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: _LevelTile(
                      level: lv,
                      selected: _level == lv,
                      suggested: s?.level == lv,
                      onTap: () => setState(() {
                        _level = lv;
                        _levelTouched = true;
                      }),
                    ),
                  ),
                ],
              ],
            ),
            if (s != null && s.reasons.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              for (final reason in s.reasons)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text('• ${_reasonLabel(reason)}',
                      style: const TextStyle(fontSize: 12.5, height: 1.4, color: AppColors.textSecondary)),
                ),
            ],
          ],
        ),
      ),
      const SizedBox(height: AppSpacing.md),
      if (r.isDisease)
        TextField(
          controller: _diagnosis,
          maxLines: 2,
          maxLength: 500,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(labelText: context.tr('Diagnosis (optional)')),
          onChanged: (_) => setState(() {}),
        ),
      TextField(
        controller: _guidance,
        maxLines: 4,
        maxLength: 2000,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(labelText: context.tr('Guidance for the farmer (optional)')),
        onChanged: (_) => setState(() {}),
      ),
      if (!r.isDisease && _isTech) ...[
        _recommendationsCard(),
        const SizedBox(height: AppSpacing.md),
      ],
      TextField(
        key: const ValueKey('reviewer-note'),
        controller: _note,
        maxLines: 3,
        maxLength: 1000,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(
          labelText: context.tr('Reviewer note (required)'),
          hintText: context.tr('What you checked and why you chose this level'),
          helperText: context.tr(
              'Kept in the review history for technicians and agriculturists. The farmer reads the guidance, not this note.'),
          helperMaxLines: 3,
          errorText: _note.text.trim().isEmpty ||
                  reviewerNoteProblem(_note.text, diagnosis: _diagnosis.text, guidance: _guidance.text) == null
              ? null
              : context.tr(reviewerNoteProblem(_note.text, diagnosis: _diagnosis.text, guidance: _guidance.text)!),
          errorMaxLines: 3,
        ),
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: AppSpacing.sm),
      if (_validateBlocker case final String why)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: Text(context.tr(why), style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
        ),
      AppPrimaryButton(
        label: context.tr('Validate'),
        icon: Icons.verified_rounded,
        onPressed: _validateBlocker == null ? _submit : null,
      ),
    ];
  }

  /// Optional: approved library options for the confirmed pest that the
  /// reviewer recommends. They are recommendations, not applied treatments.
  Widget _recommendationsCard() {
    final options = _options;
    return AppCard(
      key: const ValueKey('recommendations-card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.tr('Recommendations (not applied treatments)'),
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          const SizedBox(height: 4),
          Text(
            context.tr('Optional. Pick approved options for this pest to recommend to the farmer. '
                'They show as recommendations, not as treatments the farmer applied.'),
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: AppSpacing.sm),
          if (!_libraryLoaded)
            const LinearProgressIndicator()
          else if (_pest == null)
            Text(context.tr('Name the pest in step 1 first.'), style: const TextStyle(color: AppColors.textMuted))
          else if (options.isEmpty)
            Text(context.tr('No approved options for this pest yet.'), style: const TextStyle(color: AppColors.textMuted))
          else
            for (final o in options)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                dense: true,
                value: _recommendedIds.contains(o.id),
                title: Text(o.title, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
                subtitle: Text(kOptionTypeNames[o.optionType] ?? o.optionType),
                onChanged: (v) => setState(() => v == true ? _recommendedIds.add(o.id) : _recommendedIds.remove(o.id)),
              ),
        ],
      ),
    );
  }

  Widget _editRow(String label, String value, VoidCallback onEdit, {required String action}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(flex: 2, child: Text(label, style: const TextStyle(color: AppColors.textMuted))),
            const SizedBox(width: AppSpacing.sm),
            Expanded(flex: 4, child: Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
            TextButton(onPressed: onEdit, child: Text(action, style: const TextStyle(fontWeight: FontWeight.w800))),
          ],
        ),
      );
}

class _LevelTile extends StatelessWidget {
  final String level;
  final bool selected;
  final bool suggested;
  final VoidCallback onTap;

  const _LevelTile({required this.level, required this.selected, required this.suggested, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = levelColor(level);
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: selected ? color : color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(color: selected ? color : color.withValues(alpha: 0.35), width: 1.5),
          ),
          child: Column(
            children: [
              Icon(
                selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                size: 20,
                color: selected ? AppColors.surface : color,
              ),
              const SizedBox(height: 4),
              Text(levelLabel(level),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: selected ? AppColors.surface : color, fontWeight: FontWeight.w800)),
              Text(
                suggested ? context.tr('Suggested') : ' ',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected ? AppColors.surface.withValues(alpha: 0.85) : AppColors.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StepTitle extends StatelessWidget {
  final int number;
  final String title;
  const _StepTitle({required this.number, required this.title});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.md),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: const BoxDecoration(color: AppColors.primaryDark, shape: BoxShape.circle),
              child: Text('$number',
                  style: const TextStyle(color: AppColors.brandGold, fontSize: 14, fontWeight: FontWeight.w800)),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(title, style: const TextStyle(fontFamily: AppFonts.display, fontSize: 18, fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      );
}
