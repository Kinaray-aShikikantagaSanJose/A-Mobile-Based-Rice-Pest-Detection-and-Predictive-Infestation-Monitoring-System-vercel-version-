import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../app_router.dart';
import '../models/record.dart';
import '../services/api_client.dart';
import '../services/sync_service.dart';
import '../theme.dart';
import '../utils/formatters.dart';
import '../widgets/app_widgets.dart';
import '../widgets/detection_photo.dart';
import '../widgets/scan_map.dart';
import '../widgets/shell_scope.dart';
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
  const F61ReviewObservation({super.key, required this.scanId});

  @override
  State<F61ReviewObservation> createState() => _F61ReviewObservationState();
}

enum _Decision { returnPhoto, validate, escalate }

class _F61ReviewObservationState extends State<F61ReviewObservation> {
  Record? _r;
  String? _error;

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

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _reason.dispose();
    _diagnosis.dispose();
    _guidance.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final r = await SyncService.record(widget.scanId);
      if (!mounted || r == null) return;
      final ai = r.ai;
      setState(() {
        _r = r;
        _pest = ai?.pest;
        _count = ai?.count;
        // No pest named: the reviewer names it and enters the count.
        _countable = ai?.count != null || ai?.pest == null;
      });
      if (!r.isDisease) _refreshSuggestion(immediate: true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
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

  // ---------------------------------------------------------------- step 1: confirm or correct

  Future<void> _correctPest() async {
    final pest = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(AppSpacing.hPad, 0, AppSpacing.hPad, AppSpacing.lg),
          children: [
            const Text('Which pest is it?', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
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
                const Text('How many insects?', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                const Text(
                  'Count only when the insects can be told apart. Otherwise mark it not countable.',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: ctrl,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(labelText: 'Count', prefixIcon: Icon(Icons.tag_rounded)),
                ),
                const SizedBox(height: AppSpacing.md),
                AppPrimaryButton(
                  label: 'Use this count',
                  onPressed: () {
                    final n = int.tryParse(ctrl.text);
                    if (n != null) Navigator.pop(ctx, (n, true));
                  },
                ),
                const SizedBox(height: AppSpacing.sm),
                AppSecondaryButton(label: 'Not countable', onPressed: () => Navigator.pop(ctx, (null, false))),
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
    });
    _refreshSuggestion(immediate: true);
  }

  void _refreshSuggestion({bool immediate = false}) {
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
        if (mounted) _snack(e.message);
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

  String? get _validateBlocker {
    final r = _r!;
    if (!r.isDisease) {
      if (_pest == null) return 'Name the pest in step 1 first.';
      if (_countable && _count == null) return 'Enter the count in step 1, or mark it not countable.';
    }
    if (_level == null) return 'Pick the infestation level.';
    return null;
  }

  bool get _overridden => _suggestion != null && _level != null && _level != _suggestion!.level;

  /// Confirm, then open the result screen while the decision is sent.
  Future<void> _submit() async {
    final r = _r!;
    final Map<String, dynamic> body;
    final String confirmTitle, confirmMessage, doneTitle, doneMessage;
    final IconData icon;
    final Color color;
    final summary = <(String, String)>[];
    switch (_decision) {
      case _Decision.returnPhoto:
        body = {'action': 'return', 'reason': _reason.text.trim()};
        confirmTitle = 'Return to the farmer?';
        confirmMessage = 'They will be asked to take the photo again.';
        doneTitle = 'Returned to the farmer';
        doneMessage = 'They will see your note and send a new photo.';
        icon = Icons.replay_rounded;
        color = AppColors.danger;
        summary.add(('Reason', _reason.text.trim()));
      case _Decision.escalate:
        body = {'action': 'escalate', 'reason': _reason.text.trim()};
        confirmTitle = 'Refer to an agriculturist?';
        confirmMessage = 'The case leaves your queue and goes to an agriculturist.';
        doneTitle = 'Sent to an agriculturist';
        doneMessage = 'An agriculturist will diagnose it and guide the farmer.';
        icon = Icons.forward_to_inbox_rounded;
        color = AppColors.purple;
        summary.add(('Reason', _reason.text.trim()));
      case _Decision.validate:
        final blocker = _validateBlocker;
        if (blocker != null) {
          _snack(blocker);
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
        };
        confirmTitle = 'Validate this report?';
        confirmMessage = 'The farmer gets the result and the treatment options for their crop stage.';
        doneTitle = 'Validated';
        doneMessage = 'The farmer has been notified and can now see the treatment options.';
        icon = Icons.verified_rounded;
        color = AppColors.primary;
        if (!r.isDisease) {
          summary.add(('Pest', pestName(_pest)));
          summary.add(('Count', _countable ? '$_count' : 'Not countable'));
        }
        summary.add(('Level', '${levelLabel(_level)}${_overridden ? ' (overridden)' : ''}'));
      case null:
        return;
    }
    final ok = await confirmAction(
      context,
      title: confirmTitle,
      message: confirmMessage,
      confirmLabel: 'Yes, send',
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
              title: r == null ? 'Review' : (r.isDisease ? 'Disease report' : 'Pest report'),
              subtitle: r == null ? null : 'Waiting ${waitingLabel(r.createdAt)} · #${r.id}',
              onBack: () => context.pop(false),
            ),
            Expanded(
              child: r == null
                  ? (_error == null
                      ? const Center(child: CircularProgressIndicator())
                      : AppEmptyState(
                          icon: Icons.cloud_off_rounded,
                          title: 'Can\'t open this report',
                          message: _error!,
                          actionLabel: 'Try again',
                          onAction: _load,
                          color: AppColors.danger,
                        ))
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(AppSpacing.hPad, AppSpacing.sm, AppSpacing.hPad, AppSpacing.xl),
                      children: [
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
                                StatusChip(state: r.state),
                                const SizedBox(width: AppSpacing.md),
                                const Expanded(child: Text('Already handled.')),
                              ],
                            ),
                          )
                        else ...[
                          _StepTitle(number: 1, title: r.isDisease ? 'Check the symptoms' : 'Check the model result'),
                          r.isDisease ? _diseaseCheck(r) : _pestCheck(r),
                          const SizedBox(height: AppSpacing.xl),
                          const _StepTitle(number: 2, title: 'Your decision'),
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
    );
  }

  List<Widget> _notices(Record r) => [
        if (r.resubmissionOf != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.md),
            child: InfoBanner(
              icon: Icons.replay_rounded,
              color: AppColors.primary,
              message: 'New photo for report #${r.resubmissionOf}, which was returned because the photo was unclear.',
            ),
          ),
        if (r.followUpOf != null)
          const Padding(
            padding: EdgeInsets.only(top: AppSpacing.md),
            child: InfoBanner(
              icon: Icons.healing_rounded,
              color: AppColors.sky,
              message: 'Follow-up check: this photo shows the field after a treatment.',
            ),
          ),
      ];

  Widget _infoCard(Record r) {
    final trap = r.monitoringMethod == 'Trap-based';
    Widget row(IconData icon, String k, String v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 17, color: AppColors.textMuted),
              const SizedBox(width: AppSpacing.sm),
              SizedBox(width: 96, child: Text(k, style: const TextStyle(color: AppColors.textMuted, fontSize: 13.5))),
              Expanded(child: SelectableText(v.isEmpty ? '—' : v, style: const TextStyle(height: 1.35, fontWeight: FontWeight.w600))),
            ],
          ),
        );
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          row(Icons.person_outline_rounded, 'Submitted by', '${r.submitterName}${r.submitterRole == 'technician' ? ' (technician)' : ''}'),
          if (r.submitterPhone.isNotEmpty) row(Icons.phone_outlined, 'Phone', r.submitterPhone),
          row(Icons.location_on_outlined, 'Area', [r.barangay, r.municipality].where((x) => x.isNotEmpty).join(', ')),
          row(Icons.schedule_rounded, 'Sent', formatDateTime(r.createdAt)),
          row(Icons.grass_rounded, 'Crop stage', r.cropStage),
          row(Icons.terrain_rounded, 'Land type', landTypeLabel(r.landType)),
          if (!r.isDisease) row(Icons.visibility_outlined, 'Method', r.monitoringMethod),
          if (trap) row(Icons.lightbulb_outline_rounded, 'Trap or lure', r.trapType),
          if (trap) row(Icons.bug_report_outlined, 'Target pest', r.targetPest),
          if (trap) row(Icons.wc_rounded, 'Target sex', r.targetSex),
          if (!r.isDisease) row(Icons.notes_rounded, 'Farmer notes', r.notes),
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
                        ? (ai?.message.isNotEmpty == true ? ai!.message : 'The model result names no pest.')
                        : 'Model result: ${ai!.pestLabel} · ${((ai.confidence ?? 0) * 100).round()}% sure · '
                            '${ai.count != null ? plural(ai.count!, 'insect') : 'not countable'}',
                    style: const TextStyle(height: 1.35, fontWeight: FontWeight.w600, fontSize: 13.5),
                  ),
                ),
              ],
            ),
          ),
          if (ai != null && aiNamed && ai.count == null && ai.message.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(ai.message, style: const TextStyle(color: AppColors.textMuted, fontSize: 13, height: 1.35)),
            ),
          const SizedBox(height: AppSpacing.md),
          _editRow('Pest', _pest == null ? 'Not named yet' : pestName(_pest), _correctPest,
              action: _pest == null ? 'Name it' : 'Correct'),
          const Divider(height: 1),
          _editRow('Count', _countable ? (_count == null ? 'Not entered yet' : '$_count') : 'Not countable', _correctCount,
              action: _countable && _count == null ? 'Enter' : 'Correct'),
          const SizedBox(height: AppSpacing.sm),
          if (_sameAsAi)
            const AppChip(label: 'Confirming the model result', color: AppColors.primary, icon: Icons.check_circle_rounded)
          else if (_pest != null)
            Row(
              children: [
                const AppChip(label: 'Corrected by you', color: AppColors.orange, icon: Icons.edit_rounded),
                const Spacer(),
                if (aiNamed) TextButton(onPressed: _resetToAi, child: const Text('Use the model result')),
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
            const Text('There is no model result for disease reports. Look at the photo and what the farmer describes.',
                style: TextStyle(color: AppColors.textMuted, fontSize: 13, height: 1.4)),
            const SizedBox(height: AppSpacing.md),
            const Text('Symptoms', style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            SelectableText(r.notes.isEmpty ? '—' : r.notes,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, height: 1.4)),
          ],
        ),
      );

  List<Widget> _decisions() => [
        ChoiceTile(
          icon: Icons.replay_rounded,
          title: 'Return',
          subtitle: 'The photo is unclear. The farmer retakes it.',
          selected: _decision == _Decision.returnPhoto,
          color: AppColors.danger,
          onTap: () => _choose(_Decision.returnPhoto),
        ),
        const SizedBox(height: AppSpacing.sm),
        ChoiceTile(
          icon: Icons.verified_rounded,
          title: 'Validate',
          subtitle: 'Confirm or override the infestation level.',
          selected: _decision == _Decision.validate,
          onTap: () => _choose(_Decision.validate),
        ),
        const SizedBox(height: AppSpacing.sm),
        ChoiceTile(
          icon: Icons.forward_to_inbox_rounded,
          title: 'Escalate',
          subtitle: 'Complex case. Refer it to an agriculturist.',
          selected: _decision == _Decision.escalate,
          color: AppColors.purple,
          onTap: () => _choose(_Decision.escalate),
        ),
      ];

  List<Widget> _decisionForm(Record r) => switch (_decision!) {
        _Decision.returnPhoto => _reasonForm(
            quick: const ['Photo too blurry', 'Too far away, move closer', 'Too dark', 'Insects not visible', 'Wrong photo'],
            hint: 'What should the farmer fix? They will see this.',
            button: 'Return to the farmer',
            icon: Icons.replay_rounded,
            color: AppColors.danger,
          ),
        _Decision.escalate => _reasonForm(
            quick: const ['Unclear what pest this is', 'Unusual damage', 'Possible outbreak', 'Not one of the four pests'],
            hint: 'Why does it need an agriculturist?',
            button: 'Refer to an agriculturist',
            icon: Icons.forward_to_inbox_rounded,
            color: AppColors.purple,
          ),
        _Decision.validate => _validateForm(r),
      };

  List<Widget> _reasonForm({
    required List<String> quick,
    required String hint,
    required String button,
    required IconData icon,
    required Color color,
  }) =>
      [
        const Text('Quick reasons', style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final q in quick)
              ChoiceChip(
                label: Text(q),
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
          decoration: InputDecoration(hintText: hint),
          onChanged: (_) => setState(() {}),
        ),
        AppPrimaryButton(
          label: button,
          icon: icon,
          color: color,
          onPressed: _reason.text.trim().isEmpty ? null : _submit,
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
              const Text('Damage you can see', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              if (s == null)
                const Padding(padding: EdgeInsets.all(AppSpacing.md), child: LinearProgressIndicator())
              else if (s.availableIndicators.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text('None listed for this pest.', style: TextStyle(color: AppColors.textMuted)),
                )
              else
                for (final i in s.availableIndicators)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    dense: true,
                    value: _indicators.contains(i),
                    title: Text(i, style: const TextStyle(fontSize: 14.5)),
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
            Row(
              children: [
                Expanded(
                  child: Text(r.isDisease ? 'How bad is it in the field?' : 'Infestation level',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                ),
                if (_level != null && s != null)
                  AppChip(
                    label: _overridden ? 'Overridden' : 'Suggested level',
                    color: _overridden ? AppColors.orange : AppColors.primary,
                    icon: _overridden ? Icons.edit_rounded : Icons.check_rounded,
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              s == null
                  ? 'Pick the level you see in the field.'
                  : 'Keep the suggested level to confirm it, or pick another to override it.',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
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
                  child: Text('• $reason', style: const TextStyle(fontSize: 12.5, height: 1.4, color: AppColors.textSecondary)),
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
          decoration: const InputDecoration(labelText: 'Diagnosis (optional)'),
          onChanged: (_) => setState(() {}),
        ),
      TextField(
        controller: _guidance,
        maxLines: 4,
        maxLength: 2000,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(labelText: 'Guidance for the farmer (optional)'),
        onChanged: (_) => setState(() {}),
      ),
      if (_validateBlocker case final String why)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: Text(why, style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
        ),
      AppPrimaryButton(
        label: 'Validate',
        icon: Icons.verified_rounded,
        onPressed: _validateBlocker == null ? _submit : null,
      ),
    ];
  }

  Widget _editRow(String label, String value, VoidCallback onEdit, {required String action}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            SizedBox(width: 64, child: Text(label, style: const TextStyle(color: AppColors.textMuted))),
            Expanded(child: Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
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
                  style: TextStyle(color: selected ? AppColors.surface : color, fontWeight: FontWeight.w800)),
              Text(
                suggested ? 'Suggested' : ' ',
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
            Text(title, style: const TextStyle(fontFamily: AppFonts.display, fontSize: 18, fontWeight: FontWeight.w800)),
          ],
        ),
      );
}
