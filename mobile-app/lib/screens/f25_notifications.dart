import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../app_router.dart';
import '../l10n/app_language.dart';
import '../models/record.dart';
import '../services/api_client.dart';
import '../services/sync_service.dart';
import '../theme.dart';
import '../utils/formatters.dart';
import '../widgets/app_widgets.dart';
import '../widgets/motion.dart';
import 'f30_new_observation.dart' show ObserveArgs;

/// What the badge counts: follow-ups that are due ("How is the field now?")
/// and news about the user's observations (validated, returned, guidance).
class F25Notifications extends StatefulWidget {
  const F25Notifications({super.key});

  @override
  State<F25Notifications> createState() => _F25NotificationsState();
}

class _F25NotificationsState extends State<F25Notifications> {
  List<(Record, TreatmentInfo)> _followUps = const [];
  List<AppNotification>? _items;
  String? _error;
  bool _offline = false;
  bool _loading = false;

  /// When the list shown was saved on the phone (null = fresh).
  DateTime? _savedAt;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Cache first: the last saved list shows at once, then the server's.
  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final followUps = await SyncService.dueFollowUps();
      if (mounted) setState(() => _followUps = followUps);
    } catch (e) {
      debugPrint('[Notifications] follow-ups unavailable: $e');
    }
    if (_items == null) {
      try {
        final cached = await SyncService.cachedNotifications();
        if (cached != null && mounted && _items == null) {
          setState(() {
            _items = cached.data;
            _savedAt = cached.savedAt;
          });
        }
      } catch (e) {
        debugPrint('[Notifications] no saved list: $e');
      }
    }
    try {
      final items = await SyncService.fetchNotifications();
      if (mounted) {
        setState(() {
          _items = items;
          _error = null;
          _offline = false;
          _savedAt = null;
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _offline = e.isOffline;
          _error = e.isOffline
              ? (_items == null
                  ? 'No signal, and no notifications are saved on this phone yet.'
                  : 'No signal. Showing the notifications saved on this phone.')
              : e.message;
        });
      }
    } catch (e) {
      debugPrint('[Notifications] could not load: $e');
      if (mounted) setState(() => _error = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _open(AppNotification n) async {
    if (!n.read) {
      SyncService.markRead(ids: [n.id]).catchError((_) {});
      setState(() {
        _items = [
          for (final i in _items!)
            i.id == n.id ? AppNotification(i.id, i.scanId, i.kind, i.title, i.body, i.createdAt, true) : i,
        ];
      });
    }
    if (n.scanId != null) {
      await context.push(AppRouter.record, extra: n.scanId);
    } else if (n.kind == 'account') {
      // An agriculturist changed the account: load it and show the profile.
      ApiClient.refreshProfile().catchError((_) => null);
      await context.push(AppRouter.profile);
    }
  }

  Future<void> _markAll() async {
    try {
      await SyncService.markRead(all: true);
      await _load();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr(e.message))));
      }
    }
  }

  static IconData _icon(String kind) => switch (kind) {
        'validated' => Icons.verified_rounded,
        'returned' => Icons.replay_rounded,
        'guidance' => Icons.medical_information_outlined,
        'escalated' => Icons.forward_to_inbox_rounded,
        'account' => Icons.manage_accounts_rounded,
        _ => Icons.notifications_rounded,
      };

  static Color _color(String kind) => switch (kind) {
        'returned' => AppColors.danger,
        'escalated' => AppColors.purple,
        'guidance' => AppColors.sky,
        'account' => AppColors.teal,
        _ => AppColors.primary,
      };

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final unread = items?.where((n) => !n.read).length ?? 0;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            AppHeader(
              title: context.tr('Notifications'),
              subtitle: unread > 0 ? context.tr('{n} unread', {'n': unread}) : null,
              actions: [
                if (unread > 0)
                  TextButton.icon(
                    onPressed: _markAll,
                    icon: const Icon(Icons.done_all_rounded, size: 18),
                    label: Text(context.tr('Mark all read'), style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
              ],
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.hPad, AppSpacing.sm, AppSpacing.hPad, AppSpacing.xl),
                  children: [
                    MaxContentWidth(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                    if (_savedAt != null && items != null) SavedDataNote(savedAt: _savedAt!, refreshing: _loading),
                    if (_error != null && items != null) ...[
                      InfoBanner(
                        icon: _offline ? Icons.cloud_off_rounded : Icons.error_outline_rounded,
                        color: _offline ? AppColors.textSecondary : AppColors.danger,
                        message: context.tr(_error!),
                        actionLabel: context.tr('Retry'),
                        onAction: _load,
                      ),
                      const SizedBox(height: AppSpacing.md),
                    ],
                    for (final (rec, t) in _followUps) ...[
                      AppCard(
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
                                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                                ),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            Text(
                                context.tr('You applied "{treatment}" on {date} for {title}.', {
                                  'treatment': t.treatment,
                                  'date': formatShortDate(t.appliedAt),
                                  'title': rec.title,
                                }),
                                style: const TextStyle(height: 1.4)),
                            const SizedBox(height: AppSpacing.md),
                            AppPrimaryButton(
                              label: context.tr('Check the field'),
                              icon: Icons.photo_camera_rounded,
                              compact: true,
                              onPressed: () => context.push(
                                AppRouter.observe,
                                extra: ObserveArgs(followUpOf: t.id, followUpLabel: t.treatment),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                    ],
                    if (items == null && _error == null)
                      const SkeletonList(rows: 4)
                    else if (items == null && _followUps.isEmpty)
                      LoadErrorState(message: _error!, onRetry: _load)
                    else if (items == null)
                      InfoBanner(
                        icon: Icons.cloud_off_rounded,
                        color: AppColors.textSecondary,
                        message: context.tr(_error!),
                        actionLabel: context.tr('Retry'),
                        onAction: _load,
                      )
                    else if (items.isEmpty && _followUps.isEmpty)
                      AppEmptyState(
                        icon: Icons.notifications_none_rounded,
                        title: context.tr('You\'re all caught up'),
                        message: context.tr('You will be told here when a technician reviews your observations.'),
                      )
                    else
                      for (final (i, n) in items.indexed) ...[
                        FadeSlideIn(
                          index: i,
                          child: AppCard(
                            onTap: () => _open(n),
                            color: n.read ? null : const Color(0xFFF6FBF4),
                            borderColor: n.read ? null : _color(n.kind).withValues(alpha: 0.35),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                IconTile(icon: _icon(n.kind), color: _color(n.kind), size: 42),
                                const SizedBox(width: AppSpacing.md),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(n.title,
                                          style: TextStyle(
                                              fontSize: 15, fontWeight: n.read ? FontWeight.w600 : FontWeight.w800)),
                                      if (n.body.isNotEmpty) ...[
                                        const SizedBox(height: 2),
                                        Text(n.body, maxLines: 3, overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(color: AppColors.textSecondary, height: 1.35, fontSize: 13.5)),
                                      ],
                                      const SizedBox(height: 4),
                                      Text(formatRelativeDay(n.createdAt),
                                          style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                                    ],
                                  ),
                                ),
                                if (!n.read)
                                  Container(
                                    width: 10,
                                    height: 10,
                                    margin: const EdgeInsets.only(top: 6, left: 6),
                                    decoration: const BoxDecoration(color: AppColors.danger, shape: BoxShape.circle),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                      ],
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
}
