import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;

import '../app_router.dart';
import '../controllers/auth_controller.dart';
import '../l10n/app_language.dart';
import '../models/record.dart';
import '../platform/local_files.dart';
import '../services/antique_geofence.dart';
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

  /// Barangay of the GPS point (offline lookup), shown on the location card
  /// only. The observation is filed under the person's saved area.
  GeoMatch? _geo;
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
    if (!_gps.hasFix) {
      _detectLocation(ask: false);
    } else {
      _lookupPlace(_gps); // a retake's saved location
    }
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
        title: Text(ctx.tr('Discard this observation?')),
        content: Text(ctx.tr('The photo you took will not be sent.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.tr('Keep going'))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ctx.tr('Discard'))),
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
      // The camera already saves its photo in this folder (phones and the
      // web): use that file instead of keeping a second copy of it.
      final String dest;
      if (p.isWithin(dir, path)) {
        dest = path;
      } else {
        await createLocalDir(dir);
        dest = p.join(dir, 'obs_${DateTime.now().microsecondsSinceEpoch}${p.extension(path)}');
        await copyLocalFile(path, dest);
      }
      if (!mounted) return;
      setState(() => _photo = dest);
      _next();
    } catch (e) {
      debugPrint('[Observation] could not persist camera photo: $e');
      if (mounted) _snack(context.tr('Could not save the photo on this device.'));
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
      if (mounted) _snack(context.tr('Could not open the gallery.'));
    }
  }

  Future<void> _detectLocation({required bool ask}) async {
    setState(() {
      _gps = const GpsResult(GpsStatus.detecting);
      _geo = null;
      _locationConfirmed = false;
      _landHint = null; // a new location gets a new land type suggestion
      _landHintError = null;
    });
    final r = await GpsService.getCurrentPosition(requestPermission: ask, precise: true);
    if (!mounted) return;
    setState(() => _gps = r);
    if (r.hasFix) _lookupPlace(r);
  }

  /// Which barangay the fix is in (bundled map, works offline). Only shown
  /// to the person: it never changes their saved municipality or barangay.
  Future<void> _lookupPlace(GpsResult gps) async {
    GeoMatch? match;
    try {
      match = await AntiqueGeofence.instance.locate(gps.lat!, gps.lng!, accuracyM: gps.accuracy);
    } catch (e) {
      debugPrint('[Observation] barangay lookup failed: $e');
    }
    // Ignore a late answer for a location that was replaced meanwhile.
    if (!mounted || !identical(gps, _gps)) return;
    setState(() => _geo = match);
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
      // English key; translated where it is shown.
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
    final withLocation = _gps.hasFix && !_skipLocation;
    final ok = await confirmAction(
      context,
      title: _isDisease ? context.tr('Send this disease report?') : context.tr('Send this observation?'),
      message: _isDisease
          ? context.tr('A technician will review your photo and description.')
          : context.tr('The app will check the photo for pests, then a technician confirms the result.'),
      confirmLabel: context.tr('Yes, send it'),
      summary: [
        (context.tr('Report'), _isDisease ? context.tr('Disease report') : context.tr('Pest report')),
        (context.tr('Land type'), landTypeLabel(_landType)),
        (context.tr('Crop stage'), context.tr(_stage!)), // stage key -> its label
        (context.tr('Location'), withLocation ? context.tr('Included') : context.tr('Not included')),
        if (!_isDisease)
          (
            context.tr('Checked by'),
            trap ? context.tr('Trap-based') : context.tr('Direct field observation'),
          ),
      ],
    );
    if (!ok || !mounted) return;
    HapticFeedback.mediumImpact();
    final o = OutboxObservation(
      clientUuid: newClientUuid(),
      reportType: _type!,
      imagePath: _photo!,
      lat: withLocation ? _gps.lat : null,
      lng: withLocation ? _gps.lng : null,
      gpsAccuracyM: withLocation ? _gps.accuracy : null,
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
                    ? context.tr('Retake photo')
                    : _isFollowUp
                        ? context.tr('Follow-up check')
                        : widget.args.presetType == 'disease'
                            ? context.tr('Disease report')
                            : context.tr('New Observation'),
                subtitle: context.tr('Step {n} of {total}', {'n': index, 'total': steps.length}),
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
                      children: [
                        MaxContentWidth(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: _body()),
                        ),
                      ],
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
          _Question(context.tr('What are you reporting?')),
          ChoiceTile(
            icon: Icons.bug_report_rounded,
            title: context.tr('Pest report'),
            subtitle: context.tr('Insects, eggs, or plants they have damaged. The app looks for insects in your photo.'),
            selected: _type == 'pest',
            onTap: () => _pickType('pest'),
          ),
          const SizedBox(height: AppSpacing.md),
          ChoiceTile(
            icon: Icons.coronavirus_outlined,
            title: context.tr('Disease report'),
            subtitle: context.tr('Spots, discolored or dying leaves, strange growth. A technician checks it.'),
            selected: _type == 'disease',
            onTap: () => _pickType('disease'),
          ),
        ];

      case _Step.photo:
        return [
          if (_isFollowUp) _FollowUpBanner(label: widget.args.followUpLabel),
          if (_isRetake) _RetakeBanner(original: _retakeOf!),
          _Question(context.tr('Take a clear photo')),
          Text(
            context.tr('Get close so the insects or damage fill the picture. Hold the phone steady.'),
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 15, height: 1.4),
          ),
          const SizedBox(height: AppSpacing.lg),
          if (_photo != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.md),
              child: AspectRatio(
                aspectRatio: 3 / 4,
                child: ColoredBox(
                  color: Colors.black,
                  child: localImage(
                    _photo!,
                    fit: kIsWeb ? BoxFit.contain : BoxFit.cover,
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            AppPrimaryButton(label: context.tr('Use this photo'), icon: Icons.check_rounded, onPressed: _next),
            const SizedBox(height: AppSpacing.md),
          ],
          AppSecondaryButton(
            label: _photo == null ? context.tr('Open the camera') : context.tr('Take it again'),
            icon: Icons.photo_camera_rounded,
            onPressed: _takePhoto,
          ),
          const SizedBox(height: AppSpacing.md),
          TextButton.icon(
            onPressed: _pickFromGallery,
            icon: const Icon(Icons.photo_library_outlined),
            label: Text(context.tr('Choose a photo from the gallery instead')),
          ),
        ];

      case _Step.location:
        return [
          _Question(context.tr('Is this your field?')),
          _LocationCard(gps: _gps, geo: _geo, onRetry: () => _detectLocation(ask: true)),
          const SizedBox(height: AppSpacing.lg),
          if (_gps.hasFix) ...[
            AppPrimaryButton(
              label: context.tr('Yes, this is my field'),
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
              label: context.tr('No, find my location again'),
              icon: Icons.my_location_rounded,
              onPressed: () => _detectLocation(ask: true),
            ),
          ] else if (_gps.status != GpsStatus.detecting) ...[
            AppSecondaryButton(
              label: context.tr('Continue without location'),
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
          _Question(context.tr('What kind of land is this field?')),
          if (_landHintLoading)
            AppCard(
              child: Row(
                children: [
                  const Icon(Icons.terrain_rounded, color: AppColors.primary),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(context.tr('Checking the elevation of your field…'),
                        style: const TextStyle(fontSize: 14.5)),
                  ),
                ],
              ),
            )
          else if (hint != null && group != null)
            InfoBanner(icon: Icons.terrain_rounded, color: AppColors.primary, message: _landHintReason(hint))
          else if (_landHintError != null || hint != null)
            InfoBanner(
              icon: Icons.terrain_rounded,
              color: AppColors.textSecondary,
              message: _landHintError != null ? context.tr(_landHintError!) : _landHintReason(hint!),
            )
          else if (!_gps.hasFix || _skipLocation)
            Text(
              context.tr('Without a location the app can\'t suggest one. Pick the land type yourself.'),
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 14.5, height: 1.4),
            ),
          const SizedBox(height: AppSpacing.lg),
          for (final (i, (key, label, help)) in kLandTypes.indexed) ...[
            if (i > 0) const SizedBox(height: AppSpacing.md),
            ChoiceTile(
              icon: const [Icons.landscape_rounded, Icons.water_drop_outlined, Icons.water_rounded][i],
              title: (group == 'upland' && key == 'upland') || (group == 'lowland' && key != 'upland')
                  ? context.tr('{label} (suggested)', {'label': label})
                  : label,
              subtitle: help,
              selected: _landType == key,
              onTap: () => _pickLandType(key),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          Text(
            context.tr('The suggestion comes from the elevation only. Change it if your field is different.'),
            style: const TextStyle(color: AppColors.textMuted, fontSize: 13, height: 1.4),
          ),
        ];

      case _Step.stage:
        return [
          _Question(context.tr('What stage is the rice?')),
          for (final (i, stage) in kCropStages.indexed) ...[
            if (i > 0) const SizedBox(height: AppSpacing.md),
            ChoiceTile(
              icon: const [Icons.grass_rounded, Icons.local_florist_rounded, Icons.grain_rounded][i],
              title: context.tr(stage), // the stored value stays English
              subtitle: kCropStageHints[stage],
              selected: _stage == stage,
              onTap: () => _pickStage(stage),
            ),
          ],
        ];

      case _Step.method:
        return [
          _Question(context.tr('How did you check?')),
          ChoiceTile(
            icon: Icons.visibility_rounded,
            title: context.tr('Direct field observation'),
            subtitle: context.tr('I looked at the plants'),
            selected: _method == 'direct',
            onTap: () => setState(() => _method = 'direct'),
          ),
          const SizedBox(height: AppSpacing.md),
          ChoiceTile(
            icon: Icons.lightbulb_outline_rounded,
            title: context.tr('Trap-based'),
            subtitle: context.tr('From a sticky trap, light trap or lure'),
            selected: _method == 'trap',
            onTap: () => setState(() => _method = 'trap'),
          ),
          if (_method == 'trap') ...[
            const SizedBox(height: AppSpacing.lg),
            Text(
              context.tr('Optional: add these only if you know them. The app never decides them on its own.'),
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 14, height: 1.4),
            ),
            const SizedBox(height: AppSpacing.md),
            _Dropdown(label: context.tr('Trap or lure type'), value: _trapType, options: kTrapTypes,
                onChanged: (v) => setState(() => _trapType = v)),
            const SizedBox(height: AppSpacing.md),
            _Dropdown(label: context.tr('Target pest'), value: _targetPest, options: kTargetPests,
                onChanged: (v) => setState(() => _targetPest = v)),
            const SizedBox(height: AppSpacing.md),
            _Dropdown(label: context.tr('Target sex (if known)'), value: _targetSex, options: kTargetSexes,
                onChanged: (v) => setState(() => _targetSex = v)),
          ],
          const SizedBox(height: AppSpacing.xl),
          AppPrimaryButton(label: context.tr('Continue'), onPressed: _next),
        ];

      case _Step.notes:
        final required = _isDisease;
        return [
          _Question(required ? context.tr('Describe what you see') : context.tr('Anything to add?')),
          Text(
            required
                ? context.tr('Required. For example: color of the spots, which part of the plant, how much of the field.')
                : context.tr('Optional. For example: how many plants are affected, what you noticed.'),
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 15, height: 1.4),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _notes,
            minLines: 4,
            maxLines: 8,
            maxLength: 1000,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: required ? context.tr('What you observed…') : context.tr('Notes (optional)'),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppPrimaryButton(
            label: required || _notes.text.trim().isNotEmpty ? context.tr('Continue') : context.tr('Skip'),
            onPressed: required && _notes.text.trim().length < 3 ? null : _next,
          ),
        ];

      case _Step.review:
        final trap = !_isDisease && _method == 'trap';
        return [
          _Question(context.tr('Ready to send?')),
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
                      _SummaryRow(context.tr('Photo'), context.tr('Taken'), onEdit: () => _edit(_Step.photo)),
                      _SummaryRow(
                        context.tr('Location'),
                        _gps.hasFix && !_skipLocation && _locationConfirmed
                            ? context.tr('Field confirmed on the map')
                            : context.tr('Not included'),
                        onEdit: () => _edit(_Step.location),
                      ),
                      _SummaryRow(context.tr('Land type'), _landType == null ? '—' : landTypeLabel(_landType),
                          onEdit: () => _edit(_Step.land)),
                      _SummaryRow(context.tr('Crop stage'), _stage == null ? '—' : context.tr(_stage!),
                          onEdit: () => _edit(_Step.stage)),
                      _SummaryRow(
                          context.tr('Report'),
                          _type == null
                              ? '—'
                              : _isDisease
                                  ? context.tr('Disease report')
                                  : context.tr('Pest report'),
                          onEdit: _typeFixed ? null : () => _edit(_Step.type)),
                      if (!_isDisease)
                        _SummaryRow(
                          context.tr('Checked by'),
                          trap
                              // Option values stay English; only their display is translated.
                              ? [
                                  context.tr('Trap-based'),
                                  for (final v in [_trapType, _targetPest, _targetSex])
                                    if (v != null) context.tr(v),
                                ].join(' · ')
                              : context.tr('Direct field observation'),
                          onEdit: () => _edit(_Step.method),
                        ),
                      _SummaryRow(context.tr('Notes'), _notes.text.trim().isEmpty ? '—' : _notes.text.trim(),
                          onEdit: () => _edit(_Step.notes)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          AppPrimaryButton(
            label: context.tr('Submit'),
            icon: Icons.send_rounded,
            onPressed: _submit,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            context.tr('No signal? That\'s fine. It is saved on your phone and sent when you are back in coverage.'),
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textMuted, fontSize: 13, height: 1.4),
          ),
        ];
    }
  }

  /// The server's land type reason, in the chosen language. It contains the
  /// elevation, so the translation is rebuilt from the same parts
  /// (rice-pest-api/app/land.py); English shows the server's text as is.
  String _landHintReason(Map<String, dynamic> hint) {
    final reason = '${hint['reason']}';
    if (context.lang == AppLang.en) return reason;
    final n = (hint['elevation_m'] as num?)?.round();
    if (n != null && hint['group'] == 'upland') {
      return context.tr(
          'About {n} m above sea level, which suggests upland. Change it if the field is a flooded paddy.', {'n': n});
    }
    if (n != null && hint['group'] == 'lowland') {
      return context.tr(
          'About {n} m above sea level, which suggests lowland. '
          'Pick rainfed or irrigated depending on where the water comes from.',
          {'n': n});
    }
    return context.tr(reason); // e.g. "Elevation could not be looked up. …"
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
                  label == null || label!.isEmpty
                      ? context.tr('How is the field now? This photo will be linked to your treatment.')
                      : context.tr('How is the field now? This photo will be linked to "{treatment}".',
                          {'treatment': label}),
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
    final what = original.isDisease
        ? context.tr('New photo for your disease report')
        : context.tr('New photo for your pest report');
    final number = original.id == null ? '' : ' #${original.id}';
    final why = reason.isEmpty
        ? context.tr('The technician could not see it clearly.')
        : context.tr('The technician said: "{reason}"', {'reason': reason});
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
              child: Text('$what$number. $why', style: const TextStyle(fontSize: 14, height: 1.4)),
            ),
          ],
        ),
      ),
    );
  }
}

class _LocationCard extends StatelessWidget {
  final GpsResult gps;

  /// Barangay lookup for the fix (null while looking or when it failed).
  final GeoMatch? geo;
  final VoidCallback onRetry;
  const _LocationCard({required this.gps, this.geo, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    if (gps.status == GpsStatus.detecting) {
      return AppCard(
        child: Row(
          children: [
            const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)),
            const SizedBox(width: AppSpacing.md),
            Expanded(child: Text(context.tr('Finding your location…'), style: const TextStyle(fontSize: 15))),
          ],
        ),
      );
    }
    if (gps.hasFix) {
      final lines = _placeLines(context);
      // The map keeps its place in the tree when the status arrives, so it
      // is not rebuilt.
      return ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ScanMap(
              markers: [ScanMarker(lat: gps.lat!, lng: gps.lng!)],
              height: 280,
              zoom: 16,
              interactive: true,
            ),
            if (lines.isNotEmpty)
              ColoredBox(
                color: AppColors.surface,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.md, 10, AppSpacing.md, AppSpacing.md),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: lines),
                ),
              ),
          ],
        ),
      );
    }
    final String why = switch (gps.status) {
      GpsStatus.serviceDisabled => context.tr('Location is turned off on your phone. Turn it on and we will try again.'),
      GpsStatus.permissionDenied => gps.deniedForever
          ? context.tr('Location permission is blocked for this app. You can allow it in your phone settings.')
          : context.tr('The app needs permission to use your location.'),
      _ => context.tr('We could not get your location. Move to an open area and try again.'),
    };
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.location_off_rounded, color: AppColors.orange),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(context.tr('No location yet'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(why, style: const TextStyle(color: AppColors.textSecondary, height: 1.4)),
          const SizedBox(height: AppSpacing.md),
          // Wraps onto two lines on narrow phones or with large text.
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              AppPrimaryButton(label: context.tr('Try again'), compact: true, expanded: false, onPressed: onRetry),
              if (gps.deniedForever)
                AppSecondaryButton(
                  label: context.tr('Open settings'),
                  compact: true,
                  expanded: false,
                  onPressed: GpsService.openAppSettings,
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// Where the fix is (barangay, municipality), how sure, and whether it is
  /// an older position. Shown only; the observation is still filed under the
  /// person's saved barangay. Nothing extra when the lookup failed.
  List<Widget> _placeLines(BuildContext context) {
    final m = geo;
    final place = m?.place;
    final accuracy = gps.accuracy?.round();
    final lines = <Widget>[];
    switch (m?.status) {
      case GeoStatus.inside when place != null:
        lines.add(_PlaceLine(
          icon: Icons.place_rounded,
          color: AppColors.primary,
          strong: true,
          text: context.tr('In {barangay}, {municipality}',
              {'barangay': place.barangay, 'municipality': place.municipality}),
        ));
        if (accuracy != null) {
          lines.add(_PlaceLine(
            icon: Icons.gps_fixed_rounded,
            text: context.tr('GPS accuracy about {n} m', {'n': accuracy}),
          ));
        }
      case GeoStatus.nearBoundary || GeoStatus.nearest when place != null:
        lines.add(_PlaceLine(
          icon: Icons.place_outlined,
          color: AppColors.orange,
          strong: true,
          text: context.tr('Near {barangay}, {municipality}',
              {'barangay': place.barangay, 'municipality': place.municipality}),
        ));
        lines.add(_PlaceLine(
          icon: Icons.info_outline_rounded,
          text: context.tr('Close to a barangay boundary.'),
        ));
      case GeoStatus.inaccurate:
        lines.add(_PlaceLine(
          icon: Icons.gps_not_fixed_rounded,
          color: AppColors.orange,
          text: context.tr(
            'The GPS is not accurate yet (about {n} m). Move to an open area and tap Try again.',
            {'n': (m!.accuracyM ?? gps.accuracy ?? 0).round()},
          ),
        ));
        lines.add(Padding(
          padding: const EdgeInsets.only(top: AppSpacing.xs, left: 26),
          child: Align(
            alignment: Alignment.centerLeft,
            child: AppSecondaryButton(
              label: context.tr('Try again'),
              icon: Icons.my_location_rounded,
              compact: true,
              expanded: false,
              onPressed: onRetry,
            ),
          ),
        ));
      case GeoStatus.outside:
        final session = AuthControllerImpl.instance.session;
        final saved = [session?.barangay ?? '', session?.municipality ?? '']
            .where((s) => s.trim().isNotEmpty)
            .join(', ');
        lines.add(_PlaceLine(
          icon: Icons.wrong_location_outlined,
          color: AppColors.orange,
          text: context.tr(
            'This location is outside Antique. The observation will still be sent and filed under your saved barangay ({place}).',
            {'place': saved.isEmpty ? context.tr("your account's area") : saved},
          ),
        ));
      default: // looking up, lookup failed, invalid point: nothing extra
        break;
    }
    if (gps.stale) {
      lines.add(_PlaceLine(icon: Icons.history_rounded, text: context.tr('Using your last known location.')));
    }
    return lines;
  }
}

/// One compact line on the location card: small icon + text.
class _PlaceLine extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;
  final bool strong;
  const _PlaceLine({required this.icon, required this.text, this.color = AppColors.textMuted, this.strong = false});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(icon, size: 18, color: color),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  fontSize: strong ? 15 : 13.5,
                  height: 1.35,
                  fontWeight: strong ? FontWeight.w700 : FontWeight.normal,
                  color: strong ? AppColors.textPrimary : AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      );
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
          DropdownMenuItem<String>(value: null, child: Text(context.tr('Not specified'))),
          // The value stays English (stored and sent); only the text is translated.
          for (final o in options) DropdownMenuItem<String>(value: o, child: Text(context.tr(o))),
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
            // Label and value share the row so long words wrap on narrow phones.
            Expanded(
              flex: 2,
              child: Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 13.5)),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(flex: 3, child: Text(value, style: const TextStyle(fontSize: 15, height: 1.35))),
            if (onEdit != null)
              InkWell(
                onTap: onEdit,
                borderRadius: BorderRadius.circular(AppRadius.sm),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  child: Text(context.tr('Change'),
                      style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 13.5)),
                ),
              ),
          ],
        ),
      );
}
