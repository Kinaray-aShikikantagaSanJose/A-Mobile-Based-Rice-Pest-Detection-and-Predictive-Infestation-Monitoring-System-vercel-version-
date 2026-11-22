import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widget_previews.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../app_router.dart';
import '../l10n/app_language.dart';
import '../theme.dart';
import '../widgets/app_widgets.dart';
import '../widgets/language_button.dart';
import '../widgets/motion.dart';

/// SharedPreferences flag set once the user finishes (or skips) the tour.
/// The splash screen reads it to decide where its primary button leads.
const String kSeenOnboardingKey = 'seenOnboarding';

@Preview(name: 'F01Onboarding', size: Size(390.0, 844.0))
Widget previewF01Onboarding() {
  return const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: F01OnboardingScreen(),
  );
}

/// A small icon shown orbiting the main illustration.
class OnboardingBadge {
  final IconData icon;
  final Color color;

  const OnboardingBadge(this.icon, this.color);
}

/// Data model representing a single onboarding screen's content.
class OnboardingData {
  final IconData icon;
  final List<OnboardingBadge> badges;
  final String title;
  final String description;
  final String buttonText;

  const OnboardingData({
    required this.icon,
    required this.badges,
    required this.title,
    required this.description,
    required this.buttonText,
  });
}

class F01OnboardingScreen extends StatefulWidget {
  const F01OnboardingScreen({super.key});

  @override
  State<F01OnboardingScreen> createState() => _F01OnboardingScreenState();
}

class _F01OnboardingScreenState extends State<F01OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  bool _finishing = false;

  // Illustrations are composed from icons so the tour works offline.
  static const List<OnboardingData> _pages = [
    OnboardingData(
      icon: Icons.document_scanner_outlined,
      badges: [
        OnboardingBadge(Icons.bug_report_outlined, AppColors.danger),
        OnboardingBadge(Icons.photo_camera_outlined, AppColors.primary),
        OnboardingBadge(Icons.auto_awesome_outlined, AppColors.orange),
      ],
      title: 'Pest Identification (Model Result)',
      description:
          'Capture field images to detect supported pests, crop stages, and infestation indications in seconds.',
      buttonText: 'Next',
    ),
    OnboardingData(
      icon: Icons.fact_check_outlined,
      badges: [
        OnboardingBadge(Icons.engineering_outlined, AppColors.primary),
        OnboardingBadge(Icons.forum_outlined, AppColors.orange),
        OnboardingBadge(Icons.verified_outlined, AppColors.success),
      ],
      title: 'Expert Validation',
      description:
          'Send field data to agricultural technicians to verify diagnoses and receive custom management recommendations.',
      buttonText: 'Next',
    ),
    OnboardingData(
      icon: Icons.map_outlined,
      badges: [
        OnboardingBadge(Icons.location_on_outlined, AppColors.danger),
        OnboardingBadge(Icons.trending_up_rounded, AppColors.orange),
        OnboardingBadge(Icons.bar_chart_rounded, AppColors.primary),
      ],
      title: 'Hotspots and Field Trends',
      description:
          'Track treatment outcomes, monitor localized hotspot maps, and view quarterly pest trend advisories.',
      buttonText: 'Get Started',
    ),
  ];

  bool get _isLastPage => _currentPage == _pages.length - 1;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  bool get _reduceMotion => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  void _onNextPressed() {
    if (!_isLastPage) {
      if (_reduceMotion) {
        _pageController.jumpToPage(_currentPage + 1);
      } else {
        _pageController.nextPage(
          duration: AppMotion.page,
          curve: AppMotion.curve,
        );
      }
    } else {
      _finish();
    }
  }

  void _onPageChanged(int index) {
    HapticFeedback.selectionClick();
    setState(() => _currentPage = index);
  }

  Future<void> _finish() async {
    if (_finishing) return;
    _finishing = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(kSeenOnboardingKey, true);
    } catch (e) {
      debugPrint('[F01] could not save onboarding state: $e');
    }
    if (!mounted) return;
    context.go(AppRouter.login);
  }

  @override
  Widget build(BuildContext context) {
    final page = _pages[_currentPage];
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // Skip (fades out on the last page, space kept so nothing jumps)
            // and the language picker in the top-right corner.
            FadeSlideIn(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.hPad, AppSpacing.sm, AppSpacing.md, 0),
                child: Row(
                  children: [
                    const Spacer(),
                    IgnorePointer(
                      ignoring: _isLastPage,
                      child: ExcludeSemantics(
                        excluding: _isLastPage,
                        child: AnimatedOpacity(
                          opacity: _isLastPage ? 0 : 1,
                          duration: AppMotion.medium,
                          curve: AppMotion.curve,
                          child: TextButton(
                            onPressed: _finish,
                            style: TextButton.styleFrom(
                              foregroundColor: AppColors.textSecondary,
                              minimumSize: const Size(64, 44),
                            ),
                            child: Text(
                              context.tr('Skip'),
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    const LanguageButton(),
                  ],
                ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _pages.length,
                onPageChanged: _onPageChanged,
                itemBuilder: (context, index) => _OnboardingPage(
                  data: _pages[index],
                  index: index,
                  controller: _pageController,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.hPad, AppSpacing.md, AppSpacing.hPad, AppSpacing.xl),
              child: Column(
                children: staggered([
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      _pages.length,
                      (index) => _buildDotIndicator(index == _currentPage),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xl),
                    // "Next" -> "Get Started" cross-fades instead of snapping.
                    child: AppSwitcher(
                      child: AppPrimaryButton(
                        key: ValueKey(_isLastPage),
                        label: context.tr(page.buttonText),
                        icon: _isLastPage ? null : Icons.arrow_forward_rounded,
                        onPressed: _onNextPressed,
                      ),
                    ),
                  ),
                ], start: 4),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Builds a single pagination dot (animated width and color).
  Widget _buildDotIndicator(bool isActive) {
    return AnimatedContainer(
      duration: AppMotion.medium,
      curve: AppMotion.curve,
      margin: const EdgeInsets.symmetric(horizontal: 4.0),
      height: 8.0,
      width: isActive ? 24.0 : 8.0,
      decoration: BoxDecoration(
        color: isActive ? AppColors.primary : AppColors.border,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
    );
  }
}

/// One tour page. Kept alive so its entrance plays once; while swiping,
/// the illustration lags behind the page (parallax) and the copy fades.
class _OnboardingPage extends StatefulWidget {
  final OnboardingData data;
  final int index;
  final PageController controller;

  const _OnboardingPage({
    required this.data,
    required this.index,
    required this.controller,
  });

  @override
  State<_OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<_OnboardingPage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  /// Signed distance of this page from the settled page (0 = centred).
  double _offset() {
    final PageController c = widget.controller;
    if (!c.hasClients || !c.position.hasContentDimensions) return 0;
    final double page = c.page ?? widget.index.toDouble();
    return (page - widget.index).clamp(-1.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final bool reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final OnboardingData data = widget.data;
    return LayoutBuilder(
      builder: (context, constraints) {
        // Illustration shrinks on short screens so the text always fits;
        // anything left over scrolls instead of overflowing.
        final double art = math.max(
          120.0,
          math.min(260.0, math.min(constraints.maxWidth * 0.7, constraints.maxHeight * 0.48)),
        );
        final Widget illustration = FadeSlideIn(
          index: 1,
          child: _OnboardingIllustration(data: data, size: art),
        );
        final Widget copy = Column(
          children: staggered([
            Text(
              context.tr(data.title),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: AppFonts.display,
                fontSize: 24.0,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
                letterSpacing: -0.5,
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.md),
              child: Text(
                context.tr(data.description),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14.0,
                  color: AppColors.textSecondary,
                  height: 1.5,
                ),
              ),
            ),
          ], start: 2),
        );
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.hPad),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedBuilder(
                  animation: widget.controller,
                  builder: (context, child) {
                    final double d = reduceMotion ? 0 : _offset();
                    return Transform.translate(
                      offset: Offset(d * constraints.maxWidth * 0.3, 0),
                      child: Transform.scale(scale: 1 - d.abs() * 0.12, child: child),
                    );
                  },
                  child: illustration,
                ),
                const SizedBox(height: AppSpacing.xxl),
                AnimatedBuilder(
                  animation: widget.controller,
                  builder: (context, child) {
                    final double d = reduceMotion ? 0 : _offset();
                    return Opacity(
                      opacity: (1 - d.abs() * 1.2).clamp(0.0, 1.0),
                      child: child,
                    );
                  },
                  child: copy,
                ),
                const SizedBox(height: AppSpacing.lg),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Large tinted circle with the page's main icon and small badges around it.
class _OnboardingIllustration extends StatelessWidget {
  final OnboardingData data;
  final double size;

  const _OnboardingIllustration({required this.data, required this.size});

  @override
  Widget build(BuildContext context) {
    final double badge = size * 0.24;
    // Badge centres on a ring around the main circle (angles in degrees).
    const List<double> angles = [-40, 200, 95];
    final double ring = size * 0.44;
    final Offset c = Offset(size / 2, size / 2);

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.accentLight.withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Center(
            child: Container(
              width: size * 0.62,
              height: size * 0.62,
              decoration: const BoxDecoration(
                color: AppColors.accentLight,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Container(
                  width: size * 0.4,
                  height: size * 0.4,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Icon(data.icon, size: size * 0.2, color: AppColors.primary),
                ),
              ),
            ),
          ),
          for (int i = 0; i < data.badges.length && i < angles.length; i++)
            Positioned(
              left: c.dx + ring * math.cos(angles[i] * math.pi / 180) - badge / 2,
              top: c.dy + ring * math.sin(angles[i] * math.pi / 180) - badge / 2,
              width: badge,
              height: badge,
              // Badges settle in just after the main circle.
              child: FadeSlideIn(
                index: 3 + i,
                offset: 8,
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Icon(
                    data.badges[i].icon,
                    size: badge * 0.5,
                    color: data.badges[i].color,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
