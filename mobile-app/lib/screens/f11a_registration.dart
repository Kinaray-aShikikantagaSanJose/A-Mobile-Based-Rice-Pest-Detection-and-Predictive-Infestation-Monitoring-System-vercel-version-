import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widget_previews.dart';
import 'package:go_router/go_router.dart';
import '../app_router.dart';
import '../l10n/app_language.dart';
import '../services/antique_geofence.dart';
import '../services/auth_service.dart';
import '../theme.dart';
import '../widgets/app_widgets.dart';
import '../widgets/barangay_field.dart';
import '../widgets/brand.dart';
import '../widgets/gps_area.dart';
import '../widgets/language_button.dart';
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

	// Area from GPS (offline lookup in the Antique barangay map). Found
	// automatically once when both fields are still empty; "Use my location"
	// asks again. Typed or picked values are never replaced automatically.
	GpsAreaResult? _gpsArea;
	bool _gpsBusy = false;
	bool _gpsApplied = false;
	bool _autoDetected = false;
	String? _barangayPsgc;
	String _locationSource = 'manual';

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
		// Fill the municipality and barangay from GPS, but only when both are empty.
		if (!_autoDetected && _selectedRegion == null && _barangayController.text.trim().isEmpty) {
			_autoDetected = true;
			WidgetsBinding.instance.addPostFrameCallback((_) => _detectArea(auto: true));
		}
	}

	/// [auto]: found on its own, so it only fills empty fields. Otherwise the
	/// person tapped "Use my location" and the result replaces what is there.
	Future<void> _detectArea({required bool auto}) async {
		if (_gpsBusy) return;
		setState(() {
			_gpsBusy = true;
			_gpsApplied = false;
		});
		final result = await findAreaFromGps(ask: true);
		if (!mounted) return;
		setState(() {
			_gpsBusy = false;
			_gpsArea = result;
		});
		final empty = _selectedRegion == null && _barangayController.text.trim().isEmpty;
		if (result.usable && (!auto || empty)) _applyPlace(result.place!);
	}

	void _applyPlace(GeoPlace place) {
		setState(() {
			_selectedRegion = _antiqueMunicipalities.contains(place.municipality) ? place.municipality : _selectedRegion;
			_barangayController.text = place.barangay;
			_barangayPsgc = place.psgc;
			_locationSource = 'gps';
			_gpsApplied = true;
		});
	}

	void _backToRoles() => setState(() => _currentStep = 0);

	Future<void> _register() async {
		if (_isSubmitting) return;
		FocusScope.of(context).unfocus();
		if (!(_formKey.currentState?.validate() ?? false)) return;

		if (_selectedRegion == null) {
			_showMessage(context.tr('Please select your municipality.'));
			return;
		}

		if (!_agreedToTerms) {
			_showMessage(context.tr('Please agree to the Terms & Privacy Policy.'));
			return;
		}

		final fullName = _fullNameController.text.trim();
		final email = _emailController.text.trim();
		final password = _passwordController.text;

		setState(() => _isSubmitting = true);

		try {
			// A typed name that matches an official barangay gets its official
			// spelling and PSGC code (works offline).
			var barangay = _barangayController.text.trim();
			var psgc = _barangayPsgc;
			final official = await AntiqueGeofence.instance.match(_selectedRegion!, barangay).catchError((_) => null);
			if (official != null) {
				barangay = official.barangay;
				psgc = official.psgc;
			} else if (psgc != null) {
				psgc = null; // the picked code no longer matches what is in the field
			}
			final result = await AuthService.instance.register(
				fullName: fullName,
				email: email,
				password: password,
				phone: _phoneController.text.trim(),
				municipality: _selectedRegion!,
				role: _selectedRole,
				barangay: barangay,
				barangayPsgc: psgc,
				locationSource: psgc != null && _locationSource == 'gps' ? 'gps' : 'manual',
			);

			if (!mounted) return;

			final registeredEmail = (result['email'] ?? email).toString().trim();

			HapticFeedback.lightImpact();
			_showMessage(context.tr('Verification code sent to {email}.', {'email': registeredEmail}));
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
			_showMessage(context.tr(_cleanError(e)));
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
				const SizedBox(height: AppSpacing.md),
				const Align(alignment: Alignment.centerRight, child: LanguageButton()),
				...staggered([
					const Center(child: BrandMark(size: 104)),
					const Padding(
						padding: EdgeInsets.only(top: AppSpacing.md),
						child: Center(child: BrandWordmark(fontSize: 26, color: AppColors.primaryDark)),
					),
					Padding(
						padding: const EdgeInsets.only(top: AppSpacing.xl),
						child: Text(
							context.tr('Select Your Role'),
							textAlign: TextAlign.center,
							style: const TextStyle(
								fontFamily: AppFonts.display,
								color: AppColors.textPrimary,
								fontSize: 24,
								fontWeight: FontWeight.w800,
							),
						),
					),
					Padding(
						padding: const EdgeInsets.only(top: AppSpacing.xs, bottom: AppSpacing.xl),
						child: Text(
							context.tr('Choose how you will use the app.'),
							textAlign: TextAlign.center,
							style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
						),
					),
					_buildRoleOptionButton(
						label: context.tr("I'm a Farmer"),
						description: context.tr('Report pests and diseases, get treatment options and reminders.'),
						icon: Icons.agriculture_rounded,
						isFilled: _selectedRole == 'farmer',
						onTap: () => _selectRole('farmer'),
					),
					Padding(
						padding: const EdgeInsets.only(top: AppSpacing.md),
						child: _buildRoleOptionButton(
							label: context.tr('Agricultural Technician'),
							description: context.tr('Everything farmers have, plus validation, infestation levels, escalation and the local map.'),
							icon: Icons.engineering_rounded,
							isFilled: _selectedRole == 'technician',
							onTap: () => _selectRole('technician'),
						),
					),
					Padding(
						padding: const EdgeInsets.only(top: AppSpacing.lg),
						child: Text(
							context.tr('Agriculturists and OPA staff use the Palay Patrol web dashboard.'),
							textAlign: TextAlign.center,
							style: const TextStyle(color: AppColors.textMuted, fontSize: 12.5),
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
					Row(
						children: [
							AppCircleButton(
								icon: Icons.arrow_back_rounded,
								tooltip: context.tr('Back to role selection'),
								onTap: _backToRoles,
							),
							const Spacer(),
							const LanguageButton(),
						],
					),
					Column(
						crossAxisAlignment: CrossAxisAlignment.stretch,
						children: [
							const SizedBox(height: AppSpacing.md),
							const Center(child: BrandMark(size: 80)),
							const SizedBox(height: AppSpacing.lg),
							Text(
								context.tr('Create your account'),
								style: const TextStyle(
									fontFamily: AppFonts.display,
									color: AppColors.textPrimary,
									fontSize: 26,
									fontWeight: FontWeight.bold,
								),
							),
							const SizedBox(height: AppSpacing.xs),
							Text(
								context.tr(
									_selectedRole == 'technician'
										? 'Registering as an Agricultural Technician. Your municipal agriculture office will check your details and confirm your role before your account can be used.'
										: 'Registering as a Farmer. Your municipal agriculture office will check your details and confirm your role before your account can be used.',
								),
								style: const TextStyle(color: AppColors.textSecondary, fontSize: 14, height: 1.4),
							),
							const SizedBox(height: AppSpacing.xl),
						],
					),
					_buildLabeledInput(
						label: context.tr('Full name'),
						hintText: context.tr('e.g. Juan A. Dela Cruz'),
						controller: _fullNameController,
						keyboardType: TextInputType.name,
						textCapitalization: TextCapitalization.words,
						autofillHints: const [AutofillHints.name],
						validator: (value) {
							if (value == null || value.trim().length < 2) {
								return context.tr('Enter your full name.');
							}
							return null;
						},
					),
					Padding(
						padding: const EdgeInsets.only(top: AppSpacing.lg),
						child: _buildLabeledInput(
							label: context.tr('Email'),
							hintText: context.tr('e.g. juan.delacruz@gmail.com'),
							controller: _emailController,
							keyboardType: TextInputType.emailAddress,
							autofillHints: const [AutofillHints.email],
							validator: (value) {
								final email = value?.trim() ?? '';
								if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
									return context.tr('Enter a valid email address.');
								}
								return null;
							},
						),
					),
					Padding(
						padding: const EdgeInsets.only(top: AppSpacing.lg),
						child: _buildLabeledInput(
							label: context.tr('Mobile number'),
							hintText: context.tr('e.g. 0917 123 4567'),
							controller: _phoneController,
							keyboardType: TextInputType.phone,
							autofillHints: const [AutofillHints.telephoneNumber],
							validator: (value) {
								final v = (value ?? '').trim();
								if (!RegExp(r'^\+?[0-9][0-9 \-]{5,28}$').hasMatch(v)) {
									return context.tr('Enter a valid mobile number.');
								}
								return null;
							},
						),
					),
					Padding(
						padding: const EdgeInsets.only(top: AppSpacing.lg),
						child: _buildLabeledPasswordInput(
							label: context.tr('Password'),
							hintText: context.tr('At least 8 characters'),
							controller: _passwordController,
							obscureText: _obscurePassword,
							textInputAction: TextInputAction.next,
							onToggle: () => setState(() => _obscurePassword = !_obscurePassword),
							validator: (value) {
								if ((value ?? '').length < 8) return context.tr('Password must be at least 8 characters.');
								return null;
							},
						),
					),
					Padding(
						padding: const EdgeInsets.only(top: AppSpacing.lg),
						child: _buildLabeledPasswordInput(
							label: context.tr('Confirm password'),
							hintText: context.tr('Re-enter your password'),
							controller: _confirmPasswordController,
							obscureText: _obscureConfirmPassword,
							textInputAction: TextInputAction.done,
							onToggle: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
							validator: (value) {
								if (value != _passwordController.text) return context.tr('Passwords do not match.');
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
						child: Column(
							crossAxisAlignment: CrossAxisAlignment.start,
							children: [
								_buildFieldLabel(context.tr('Barangay')),
								BarangayField(
									controller: _barangayController,
									municipality: _selectedRegion ?? '',
									style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
									decoration: InputDecoration(hintText: context.tr('e.g. Poblacion')),
									onPlace: (place) => setState(() {
										_barangayPsgc = place?.psgc;
										_locationSource = 'manual';
										_gpsApplied = false;
									}),
									validator: (value) {
										if ((value ?? '').trim().isEmpty) return context.tr('Enter your barangay.');
										return null;
									},
								),
								GpsAreaNote(
									busy: _gpsBusy,
									result: _gpsArea,
									applied: _gpsApplied,
									onRetry: () => _detectArea(auto: false),
									onUseAnyway: _gpsArea?.place == null ? null : () => _applyPlace(_gpsArea!.place!),
								),
								Align(
									alignment: Alignment.centerLeft,
									child: TextButton.icon(
										key: const ValueKey('use-my-location'),
										onPressed: _gpsBusy ? null : () => _detectArea(auto: false),
										icon: const Icon(Icons.my_location_rounded, size: 18),
										label: Text(context.tr('Use my location')),
									),
								),
							],
						),
					),
					Padding(
						padding: const EdgeInsets.only(top: AppSpacing.md),
						child: _buildTermsCheckbox(),
					),
					Padding(
						padding: const EdgeInsets.only(top: AppSpacing.xl),
						child: AppPrimaryButton(
							label: context.tr('Continue'),
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
							tooltip: context.tr(obscureText ? 'Show password' : 'Hide password'),
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
				_buildFieldLabel(context.tr('Municipality')),
				DropdownButtonFormField<String>(
					// Rebuilt when GPS fills the municipality in.
					key: ValueKey('region:$_selectedRegion'),
					initialValue: _selectedRegion,
					isExpanded: true,
					icon: const Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.primary),
					dropdownColor: AppColors.surface,
					borderRadius: BorderRadius.circular(AppRadius.sm),
					hint: Text(
						context.tr('Select your municipality'),
						style: const TextStyle(color: AppColors.textMuted, fontSize: 14),
					),
					items: _antiqueMunicipalities.map((muni) {
						return DropdownMenuItem<String>(
							value: muni,
							child: Text(muni, style: const TextStyle(color: AppColors.textPrimary, fontSize: 14)),
						);
					}).toList(),
					validator: (val) => val == null ? context.tr('Select your municipality.') : null,
					onChanged: (val) => setState(() {
						if (val != _selectedRegion) {
							// A barangay code from another municipality no longer applies.
							_barangayPsgc = null;
							_locationSource = 'manual';
							_gpsApplied = false;
						}
						_selectedRegion = val;
					}),
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
						Expanded(
							child: Text(
								context.tr('I agree to the Terms & Privacy Policy'),
								style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
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
				Text(context.tr('Already have an account?'), style: const TextStyle(color: AppColors.textSecondary, fontSize: 14)),
				TextButton(
					onPressed: () => context.go(AppRouter.login),
					child: Text(
						context.tr('Log In'),
						style: const TextStyle(
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
