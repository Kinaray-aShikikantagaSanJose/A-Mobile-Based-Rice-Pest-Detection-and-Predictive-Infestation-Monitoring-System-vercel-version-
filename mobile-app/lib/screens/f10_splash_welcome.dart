import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widget_previews.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../app_router.dart';
import '../controllers/auth_controller.dart';
import '../theme.dart';
import '../widgets/brand.dart';
import '../widgets/motion.dart';
import 'f01_onboarding.dart' show kSeenOnboardingKey;

@Preview(name: 'F10SplashWelcome', size: Size(390.0, 844.0))
Widget previewF10SplashWelcome() {
	return const MaterialApp(
		debugShowCheckedModeBanner: false,
		home: F10SplashWelcome(skipSessionCheck: true),
	);
}

class F10SplashWelcome extends StatefulWidget {
	final bool skipSessionCheck;
	const F10SplashWelcome({super.key, this.skipSessionCheck = false});

	@override
	F10SplashWelcomeState createState() => F10SplashWelcomeState();
}

class F10SplashWelcomeState extends State<F10SplashWelcome>
		with SingleTickerProviderStateMixin {
	// Single controller, staggered via Intervals: logo, then title, then
	// subtitle, then each button. Finite, so pumpAndSettle stays happy.
	late final AnimationController _entrance;
	late final Animation<double> _logoFade;
	late final Animation<double> _logoScale;
	late final Animation<double> _titleIn;
	late final Animation<double> _subtitleIn;
	late final Animation<double> _primaryIn;
	late final Animation<double> _secondaryIn;
	bool _started = false;

	/// First launch (onboarding not finished yet): the primary CTA opens the
	/// onboarding tour instead of the login form. Defaults to "seen" so a
	/// storage failure never traps anyone in the tour.
	bool _seenOnboarding = true;

	Animation<double> _interval(double begin, double end) => CurvedAnimation(
		parent: _entrance,
		curve: Interval(begin, end, curve: AppMotion.curve),
	);

	@override
	void initState() {
		super.initState();
		SystemChrome.setPreferredOrientations([
			DeviceOrientation.portraitUp,
			DeviceOrientation.portraitDown,
		]);

		_entrance = AnimationController(
			vsync: this,
			duration: const Duration(milliseconds: 1100),
		);
		_logoFade = CurvedAnimation(
			parent: _entrance,
			curve: const Interval(0.0, 0.45, curve: Curves.easeOut),
		);
		_logoScale = Tween<double>(begin: 0.88, end: 1.0).animate(
			CurvedAnimation(parent: _entrance, curve: const Interval(0.0, 0.55, curve: AppMotion.curve)),
		);
		_titleIn = _interval(0.22, 0.65);
		_subtitleIn = _interval(0.32, 0.75);
		_primaryIn = _interval(0.5, 0.9);
		_secondaryIn = _interval(0.58, 1.0);

		_loadOnboardingState();
		if (!widget.skipSessionCheck) {
			_checkExistingSession();
		}
	}

	@override
	void didChangeDependencies() {
		super.didChangeDependencies();
		if (_started) return;
		_started = true;
		// "Remove animations" shows the finished layout straight away.
		if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
			_entrance.value = 1;
		} else {
			_entrance.forward();
		}
	}

	@override
	void dispose() {
		_entrance.dispose();
		super.dispose();
	}

	Future<void> _loadOnboardingState() async {
		try {
			final prefs = await SharedPreferences.getInstance();
			final bool seen = prefs.getBool(kSeenOnboardingKey) ?? false;
			if (mounted && seen != _seenOnboarding) {
				setState(() => _seenOnboarding = seen);
			}
		} catch (e) {
			debugPrint('[F10] could not read onboarding state: $e');
		}
	}

	/// A remembered session skips the welcome screen (the router also does this).
	void _checkExistingSession() {
		final auth = AuthControllerImpl.instance;
		if (auth.isLoggedIn && mounted) context.go(AppRouter.homeFor(auth.role));
	}

	/// Fade + short rise driven by one of the entrance intervals.
	Widget _rise(Animation<double> progress, Widget child, {double offset = 16}) {
		return FadeTransition(
			opacity: progress,
			child: AnimatedBuilder(
				animation: progress,
				builder: (context, child) => Transform.translate(
					offset: Offset(0, (1 - progress.value) * offset),
					child: child,
				),
				child: child,
			),
		);
	}

	@override
	Widget build(BuildContext context) {
		final double logoWidth = (MediaQuery.sizeOf(context).width * 0.6).clamp(170.0, 280.0);
		return AnnotatedRegion<SystemUiOverlayStyle>(
			value: SystemUiOverlayStyle.light.copyWith(
				statusBarColor: Colors.transparent,
				systemNavigationBarColor: AppColors.brandGreen,
			),
			child: Scaffold(
				backgroundColor: AppColors.brandGreen,
				body: SafeArea(
					child: LayoutBuilder(
						builder: (context, constraints) => SingleChildScrollView(
							child: ConstrainedBox(
								constraints: BoxConstraints(minHeight: constraints.maxHeight),
								child: IntrinsicHeight(
									child: Column(
										children: [
											Expanded(
												child: Padding(
													padding: const EdgeInsets.symmetric(horizontal: AppSpacing.hPad),
													child: Column(
														mainAxisAlignment: MainAxisAlignment.center,
														children: [
															const Spacer(flex: 2),
															const SizedBox(height: AppSpacing.xl),
															FadeTransition(
																opacity: _logoFade,
																child: ScaleTransition(
																	scale: _logoScale,
																	child: PalayPatrolLogo(width: logoWidth),
																),
															),
															const SizedBox(height: AppSpacing.xl),
															_rise(_titleIn, const BrandTitle(fontSize: 38)),
															const SizedBox(height: AppSpacing.md),
															_rise(
																_subtitleIn,
																ConstrainedBox(
																	constraints: const BoxConstraints(maxWidth: 340),
																	child: const Text(
																		kAppTagline,
																		style: TextStyle(
																			color: AppColors.brandTagline,
																			fontSize: 15.5,
																			fontWeight: FontWeight.w700,
																			height: 1.4,
																		),
																		textAlign: TextAlign.center,
																	),
																),
															),
															const SizedBox(height: AppSpacing.xl),
															const Spacer(flex: 3),
														],
													),
												),
											),
											Padding(
												padding: const EdgeInsets.fromLTRB(AppSpacing.hPad, 0, AppSpacing.hPad, AppSpacing.xl),
												child: _buildActions(),
											),
										],
									),
								),
							),
						),
					),
				),
			),
		);
	}

	Widget _buildActions() {
		return Column(
			children: [
				_rise(
					_primaryIn,
					_ActionButton(
						label: _seenOnboarding ? "Log In" : "Get Started",
						backgroundColor: AppColors.brandGold,
						textColor: AppColors.brandGreen,
						elevated: true,
						onTap: () => context.go(_seenOnboarding ? AppRouter.login : AppRouter.onboarding),
					),
				),
				const SizedBox(height: AppSpacing.lg),
				_rise(
					_secondaryIn,
					Column(
						children: [
							_ActionButton(
								label: "Create Account",
								backgroundColor: AppColors.brandLime.withValues(alpha: 0.08),
								textColor: AppColors.brandTagline,
								borderColor: AppColors.brandLime.withValues(alpha: 0.55),
								onTap: () => context.go(AppRouter.register),
							),
							_buildLoginLink(),
						],
					),
				),
			],
		);
	}

	/// First launch adds a text link; it grows in (rather than jumping) when
	/// the stored onboarding flag arrives. AnimatedSize can't take a zero
	/// duration, so reduced motion simply shows or hides it.
	Widget _buildLoginLink() {
		final Widget link = _seenOnboarding
				? const SizedBox(width: double.infinity)
				: FadeSlideIn(
						offset: 6,
						child: Padding(
							padding: const EdgeInsets.only(top: AppSpacing.sm),
							child: TextButton(
								onPressed: () => context.go(AppRouter.login),
								style: TextButton.styleFrom(
									foregroundColor: AppColors.brandTagline,
									minimumSize: const Size(64, 44),
								),
								child: const Text(
									'I already have an account',
									style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
								),
							),
						),
					);
		if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return link;
		return AnimatedSize(
			duration: AppMotion.medium,
			curve: AppMotion.curve,
			alignment: Alignment.topCenter,
			child: link,
		);
	}
}

class _ActionButton extends StatelessWidget {
	final String label;
	final Color backgroundColor;
	final Color textColor;
	final Color? borderColor;
	final bool elevated;
	final VoidCallback onTap;

	const _ActionButton({
		required this.label,
		required this.backgroundColor,
		required this.textColor,
		this.borderColor,
		this.elevated = false,
		required this.onTap,
	});

	@override
	Widget build(BuildContext context) {
		return PressScale(
			child: DecoratedBox(
				decoration: BoxDecoration(
					borderRadius: BorderRadius.circular(AppRadius.pill),
					// Soft elevated shadow on the primary CTA only — separates it
					// from the ghost button below.
					boxShadow: elevated
							? [
									BoxShadow(
										color: AppColors.brandGold.withValues(alpha: 0.30),
										blurRadius: 18,
										offset: const Offset(0, 8),
									),
								]
							: null,
				),
				child: Material(
					color: backgroundColor,
					clipBehavior: Clip.antiAlias,
					shape: StadiumBorder(
						side: borderColor != null ? BorderSide(color: borderColor!) : BorderSide.none,
					),
					child: InkWell(
						onTap: onTap,
						child: Padding(
							padding: const EdgeInsets.symmetric(vertical: 18, horizontal: AppSpacing.lg),
							child: SizedBox(
								width: double.infinity,
								// Label swaps ("Log In" / "Get Started") cross-fade.
								child: AppSwitcher(
									duration: AppMotion.fast,
									alignment: Alignment.center,
									child: Text(
										label,
										key: ValueKey(label),
										style: TextStyle(
											color: textColor,
											fontSize: 15,
											fontWeight: FontWeight.bold,
										),
										textAlign: TextAlign.center,
									),
								),
							),
						),
					),
				),
			),
		);
	}
}
