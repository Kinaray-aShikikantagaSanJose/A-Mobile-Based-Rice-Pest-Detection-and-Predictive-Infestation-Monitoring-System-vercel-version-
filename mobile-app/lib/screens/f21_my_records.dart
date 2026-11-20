import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../app_router.dart';
import '../models/record.dart';
import '../services/sync_service.dart';
import '../theme.dart';
import '../utils/formatters.dart';
import '../widgets/app_widgets.dart';
import '../widgets/motion.dart';
import 'f20_home.dart' show RecordTile;

enum _Filter { all, waiting, review, returned, validated }

/// Everything the user submitted, newest first, each with its status and a
/// filter by status. Works offline from the phone's copy; pull down to refresh.
class F21MyRecords extends StatefulWidget {
  const F21MyRecords({super.key});

  @override
  State<F21MyRecords> createState() => _F21MyRecordsState();
}

class _F21MyRecordsState extends State<F21MyRecords> {
  List<Record>? _records;
  _Filter _filter = _Filter.all;

  @override
  void initState() {
    super.initState();
    SyncService.revision.addListener(_load);
    _load();
    SyncService.syncAll();
  }

  @override
  void dispose() {
    SyncService.revision.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await SyncService.records();
      if (mounted) setState(() => _records = r);
    } catch (e) {
      debugPrint('[Records] could not read records: $e');
      if (mounted) setState(() => _records = const []);
    }
  }

  Future<void> _refresh() async {
    await SyncService.syncAll();
    await _load();
  }

  static bool _matches(Record r, _Filter f) => switch (f) {
        _Filter.all => true,
        _Filter.waiting => r.state == RecordState.waiting,
        _Filter.review => const {RecordState.forValidation, RecordState.sentForReview, RecordState.withAgriculturist}
            .contains(r.state),
        _Filter.returned => r.state == RecordState.returned,
        _Filter.validated => r.state == RecordState.validated,
      };

  static const Map<_Filter, String> _labels = {
    _Filter.all: 'All',
    _Filter.waiting: 'Not sent',
    _Filter.review: 'In review',
    _Filter.returned: 'Returned',
    _Filter.validated: 'Validated',
  };

  @override
  Widget build(BuildContext context) {
    final records = _records;
    final shown = records?.where((r) => _matches(r, _filter)).toList();
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            AppHeader(
              title: 'My Records',
              subtitle: records == null ? null : '${plural(records.length, 'observation')} you sent',
            ),
            if (records != null && records.isNotEmpty)
              SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.hPad, vertical: 4),
                  children: [
                    for (final f in _Filter.values)
                      Padding(
                        padding: const EdgeInsets.only(right: AppSpacing.sm),
                        child: _FilterChip(
                          label: _labels[f]!,
                          count: records.where((r) => _matches(r, f)).length,
                          selected: _filter == f,
                          onTap: () => setState(() => _filter = f),
                        ),
                      ),
                  ],
                ),
              ),
            Expanded(
              child: records == null
                  ? const Padding(
                      padding: EdgeInsets.all(AppSpacing.hPad),
                      child: SkeletonList(rows: 5, cards: true, cardHeight: 96),
                    )
                  : RefreshIndicator(
                      onRefresh: _refresh,
                      child: AppSwitcher(
                        child: KeyedSubtree(
                          key: ValueKey('${_filter.name}:${shown!.isEmpty}'),
                          child: shown.isEmpty
                              ? ListView(
                                  children: [
                                    records.isEmpty
                                        ? AppEmptyState(
                                            icon: Icons.photo_library_outlined,
                                            title: 'Nothing here yet',
                                            message: 'Observations you send will appear here with their status.',
                                            actionLabel: 'New Observation',
                                            onAction: () => context.push(AppRouter.observe),
                                          )
                                        : AppEmptyState(
                                            icon: Icons.filter_alt_off_outlined,
                                            title: 'No ${_labels[_filter]!.toLowerCase()} records',
                                            message: 'Try another filter to see your other observations.',
                                            actionLabel: 'Show all',
                                            onAction: () => setState(() => _filter = _Filter.all),
                                          ),
                                  ],
                                )
                              : ListView.separated(
                                  padding: const EdgeInsets.fromLTRB(
                                      AppSpacing.hPad, AppSpacing.md, AppSpacing.hPad, AppSpacing.xl),
                                  itemCount: shown.length,
                                  separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
                                  itemBuilder: (context, i) => FadeSlideIn(
                                    index: i,
                                    child: RecordTile(
                                      record: shown[i],
                                      onTap: () => context.push(AppRouter.record, extra: shown[i]),
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

class _FilterChip extends StatelessWidget {
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({required this.label, required this.count, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => PressScale(
        child: Ink(
          decoration: ShapeDecoration(
            gradient: selected ? kPrimaryGradient : null,
            color: selected ? null : AppColors.surface,
            shape: StadiumBorder(side: BorderSide(color: selected ? Colors.transparent : AppColors.border)),
          ),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: selected ? AppColors.surface : AppColors.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  if (count > 0) ...[
                    const SizedBox(width: 6),
                    Text(
                      '$count',
                      style: TextStyle(
                        color: selected ? AppColors.brandGold : AppColors.textMuted,
                        fontWeight: FontWeight.w800,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
}
