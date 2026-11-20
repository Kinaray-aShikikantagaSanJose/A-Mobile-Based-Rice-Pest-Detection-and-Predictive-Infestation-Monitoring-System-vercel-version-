import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../app_router.dart';
import '../controllers/auth_controller.dart';
import '../models/record.dart';
import '../services/api_client.dart';
import '../services/sync_service.dart';
import '../theme.dart';
import '../utils/formatters.dart';
import '../widgets/app_widgets.dart';
import '../widgets/motion.dart';

/// Technicians' validation queue: observations from their assigned area
/// waiting for review, oldest first, with pest and disease reports kept apart.
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

  Future<void> _load() async {
    try {
      final results = await Future.wait([SyncService.queue('pest'), SyncService.queue('disease')]);
      if (!mounted) return;
      setState(() {
        _items['pest'] = results[0];
        _items['disease'] = results[1];
        _error = null;
      });
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _offline = e.isOffline;
        });
      }
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
    final area = s?.municipality.isNotEmpty == true ? 'Your area: ${s!.municipality}' : 'No area assigned yet';
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            AppHeader(title: 'Validation queue', subtitle: area),
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.hPad, AppSpacing.xs, AppSpacing.hPad, AppSpacing.sm),
              child: _KindToggle(
                value: _kind,
                pest: _items['pest']?.length,
                disease: _items['disease']?.length,
                onChanged: (k) => setState(() => _kind = k),
              ),
            ),
            if (_error != null && list != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.hPad, 0, AppSpacing.hPad, AppSpacing.sm),
                child: InfoBanner(
                  icon: _offline ? Icons.cloud_off_rounded : Icons.error_outline_rounded,
                  color: _offline ? AppColors.textSecondary : AppColors.danger,
                  message: _offline ? 'No signal. Showing the last list.' : _error!,
                  actionLabel: 'Retry',
                  onAction: _load,
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
                              title: 'Can\'t load the queue',
                              message: _error!,
                              actionLabel: 'Try again',
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
                                      title: 'All caught up',
                                      message: 'No ${_kind == 'pest' ? 'pest' : 'disease'} observations waiting in your area.',
                                    ),
                                  ])
                                : ListView.separated(
                                    padding: const EdgeInsets.fromLTRB(AppSpacing.hPad, AppSpacing.sm, AppSpacing.hPad, AppSpacing.xl),
                                    itemCount: list.length,
                                    separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
                                    itemBuilder: (context, i) => FadeSlideIn(
                                      index: i,
                                      child: _QueueRow(record: list[i], onTap: () => _open(list[i])),
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
                Text(label,
                    style: TextStyle(
                      color: selected ? AppColors.surface : AppColors.textSecondary,
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    )),
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
          option('pest', 'Pest', Icons.bug_report_outlined, pest),
          option('disease', 'Disease', Icons.coronavirus_outlined, disease),
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
      title = 'Disease report';
    } else if (ai != null && ai.recognized) {
      title = ai.pestLabel;
    } else {
      title = 'Model result: not identified';
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
                    '${((ai.confidence ?? 0) * 100).round()}% sure · ${ai.count != null ? plural(ai.count!, 'insect') : 'not countable'}',
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
                  '${r.submitterName}${r.submitterRole == 'technician' ? ' (technician)' : ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 12.5),
                ),
                if (r.resubmissionOf != null || r.followUpOf != null) ...[
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    children: [
                      if (r.resubmissionOf != null)
                        AppChip(label: 'Retake of #${r.resubmissionOf}', color: AppColors.primary, icon: Icons.replay_rounded),
                      if (r.followUpOf != null)
                        const AppChip(label: 'Follow-up', color: AppColors.sky, icon: Icons.healing_rounded),
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
