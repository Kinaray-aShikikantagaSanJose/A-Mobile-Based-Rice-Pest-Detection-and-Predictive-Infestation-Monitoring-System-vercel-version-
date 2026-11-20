import 'package:flutter/material.dart';
import '../theme.dart';

/// Shared motion primitives so every screen moves like the F20 home
/// dashboard: staggered fade-and-rise entrances, press feedback, animated
/// state swaps, count-ups, progress fills and shimmer skeletons.
///
/// Everything honours the system "remove animations" setting
/// (MediaQuery.disableAnimations) and uses only finite animations except
/// [Shimmer], which only runs while a skeleton is on screen.

bool _reduceMotion(BuildContext context) =>
    MediaQuery.maybeDisableAnimationsOf(context) ?? false;

/// Fades and rises [child] into place once, when first built. [index]
/// staggers siblings (index * [AppMotion.stagger], capped at
/// [AppMotion.maxStagger]); items far down a list appear instantly.
class FadeSlideIn extends StatefulWidget {
  final Widget child;
  final int index;
  final double offset;
  final Duration? delay;

  const FadeSlideIn({
    super.key,
    required this.child,
    this.index = 0,
    this.offset = 14,
    this.delay,
  });

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _progress;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    final int steps = widget.index.clamp(0, AppMotion.maxStagger);
    final Duration delay = widget.delay ?? AppMotion.stagger * steps;
    final Duration total = delay + AppMotion.entrance;
    _controller = AnimationController(vsync: this, duration: total);
    // The delay lives inside the curve (no Timer), so tests and
    // pumpAndSettle never see a pending timer.
    final double start = total.inMicroseconds == 0
        ? 0
        : delay.inMicroseconds / total.inMicroseconds;
    _progress = CurvedAnimation(
      parent: _controller,
      curve: Interval(start, 1, curve: AppMotion.curve),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (_reduceMotion(context) || widget.index > AppMotion.maxStagger * 2) {
      _controller.value = 1;
    } else {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _progress,
      child: AnimatedBuilder(
        animation: _progress,
        builder: (context, child) => Transform.translate(
          offset: Offset(0, (1 - _progress.value) * widget.offset),
          child: child,
        ),
        child: widget.child,
      ),
    );
  }
}

/// Wraps each child in a [FadeSlideIn] with an increasing stagger index.
List<Widget> staggered(Iterable<Widget> children, {int start = 0}) {
  var i = start;
  return [for (final c in children) FadeSlideIn(index: i++, child: c)];
}

/// Subtle scale-down while pressed (cards, buttons). Uses a [Listener] so it
/// never competes with the child's own tap handling, and releases as soon as
/// the finger starts scrolling.
class PressScale extends StatefulWidget {
  final Widget child;
  final bool enabled;
  final double scale;

  const PressScale({
    super.key,
    required this.child,
    this.enabled = true,
    this.scale = 0.97,
  });

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _pressed = false;
  Offset? _down;

  void _set(bool v) {
    if (_pressed != v && mounted) setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled || _reduceMotion(context)) return widget.child;
    return Listener(
      onPointerDown: (e) {
        _down = e.position;
        _set(true);
      },
      onPointerMove: (e) {
        final d = _down;
        if (d != null && (e.position - d).distance > 8) _set(false);
      },
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: AnimatedScale(
        scale: _pressed ? widget.scale : 1,
        duration: AppMotion.fast,
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

/// Animated swap between states (loading -> content, filter/tab changes,
/// empty <-> list). Give each state's child a distinct [Key].
class AppSwitcher extends StatelessWidget {
  final Widget child;
  final Duration duration;
  final AlignmentGeometry alignment;

  const AppSwitcher({
    super.key,
    required this.child,
    this.duration = AppMotion.medium,
    this.alignment = Alignment.topCenter,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: _reduceMotion(context) ? Duration.zero : duration,
      switchInCurve: AppMotion.curve,
      switchOutCurve: Curves.easeIn,
      layoutBuilder: (current, previous) =>
          Stack(alignment: alignment, children: [...previous, ?current]),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.015),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

/// Rounded progress bar that fills smoothly (and re-animates on change).
class AnimatedProgressBar extends StatelessWidget {
  final double value;
  final Color color;
  final Color? track;
  final double height;

  const AnimatedProgressBar({
    super.key,
    required this.value,
    this.color = AppColors.primary,
    this.track,
    this.height = 6,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: Stack(
        children: [
          Container(
            height: height,
            width: double.infinity,
            color: track ?? AppColors.primary.withValues(alpha: 0.12),
          ),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: value.clamp(0.0, 1.0)),
            duration: _reduceMotion(context)
                ? Duration.zero
                : AppMotion.countUp,
            curve: AppMotion.curve,
            builder: (context, v, child) =>
                FractionallySizedBox(widthFactor: v, child: child),
            child: Container(
              height: height,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Number that counts up to [value] (and animates between later values).
class CountUp extends StatelessWidget {
  final num value;
  final TextStyle? style;
  final int decimals;
  final String prefix;
  final String suffix;
  final TextAlign? textAlign;

  const CountUp({
    super.key,
    required this.value,
    this.style,
    this.decimals = 0,
    this.prefix = '',
    this.suffix = '',
    this.textAlign,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value.toDouble()),
      duration: _reduceMotion(context) ? Duration.zero : AppMotion.countUp,
      curve: AppMotion.curve,
      builder: (context, v, _) => Text(
        '$prefix${v.toStringAsFixed(decimals)}$suffix',
        style: style,
        textAlign: textAlign,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

/// Chevron that rotates when [expanded] flips.
class AnimatedChevron extends StatelessWidget {
  final bool expanded;
  final Color color;
  final double size;

  const AnimatedChevron({
    super.key,
    required this.expanded,
    this.color = AppColors.textMuted,
    this.size = 22,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedRotation(
      turns: expanded ? 0.5 : 0,
      duration: AppMotion.medium,
      curve: AppMotion.curve,
      child: Icon(Icons.keyboard_arrow_down_rounded, size: size, color: color),
    );
  }
}

/// Smoothly grows/shrinks to reveal [child] when [expanded].
class AnimatedReveal extends StatelessWidget {
  final bool expanded;
  final Widget child;

  const AnimatedReveal({
    super.key,
    required this.expanded,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    // AnimatedSize asserts on a zero duration ("mutated in its own
    // performLayout"), so with reduced motion just show or hide.
    if (_reduceMotion(context)) {
      return expanded ? child : const SizedBox(width: double.infinity);
    }
    return AnimatedSize(
      duration: AppMotion.medium,
      curve: AppMotion.curve,
      alignment: Alignment.topCenter,
      child: expanded
          ? FadeSlideIn(offset: 6, child: child)
          : const SizedBox(width: double.infinity),
    );
  }
}

// ---------------------------------------------------------------------------
// Skeleton loading
// ---------------------------------------------------------------------------

/// Sweeping highlight over skeleton shapes while content loads.
class Shimmer extends StatefulWidget {
  final Widget child;
  const Shimmer({super.key, required this.child});

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_reduceMotion(context)) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final double t = _controller.value;
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (rect) => LinearGradient(
            begin: Alignment(-1.6 + 3.2 * t, -0.2),
            end: Alignment(-0.6 + 3.2 * t, 0.2),
            colors: [
              AppColors.border.withValues(alpha: 0.0),
              AppColors.surface.withValues(alpha: 0.65),
              AppColors.border.withValues(alpha: 0.0),
            ],
          ).createShader(rect),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

/// Placeholder block used inside skeletons.
class SkeletonBox extends StatelessWidget {
  final double? width;
  final double height;
  final double radius;
  final bool circle;

  const SkeletonBox({
    super.key,
    this.width,
    this.height = 12,
    this.radius = AppRadius.xs,
    this.circle = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: circle ? height : width,
      height: height,
      decoration: BoxDecoration(
        color: AppColors.border.withValues(alpha: 0.75),
        shape: circle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: circle ? null : BorderRadius.circular(radius),
      ),
    );
  }
}

/// Skeleton of a list row (48px circle, two text lines, trailing chip),
/// matching the F20 list rows.
class SkeletonRow extends StatelessWidget {
  const SkeletonRow({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        children: [
          SkeletonBox(height: 48, circle: true),
          SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FractionallySizedBox(
                  widthFactor: 0.6,
                  child: SkeletonBox(height: 14),
                ),
                SizedBox(height: 8),
                FractionallySizedBox(
                  widthFactor: 0.4,
                  child: SkeletonBox(height: 11),
                ),
              ],
            ),
          ),
          SizedBox(width: AppSpacing.sm),
          SkeletonBox(width: 56, height: 22, radius: AppRadius.pill),
        ],
      ),
    );
  }
}

/// Skeleton of a bordered card of [height].
class SkeletonCard extends StatelessWidget {
  final double height;
  const SkeletonCard({super.key, this.height = 120});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: height,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.border),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FractionallySizedBox(
            widthFactor: 0.45,
            child: SkeletonBox(height: 14),
          ),
          SizedBox(height: 12),
          FractionallySizedBox(
            widthFactor: 0.8,
            child: SkeletonBox(height: 11),
          ),
          SizedBox(height: 8),
          FractionallySizedBox(
            widthFactor: 0.65,
            child: SkeletonBox(height: 11),
          ),
        ],
      ),
    );
  }
}

/// Ready-made loading state: [rows] list-row skeletons (optionally inside
/// cards) under a shimmer.
class SkeletonList extends StatelessWidget {
  final int rows;
  final bool cards;
  final double cardHeight;

  const SkeletonList({
    super.key,
    this.rows = 4,
    this.cards = false,
    this.cardHeight = 110,
  });

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: Column(
        children: [
          for (var i = 0; i < rows; i++)
            Padding(
              padding: EdgeInsets.only(bottom: cards ? AppSpacing.md : 0),
              child: cards
                  ? SkeletonCard(height: cardHeight)
                  : const SkeletonRow(),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Page transitions
// ---------------------------------------------------------------------------

/// Fade + short horizontal slide for pushed screens (same feel as the
/// capture flow). The outgoing page recedes slightly underneath.
class AppPageTransitionsBuilder extends PageTransitionsBuilder {
  const AppPageTransitionsBuilder();

  @override
  Duration get transitionDuration => AppMotion.page;

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 260);

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (_reduceMotion(context)) return child;
    final incoming = CurvedAnimation(
      parent: animation,
      curve: AppMotion.curve,
      reverseCurve: Curves.easeInCubic,
    );
    final outgoing = CurvedAnimation(
      parent: secondaryAnimation,
      curve: AppMotion.curve,
    );
    return SlideTransition(
      position: Tween<Offset>(
        begin: Offset.zero,
        end: const Offset(-0.04, 0),
      ).animate(outgoing),
      child: FadeTransition(
        opacity: incoming,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.06, 0),
            end: Offset.zero,
          ).animate(incoming),
          child: child,
        ),
      ),
    );
  }
}

/// Scales and fades [child] in once with a slight overshoot, after [delay]
/// (status icons, badges, check marks).
class PopIn extends StatelessWidget {
  final Duration delay;
  final Widget child;

  const PopIn({super.key, this.delay = Duration.zero, required this.child});

  @override
  Widget build(BuildContext context) {
    final Duration total = delay + AppMotion.entrance;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: _reduceMotion(context) ? Duration.zero : total,
      curve: Interval(delay.inMicroseconds / total.inMicroseconds, 1, curve: Curves.easeOutBack),
      builder: (context, t, child) => Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: Transform.scale(scale: 0.6 + 0.4 * t, child: child),
      ),
      child: child,
    );
  }
}
