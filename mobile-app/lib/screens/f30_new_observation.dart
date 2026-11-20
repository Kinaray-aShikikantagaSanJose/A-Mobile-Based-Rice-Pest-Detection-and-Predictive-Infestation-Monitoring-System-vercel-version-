import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;

import '../app_router.dart';
import '../models/record.dart';
import '../platform/local_files.dart';
import '../services/api_client.dart';
import '../services/gps_service.dart';
import '../services/local_store.dart';
import '../services/sync_service.dart';
import '../theme.dart';
import '../utils/formatters.dart';
import '../widgets/app_widgets.dart';
import '../widgets/motion.dart';
import '../widgets/scan_map.dart';
import 'f46_observation_submitted.dart' show PendingSubmission;

/// How the observation flow was opened.
class ObserveArgs {
  /// Server id of the treatment this observation follows up on ("How is the
  /// field now?"). Follow-ups are pest observations and skip the type step.
  final int? followUpOf;
  final String? followUpLabel;

  /// A returned observation (photo unclear) the farmer is retaking. Its
  /// details are reused, so only the new photo is needed before sending.
  final Record? retakeOf;

  /// 'pest' or 'disease' when the report type was chosen before opening the
  /// flow (e.g. "Report a disease" on Home); the type step is skipped.
  final String? presetType;

  const ObserveArgs({this.followUpOf, this.followUpLabel, this.retakeOf, this.presetType});
}

enum _Step { photo, location, land, stage, type, method, notes, review }

/// New observation, one decision per screen:
/// 1 photo · 2 location · 3 land type · 4 crop stage · 5 pest or disease report ·
/// 6 monitoring method (pest only) · 7 notes · 8 submit.
class F30NewObservation extends StatefulWidget {
  final ObserveArgs args;
  const F30NewObservation({super.key, this.args = const ObserveArgs()});

  @override
  State<F30NewObservation> createState() => _F30NewObservationState();
}

class _F30NewObservationState extends State<F30NewObservation> {
  late _Step _step;
  String? _type; // pest | disease
  String? _photo;
  GpsResult _gps = const GpsResult(GpsStatus.detecting);
  bool _locationConfirmed = false;
  bool _skipLocation = false;
  String? _stage;

  /// Required: upland | rainfed_lowland | irrigated_lowland.
  String? _landType;

  /// Elevation-based suggestion from the server (null until looked up).
  Map<String, dynamic>? _landHint;
  bool _landHintLoading = false;
  String? _landHintError;
  String _method = 'direct';
  String? _trapType;
  String? _targetPest;
  String? _targetSex;
  final TextEditingController _notes = TextEditingController();
  StreamSubscription<bool>? _gpsService;

  /// Set when a step was opened with "Change" on the summary (or for a
  /// retake): finishing that step goes straight back to the summary.
  bool _returnToReview = false;

  bool get _isDisease => _type == 'disease';
  bool get _isFollowUp => widget.args.followUpOf != null;
  Record? get _retakeOf => widget.args.retakeOf;
  bool get _isRetake => _retakeOf != null;
  bool get _typeFixed => _isFollowUp || _isRetake || widget.args.presetType != null;

  List<_Step> get _steps => [
        _Step.photo,
        _Step.location,
        _Step.land,
        _Step.stage,
        if (!_typeFixed) _Step.type,
        if (!_isDisease) _Step.method,
        _Step.notes,
        _Step.review,
      ];

  @override
  void initState() {
    super.initState();
    _step = _Step.photo;
    final original = _retakeOf;
    if (original != null) {
      _prefillFrom(original);
    } else if (_isFollowUp) {
      _type = 'pest';
    } else if (widget.args.presetType != null) {
      _type = widget.args.presetType;
    }
    // The observation starts with the photo: open the camera straight away.
    WidgetsBinding.instance.addPostFrameCallback((_) => _takePhoto());
    // Look for GPS meanwhile so it's ready by the location step.
    if (!_gps.hasFix) _detectLocation(ask: false);
    _gpsService = GpsService.serviceStatusStream.listen((on) {
      if (on && !_gps.hasFix) _detectLocation(ask: false);
    });
  }

  @override
  void dispose() {
    _gpsService?.cancel();
    _notes.dispose();
    super.dispose();
  }

  /// A retake keeps everything from the returned observation except the photo.
  void _prefillFrom(Record r) {
    String? known(String v, List<String> options) => options.contains(v) ? v : null;
    _type = r.isDisease ? 'disease' : 'pest';
    _stage = kCropStages.contains(r.cropStage) ? r.cropStage : null;
    _landType = known(r.landType, [for (final (k, _, _) in kLandTypes) k]);
    _method = !r.isDisease && r.monitoringMethod == 'Trap-based' ? 'trap' : 'direct';
    _trapType = known(r.trapType, kTrapTypes);
    _targetPest = known(r.targetPest, kTargetPests);
    _targetSex = known(r.targetSex, kTargetSexes);
    _notes.text = r.notes;
    if (r.lat != null && r.lng != null) {
      _gps = GpsResult(GpsStatus.ok, r.lat, r.lng);
      _locationConfirmed = true;
    }
    // Missing details (e.g. an unknown crop stage) are asked in order.
    _returnToReview = _stage != null && _landType != null && (!r.isDisease || r.notes.trim().length >= 3);
  }

  // ---------------------------------------------------------------- navigation

  void _go(_Step step) {
    FocusScope.of(context).unfocus();
    setState(() => _step = step);
    if (step == _Step.location && !_gps.hasFix) _detectLocation(ask: true);
    if (step == _Step.land) _suggestLandType();
  }

  void _next() {
    if (_returnToReview && _photo != null) {
      _returnToReview = false;
      _go(_Step.review);
      return;
    }
    final steps = _steps;
    final i = steps.indexOf(_step);
    if (i < steps.length - 1) _go(steps[i + 1]);
  }

  /// "Change" on the summary: edit one answer, then come back.
  void _edit(_Step step) {
    _returnToReview = true;
    _go(step);
    if (step == _Step.photo) _takePhoto();
  }

  Future<bool> _back() async {
    if (_returnToReview && _photo != null && _step != _Step.review) {
      _returnToReview = false;
      _go(_Step.review);
      return false;
    }
    final steps = _steps;
    final i = steps.indexOf(_step);
    if (i > 0) {
      _go(steps[i - 1]);
      return false;
    }
    if (_photo == null) return true;
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard this observation?'),
        content: const Text('The photo you took will not be sent.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep going')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Discard')),
        ],
      ),
    );
    return leave == true;
  }

  // ---------------------------------------------------------------- actions

  void _pickType(String type) {
    setState(() => _type = type);
    // A disease report needs a description, even when changed from the summary.
    if (_returnToReview && type == 'disease' && _notes.text.trim().length < 3) {
      _go(_Step.notes);
      return;
    }
    _next();
  }

  /// The camera opens directly; the gallery is the fallback.
  Future<void> _takePhoto() async {
    final path = await context.push<String>(AppRouter.camera);
    if (!mounted || path == null) return;
    try {
      final dir = p.join(await documentsDirPath(), 'observations');
      await createLocalDir(dir);
      final dest = p.join(
        dir,
        'obs_${DateTime.now().microsecondsSinceEpoch}${p.extension(path)}',
      );
      await copyLocalFile(path, dest);
      if (!mounted) return;
      setState(() => _photo = dest);
      _next();
    } catch (e) {
      debugPrint('[Observation] could not persist camera photo: $e');
      _snack('Could not save the photo on this device.');
    }
  }

  Future<void> _pickFromGallery() async {
    try {
      final picked = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 2048, imageQuality: 90);
      if (picked == null || !mounted) return;
      final dir = p.join(await documentsDirPath(), 'observations');
      await createLocalDir(dir);
      final dest = p.join(dir, 'obs_${DateTime.now().microsecondsSinceEpoch}${pickedFileExtension(picked)}');
      await copyLocalFile(picked.path, dest);
      if (!mounted) return;
      setState(() => _photo = dest);
      _next();
    } catch (e) {
      _snack('Could not open the gallery.');
    }
  }

  Future<void> _detectLocation({required bool ask}) async {
    setState(() {
      _gps = const GpsResult(GpsStatus.detecting);
      _locationConfirmed = false;
      _landHint = null; // a new location gets a new land type suggestion
      _landHintError = null;
    });
    final r = await GpsService.getCurrentPosition(requestPermission: ask);
    if (mounted) setState(() => _gps = r);
  }

  /// Looks up the field's elevation once (needs the location and signal) and
  /// suggests a land type. The farmer or technician always picks it.
  Future<void> _suggestLandType() async {
    final useGps = _gps.hasFix && !_skipLocation;
    if (!useGps || _landHint != null || _landHintLoading) return;
    final lat = _gps.lat!, lng = _gps.lng!;
    setState(() {
      _landHintLoading = true;
      _landHintError = null;
    });
    try {
      final data = await ApiClient.get('/sync/land-type-suggestion', query: {
        'lat': lat.toStringAsFixed(6),
        'lng': lng.toStringAsFixed(6),
      }) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _landHint = data;
        // Upland can be suggested outright; lowland needs the water source.
        if (_landType == null && data['suggested'] is String) _landType = data['suggested'] as String;
      });
    } catch (_) {
      if (mounted) setState(() => _landHintError = 'No suggestion right now (no signal). Pick the land type yourself.');
    } finally {
      if (mounted) setState(() => _landHintLoading = false);
    }
  }

  void _pickLandType(String key) {
    setState(() => _landType = key);
    _next();
  }

  void _pickStage(String stage) {
    setState(() => _stage = stage);
    _next();
  }

  /// Asks for confirmation, then opens the result screen straight away: the
  /// observation is saved on the phone and sent while that screen shows.
  Future<void> _submit() async {
    if (_photo == null) return;
    // Anything still missing is asked for, then back to the summary.
    final missing = _landType == null
        ? _Step.land
        : _stage == null
        ? _Step.stage
        : _type == null
            ? _Step.type
            : _isDisease && _notes.text.trim().length < 3
                ? _Step.notes
                : null;
    if (missing != null) {
      _edit(missing);
      return;
    }
    final trap = !_isDisease && _method == 'trap';
    final ok = await confirmAction(
      context,
      title: _isDisease ? 'Send this disease report?' : 'Send this observation?',
      message: _isDisease
          ? 'A technician will review your photo and description.'
          : 'The app will check the photo for pests, then a technician confirms the result.',
      confirmLabel: 'Yes, send it',
      summary: [
        ('Report', _isDisease ? 'Disease report' : 'Pest report'),
        ('Land type', landTypeLabel(_landType)),
        ('Crop stage', _stage!),
        ('Location', _gps.hasFix && !_skipLocation ? 'Included' : 'Not included'),
        if (!_isDisease) ('Checked by', trap ? 'Trap-based' : 'Direct field observation'),
      ],
    );
    if (!ok || !mounted) return;
    HapticFeedback.mediumImpact();
    final o = OutboxObservation(
      clientUuid: newClientUuid(),
      reportType: _type!,
      imagePath: _photo!,
      lat: _gps.hasFix && !_skipLocation ? _gps.lat : null,
      lng: _gps.hasFix && !_skipLocation ? _gps.lng : null,
      cropStage: _stage!,
      method: _isDisease ? 'direct' : _method,
      trapType: trap ? (_trapType ?? '') : '',
      targetPest: trap ? (_targetPest ?? '') : '',
      targetSex: trap ? (_targetSex ?? '') : '',
      notes: _notes.text.trim(),
      followUpOf: widget.args.followUpOf,
      resubmissionOf: _retakeOf?.id,
      landType: _landType!,
      elevationM: (_landHint?['elevation_m'] as num?)?.toDouble(),
      createdAt: nowWithOffset(),
    );
    context.pushReplacement(AppRouter.submitted, extra: PendingSubmission(o, SyncService.submit(o)));
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  // ---------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final steps = _steps;
    final index = steps.indexOf(_step) + 1;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _back() && context.mounted) context.pop();
      },
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              AppHeader(
                title: _isRetake
                    ? 'Retake photo'
                    : _isFollowUp
                        ? 'Follow-up check'
                        : widget.args.presetType == 'disease'
                            ? 'Disease report'
                            : 'New Observation',
                subtitle: 'Step $index of ${steps.length}',
                onBack: () async {
                  if (await _back() && context.mounted) context.pop();
                },
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.hPad),
                child: _StepDots(count: steps.length, current: index - 1),
              ),
              Expanded(
                child: AppSwitcher(
                  child: KeyedSubtree(
                    key: ValueKey(_step),
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(AppSpacing.hPad, AppSpacing.lg, AppSpacing.hPad, AppSpacing.xl),
                      children: _body(),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _body() {
    switch (_step) {
      case _Step.type:
        return [
          const _Question('What are you reporting?'),
          ChoiceTile(
            icon: Icons.bug_report_rounded,
            title: 'Pest report',
            subtitle: 'Insects, eggs, or plants they have damaged. The app looks for insects in your photo.',
            selected: _type == 'pest',
            onTap: () => _pickType('pest'),
          ),
          const SizedBox(height: AppSpacing.md),
          ChoiceTile(
            icon: Icons.coronavirus_outlined,
            title: 'Disease report',
            subtitle: 'Spots, discolored or dying leaves, strange growth. A technician checks it.',
            selected: _type == 'disease',
            onTap: () => _pickType('disease'),
          ),
        ];

      case _Step.photo:
        return [
          if (_isFollowUp) _FollowUpBanner(label: widget.args.followUpLabel),
          if (_isRetake) _RetakeBanner(original: _retakeOf!),
          const _Question('Take a clear photo'),
          const Text(
            'Get close so the insects or damage fill the picture. Hold the phone steady.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 15, height: 1.4),
          ),
          const SizedBox(height: AppSpacing.lg),
          if (_photo != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.md),
              child: AspectRatio(aspectRatio: 3 / 4, child: localImage(_photo!, fit: BoxFit.cover)),
            ),
            const SizedBox(height: AppSpacing.lg),
            AppPrimaryButton(label: 'Use this photo', icon: Icons.check_rounded, onPressed: _next),
            const SizedBox(height: AppSpacing.md),
          ],
          AppSecondaryButton(
            label: _photo == null ? 'Open the camera' : 'Take it again',
            icon: Icons.photo_camera_rounded,
            onPressed: _takePhoto,
          ),
          const SizedBox(height: AppSpacing.md),
          TextButton.icon(
            onPressed: _pickFromGallery,
            icon: const Icon(Icons.photo_library_outlined),
            label: const Text('Choose a photo from the gallery instead'),
          ),
        ];

      case _Step.location:
        return [
          const _Question('Is this your field?'),
          _LocationCard(gps: _gps, onRetry: () => _detectLocation(ask: true)),
          const SizedBox(height: AppSpacing.lg),
          if (_gps.hasFix) ...[
            AppPrimaryButton(
              label: 'Yes, this is my field',
              icon: Icons.check_rounded,
              onPressed: () {
                setState(() {
                  _locationConfirmed = true;
                  _skipLocation = false;
                });
                _next();
              },
            ),
            const SizedBox(height: AppSpacing.md),
            AppSecondaryButton(
              label: 'No, find my location again',
              icon: Icons.my_location_rounded,
              onPressed: () => _detectLocation(ask: true),
            ),
          ] else if (_gps.status != GpsStatus.detecting) ...[
            AppSecondaryButton(
              label: 'Continue without location',
              onPressed: () {
                setState(() => _skipLocation = true);
                _next();
              },
            ),
          ],
        ];

      case _Step.land:
        final hint = _landHint;
        final group = hint?['group'] as String?;
        return [
          const _Question('What kind of land is this field?'),
          if (_landHintLoading)
            const AppCard(
              child: Row(
                children: [
                  Icon(Icons.terrain_rounded, color: AppColors.primary),
                  SizedBox(width: AppSpacing.md),
                  Expanded(child: Text('Checking the elevation of your field…', style: TextStyle(fontSize: 14.5))),
                ],
              ),
            )
          else if (hint != null && group != null)
            InfoBanner(icon: Icons.terrain_rounded, color: AppColors.primary, message: '${hint['reason']}')
          else if (_landHintError != null || hint != null)
            InfoBanner(
              icon: Icons.terrain_rounded,
              color: AppColors.textSecondary,
              message: _landHintError ?? '${hint!['reason']}',
            )
          else if (!_gps.hasFix || _skipLocation)
            const Text(
              'Without a location the app can\'t suggest one. Pick the land type yourself.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 14.5, height: 1.4),
            ),
          const SizedBox(height: AppSpacing.lg),
          for (final (i, (key, label, help)) in kLandTypes.indexed) ...[
            if (i > 0) const SizedBox(height: AppSpacing.md),
            ChoiceTile(
              icon: const [Icons.landscape_rounded, Icons.water_drop_outlined, Icons.water_rounded][i],
              title: (group == 'upland' && key == 'upland') || (group == 'lowland' && key != 'upland')
                  ? '$label (suggested)'
                  : label,
              subtitle: help,
              selected: _landType == key,
              onTap: () => _pickLandType(key),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          const Text(
            'The suggestion comes from the elevation only. Change it if your field is different.',
            style: TextStyle(color: AppColors.textMuted, fontSize: 13, height: 1.4),
          ),
        ];

      case _Step.stage:
        return [
          const _Question('What stage is the rice?'),
          for (final (i, stage) in kCropStages.indexed) ...[
            if (i > 0) const SizedBox(height: AppSpacing.md),
            ChoiceTile(
              icon: const [Icons.grass_rounded, Icons.local_florist_rounded, Icons.grain_rounded][i],
              title: stage,
              subtitle: kCropStageHints[stage],
              selected: _stage == stage,
              onTap: () => _pickStage(stage),
            ),
          ],
        ];

      case _Step.method:
        return [
          const _Question('How did you check?'),
          ChoiceTile(
            icon: Icons.visibility_rounded,
            title: 'Direct field observation',
            subtitle: 'I looked at the plants',
            selected: _method == 'direct',
            onTap: () => setState(() => _method = 'direct'),
          ),
          const SizedBox(height: AppSpacing.md),
          ChoiceTile(
            icon: Icons.lightbulb_outline_rounded,
            title: 'Trap-based',
            subtitle: 'From a sticky trap, light trap or lure',
            selected: _method == 'trap',
            onTap: () => setState(() => _method = 'trap'),
          ),
          if (_method == 'trap') ...[
            const SizedBox(height: AppSpacing.lg),
            const Text(
              'Optional: add these only if you know them. The app never decides them on its own.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 14, height: 1.4),
            ),
            const SizedBox(height: AppSpacing.md),
            _Dropdown(label: 'Trap or lure type', value: _trapType, options: kTrapTypes,
                onChanged: (v) => setState(() => _trapType = v)),
            const SizedBox(height: AppSpacing.md),
            _Dropdown(label: 'Target pest', value: _targetPest, options: kTargetPests,
                onChanged: (v) => setState(() => _targetPest = v)),
            const SizedBox(height: AppSpacing.md),
            _Dropdown(label: 'Target sex (if known)', value: _targetSex, options: kTargetSexes,
                onChanged: (v) => setState(() => _targetSex = v)),
          ],
          const SizedBox(height: AppSpacing.xl),
          AppPrimaryButton(label: 'Continue', onPressed: _next),
        ];

      case _Step.notes:
        final required = _isDisease;
        return [
          _Question(required ? 'Describe what you see' : 'Anything to add?'),
          Text(
            required
                ? 'Required. For example: color of the spots, which part of the plant, how much of the field.'
                : 'Optional. For example: how many plants are affected, what you noticed.',
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 15, height: 1.4),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _notes,
            minLines: 4,
            maxLines: 8,
            maxLength: 1000,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(hintText: required ? 'What you observed…' : 'Notes (optional)'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppPrimaryButton(
            label: required || _notes.text.trim().isNotEmpty ? 'Continue' : 'Skip',
            onPressed: required && _notes.text.trim().length < 3 ? null : _next,
          ),
        ];

      case _Step.review:
        final trap = !_isDisease && _method == 'trap';
        return [
          const _Question('Ready to send?'),
          if (_isFollowUp) _FollowUpBanner(label: widget.args.followUpLabel),
          if (_isRetake) _RetakeBanner(original: _retakeOf!),
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                if (_photo != null)
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.md)),
                    child: AspectRatio(aspectRatio: 16 / 10, child: localImage(_photo!, fit: BoxFit.cover)),
                  ),
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    children: [
                      _SummaryRow('Photo', 'Taken', onEdit: () => _edit(_Step.photo)),
                      _SummaryRow(
                        'Location',
                        _gps.hasFix && !_skipLocation && _locationConfirmed ? 'Field confirmed on the map' : 'Not included',
                        onEdit: () => _edit(_Step.location),
                      ),
                      _SummaryRow('Land type', _landType == null ? '—' : landTypeLabel(_landType),
                          onEdit: () => _edit(_Step.land)),
                      _SummaryRow('Crop stage', _stage ?? '—', onEdit: () => _edit(_Step.stage)),
                      _SummaryRow('Report', _type == null ? '—' : _isDisease ? 'Disease report' : 'Pest report',
                          onEdit: _typeFixed ? null : () => _edit(_Step.type)),
                      if (!_isDisease)
                        _SummaryRow(
                          'Checked by',
                          trap
                              ? ['Trap-based', _trapType, _targetPest, _targetSex].whereType<String>().join(' · ')
                              : 'Direct field observation',
                          onEdit: () => _edit(_Step.method),
                        ),
                      _SummaryRow('Notes', _notes.text.trim().isEmpty ? '—' : _notes.text.trim(),
                          onEdit: () => _edit(_Step.notes)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          AppPrimaryButton(
            label: 'Submit',
            icon: Icons.send_rounded,
            onPressed: _submit,
          ),
          const SizedBox(height: AppSpacing.md),
          const Text(
            'No signal? That\'s fine. It is saved on your phone and sent when you are back in coverage.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textMuted, fontSize: 13, height: 1.4),
          ),
        ];
    }
  }
}

/// One segment per step: done steps filled, the current one highlighted.
class _StepDots extends StatelessWidget {
  final int count;
  final int current;
  const _StepDots({required this.count, required this.current});

  @override
  Widget build(BuildContext context) => Row(
        children: [
          for (var i = 0; i < count; i++) ...[
            if (i > 0) const SizedBox(width: 5),
            Expanded(
              child: AnimatedContainer(
                duration: AppMotion.medium,
                curve: AppMotion.curve,
                height: 6,
                decoration: BoxDecoration(
                  color: i < current
                      ? AppColors.primary
                      : i == current
                          ? AppColors.brandGold
                          : AppColors.border,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
              ),
            ),
          ],
        ],
      );
}

class _Question extends StatelessWidget {
  final String text;
  const _Question(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.md),
        child: Text(
          text,
          style: const TextStyle(
            fontFamily: AppFonts.display,
            fontSize: 25,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
            height: 1.2,
          ),
        ),
      );
}

class _FollowUpBanner extends StatelessWidget {
  final String? label;
  const _FollowUpBanner({this.label});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.lg),
        child: AppCard(
          tinted: true,
          child: Row(
            children: [
              const Icon(Icons.healing_rounded, color: AppColors.primary),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  'How is the field now? This photo will be linked to '
                  '${label == null || label!.isEmpty ? 'your treatment' : '"$label"'}.',
                  style: const TextStyle(fontSize: 14, height: 1.4),
                ),
              ),
            ],
          ),
        ),
      );
}

class _RetakeBanner extends StatelessWidget {
  final Record original;
  const _RetakeBanner({required this.original});

  @override
  Widget build(BuildContext context) {
    final reason = original.returnReason.trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: AppCard(
        tinted: true,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.replay_rounded, color: AppColors.primary),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                'New photo for your ${original.isDisease ? 'disease' : 'pest'} report'
                '${original.id == null ? '' : ' #${original.id}'}. '
                '${reason.isEmpty ? 'The technician could not see it clearly.' : 'The technician said: "$reason"'}',
                style: const TextStyle(fontSize: 14, height: 1.4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LocationCard extends StatelessWidget {
  final GpsResult gps;
  final VoidCallback onRetry;
  const _LocationCard({required this.gps, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    if (gps.status == GpsStatus.detecting) {
      return const AppCard(
        child: Row(
          children: [
            SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)),
            SizedBox(width: AppSpacing.md),
            Expanded(child: Text('Finding your location…', style: TextStyle(fontSize: 15))),
          ],
        ),
      );
    }
    if (gps.hasFix) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: ScanMap(
          markers: [ScanMarker(lat: gps.lat!, lng: gps.lng!)],
          height: 280,
          zoom: 16,
          interactive: true,
        ),
      );
    }
    final String why = switch (gps.status) {
      GpsStatus.serviceDisabled => 'Location is turned off on your phone. Turn it on and we will try again.',
      GpsStatus.permissionDenied => gps.deniedForever
          ? 'Location permission is blocked for this app. You can allow it in your phone settings.'
          : 'The app needs permission to use your location.',
      _ => 'We could not get your location. Move to an open area and try again.',
    };
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.location_off_rounded, color: AppColors.orange),
              SizedBox(width: AppSpacing.sm),
              Text('No location yet', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(why, style: const TextStyle(color: AppColors.textSecondary, height: 1.4)),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              AppPrimaryButton(label: 'Try again', compact: true, expanded: false, onPressed: onRetry),
              if (gps.deniedForever) ...[
                const SizedBox(width: AppSpacing.sm),
                AppSecondaryButton(
                  label: 'Open settings',
                  compact: true,
                  expanded: false,
                  onPressed: GpsService.openAppSettings,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _Dropdown extends StatelessWidget {
  final String label;
  final String? value;
  final List<String> options;
  final ValueChanged<String?> onChanged;

  const _Dropdown({required this.label, required this.value, required this.options, required this.onChanged});

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String>(
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(labelText: label),
        items: [
          const DropdownMenuItem<String>(value: null, child: Text('Not specified')),
          for (final o in options) DropdownMenuItem<String>(value: o, child: Text(o)),
        ],
        onChanged: onChanged,
      );
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback? onEdit;
  const _SummaryRow(this.label, this.value, {this.onEdit});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 96,
              child: Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 13.5)),
            ),
            Expanded(child: Text(value, style: const TextStyle(fontSize: 15, height: 1.35))),
            if (onEdit != null)
              InkWell(
                onTap: onEdit,
                borderRadius: BorderRadius.circular(AppRadius.sm),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  child: Text('Change',
                      style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 13.5)),
                ),
              ),
          ],
        ),
      );
}
