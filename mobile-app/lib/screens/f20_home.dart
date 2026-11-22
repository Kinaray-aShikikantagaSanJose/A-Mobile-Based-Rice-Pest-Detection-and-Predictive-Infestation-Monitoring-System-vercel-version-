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
import '../widgets/account_sheet.dart';
import '../widgets/language_button.dart';
import '../widgets/app_widgets.dart';
import '../widgets/motion.dart';
import '../widgets/shell_scope.dart';
import 'f30_new_observation.dart' show ObserveArgs;

/// Home dashboard for farmers and technicians: who and where you are, the
/// pest scan, what needs your attention, and how your field has been doing.
/// Technicians also see their validation queue and a shortcut to the map.
class F20Home extends StatefulWidget {
  const F20Home({super.key});

  @override
  State<F20Home> createState() => _F20HomeState();
}

class _F20HomeState extends State<F20Home> {
  List<Record> _records = const [];
  List<(Record, TreatmentInfo)> _followUps = const [];
  bool _loaded = false;
  bool _sending = false;

  // Technicians
  int? _pestQueue;
  int? _diseaseQueue;
  String? _oldestWaiting;
  String? _queueError;

  bool get _isTech => AuthControllerImpl.instance.role == AppRole.technician;

  @override
  void initState() {
    super.initState();
    SyncService.revision.addListener(_load);
    _load();
    SyncService.refreshBadge();
    if (_isTech) _loadQueue();
  }

  @override
  void dispose() {
    SyncService.revision.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final records = await SyncService.records();
      final followUps = await SyncService.dueFollowUps();
      if (!mounted) return;
      setState(() {
        _records = records;
        _followUps = followUps;
        _loaded = true;
      });
    } catch (e) {
      // No local database (e.g. first start failed): show an empty dashboard.
      debugPrint('[Home] could not read records: $e');
      if (mounted) setState(() => _loaded = true);
    }
  }

  Future<void> _loadQueue() async {
    try {
      final results = await Future.wait([SyncService.queue('pest'), SyncService.queue('disease')]);
      final all = [...results[0], ...results[1]]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      if (!mounted) return;
      setState(() {
        _pestQueue = results[0].length;
        _diseaseQueue = results[1].length;
        _oldestWaiting = all.isEmpty ? null : waitingLabel(all.first.createdAt);
        _queueError = null;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _queueError = e.isOffline ? 'No signal. Pull down to try again.' : e.message);
    }
  }

  Future<void> _refresh() async {
    await SyncService.syncAll();
    await _load();
    if (_isTech) await _loadQueue();
  }

  Future<void> _sendNow() async {
    setState(() => _sending = true);
    await SyncService.syncAll();
    if (!mounted) return;
    setState(() => _sending = false);
    if (_records.any((r) => !r.uploaded)) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(context.tr('Still no signal. They will be sent automatically.'))));
    }
  }

  void _openTab(String tab, String fallbackRoute) {
    if (!ShellScope.tryGoTab(context, tab)) context.push(fallbackRoute);
  }

  @override
  Widget build(BuildContext context) {
    final waiting = _records.where((r) => !r.uploaded).length;
    return Scaffold(
      body: Column(
        children: [
          _Hero(records: _records, loaded: _loaded),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.hPad,
                      AppSpacing.lg,
                      AppSpacing.hPad,
                      AppSpacing.xl,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: staggered([
                        if (waiting > 0)
                          Padding(
                            padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                            child: InfoBanner(
                              icon: Icons.cloud_upload_outlined,
                              message: context.tr(
                                waiting == 1
                                    ? '{n} observation saved on this phone, waiting for signal.'
                                    : '{n} observations saved on this phone, waiting for signal.',
                                {'n': waiting},
                              ),
                              actionLabel: context.tr('Send now'),
                              busy: _sending,
                              onAction: _sendNow,
                            ),
                          ),
                        const _ScanCard(),
                        if (_isTech) ...[
                          const SizedBox(height: AppSpacing.lg),
                          _QueueCard(
                            pest: _pestQueue,
                            disease: _diseaseQueue,
                            oldest: _oldestWaiting,
                            error: _queueError,
                            onOpen: () => _openTab(AppTab.queue, AppRouter.queue),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          Row(
                            children: [
                              Expanded(
                                child: _Shortcut(
                                  icon: Icons.map_rounded,
                                  color: AppColors.sky,
                                  title: context.tr('Local map'),
                                  subtitle: context.tr('Reports near you'),
                                  onTap: () => _openTab(AppTab.map, AppRouter.map),
                                ),
                              ),
                              const SizedBox(width: AppSpacing.md),
                              Expanded(
                                child: _Shortcut(
                                  icon: Icons.healing_rounded,
                                  color: AppColors.purple,
                                  title: context.tr('Treatments'),
                                  subtitle: context.tr('Options & follow-ups'),
                                  onTap: () => context.push(AppRouter.treatments),
                                ),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: AppSpacing.md),
                        _Shortcut(
                          icon: Icons.menu_book_rounded,
                          color: AppColors.primary,
                          title: context.tr('What to look for'),
                          subtitle: context.tr('Pests, damage and crop stages'),
                          onTap: () => context.push(AppRouter.guide),
                        ),
                        ..._attention(),
                        const SizedBox(height: AppSpacing.xl),
                        _ScanHistory(records: _records),
                        ..._treatmentSuccess(),
                        ..._recent(),
                      ]),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- needs attention

  List<Widget> _attention() {
    final cards = <Widget>[
      for (final (rec, t) in _followUps)
        _AttentionCard(
          icon: Icons.healing_rounded,
          color: AppColors.primary,
          title: context.tr('How is the field now?'),
          body: context.tr(
            'You applied "{treatment}" on {date}. Take a photo so your technician can see if it worked.',
            {'treatment': t.treatment, 'date': formatShortDate(t.appliedAt)},
          ),
          action: context.tr('Check the field'),
          onTap: () => context.push(
            AppRouter.observe,
            extra: ObserveArgs(followUpOf: t.id, followUpLabel: t.treatment),
          ),
          subtitle: rec.title,
        ),
      for (final r in _records.where((r) => r.state == RecordState.returned && r.resubmittedAs == null && r.isMine))
        _AttentionCard(
          icon: Icons.replay_rounded,
          color: AppColors.danger,
          title: context.tr('Retake needed'),
          body: r.returnReason.isEmpty
              ? context.tr('Your technician could not see the photo clearly.')
              : context.tr('Your technician says: "{reason}"', {'reason': r.returnReason}),
          action: context.tr('Open the report'),
          onTap: () => context.push(AppRouter.record, extra: r),
          subtitle: context.tr(
            r.isDisease ? 'Disease report · {when}' : 'Pest report · {when}',
            {'when': formatRelativeDay(r.createdAt)},
          ),
        ),
      for (final r in _records.where(_readyForTreatment))
        _AttentionCard(
          icon: Icons.verified_rounded,
          color: levelColor(r.level ?? r.confirmed?.level),
          title: context.tr(
            '{title}: {level} infestation',
            {'title': r.title, 'level': levelLabel(r.level ?? r.confirmed?.level)},
          ),
          body: context.tr('Validated by your technician. See the treatment options for your crop stage.'),
          action: context.tr('See treatment options'),
          onTap: () => context.push(AppRouter.record, extra: r),
          subtitle: formatRelativeDay(r.createdAt),
        ),
    ];
    if (cards.isEmpty) return const [];
    return [
      const SizedBox(height: AppSpacing.xl),
      AppSectionHeader(
        title: context.tr('Needs your attention'),
        trailing: AppChip(label: '${cards.length}', color: AppColors.danger),
        actionLabel: cards.length > 3 ? context.tr('See all') : null,
        onAction: () => _openTab(AppTab.treatments, AppRouter.treatments),
      ),
      const SizedBox(height: AppSpacing.md),
      for (final c in cards.take(3)) ...[c, const SizedBox(height: AppSpacing.md)],
    ];
  }

  /// Validated pest report without a logged treatment, from the last three weeks.
  static bool _readyForTreatment(Record r) {
    if (r.state != RecordState.validated || r.isDisease || !r.isMine || r.treatments.isNotEmpty) return false;
    final created = parseLocal(r.createdAt);
    return created != null && DateTime.now().difference(created).inDays <= 21;
  }

  // ---------------------------------------------------------------- treatment success

  List<Widget> _treatmentSuccess() {
    final byId = {for (final r in _records) if (r.id != null) r.id!: r};
    var logged = 0, followedUp = 0, evaluated = 0, improved = 0;
    String? lastTreated;
    for (final r in _records) {
      for (final t in r.treatments) {
        logged++;
        lastTreated ??= r.title;
        if (t.followUpScanId == null) continue;
        followedUp++;
        final after = byId[t.followUpScanId];
        final before = r.level ?? r.confirmed?.level;
        final now = after?.level ?? after?.confirmed?.level;
        if (before == null || now == null) continue;
        evaluated++;
        if (now == 'LOW' || _rank(now) < _rank(before)) improved++;
      }
    }
    if (logged == 0) return const [];
    final bool haveOutcome = evaluated > 0;
    final double value = haveOutcome ? improved / evaluated : followedUp / logged;
    return [
      const SizedBox(height: AppSpacing.md),
      AppCard(
        onTap: () => _openTab(AppTab.treatments, AppRouter.treatments),
        child: Row(
          children: [
            _Ring(value: value, color: haveOutcome ? AppColors.success : AppColors.primary),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    haveOutcome ? context.tr('Treatment success') : context.tr('Follow-ups done'),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    haveOutcome
                        ? context.tr(
                            evaluated == 1
                                ? '{a} of {b} treated field improved after the follow-up check.'
                                : '{a} of {b} treated fields improved after the follow-up check.',
                            {'a': improved, 'b': evaluated},
                          )
                        : context.tr(
                            logged == 1
                                ? '{a} of {b} treatment checked again. Follow-ups show if a treatment worked.'
                                : '{a} of {b} treatments checked again. Follow-ups show if a treatment worked.',
                            {'a': followedUp, 'b': logged},
                          ),
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.4),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ];
  }

  static int _rank(String level) => const {'LOW': 1, 'MEDIUM': 2, 'HIGH': 3}[level.toUpperCase()] ?? 0;

  // ---------------------------------------------------------------- recent

  List<Widget> _recent() {
    if (!_loaded) {
      return const [SizedBox(height: AppSpacing.xl), SkeletonList(rows: 3)];
    }
    if (_records.isEmpty) return const [];
    return [
      const SizedBox(height: AppSpacing.xl),
      AppSectionHeader(
        title: context.tr('Recent observations'),
        actionLabel: context.tr('See all'),
        onAction: () => _openTab(AppTab.records, AppRouter.records),
      ),
      const SizedBox(height: AppSpacing.md),
      for (final r in _records.take(3)) ...[
        RecordTile(record: r, onTap: () => context.push(AppRouter.record, extra: r)),
        const SizedBox(height: AppSpacing.md),
      ],
    ];
  }
}

// ---------------------------------------------------------------- hero

class _Hero extends StatelessWidget {
  final List<Record> records;
  final bool loaded;
  const _Hero({required this.records, required this.loaded});

  static String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning,';
    if (h < 18) return 'Good afternoon,';
    return 'Good evening,';
  }

  @override
  Widget build(BuildContext context) {
    final s = AuthControllerImpl.instance.session;
    final first = (s?.name ?? '').trim().split(' ').first;
    final place = [s?.barangay ?? '', s?.municipality ?? ''].where((x) => x.isNotEmpty).join(', ');
    final isTech = s?.role == AppRole.technician;
    final validated = records.where((r) => r.state == RecordState.validated).length;
    final inReview = records
        .where((r) => r.uploaded && r.state != RecordState.validated && r.state != RecordState.noPests)
        .length;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Container(
        decoration: const BoxDecoration(
          gradient: kHeroGradient,
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(30)),
        ),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.hPad, AppSpacing.md, AppSpacing.hPad, AppSpacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const AccountButton(onDark: true),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(context.tr(_greeting()), style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 13.5)),
                          Text(
                            first.isEmpty ? context.tr('Welcome') : first,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontFamily: AppFonts.display,
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              height: 1.15,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    // Language: English / Filipino / Kinaray-a.
                    const LanguageButton(dark: true),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    _HeroChip(icon: Icons.location_on_rounded, label: place.isEmpty ? 'Antique' : place),
                    _HeroChip(
                      icon: isTech ? Icons.engineering_rounded : Icons.agriculture_rounded,
                      label: isTech ? context.tr('Technician') : context.tr('Farmer'),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                Row(
                  children: [
                    _HeroStat(
                      value: loaded ? records.length : null,
                      label: context.tr('Observations'),
                      icon: Icons.photo_library_rounded,
                      colors: const [Color(0xFF0EA5E9), Color(0xFF2563EB)],
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    _HeroStat(
                      value: loaded ? validated : null,
                      label: context.tr('Validated'),
                      icon: Icons.verified_rounded,
                      colors: const [Color(0xFF22C55E), Color(0xFF0F9F6E)],
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    _HeroStat(
                      value: loaded ? inReview : null,
                      label: context.tr('In review'),
                      icon: Icons.hourglass_top_rounded,
                      colors: const [Color(0xFFF59E0B), Color(0xFFEA580C)],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HeroChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _HeroChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: AppColors.brandGold),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      );
}

/// White stat card on the hero: the number in its own colour (gradient text).
class _HeroStat extends StatelessWidget {
  final int? value;
  final String label;
  final IconData icon;
  final List<Color> colors;
  const _HeroStat({required this.value, required this.label, required this.icon, required this.colors});

  @override
  Widget build(BuildContext context) {
    const numberStyle = TextStyle(
      fontFamily: AppFonts.display,
      color: Colors.white, // painted over by the gradient below
      fontSize: 24,
      fontWeight: FontWeight.w800,
      height: 1.1,
    );
    return Expanded(
      child: Container(
        padding: const EdgeInsets.fromLTRB(AppSpacing.md, 10, AppSpacing.sm, 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(AppRadius.sm),
          boxShadow: [BoxShadow(color: colors.last.withValues(alpha: 0.22), blurRadius: 12, offset: const Offset(0, 5))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: ShaderMask(
                    blendMode: BlendMode.srcIn,
                    shaderCallback: (r) => LinearGradient(colors: colors).createShader(r),
                    child: value == null ? const Text('–', style: numberStyle) : CountUp(value: value!, style: numberStyle),
                  ),
                ),
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: colors),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 14, color: Colors.white),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- scan card

class _ScanCard extends StatelessWidget {
  const _ScanCard();

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const IconTile(icon: Icons.document_scanner_rounded, size: 50),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(context.tr('Scan your field for pests'),
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text(
                      context.tr('Take a photo. The app names the pest and counts the insects when it can.'),
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.35),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          AppPrimaryButton(
            label: context.tr('Start pest scan'),
            icon: Icons.photo_camera_rounded,
            onPressed: () => context.push(AppRouter.observe),
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              Expanded(
                child: TextButton.icon(
                  onPressed: () => context.push(AppRouter.observe, extra: const ObserveArgs(presetType: 'disease')),
                  icon: const Icon(Icons.coronavirus_outlined, size: 18),
                  label: Text(context.tr('Report disease'), style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
              Container(width: 1, height: 20, color: AppColors.border),
              Expanded(
                child: TextButton.icon(
                  onPressed: () => showScanGuidelines(context),
                  icon: const Icon(Icons.tips_and_updates_outlined, size: 18),
                  label: Text(context.tr('Scan tips'), style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// How to take a photo the pest check can use.
Future<void> showScanGuidelines(BuildContext context) {
  const tips = [
    (Icons.center_focus_strong_rounded, 'Get close', 'Fill the picture with the insects or the damage.'),
    (Icons.back_hand_outlined, 'Hold steady', 'Tap the screen to focus and keep the phone still.'),
    (Icons.wb_sunny_outlined, 'Use daylight', 'Avoid strong shadows and night photos.'),
    (Icons.grid_on_rounded, 'Sticky traps', 'Photograph the whole trap, flat and straight on.'),
    (Icons.crop_free_rounded, 'One spot per photo', 'Send one observation for each field or trap.'),
  ];
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(AppSpacing.hPad, 0, AppSpacing.hPad, AppSpacing.lg),
        children: [
          Text(ctx.tr('Scan tips'),
              style: const TextStyle(fontFamily: AppFonts.display, fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(
            ctx.tr('The app recognizes Brown Planthopper, Green Leafhopper, Rice Bug and Rice Stem Borer. '
                'It counts the insects only when they can be told apart.'),
            style: const TextStyle(color: AppColors.textSecondary, height: 1.4),
          ),
          const SizedBox(height: AppSpacing.lg),
          for (final (icon, title, body) in tips)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: Row(
                children: [
                  IconTile(icon: icon, size: 40),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(ctx.tr(title), style: const TextStyle(fontWeight: FontWeight.bold)),
                        Text(ctx.tr(body), style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: AppSpacing.sm),
          AppPrimaryButton(
            label: ctx.tr('Start pest scan'),
            icon: Icons.photo_camera_rounded,
            onPressed: () {
              Navigator.pop(ctx);
              context.push(AppRouter.observe);
            },
          ),
        ],
      ),
    ),
  );
}

// ---------------------------------------------------------------- technician

class _QueueCard extends StatelessWidget {
  final int? pest;
  final int? disease;
  final String? oldest;
  final String? error;
  final VoidCallback onOpen;

  const _QueueCard({required this.pest, required this.disease, required this.oldest, required this.error, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final total = (pest ?? 0) + (disease ?? 0);
    final loading = pest == null && error == null;
    return AppCard(
      onTap: onOpen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const IconTile(icon: Icons.fact_check_rounded, color: AppColors.orange),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(context.tr('Validation queue'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                    Text(context.tr('Observations in your area'),
                        style: const TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
                  ],
                ),
              ),
              if (total > 0)
                AppChip(label: context.tr('Action needed'), color: AppColors.orange)
              else if (!loading && error == null)
                AppChip(label: context.tr('All caught up'), color: AppColors.primary, icon: Icons.check_rounded),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          if (error != null)
            Text(context.tr(error!), style: const TextStyle(color: AppColors.textSecondary, fontSize: 13))
          else
            Row(
              children: [
                _QueueStat(label: context.tr('Pest'), value: pest, color: AppColors.orange),
                _QueueStat(label: context.tr('Disease'), value: disease, color: AppColors.purple),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        loading ? '–' : (oldest ?? context.tr('None')),
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: loading ? AppColors.textMuted : (oldest == null ? AppColors.success : AppColors.danger),
                        ),
                      ),
                      Text(context.tr('Oldest waiting'), style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
          const SizedBox(height: AppSpacing.md),
          AppPrimaryButton(
            label: total > 0 ? context.tr('Review now') : context.tr('Open the queue'),
            icon: Icons.arrow_forward_rounded,
            compact: true,
            color: total > 0 ? AppColors.orange : AppColors.primary,
            onPressed: onOpen,
          ),
        ],
      ),
    );
  }
}

class _QueueStat extends StatelessWidget {
  final String label;
  final int? value;
  final Color color;
  const _QueueStat({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            value == null
                ? Text('–', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: color))
                : CountUp(value: value!, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: color)),
            Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
          ],
        ),
      );
}

class _Shortcut extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _Shortcut({required this.icon, required this.color, required this.title, required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) => AppCard(
        onTap: onTap,
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IconTile(icon: icon, color: color, size: 40),
            const SizedBox(height: AppSpacing.sm),
            Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
            Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
          ],
        ),
      );
}

// ---------------------------------------------------------------- attention

class _AttentionCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String? subtitle;
  final String body;
  final String action;
  final VoidCallback onTap;

  const _AttentionCard({
    required this.icon,
    required this.color,
    required this.title,
    this.subtitle,
    required this.body,
    required this.action,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => AppCard(
        onTap: onTap,
        padding: EdgeInsets.zero,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 5, color: color),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      IconTile(icon: icon, color: color, size: 40),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                            if (subtitle != null)
                              Text(subtitle!, style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                            const SizedBox(height: 4),
                            Text(body, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.4)),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Text(action, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 13)),
                                Icon(Icons.chevron_right_rounded, size: 18, color: color),
                              ],
                            ),
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

// ---------------------------------------------------------------- scan history

/// Observations per week for the last four weeks, each bar coloured by the
/// highest level a technician confirmed that week.
class _ScanHistory extends StatelessWidget {
  final List<Record> records;
  const _ScanHistory({required this.records});

  static const _labels = ['3 weeks ago', '2 weeks ago', 'Last week', 'This week'];

  @override
  Widget build(BuildContext context) {
    final today = DateUtils.dateOnly(DateTime.now());
    final weeks = List.generate(4, (_) => <Record>[]);
    for (final r in records) {
      final d = parseLocal(r.createdAt);
      if (d == null) continue;
      final ago = today.difference(DateUtils.dateOnly(d)).inDays;
      if (ago < 0 || ago >= 28) continue;
      weeks[3 - ago ~/ 7].add(r);
    }
    final maxCount = weeks.map((w) => w.length).fold(1, (a, b) => a > b ? a : b);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                  child: Text(context.tr('Scan history'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
              Text(context.tr('Last 4 weeks'),
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 12.5, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          for (var i = 0; i < 4; i++) _WeekRow(label: context.tr(_labels[i]), records: weeks[i], maxCount: maxCount),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: 4,
            children: [
              _Legend(color: AppColors.primary, label: context.tr('Low')),
              _Legend(color: AppColors.orange, label: context.tr('Medium')),
              _Legend(color: AppColors.danger, label: context.tr('High')),
              _Legend(color: AppColors.textMuted, label: context.tr('Not validated yet')),
            ],
          ),
        ],
      ),
    );
  }
}

class _WeekRow extends StatelessWidget {
  final String label;
  final List<Record> records;
  final int maxCount;
  const _WeekRow({required this.label, required this.records, required this.maxCount});

  @override
  Widget build(BuildContext context) {
    String? worst;
    for (final r in records) {
      final l = r.level ?? r.confirmed?.level;
      if (l == null) continue;
      if (worst == null || _F20HomeState._rank(l) > _F20HomeState._rank(worst)) worst = l;
    }
    final Color color = worst == null ? AppColors.textMuted : levelColor(worst);
    final String status =
        records.isEmpty ? context.tr('None') : (worst == null ? context.tr('Pending') : levelLabel(worst));
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        children: [
          SizedBox(
            width: 86,
            child: Text(label, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
          ),
          Expanded(
            child: AnimatedProgressBar(
              value: records.isEmpty ? 0 : records.length / maxCount,
              color: color,
              track: AppColors.border.withValues(alpha: 0.6),
              height: 9,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          SizedBox(
            width: 70,
            child: Text(
              records.isEmpty ? status : '${records.length} · $status',
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: records.isEmpty ? AppColors.textMuted : color,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  final Color color;
  final String label;
  const _Legend({required this.color, required this.label});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5)),
        ],
      );
}

class _Ring extends StatelessWidget {
  final double value;
  final Color color;
  const _Ring({required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    final bool still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value.clamp(0.0, 1.0)),
      duration: still ? Duration.zero : AppMotion.countUp,
      curve: AppMotion.curve,
      builder: (context, v, _) => SizedBox(
        width: 68,
        height: 68,
        child: Stack(
          fit: StackFit.expand,
          children: [
            CircularProgressIndicator(
              value: v,
              strokeWidth: 7,
              strokeCap: StrokeCap.round,
              color: color,
              backgroundColor: color.withValues(alpha: 0.13),
            ),
            Center(
              child: Text('${(v * 100).round()}%',
                  style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- record tile

/// Compact record row (photo, title, date and stage, status and level chips),
/// shared by Home, My Records and the Treatments tab.
class RecordTile extends StatelessWidget {
  final Record record;
  final VoidCallback onTap;
  final Widget? trailing;
  const RecordTile({super.key, required this.record, required this.onTap, this.trailing});

  @override
  Widget build(BuildContext context) {
    final r = record;
    final dueFollowUp = r.treatments.any((t) => t.followUpIsDue);
    final level = r.confirmed?.level ?? r.level;
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: SizedBox(
              width: 72,
              height: 72,
              child: RecordPhoto(
                localPath: r.localPhoto,
                serverId: r.id,
                clientUuid: r.clientUuid,
                cacheWidth: 216,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(r.isDisease ? Icons.coronavirus_outlined : Icons.bug_report_outlined,
                        size: 16, color: AppColors.textMuted),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        r.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  [formatRelativeDay(r.createdAt), r.cropStage].where((x) => x.isNotEmpty).join(' · '),
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 12.5),
                ),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    StatusChip(state: r.state),
                    if (level != null && r.state == RecordState.validated) LevelChip(level: level),
                    if (dueFollowUp)
                      AppChip(label: context.tr('Check the field'), color: AppColors.primary, icon: Icons.healing_rounded),
                  ],
                ),
              ],
            ),
          ),
          trailing ?? const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
        ],
      ),
    );
  }
}
