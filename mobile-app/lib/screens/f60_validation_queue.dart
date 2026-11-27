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
import '../widgets/motion.dart';

/// Technicians' validation queue: the "Not Validated" queue (observations
/// from their assigned area waiting for the first review), oldest first,
/// with pest and disease reports kept apart. Escalated cases go to the
/// agriculturist's "To Be Validated" queue on the dashboard.
class F60ValidationQueue extends StatefulWidget {
  const F60ValidationQueue({super.key});

  @override
  State<F60ValidationQueue> createState() => _F60ValidationQueueState();
}

class _F60ValidationQueueState extends State<F60ValidationQueue> with WidgetsBindingObserver {
  String _kind = 'pest';
  final Map<String, List<Record>?> _items = {'pest': null, 'disease': null};
  String? _error;
  bool _offline = false;
  bool _loading = false;

  /// When the lists shown were saved on the phone (null = fresh).
  DateTime? _savedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // A review sent from anywhere changes the queue.
    SyncService.revision.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    SyncService.revision.removeListener(_load);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  /// Cache first: the last saved lists show at once, then the server's.
  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    if (_items['pest'] == null) {
      try {
        final cached = await Future.wait([SyncService.cachedQueue('pest'), SyncService.cachedQueue('disease')]);
        if (mounted && _items['pest'] == null && cached.any((c) => c != null)) {
          setState(() {
            _items['pest'] = cached[0]?.data ?? const [];
            _items['disease'] = cached[1]?.data ?? const [];
            _savedAt = [cached[0]?.savedAt, cached[1]?.savedAt].whereType<DateTime>().firstOrNull;
          });
        }
      } catch (e) {
        debugPrint('[Queue] no saved lists: $e');
      }
    }
    try {
      final results = await Future.wait([SyncService.fetchQueue('pest'), SyncService.fetchQueue('disease')]);
      if (!mounted) return;
      setState(() {
        _items['pest'] = results[0];
        _items['disease'] = results[1];
        _error = null;
        _savedAt = null;
      });
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _offline = e.isOffline;
        });
      }
    } catch (e) {
      debugPrint('[Queue] could not load: $e');
      if (mounted) setState(() => _error = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _open(Record r) async {
    final changed = await context.push<bool>('${AppRouter.review}/${r.id}');
    if (changed == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final s = AuthControllerImpl.instance.session;
    final list = _items[_kind];
    final area = s?.municipality.isNotEmpty == true
        ? context.tr('Your area: {area}', {'area': s!.municipality})
        : context.tr('No area assigned yet');
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            AppHeader(title: context.tr('Not Validated queue'), subtitle: area),
            MaxContentWidth(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.hPad, 0, AppSpacing.hPad, AppSpacing.xs),
                child: Text(
                  context.tr('New observations waiting for your first review. Cases you escalate go to the '
                      "agriculturist's To Be Validated queue."),
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5, height: 1.4),
                ),
              ),
            ),
            MaxContentWidth(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.hPad, AppSpacing.xs, AppSpacing.hPad, AppSpacing.sm),
                child: _KindToggle(
                  value: _kind,
                  pest: _items['pest']?.length,
                  disease: _items['disease']?.length,
                  onChanged: (k) => setState(() => _kind = k),
                ),
              ),
            ),
            if (_savedAt != null && list != null)
              MaxContentWidth(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.hPad),
                  child: SavedDataNote(savedAt: _savedAt!, refreshing: _loading),
                ),
              ),
            if (_error != null && list != null)
              MaxContentWidth(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.hPad, 0, AppSpacing.hPad, AppSpacing.sm),
                  child: InfoBanner(
                    icon: _offline ? Icons.cloud_off_rounded : Icons.error_outline_rounded,
                    color: _offline ? AppColors.textSecondary : AppColors.danger,
                    message: _offline ? context.tr('No signal. Showing the last list.') : context.tr(_error!),
                    actionLabel: context.tr('Retry'),
                    onAction: _load,
                  ),
                ),
              ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _load,
                child: AppSwitcher(
                  child: KeyedSubtree(
                    key: ValueKey('$_kind:${list == null}:${list?.isEmpty}:${_error != null && list == null}'),
                    child: _error != null && list == null
                        ? ListView(children: [
                            AppEmptyState(
                              icon: Icons.cloud_off_rounded,
                              title: context.tr('Can\'t load the queue'),
                              message: context.tr(_offline ? 'No signal, and no list is saved on this phone yet.' : _error!),
                              actionLabel: context.tr('Try again'),
                              onAction: _load,
                              color: AppColors.danger,
                            ),
                          ])
                        : list == null
                            ? const Padding(
                                padding: EdgeInsets.all(AppSpacing.hPad),
                                child: SkeletonList(rows: 4, cards: true, cardHeight: 96),
                              )
                            : list.isEmpty
                                ? ListView(children: [
                                    AppEmptyState(
                                      icon: Icons.task_alt_rounded,
                                      title: context.tr('All caught up'),
                                      message: _kind == 'pest'
                                          ? context.tr('No pest observations waiting in your area.')
                                          : context.tr('No disease observations waiting in your area.'),
                                    ),
                                  ])
                                : ListView.separated(
                                    padding: const EdgeInsets.fromLTRB(AppSpacing.hPad, AppSpacing.sm, AppSpacing.hPad, AppSpacing.xl),
                                    itemCount: list.length,
                                    separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
                                    itemBuilder: (context, i) => MaxContentWidth(
                                      child: FadeSlideIn(
                                        index: i,
                                        child: _QueueRow(record: list[i], onTap: () => _open(list[i])),
                                      ),
                                    ),
                                  ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _KindToggle extends StatelessWidget {
  final String value;
  final int? pest;
  final int? disease;
  final ValueChanged<String> onChanged;

  const _KindToggle({required this.value, required this.pest, required this.disease, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    Widget option(String kind, String label, IconData icon, int? count) {
      final selected = value == kind;
      return Expanded(
        child: GestureDetector(
          onTap: () => onChanged(kind),
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: AppMotion.medium,
            curve: AppMotion.curve,
            padding: const EdgeInsets.symmetric(vertical: 11),
            decoration: BoxDecoration(
              gradient: selected ? kPrimaryGradient : null,
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 18, color: selected ? AppColors.surface : AppColors.textSecondary),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: selected ? AppColors.surface : AppColors.textSecondary,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      )),
                ),
                if (count != null && count > 0) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                    decoration: BoxDecoration(
                      color: selected ? AppColors.brandGold : AppColors.orange.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                    child: Text('$count',
                        style: TextStyle(
                          color: selected ? AppColors.primaryDeep : AppColors.orange,
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        )),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        boxShadow: AppShadows.card,
      ),
      child: Row(
        children: [
          option('pest', context.tr('Pest'), Icons.bug_report_outlined, pest),
          option('disease', context.tr('Disease'), Icons.coronavirus_outlined, disease),
        ],
      ),
    );
  }
}

class _QueueRow extends StatelessWidget {
  final Record record;
  final VoidCallback onTap;
  const _QueueRow({required this.record, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final r = record;
    final ai = r.ai;
    final hours = DateTime.now().difference(parseLocal(r.createdAt) ?? DateTime.now()).inHours;
    final waitColor = hours >= 72 ? AppColors.danger : (hours >= 24 ? AppColors.orange : AppColors.primary);
    final String title;
    if (r.isDisease) {
      title = context.tr('Disease report');
    } else if (ai != null && ai.recognized) {
      title = ai.pestLabel;
    } else {
      title = context.tr('Model result: not identified');
    }
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: SizedBox(
              width: 76,
              height: 76,
              child: RecordPhoto(serverId: r.id, clientUuid: r.clientUuid, cacheWidth: 228),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800)),
                if (!r.isDisease && ai != null && ai.recognized)
                  Text(
                    '${context.tr('{n}% sure', {'n': ((ai.confidence ?? 0) * 100).round()})} · '
                    '${ai.count != null ? plural(ai.count!, 'insect') : context.tr('not countable')}',
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
                  ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    const Icon(Icons.location_on_outlined, size: 14, color: AppColors.textMuted),
                    const SizedBox(width: 2),
                    Expanded(
                      child: Text(
                        [r.barangay, r.municipality].where((x) => x.isNotEmpty).join(', '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AppColors.textMuted, fontSize: 12.5),
                      ),
                    ),
                  ],
                ),
                Text(
                  r.submitterRole == 'technician'
                      ? context.tr('{name} (technician)', {'name': r.submitterName})
                      : r.submitterName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 12.5),
                ),
                Text(
                  '${context.tr('Land type')}: ${landTypeLabel(r.landType)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 12.5),
                ),
                if (r.escalationReason.isNotEmpty || r.queueReason.isNotEmpty)
                  Text(
                    r.escalationReason.isNotEmpty
                        ? context.tr('Reason: {reason}', {'reason': context.tr(r.escalationReason)})
                        : context.tr(r.queueReason == 'no_technician'
                            ? 'No technician covers this area'
                            : r.queueReason == 'escalated'
                                ? 'Escalated by a technician'
                                : r.queueReason),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.purple, fontSize: 12.5, fontWeight: FontWeight.w600),
                  ),
                if (r.resubmissionOf != null || r.followUpOf != null || r.possiblyUnrelated) ...[
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      if (r.possiblyUnrelated)
                        AppChip(
                          label: context.tr('Possibly unrelated photo'),
                          color: AppColors.danger,
                          icon: Icons.image_not_supported_outlined,
                        ),
                      if (r.resubmissionOf != null)
                        AppChip(
                          label: context.tr('Retake of #{id}', {'id': r.resubmissionOf}),
                          color: AppColors.primary,
                          icon: Icons.replay_rounded,
                        ),
                      if (r.followUpOf != null)
                        AppChip(label: context.tr('Follow-up'), color: AppColors.sky, icon: Icons.healing_rounded),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: waitColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Column(
              children: [
                Icon(Icons.schedule_rounded, size: 16, color: waitColor),
                const SizedBox(height: 2),
                Text(waitingLabel(r.createdAt),
                    style: TextStyle(color: waitColor, fontSize: 12, fontWeight: FontWeight.w800)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
