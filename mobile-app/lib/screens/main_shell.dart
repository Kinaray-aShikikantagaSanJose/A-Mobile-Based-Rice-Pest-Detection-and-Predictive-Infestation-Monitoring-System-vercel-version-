import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../app_router.dart';
import '../controllers/auth_controller.dart';
import '../l10n/app_language.dart';
import '../services/notification_service.dart';
import '../services/sync_service.dart';
import '../theme.dart';
import '../widgets/motion.dart';
import '../widgets/shell_scope.dart';
import 'f20_home.dart';
import 'f21_my_records.dart';
import 'f25_notifications.dart';
import 'f26_treatments.dart';
import 'f60_validation_queue.dart';
import 'f62_local_map.dart';

class _TabSpec {
  final String id;
  final String label;
  final IconData icon;
  final IconData activeIcon;
  final WidgetBuilder builder;
  final ValueListenable<int>? badge;

  const _TabSpec(this.id, this.label, this.icon, this.activeIcon, this.builder, {this.badge});
}

/// The signed-in app: four tabs and a Scan button in the middle of the
/// bottom bar. Farmers: Home · Records · Scan · Treatments · Alerts.
/// Technicians: Home · Queue · Scan · Map · Records (alerts and treatments
/// open from Home). Tabs keep their state while you switch.
class MainShell extends StatefulWidget {
  final String? initialTab;
  const MainShell({super.key, this.initialTab});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  late String _tab;
  final Set<String> _opened = {};

  bool get _isTech => AuthControllerImpl.instance.role == AppRole.technician;

  List<_TabSpec> get _tabs => _isTech
      ? [
          _TabSpec(AppTab.home, 'Home', Icons.home_outlined, Icons.home_rounded, (_) => const F20Home()),
          _TabSpec(AppTab.queue, 'Queue', Icons.fact_check_outlined, Icons.fact_check_rounded,
              (_) => const F60ValidationQueue(), badge: SyncService.queueCount),
          _TabSpec(AppTab.map, 'Map', Icons.map_outlined, Icons.map_rounded, (_) => const F62LocalMap()),
          _TabSpec(AppTab.records, 'Records', Icons.photo_library_outlined, Icons.photo_library_rounded,
              (_) => const F21MyRecords()),
        ]
      : [
          _TabSpec(AppTab.home, 'Home', Icons.home_outlined, Icons.home_rounded, (_) => const F20Home()),
          _TabSpec(AppTab.records, 'Records', Icons.photo_library_outlined, Icons.photo_library_rounded,
              (_) => const F21MyRecords()),
          _TabSpec(AppTab.treatments, 'Treatments', Icons.healing_outlined, Icons.healing_rounded,
              (_) => const F26Treatments()),
          _TabSpec(AppTab.alerts, 'Alerts', Icons.notifications_none_rounded, Icons.notifications_rounded,
              (_) => const F25Notifications(), badge: SyncService.badge),
        ];

  String _valid(String? id) => _tabs.any((t) => t.id == id) ? id! : AppTab.home;

  @override
  void initState() {
    super.initState();
    _tab = _valid(ShellNav.request.value ?? widget.initialTab);
    ShellNav.request.value = null;
    ShellNav.request.addListener(_onRequest);
    _opened.add(_tab);
    SyncService.refreshBadge();
    final notify = NotificationService.instance;
    notify.taps.addListener(_onNotificationTap);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      notify.requestPermission();
      // Opened by tapping a notification before the shell existed.
      _onNotificationTap();
    });
  }

  /// A phone notification was tapped: open what it is about.
  void _onNotificationTap() {
    final tap = NotificationService.instance.taps.value;
    if (tap == null || !mounted) return;
    NotificationService.instance.taps.value = null;
    SyncService.refreshBadge();
    if (tap.target == 'profile') {
      context.push(AppRouter.profile);
    } else if (tap.target == 'queue') {
      if (_isTech && tap.scanId != null) {
        context.push('${AppRouter.review}/${tap.scanId}');
      } else {
        _go(_valid(AppTab.queue));
      }
    } else if (tap.scanId != null) {
      context.push(AppRouter.record, extra: tap.scanId);
    } else if (_tabs.any((t) => t.id == AppTab.alerts)) {
      _go(AppTab.alerts);
    } else {
      context.push(AppRouter.notifications);
    }
  }

  @override
  void didUpdateWidget(covariant MainShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A deep link such as /queue (-> /home?tab=queue) while the shell is showing.
    if (widget.initialTab != oldWidget.initialTab && widget.initialTab != null) _go(_valid(widget.initialTab));
  }

  @override
  void dispose() {
    ShellNav.request.removeListener(_onRequest);
    NotificationService.instance.taps.removeListener(_onNotificationTap);
    super.dispose();
  }

  void _onRequest() {
    final tab = ShellNav.request.value;
    if (tab == null) return;
    ShellNav.request.value = null;
    _go(_valid(tab));
  }

  void _go(String id) {
    if (id == _tab) return;
    HapticFeedback.selectionClick();
    setState(() {
      _tab = id;
      _opened.add(id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final tabs = _tabs;
    final index = tabs.indexWhere((t) => t.id == _tab).clamp(0, tabs.length - 1);
    return PopScope(
      // Back on another tab returns to Home before leaving the app.
      canPop: _tab == AppTab.home,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _go(AppTab.home);
      },
      child: Scaffold(
        body: ShellScope(
          currentTab: _tab,
          tabs: [for (final t in tabs) t.id],
          goTab: _go,
          child: IndexedStack(
            index: index,
            children: [
              for (final t in tabs)
                KeyedSubtree(
                  key: ValueKey(t.id),
                  // Tabs are built the first time they are opened.
                  child: _opened.contains(t.id) ? t.builder(context) : const SizedBox.shrink(),
                ),
            ],
          ),
        ),
        bottomNavigationBar: _BottomBar(
          tabs: tabs,
          current: _tab,
          onTap: _go,
          onScan: () => context.push(AppRouter.observe),
        ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  final List<_TabSpec> tabs;
  final String current;
  final ValueChanged<String> onTap;
  final VoidCallback onScan;

  const _BottomBar({required this.tabs, required this.current, required this.onTap, required this.onScan});

  @override
  Widget build(BuildContext context) {
    Widget item(_TabSpec t) => Expanded(child: _NavItem(tab: t, active: t.id == current, onTap: () => onTap(t.id)));
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: AppShadows.raised,
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 74,
          child: Row(
            children: [
              item(tabs[0]),
              item(tabs[1]),
              SizedBox(width: 84, child: _ScanButton(onTap: onScan)),
              item(tabs[2]),
              item(tabs[3]),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final _TabSpec tab;
  final bool active;
  final VoidCallback onTap;

  const _NavItem({required this.tab, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final Color color = active ? AppColors.primary : AppColors.textMuted;
    // Tab labels are English in _TabSpec; shown in the chosen language.
    final label = context.tr(tab.label);
    Widget icon = Icon(active ? tab.activeIcon : tab.icon, size: 24, color: color);
    if (tab.badge != null) {
      icon = ValueListenableBuilder<int>(
        valueListenable: tab.badge!,
        builder: (context, n, child) => Badge(
          isLabelVisible: n > 0,
          label: Text(n > 99 ? '99+' : '$n'),
          backgroundColor: AppColors.danger,
          child: child,
        ),
        child: icon,
      );
    }
    return Semantics(
      button: true,
      selected: active,
      label: label,
      child: InkResponse(
        onTap: onTap,
        radius: 36,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: AppMotion.medium,
              curve: AppMotion.curve,
              width: 56,
              height: 32,
              decoration: BoxDecoration(
                gradient: active ? tintGradient(AppColors.emerald, AppColors.teal, 0.18) : null,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              alignment: Alignment.center,
              child: icon,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: active ? AppColors.primaryDark : AppColors.textMuted,
                fontSize: 11.5,
                fontWeight: active ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The big round camera button in the middle of the bar: starts a new observation.
class _ScanButton extends StatelessWidget {
  final VoidCallback onTap;
  const _ScanButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: context.tr('New observation'),
      child: PressScale(
        scale: 0.92,
        child: InkResponse(
          radius: 40,
          onTap: () {
            HapticFeedback.lightImpact();
            onTap();
          },
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppColors.lime, AppColors.emerald, AppColors.teal],
                  ),
                  border: Border.all(color: AppColors.brandGold, width: 2.5),
                  boxShadow: [
                    BoxShadow(color: AppColors.primary.withValues(alpha: 0.4), blurRadius: 14, offset: const Offset(0, 5)),
                  ],
                ),
                child: const Icon(Icons.photo_camera_rounded, color: AppColors.surface, size: 26),
              ),
              const SizedBox(height: 2),
              Text(
                context.tr('Scan'),
                style: const TextStyle(color: AppColors.primaryDark, fontSize: 11.5, fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
