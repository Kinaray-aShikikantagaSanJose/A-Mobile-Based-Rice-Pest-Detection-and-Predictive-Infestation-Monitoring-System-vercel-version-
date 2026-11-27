import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../app_router.dart';
import '../l10n/app_language.dart';
import '../models/record.dart';
import '../services/sync_service.dart';
import '../theme.dart';
import '../utils/formatters.dart';
import '../widgets/app_widgets.dart';
import '../widgets/motion.dart';
import 'f20_home.dart' show RecordTile;
import 'f30_new_observation.dart' show ObserveArgs;

/// Everything about treatments in one place: follow-up checks that are due,
/// validated reports whose treatment options are ready, and every treatment
/// applied with the date and the follow-up status.
class F26Treatments extends StatefulWidget {
  const F26Treatments({super.key});

  @override
  State<F26Treatments> createState() => _F26TreatmentsState();
}

class _F26TreatmentsState extends State<F26Treatments> {
  List<Record>? _records;
  List<(Record, TreatmentInfo)> _followUps = const [];
  List<(int, TreatmentInfo)> _unsent = const [];

  @override
  void initState() {
    super.initState();
    SyncService.revision.addListener(_load);
    _load();
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
      final unsent = await SyncService.pendingTreatments();
      if (!mounted) return;
      setState(() {
        _records = records;
        _followUps = followUps;
        _unsent = unsent;
      });
    } catch (e) {
      debugPrint('[Treatments] could not read records: $e');
      if (mounted) setState(() => _records = const []);
    }
  }

  Future<void> _refresh() async {
    await SyncService.syncAll(force: true);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final records = _records;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            AppHeader(
              title: context.tr('Treatments'),
              subtitle: context.tr('Options, what you applied, and follow-ups'),
            ),
            Expanded(
              child: records == null
                  ? const Padding(
                      padding: EdgeInsets.all(AppSpacing.hPad),
                      child: SkeletonList(rows: 4, cards: true),
                    )
                  : RefreshIndicator(onRefresh: _refresh, child: _body(records)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(List<Record> records) {
    final ready = records
        .where((r) => r.state == RecordState.validated && !r.isDisease && r.isMine && r.treatments.isEmpty)
        .where((r) => !_unsent.any((u) => u.$1 == r.id))
        .toList();
    final byId = {for (final r in records) if (r.id != null) r.id!: r};
    final applied = <(Record?, TreatmentInfo)>[
      for (final (id, t) in _unsent) (byId[id], t),
      for (final r in records)
        for (final t in r.treatments) (r, t),
    ]..sort((a, b) => b.$2.appliedAt.compareTo(a.$2.appliedAt));

    if (_followUps.isEmpty && ready.isEmpty && applied.isEmpty) {
      return ListView(
        children: [
          AppEmptyState(
            icon: Icons.healing_outlined,
            title: context.tr('No treatments yet'),
            message: context.tr('When a technician validates your pest report, the treatment options for your crop stage '
                'appear here. Log what you apply and the app reminds you to check the field.'),
            actionLabel: context.tr('Start pest scan'),
            onAction: () => context.push(AppRouter.observe),
          ),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.hPad, AppSpacing.sm, AppSpacing.hPad, AppSpacing.xl),
      children: [MaxContentWidth(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: staggered([
        _Summary(followUps: _followUps.length, ready: ready.length, applied: applied.length),
        if (_followUps.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xl),
          AppSectionHeader(title: context.tr('Follow-up reminders')),
          const SizedBox(height: AppSpacing.md),
          for (final (rec, t) in _followUps) ...[
            _FollowUpCard(record: rec, treatment: t),
            const SizedBox(height: AppSpacing.md),
          ],
        ],
        if (ready.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          AppSectionHeader(title: context.tr('Ready for treatment')),
          const SizedBox(height: 4),
          Text(
            context.tr('Validated by your technician. Open one to see the approved options for its crop stage.'),
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: AppSpacing.md),
          for (final r in ready) ...[
            RecordTile(record: r, onTap: () => context.push(AppRouter.record, extra: r)),
            const SizedBox(height: AppSpacing.md),
          ],
        ],
        if (applied.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          AppSectionHeader(title: context.tr('What you applied')),
          const SizedBox(height: AppSpacing.md),
          AppCard(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
            child: Column(
              children: [
                for (final (i, (rec, t)) in applied.indexed) ...[
                  if (i > 0) const Divider(height: 1),
                  _AppliedRow(record: rec, treatment: t),
                ],
              ],
            ),
          ),
        ],
      ])))],
    );
  }
}

class _Summary extends StatelessWidget {
  final int followUps;
  final int ready;
  final int applied;
  const _Summary({required this.followUps, required this.ready, required this.applied});

  @override
  Widget build(BuildContext context) {
    Widget tile(IconData icon, Color color, int n, String label) => Expanded(
          child: AppCard(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IconTile(icon: icon, color: color, size: 34),
                const SizedBox(height: AppSpacing.sm),
                CountUp(value: n, style: const TextStyle(fontFamily: AppFonts.display, fontSize: 22, fontWeight: FontWeight.w800)),
                Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
              ],
            ),
          ),
        );
    return Row(
      children: [
        tile(Icons.alarm_rounded, AppColors.danger, followUps, context.tr('Checks due')),
        const SizedBox(width: AppSpacing.sm),
        tile(Icons.verified_rounded, AppColors.orange, ready, context.tr('To treat')),
        const SizedBox(width: AppSpacing.sm),
        tile(Icons.task_alt_rounded, AppColors.primary, applied, context.tr('Applied')),
      ],
    );
  }
}

class _FollowUpCard extends StatelessWidget {
  final Record record;
  final TreatmentInfo treatment;
  const _FollowUpCard({required this.record, required this.treatment});

  @override
  Widget build(BuildContext context) => AppCard(
        tinted: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const IconTile(icon: Icons.alarm_rounded, color: AppColors.primary, size: 40),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(context.tr('How is the field now?'),
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                      Text(record.title, style: const TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              context.tr(
                'You applied "{treatment}" on {date}. Take a photo so your technician can see if it worked.',
                {'treatment': treatment.treatment, 'date': formatShortDate(treatment.appliedAt)},
              ),
              style: const TextStyle(height: 1.4, fontSize: 13.5),
            ),
            const SizedBox(height: AppSpacing.md),
            AppPrimaryButton(
              label: context.tr('Check the field'),
              icon: Icons.photo_camera_rounded,
              compact: true,
              onPressed: () => context.push(
                AppRouter.observe,
                extra: ObserveArgs(followUpOf: treatment.id, followUpLabel: treatment.treatment),
              ),
            ),
          ],
        ),
      );
}

class _AppliedRow extends StatelessWidget {
  final Record? record;
  final TreatmentInfo treatment;
  const _AppliedRow({required this.record, required this.treatment});

  @override
  Widget build(BuildContext context) {
    final t = treatment;
    final (String status, Color color) = t.pending
        ? (context.tr('Waiting for signal'), AppColors.textMuted)
        : t.followUpScanId != null
            ? (context.tr('Follow-up sent'), AppColors.primary)
            : t.followUpIsDue
                ? (context.tr('Follow-up due now'), AppColors.danger)
                : (context.tr('Follow-up {date}', {'date': formatShortDate(t.followUpDue)}), AppColors.orange);
    return InkWell(
      onTap: record == null ? null : () => context.push(AppRouter.record, extra: record),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Row(
          children: [
            IconTile(icon: kOptionTypeIcons[t.optionType] ?? Icons.task_alt_rounded, size: 40),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.treatment, maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
                  Text(
                    [formatShortDate(t.appliedAt), if (record != null) record!.title].join(' · '),
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 12.5),
                  ),
                  const SizedBox(height: 4),
                  AppChip(label: status, color: color),
                ],
              ),
            ),
            if (record != null) const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}
