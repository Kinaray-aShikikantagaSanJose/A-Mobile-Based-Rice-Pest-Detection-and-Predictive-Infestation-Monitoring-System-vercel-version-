import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../app_router.dart';

/// Goes back to the tab shell and opens [tab] there, from anywhere (a result
/// screen's "Back to dashboard", "Next in queue"). The shell may still be
/// alive under the current screen, so the tab is passed as a request it
/// listens for rather than a route parameter.
class ShellNav {
  static final ValueNotifier<String?> request = ValueNotifier<String?>(null);

  static void open(BuildContext context, [String tab = AppTab.home]) {
    request.value = tab;
    context.go(AppRouter.home);
  }
}

/// Tab ids used by the bottom navigation (see screens/main_shell.dart).
class AppTab {
  static const String home = 'home';
  static const String records = 'records';
  static const String treatments = 'treatments';
  static const String alerts = 'alerts';
  static const String queue = 'queue';
  static const String map = 'map';
}

/// Lets a page inside the bottom-navigation shell switch tabs, and tells a
/// screen whether it is showing as a tab (no back button) or was pushed.
class ShellScope extends InheritedWidget {
  final String currentTab;
  final List<String> tabs;
  final ValueChanged<String> goTab;

  const ShellScope({
    super.key,
    required this.currentTab,
    required this.tabs,
    required this.goTab,
    required super.child,
  });

  /// Doesn't subscribe to tab changes (safe to call from callbacks).
  static ShellScope? maybeOf(BuildContext context) => context.getInheritedWidgetOfExactType<ShellScope>();

  /// Switches to [tab] when this user has it; returns false otherwise so the
  /// caller can push a screen instead.
  static bool tryGoTab(BuildContext context, String tab) {
    final scope = maybeOf(context);
    if (scope == null || !scope.tabs.contains(tab)) return false;
    scope.goTab(tab);
    return true;
  }

  @override
  bool updateShouldNotify(ShellScope oldWidget) =>
      oldWidget.currentTab != currentTab || oldWidget.tabs.length != tabs.length;
}
