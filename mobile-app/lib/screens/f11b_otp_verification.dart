import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widget_previews.dart';
import 'package:go_router/go_router.dart';
import '../app_router.dart';
import '../services/auth_service.dart';
import '../controllers/auth_controller.dart';
import '../l10n/app_language.dart';
import '../theme.dart';
import '../widgets/app_widgets.dart';
import '../widgets/motion.dart';

@Preview(name: 'F11bOtpVerification', size: Size(390.0, 844.0))
Widget previewF11bOtpVerification() {
	return const MaterialApp(
		debugShowCheckedModeBanner: false,
		home: F11bOtpVerification(contact: 'farmer@example.com', fullName: 'Juan Dela Cruz'),
	);
}

const int _kCodeLength = 6;

/// Matches the backend's resend cooldown (RESEND_COOLDOWN_SECONDS).
const int _kResendCooldownSeconds = 45;

class F11bOtpVerification extends StatefulWidget {
	final String contact;
	final String fullName;
	/// Password from registration, used once to sign in after verification
	/// so the session gets a real token and role. Held in memory only.
	final String password;

	const F11bOtpVerification({
		super.key,
		required this.contact,
		this.fullName = '',
		this.password = '',
	});

	@override
	F11bOtpVerificationState createState() => F11bOtpVerificationState();
}

class F11bOtpVerificationState extends State<F11bOtpVerification> {
	final List<TextEditingController> _controllers =
			List.generate(_kCodeLength, (_) => TextEditingController());
	late final List<FocusNode> _focusNodes = List.generate(
		_kCodeLength,
		(i) => FocusNode(onKeyEvent: (_, event) => _handleKey(i, event)),
	);
	Timer? _timer;
	int _secondsRemaining = _kResendCooldownSeconds;
	int _activeIndex = 0;
	bool _isVerifying = false;
	bool _isResending = false;

	@override
	void initState() {
		super.initState();
		SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);
		for (int i = 0; i < _kCodeLength; i++) {
			_focusNodes[i].addListener(() {
				if (!mounted) return;
				if (_focusNodes[i].hasFocus && _activeIndex != i) {
					setState(() => _activeIndex = i);
				} else if (!_focusNodes[i].hasFocus && _activeIndex == i) {
					// Keyboard dismissed: drop the focus ring.
					setState(() {});
				}
			});
		}
		_startTimer();
		WidgetsBinding.instance.addPostFrameCallback((_) {
			if (mounted) _focusNodes[0].requestFocus();
		});
	}

	@override
	void dispose() {
		_timer?.cancel();
		for (final c in _controllers) {
			c.dispose();
		}
		for (final f in _focusNodes) {
			f.dispose();
		}
		super.dispose();
	}

	void _startTimer() {
		_timer?.cancel();
		_secondsRemaining = _kResendCooldownSeconds;
		_timer = Timer.periodic(const Duration(seconds: 1), (timer) {
			if (!mounted) {
				timer.cancel();
				return;
			}
			if (_secondsRemaining <= 1) {
				timer.cancel();
				setState(() => _secondsRemaining = 0);
			} else {
				setState(() => _secondsRemaining--);
			}
		});
	}

	String get _code => _controllers.map((c) => c.text).join();

	/// Fills every box from a pasted/autofilled code.
	void _fillFrom(String digits) {
		for (int i = 0; i < _kCodeLength; i++) {
			final d = i < digits.length ? digits[i] : '';
			_controllers[i].value = TextEditingValue(
				text: d,
				selection: TextSelection.collapsed(offset: d.length),
			);
		}
	}

	void _onOtpChanged(int index, String value) {
		if (value.length == _kCodeLength) {
			// Pasted or autofilled the whole code into one box.
			_fillFrom(value);
			_focusNodes[_kCodeLength - 1].requestFocus();
		} else if (value.isEmpty) {
			// Deleted this box's digit: step back so repeated backspace clears the code.
			if (index > 0) _focusNodes[index - 1].requestFocus();
		} else if (index < _kCodeLength - 1) {
			_focusNodes[index + 1].requestFocus();
		}
		setState(() {});
	}

	/// Backspace in an already-empty box clears and focuses the previous one
	/// (no text change happens, so onChanged never fires for it).
	KeyEventResult _handleKey(int index, KeyEvent event) {
		if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
		if (event.logicalKey != LogicalKeyboardKey.backspace) return KeyEventResult.ignored;
		if (index == 0 || _controllers[index].text.isNotEmpty) return KeyEventResult.ignored;
		_controllers[index - 1].clear();
		_focusNodes[index - 1].requestFocus();
		setState(() {});
		return KeyEventResult.handled;
	}

	void _onBoxTap(int index) {
		// Select the digit so typing replaces it.
		final c = _controllers[index];
		c.selection = TextSelection(baseOffset: 0, extentOffset: c.text.length);
	}

	Future<void> _verify() async {
		if (_isVerifying) return;
		final code = _code;
		if (code.length != _kCodeLength || code.contains(RegExp(r'\D'))) {
			_showMessage('Enter the complete 6-digit code.');
			return;
		}
		FocusScope.of(context).unfocus();
		setState(() => _isVerifying = true);

		try {
			await AuthService.instance.verifyOtp(email: widget.contact, code: code);
		} catch (e) {
			if (!mounted) return;
			setState(() => _isVerifying = false);
			_showMessage(_cleanError(e));
			return;
		}

		// Verified. Sign in with the registration password; the account is active
		// right away (approval is off on the backend), so the router opens home.
		Session? session;
		if (widget.password.isNotEmpty) {
			try {
				session = await AuthService.instance.signIn(
					email: widget.contact,
					password: widget.password,
				);
			} catch (e) {
				debugPrint('[F11b] sign-in after verification failed: $e');
			}
		}
		if (!mounted) return;

		if (session == null) {
			setState(() => _isVerifying = false);
			_showMessage('Email verified. Please log in.');
			context.go(AppRouter.login);
			return;
		}

		HapticFeedback.lightImpact();
		_showMessage('Email verified.');
		await AuthControllerImpl.instance.startSession(session);
	}

	Future<void> _resend() async {
		if (_secondsRemaining > 0 || _isResending) return;
		setState(() => _isResending = true);
		try {
			await AuthService.instance.resendOtp(email: widget.contact);
			if (!mounted) return;
			for (final controller in _controllers) {
				controller.clear();
			}
			setState(_startTimer);
			_focusNodes[0].requestFocus();
			_showMessage('New code sent.');
		} catch (e) {
			if (!mounted) return;
			_showMessage(_cleanError(e));
		} finally {
			if (mounted) setState(() => _isResending = false);
		}
	}

	void _goBack() {
		if (context.canPop()) {
			context.pop();
		} else {
			context.go(AppRouter.register);
		}
	}

	void _showMessage(String message) {
		ScaffoldMessenger.of(context)..hideCurrentSnackBar()..showSnackBar(SnackBar(content: Text(context.tr(message))));
	}

	String _cleanError(Object error) => error.toString().replaceFirst('Exception: ', '');

	@override
	Widget build(BuildContext context) {
		return Scaffold(
			backgroundColor: AppColors.background,
			body: SafeArea(
				child: Column(
					children: [
						Expanded(
							child: SingleChildScrollView(
								padding: const EdgeInsets.symmetric(horizontal: AppSpacing.hPad),
								child: Column(
									crossAxisAlignment: CrossAxisAlignment.start,
									children: [
										const SizedBox(height: AppSpacing.md),
										...staggered([
											AppCircleButton(
												icon: Icons.arrow_back_rounded,
												tooltip: context.tr('Back'),
												onTap: _isVerifying ? null : _goBack,
											),
											Padding(
												padding: const EdgeInsets.only(top: AppSpacing.lg),
												child: _buildHeader(),
											),
											Padding(
												padding: const EdgeInsets.only(top: AppSpacing.xl),
												child: _buildEmailIcon(),
											),
											Padding(
												padding: const EdgeInsets.only(top: AppSpacing.xl),
												child: _buildOtpRow(),
											),
											Padding(
												padding: const EdgeInsets.only(top: AppSpacing.md),
												child: _buildResendRow(),
											),
										]),
										const SizedBox(height: AppSpacing.lg),
									],
								),
							),
						),
						FadeSlideIn(
							index: 5,
							child: Padding(
								padding: const EdgeInsets.fromLTRB(AppSpacing.hPad, AppSpacing.md, AppSpacing.hPad, AppSpacing.lg),
								child: AppPrimaryButton(
									label: context.tr('Verify'),
									loading: _isVerifying,
									onPressed: _verify,
								),
							),
						),
					],
				),
			),
		);
	}

	Widget _buildHeader() {
		final String target = widget.contact.isNotEmpty ? widget.contact : context.tr('your email');
		// Split the translated sentence around {email} so the address stays bold.
		final List<String> sentence =
				context.tr('Enter the 6-digit code sent to {email} to continue.').split('{email}');
		return Column(
			crossAxisAlignment: CrossAxisAlignment.start,
			children: [
				Text(
					context.tr('Verify Your Account'),
					style: const TextStyle(
						fontFamily: AppFonts.display,
						color: AppColors.textPrimary,
						fontSize: 28,
						fontWeight: FontWeight.bold,
						height: 1.2,
					),
				),
				const SizedBox(height: AppSpacing.sm),
				Text.rich(
					TextSpan(
						style: const TextStyle(color: AppColors.textSecondary, fontSize: 14, height: 1.4),
						children: [
							TextSpan(text: sentence.first),
							TextSpan(
								text: target,
								style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600),
							),
							if (sentence.length > 1) TextSpan(text: sentence.sublist(1).join()),
						],
					),
				),
			],
		);
	}

	Widget _buildEmailIcon() {
		return Center(
			child: Container(
				width: 88,
				height: 88,
				decoration: const BoxDecoration(color: AppColors.accentLight, shape: BoxShape.circle),
				child: const Icon(Icons.mark_email_unread_outlined, color: AppColors.primary, size: 40),
			),
		);
	}

	Widget _buildOtpRow() {
		return LayoutBuilder(
			builder: (context, constraints) {
				const double gap = 8;
				// Six boxes always fit the available width (312dp on a 360dp phone).
				final double boxWidth = ((constraints.maxWidth - gap * (_kCodeLength - 1)) / _kCodeLength)
						.clamp(0.0, 52.0);
				final double boxHeight = (boxWidth * 1.2).clamp(44.0, 60.0);
				return Row(
					mainAxisAlignment: MainAxisAlignment.center,
					children: [
						for (int index = 0; index < _kCodeLength; index++) ...[
							if (index > 0) const SizedBox(width: gap),
							SizedBox(
								width: boxWidth,
								height: boxHeight,
								child: _OtpBox(
									controller: _controllers[index],
									focusNode: _focusNodes[index],
									isActive: index == _activeIndex && _focusNodes[index].hasFocus,
									isFilled: _controllers[index].text.isNotEmpty,
									isLast: index == _kCodeLength - 1,
									fontSize: (boxWidth * 0.48).clamp(16.0, 24.0),
									onChanged: (v) => _onOtpChanged(index, v),
									onTap: () => _onBoxTap(index),
									onSubmitted: _verify,
								),
							),
						],
					],
				);
			},
		);
	}

	Widget _buildResendRow() {
		final minutes = (_secondsRemaining ~/ 60).toString();
		final seconds = (_secondsRemaining % 60).toString().padLeft(2, '0');
		final bool canResend = _secondsRemaining == 0 && !_isResending;
		return Center(
			child: Wrap(
				alignment: WrapAlignment.center,
				crossAxisAlignment: WrapCrossAlignment.center,
				children: [
					Text(
						context.tr("Didn't receive the code?"),
						style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
					),
					TextButton(
						onPressed: canResend ? _resend : null,
						style: TextButton.styleFrom(
							foregroundColor: AppColors.primary,
							disabledForegroundColor: AppColors.textMuted,
						),
						// Cross-fades between countdown / ready / sending; the
						// countdown itself ticks in place (same key).
						child: AppSwitcher(
							duration: AppMotion.fast,
							alignment: Alignment.center,
							child: Text(
								_isResending
										? context.tr('Sending...')
										: _secondsRemaining > 0
												? context.tr('Resend in {time}', {'time': '$minutes:$seconds'})
												: context.tr('Resend code'),
								key: ValueKey(
									_isResending ? 'sending' : (_secondsRemaining > 0 ? 'countdown' : 'ready'),
								),
								style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
							),
						),
					),
				],
			),
		);
	}
}

/// Keeps one digit per box. A 6-digit value is let through as a paste
/// (distributed by onChanged); otherwise the digit just typed wins.
class _OtpDigitFormatter extends TextInputFormatter {
	@override
	TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
		final String digits = newValue.text.replaceAll(RegExp(r'\D'), '');
		if (digits.length <= 1 || digits.length == _kCodeLength) {
			return TextEditingValue(
				text: digits,
				selection: TextSelection.collapsed(offset: digits.length),
			);
		}
		// Typed into a box that already had a digit: keep the character just
		// entered (the one before the cursor), not the old one.
		String typed = digits[digits.length - 1];
		final int cursor = newValue.selection.baseOffset;
		if (cursor > 0 && cursor <= newValue.text.length) {
			final String ch = newValue.text[cursor - 1];
			if (RegExp(r'\d').hasMatch(ch)) typed = ch;
		}
		return TextEditingValue(
			text: typed,
			selection: const TextSelection.collapsed(offset: 1),
		);
	}
}

class _OtpBox extends StatelessWidget {
	final TextEditingController controller;
	final FocusNode focusNode;
	final bool isActive;
	final bool isFilled;
	final bool isLast;
	final double fontSize;
	final ValueChanged<String> onChanged;
	final VoidCallback onTap;
	final VoidCallback onSubmitted;

	const _OtpBox({
		required this.controller,
		required this.focusNode,
		required this.isActive,
		required this.isFilled,
		required this.isLast,
		required this.fontSize,
		required this.onChanged,
		required this.onTap,
		required this.onSubmitted,
	});

	@override
	Widget build(BuildContext context) {
		// Focus: thick primary ring with a soft glow. Filled: tinted with a
		// primary hairline. Both ease in so typing feels continuous.
		final Color border = isActive
				? AppColors.primary
				: (isFilled ? AppColors.primary.withValues(alpha: 0.45) : AppColors.border);
		return AnimatedContainer(
			duration: AppMotion.fast,
			curve: AppMotion.curve,
			decoration: BoxDecoration(
				color: isFilled && !isActive
						? AppColors.accentLight.withValues(alpha: 0.45)
						: AppColors.surface,
				borderRadius: BorderRadius.circular(AppRadius.sm),
				border: Border.all(color: border, width: isActive ? 2 : 1),
				boxShadow: [
					BoxShadow(
						color: AppColors.primary.withValues(alpha: isActive ? 0.14 : 0),
						blurRadius: 10,
						offset: const Offset(0, 3),
					),
				],
			),
			alignment: Alignment.center,
			child: TextField(
				controller: controller,
				focusNode: focusNode,
				textAlign: TextAlign.center,
				textAlignVertical: TextAlignVertical.center,
				keyboardType: TextInputType.number,
				textInputAction: isLast ? TextInputAction.done : TextInputAction.next,
				autofillHints: const [AutofillHints.oneTimeCode],
				// No maxLength: a pasted 6-digit string must reach onChanged so it
				// can be distributed across the boxes.
				inputFormatters: [_OtpDigitFormatter()],
				style: TextStyle(color: AppColors.textPrimary, fontSize: fontSize, fontWeight: FontWeight.bold),
				decoration: const InputDecoration(
					counterText: '',
					filled: false,
					isDense: true,
					border: InputBorder.none,
					enabledBorder: InputBorder.none,
					focusedBorder: InputBorder.none,
					contentPadding: EdgeInsets.zero,
				),
				onTap: onTap,
				onChanged: onChanged,
				onSubmitted: isLast ? (_) => onSubmitted() : null,
			),
		);
	}
}
