import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widget_previews.dart';
import 'package:go_router/go_router.dart';
import '../app_router.dart';
import '../services/auth_service.dart';
import '../theme.dart';
import '../widgets/app_widgets.dart';
import '../widgets/brand.dart';
import '../widgets/motion.dart';
import '../utils/places.dart';

@Preview(name: 'F11aRegistration', size: Size(390.0, 844.0))
Widget previewF11aRegistration() {
	return const MaterialApp(
		debugShowCheckedModeBanner: false,
		home: F11aRegistration(),
	);
}

class F11aRegistration extends StatefulWidget {
	const F11aRegistration({super.key});

	@override
	F11aRegistrationState createState() => F11aRegistrationState();
}

class F11aRegistrationState extends State<F11aRegistration> {
	final _formKey = GlobalKey<FormState>();
	final _fullNameController = TextEditingController();
	final _emailController = TextEditingController();
	final _phoneController = TextEditingController();
	final _barangayController = TextEditingController();
	final _passwordController = TextEditingController();
	final _confirmPasswordController = TextEditingController();

	bool _obscurePassword = true;
	bool _obscureConfirmPassword = true;
	bool _agreedToTerms = false;
	bool _isSubmitting = false;
	String? _selectedRegion;
	String _selectedRole = 'farmer';
	int _currentStep = 0; // 0: Role (f11a_registration_001), 1: Account (f11a_registration_002)

	final List<String> _antiqueMunicipalities = kAntiqueMunicipalities;

	@override
	void initState() {
		super.initState();
		SystemChrome.setPreferredOrientations([
			DeviceOrientation.portraitUp,
			DeviceOrientation.portraitDown,
		]);
	}

	@override
	void dispose() {
		_fullNameController.dispose();
		_emailController.dispose();
		_phoneController.dispose();
		_barangayController.dispose();
		_passwordController.dispose();
		_confirmPasswordController.dispose();
		super.dispose();
	}

	void _selectRole(String role) {
		HapticFeedback.selectionClick();
		setState(() {
			_selectedRole = role;
			_currentStep = 1;
		});
	}

	void _backToRoles() => setState(() => _currentStep = 0);

	Future<void> _register() async {
		if (_isSubmitting) return;
		FocusScope.of(context).unfocus();
		if (!(_formKey.currentState?.validate() ?? false)) return;

		if (_selectedRegion == null) {
			_showMessage('Please select your municipality.');
			return;
		}

		if (!_agreedToTerms) {
			_showMessage('Please agree to the Terms & Privacy Policy.');
			return;
		}

		final fullName = _fullNameController.text.trim();
		final email = _emailController.text.trim();
		final password = _passwordController.text;

		setState(() => _isSubmitting = true);

		try {
			final result = await AuthService.instance.register(
				fullName: fullName,
				email: email,
				password: password,
				phone: _phoneController.text.trim(),
				municipality: _selectedRegion!,
				role: _selectedRole,
				barangay: _barangayController.text.trim(),
			);

			if (!mounted) return;

			final registeredEmail = (result['email'] ?? email).toString().trim();

			HapticFeedback.lightImpact();
			_showMessage('Verification code sent to $registeredEmail.');
			context.push(
				AppRouter.otp,
				extra: <String, dynamic>{
					'email': registeredEmail,
					'fullName': fullName,
					// Used once after verification to sign in; never persisted.
					'password': password,
				},
			);
		} catch (e) {
			if (!mounted) return;
			_showMessage(_cleanError(e));
		} finally {
			if (mounted) setState(() => _isSubmitting = false);
		}
	}

	void _showMessage(String message) {
		ScaffoldMessenger.of(context)
			..hideCurrentSnackBar()
			..showSnackBar(SnackBar(content: Text(message)));
	}

	String _cleanError(Object error) {
		return error.toString().replaceFirst('Exception: ', '');
	}

	@override
	Widget build(BuildContext context) {
		// Android back on the account step returns to the role step.
		return PopScope(
			canPop: _currentStep == 0,
			onPopInvokedWithResult: (didPop, _) {
				if (!didPop && _currentStep == 1) _backToRoles();
			},
			child: Scaffold(
				backgroundColor: AppColors.background,
				body: SafeArea(
					// The form wraps both steps so its GlobalKey is never duplicated
					// while the steps cross-fade.
					child: AutofillGroup(
						child: Form(
							key: _formKey,
							child: SizedBox.expand(
								child: AppSwitcher(
									child: _currentStep == 0
											? _buildStepScroll('role', _buildRoleSelectionStep())
											: _buildStepScroll('account', _buildAccountSetupStep()),
								),
							),
						),
					),
				),
			),
		);
	}

	/// Each step scrolls on its own so switching steps starts at the top.
	Widget _buildStepScroll(String step, Widget child) {
		return SizedBox.expand(
			key: ValueKey(step),
			child: SingleChildScrollView(
				keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
				padding: const EdgeInsets.symmetric(horizontal: AppSpacing.hPad),
				child: child,
			),
		);
	}

	// ------------------------------------------------------------------
	// STEP 0: SELECT YOUR ROLE (f11a_registration_001)
	// ------------------------------------------------------------------
	Widget _buildRoleSelectionStep() {
		return Column(
			crossAxisAlignment: CrossAxisAlignment.stretch,
			children: [
				const SizedBox(height: 40),
				...staggered([
					const Center(child: BrandMark(size: 104)),
					const Padding(
						padding: EdgeInsets.only(top: AppSpacing.md),
						child: Center(child: BrandWordmark(fontSize: 26, color: AppColors.primaryDark)),
					),
					const Padding(
						padding: EdgeInsets.only(top: AppSpacing.xl),
						child: Text(
							'Select Your Role',
							textAlign: TextAlign.center,
							style: TextStyle(
								fontFamily: AppFonts.display,
								color: AppColors.textPrimary,
								fontSize: 24,
								fontWeight: FontWeight.w800,
							),
						),
					),
					const Padding(
						padding: EdgeInsets.only(top: AppSpacing.xs, bottom: AppSpacing.xl),
						child: Text(
							'Choose how you will use the app.',
							textAlign: TextAlign.center,
							style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
						),
					),
					_buildRoleOptionButton(
						label: "I'm a Farmer",
						description: 'Report pests and diseases, get treatment options and reminders.',
						icon: Icons.agriculture_rounded,
						isFilled: _selectedRole == 'farmer',
						onTap: () => _selectRole('farmer'),
					),
					Padding(
						padding: const EdgeInsets.only(top: AppSpacing.md),
						child: _buildRoleOptionButton(
							label: 'Agricultural Technician',
							description: 'Everything farmers have, plus validation, infestation levels, escalation and the local map.',
							icon: Icons.engineering_rounded,
							isFilled: _selectedRole == 'technician',
							onTap: () => _selectRole('technician'),
						),
					),
					const Padding(
						padding: EdgeInsets.only(top: AppSpacing.lg),
						child: Text(
							'Agriculturists and OPA staff use the Palay Patrol web dashboard.',
							textAlign: TextAlign.center,
							style: TextStyle(color: AppColors.textMuted, fontSize: 12.5),
						),
					),
					Padding(
						padding: const EdgeInsets.only(top: AppSpacing.md),
						child: _buildLoginLink(),
					),
				]),
				const SizedBox(height: AppSpacing.xl),
			],
		);
	}

	Widget _buildRoleOptionButton({
		required String label,
		required String description,
		required IconData icon,
		required bool isFilled,
		required VoidCallback onTap,
	}) {
		final BorderRadius radius = BorderRadius.circular(AppRadius.md);
		return PressScale(
			scale: 0.985,
			child: AnimatedContainer(
				duration: AppMotion.fast,
				curve: AppMotion.curve,
				decoration: BoxDecoration(
					color: isFilled ? AppColors.primaryDark : AppColors.surface,
					borderRadius: radius,
					border: Border.all(color: isFilled ? AppColors.primaryDark : AppColors.border, width: 1.5),
					boxShadow: AppShadows.card,
				),
				child: Material(
					type: MaterialType.transparency,
					child: InkWell(
						onTap: onTap,
						borderRadius: radius,
						child: Padding(
							padding: const EdgeInsets.all(AppSpacing.lg),
							child: Row(
								children: [
									Container(
										width: 52,
										height: 52,
										decoration: BoxDecoration(
											color: isFilled ? AppColors.brandGold : AppColors.primary.withValues(alpha: 0.12),
											borderRadius: BorderRadius.circular(16),
										),
										child: Icon(icon, size: 28, color: isFilled ? AppColors.primaryDeep : AppColors.primary),
									),
									const SizedBox(width: AppSpacing.md),
									Expanded(
										child: Column(
											crossAxisAlignment: CrossAxisAlignment.start,
											children: [
												Text(
													label,
													style: TextStyle(
														color: isFilled ? AppColors.surface : AppColors.textPrimary,
														fontSize: 16.5,
														fontWeight: FontWeight.w800,
													),
												),
												const SizedBox(height: 2),
												Text(
													description,
													style: TextStyle(
														color: isFilled ? Colors.white.withValues(alpha: 0.8) : AppColors.textSecondary,
														fontSize: 13,
														height: 1.35,
													),
												),
											],
										),
									),
									const SizedBox(width: AppSpacing.sm),
									Icon(Icons.chevron_right_rounded, size: 24, color: isFilled ? AppColors.brandGold : AppColors.textMuted),
								],
							),
						),
					),
				),
			),
		);
	}

	// ------------------------------------------------------------------
	// STEP 1: SETUP ACCOUNT (f11a_registration_002)
	// ------------------------------------------------------------------
	Widget _buildAccountSetupStep() {
		return Column(
			crossAxisAlignment: CrossAxisAlignment.stretch,
			children: [
				const SizedBox(height: AppSpacing.md),
				...staggered([
					Align(
						alignment: Alignment.centerLeft,
						child: AppCircleButton(
							icon: Icons.arrow_back_rounded,
							tooltip: 'Back to role selection',
							onTap: _backToRoles,
						),
					),
					Column(
						crossAxisAlignment: CrossAxisAlignment.stretch,
						children: [
							const SizedBox(height: AppSpacing.md),
							const Center(child: BrandMark(size: 80)),
							const SizedBox(height: AppSpacing.lg),
							const Text(
								'Create your account',
								style: TextStyle(
									fontFamily: AppFonts.display,
									color: AppColors.textPrimary,
									fontSize: 26,
									fontWeight: FontWeight.bold,
								),
							),
							const SizedBox(height: AppSpacing.xs),
							Text(
								'Registering as ${_roleLabel(_selectedRole)}. Your municipal agriculture office '
								'will check your details and confirm your role before your account can be used.',
								style: const TextStyle(color: AppColors.textSecondary, fontSize: 14, height: 1.4),
							),
							const SizedBox(height: AppSpacing.xl),
						],
					),
					_buildLabeledInput(
						label: 'Full name',
						hintText: 'e.g. Juan A. Dela Cruz',
						controller: _fullNameController,
						keyboardType: TextInputType.name,
						textCapitalization: TextCapitalization.words,
						autofillHints: const [AutofillHints.name],
						validator: (value) {
							if (value == null || value.trim().length < 2) {
								return 'Enter your full name.';
							}
							return null;
						},
					),
					Padding(
						padding: const EdgeInsets.only(top: AppSpacing.lg),
						child: _buildLabeledInput(
							label: 'Email',
							hintText: 'e.g. juan.delacruz@gmail.com',
							controller: _emailController,
							keyboardType: TextInputType.emailAddress,
							autofillHints: const [AutofillHints.email],
							validator: (value) {
								final email = value?.trim() ?? '';
								if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
									return 'Enter a valid email address.';
								}
								return null;
							},
						),
					),
					Padding(
						padding: const EdgeInsets.only(top: AppSpacing.lg),
						child: _buildLabeledInput(
							label: 'Mobile number',
							hintText: 'e.g. 0917 123 4567',
							controller: _phoneController,
							keyboardType: TextInputType.phone,
							autofillHints: const [AutofillHints.telephoneNumber],
							validator: (value) {
								final v = (value ?? '').trim();
								if (!RegExp(r'^\+?[0-9][0-9 \-]{5,28}$').hasMatch(v)) {
									return 'Enter a valid mobile number.';
								}
								return null;
							},
						),
					),
					Padding(
						padding: const EdgeInsets.only(top: AppSpacing.lg),
						child: _buildLabeledPasswordInput(
							label: 'Password',
							hintText: 'At least 8 characters',
							controller: _passwordController,
							obscureText: _obscurePassword,
							textInputAction: TextInputAction.next,
							onToggle: () => setState(() => _obscurePassword = !_obscurePassword),
							validator: (value) {
								if ((value ?? '').length < 8) return 'Password must be at least 8 characters.';
								return null;
							},
						),
					),
					Padding(
						padding: const EdgeInsets.only(top: AppSpacing.lg),
						child: _buildLabeledPasswordInput(
							label: 'Confirm password',
							hintText: 'Re-enter your password',
							controller: _confirmPasswordController,
							obscureText: _obscureConfirmPassword,
							textInputAction: TextInputAction.done,
							onToggle: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
							validator: (value) {
								if (value != _passwordController.text) return 'Passwords do not match.';
								return null;
							},
						),
					),
					Padding(
						padding: const EdgeInsets.only(top: AppSpacing.lg),
						child: _buildRegionDropdown(),
					),
					Padding(
						padding: const EdgeInsets.only(top: AppSpacing.lg),
						child: _buildLabeledInput(
							label: 'Barangay',
							hintText: 'e.g. Poblacion',
							controller: _barangayController,
							keyboardType: TextInputType.text,
							textCapitalization: TextCapitalization.words,
							validator: (value) {
								if ((value ?? '').trim().isEmpty) return 'Enter your barangay.';
								return null;
							},
						),
					),
					Padding(
						padding: const EdgeInsets.only(top: AppSpacing.md),
						child: _buildTermsCheckbox(),
					),
					Padding(
						padding: const EdgeInsets.only(top: AppSpacing.xl),
						child: AppPrimaryButton(
							label: 'Continue',
							loading: _isSubmitting,
							onPressed: _register,
						),
					),
					Padding(
						padding: const EdgeInsets.only(top: AppSpacing.md),
						child: _buildLoginLink(),
					),
				]),
				const SizedBox(height: AppSpacing.xl),
			],
		);
	}

	String _roleLabel(String role) {
		switch (role) {
			case 'technician':
				return 'an Agricultural Technician';
			default:
				return 'a Farmer';
		}
	}

	Widget _buildFieldLabel(String label) {
		return Padding(
			padding: const EdgeInsets.only(bottom: AppSpacing.sm),
			child: Text(
				label,
				style: const TextStyle(
					color: AppColors.textPrimary,
					fontSize: 14,
					fontWeight: FontWeight.w600,
				),
			),
		);
	}

	Widget _buildLabeledInput({
		required String label,
		required String hintText,
		required TextEditingController controller,
		TextInputType keyboardType = TextInputType.text,
		TextCapitalization textCapitalization = TextCapitalization.none,
		Iterable<String>? autofillHints,
		String? Function(String?)? validator,
	}) {
		return Column(
			crossAxisAlignment: CrossAxisAlignment.start,
			children: [
				_buildFieldLabel(label),
				TextFormField(
					controller: controller,
					keyboardType: keyboardType,
					textCapitalization: textCapitalization,
					textInputAction: TextInputAction.next,
					autofillHints: autofillHints,
					autocorrect: false,
					validator: validator,
					style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
					decoration: InputDecoration(hintText: hintText),
				),
			],
		);
	}

	Widget _buildLabeledPasswordInput({
		required String label,
		required String hintText,
		required TextEditingController controller,
		required bool obscureText,
		required TextInputAction textInputAction,
		required VoidCallback onToggle,
		String? Function(String?)? validator,
	}) {
		return Column(
			crossAxisAlignment: CrossAxisAlignment.start,
			children: [
				_buildFieldLabel(label),
				TextFormField(
					controller: controller,
					obscureText: obscureText,
					textInputAction: textInputAction,
					autofillHints: const [AutofillHints.newPassword],
					autocorrect: false,
					enableSuggestions: false,
					validator: validator,
					style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
					decoration: InputDecoration(
						hintText: hintText,
						suffixIcon: IconButton(
							tooltip: obscureText ? 'Show password' : 'Hide password',
							icon: AppSwitcher(
								duration: AppMotion.fast,
								alignment: Alignment.center,
								child: Icon(
									obscureText ? Icons.visibility_outlined : Icons.visibility_off_outlined,
									key: ValueKey(obscureText),
									color: AppColors.textMuted,
									size: 20,
								),
							),
							onPressed: onToggle,
						),
					),
				),
			],
		);
	}

	Widget _buildRegionDropdown() {
		return Column(
			crossAxisAlignment: CrossAxisAlignment.start,
			children: [
				_buildFieldLabel('Municipality'),
				DropdownButtonFormField<String>(
					initialValue: _selectedRegion,
					isExpanded: true,
					icon: const Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.primary),
					dropdownColor: AppColors.surface,
					borderRadius: BorderRadius.circular(AppRadius.sm),
					hint: const Text(
						'Select your municipality',
						style: TextStyle(color: AppColors.textMuted, fontSize: 14),
					),
					items: _antiqueMunicipalities.map((muni) {
						return DropdownMenuItem<String>(
							value: muni,
							child: Text(muni, style: const TextStyle(color: AppColors.textPrimary, fontSize: 14)),
						);
					}).toList(),
					validator: (val) => val == null ? 'Select your municipality.' : null,
					onChanged: (val) => setState(() => _selectedRegion = val),
				),
			],
		);
	}

	Widget _buildTermsCheckbox() {
		// The whole row toggles the box so the tap target is comfortably large.
		return InkWell(
			onTap: () => setState(() => _agreedToTerms = !_agreedToTerms),
			borderRadius: BorderRadius.circular(AppRadius.sm),
			child: ConstrainedBox(
				constraints: const BoxConstraints(minHeight: 48),
				child: Row(
					children: [
						Checkbox(
							value: _agreedToTerms,
							activeColor: AppColors.primary,
							side: const BorderSide(color: AppColors.textMuted, width: 1.5),
							shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
							onChanged: (v) => setState(() => _agreedToTerms = v ?? false),
						),
						const SizedBox(width: AppSpacing.xs),
						const Expanded(
							child: Text(
								'I agree to the Terms & Privacy Policy',
								style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
							),
						),
					],
				),
			),
		);
	}

	Widget _buildLoginLink() {
		return Wrap(
			alignment: WrapAlignment.center,
			crossAxisAlignment: WrapCrossAlignment.center,
			children: [
				const Text('Already have an account?', style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
				TextButton(
					onPressed: () => context.go(AppRouter.login),
					child: const Text(
						'Log In',
						style: TextStyle(
							fontSize: 14,
							fontWeight: FontWeight.bold,
							decoration: TextDecoration.underline,
							decorationColor: AppColors.primary,
						),
					),
				),
			],
		);
	}
}
