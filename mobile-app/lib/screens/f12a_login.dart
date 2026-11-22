import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widget_previews.dart';
import 'package:go_router/go_router.dart';
import '../app_router.dart';
import '../services/auth_service.dart';
import '../utils/api_config.dart';
import '../controllers/auth_controller.dart';
import '../l10n/app_language.dart';
import '../theme.dart';
import '../widgets/brand.dart';
import '../widgets/app_widgets.dart';
import '../widgets/language_button.dart';
import '../widgets/motion.dart';

@Preview(name: 'F12aLogin', size: Size(390.0, 844.0))
Widget previewF12aLogin() {
  return const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: F12aLogin(),
  );
}

final RegExp _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

class F12aLogin extends StatefulWidget {
  const F12aLogin({super.key});

  @override
  F12aLoginState createState() => F12aLoginState();
}

class F12aLoginState extends State<F12aLogin> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final FocusNode _passwordFocus = FocusNode();

  bool _obscurePassword = true;
  bool _isLoggingIn = false;
  bool _isOpeningVerification = false;
  bool _sessionExpired = false;
  bool _needsVerification = false;
  // The last attempt could not reach the server (not a wrong password).
  bool _serverUnreachable = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);

    // After the server rejected the saved token the controller keeps the
    // email so the user only has to re-enter the password.
    final auth = AuthControllerImpl.instance;
    _sessionExpired = auth.sessionExpired;
    final savedEmail = auth.lastEmail ?? '';
    if (_sessionExpired && savedEmail.isNotEmpty) {
      _emailController.text = savedEmail;
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (_isLoggingIn) return;
    FocusScope.of(context).unfocus();

    final email = _emailController.text.trim();
    final password = _passwordController.text;

    String? problem;
    if (email.isEmpty || password.isEmpty) {
      problem = 'Enter your email and password.';
    } else if (!_emailPattern.hasMatch(email)) {
      problem = 'Enter a valid email address.';
    }
    if (problem != null) {
      setState(() {
        _errorMessage = problem;
        _needsVerification = false;
      });
      return;
    }

    setState(() {
      _isLoggingIn = true;
      _errorMessage = null;
      _needsVerification = false;
      _serverUnreachable = false;
    });

    try {
      final session = await AuthService.instance.signIn(
        email: email,
        password: password,
      );

      if (!mounted) return;

      // The mobile app is for farmers and technicians only.
      if (session.role == AppRole.agriculturist) {
        setState(() {
          _errorMessage = kAgriculturistOnWeb;
          _needsVerification = false;
        });
        return;
      }

      // Lets the platform password manager offer to save the credentials.
      TextInput.finishAutofillContext();
      HapticFeedback.lightImpact();
      // The router sends pending accounts to "Waiting for approval" and
      // approved ones to their home.
      await AuthControllerImpl.instance.startSession(session);
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.message;
        _needsVerification = e.needsVerification;
        _serverUnreachable = e.statusCode == null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _errorMessage = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoggingIn = false);
    }
  }

  /// For accounts that registered but never entered their code: send a
  /// fresh code and open the verification screen for this email.
  Future<void> _openVerification() async {
    if (_isOpeningVerification) return;
    final email = _emailController.text.trim().toLowerCase();
    final password = _passwordController.text;
    if (!_emailPattern.hasMatch(email)) {
      setState(() => _errorMessage = 'Enter a valid email address.');
      return;
    }

    setState(() => _isOpeningVerification = true);
    String note;
    try {
      await AuthService.instance.resendOtp(email: email);
      note = 'We sent a new verification code to {email}.';
    } on AuthException catch (e) {
      if (!mounted) return;
      // 429: a code went out moments ago and is still valid.
      if (e.statusCode != 429) {
        setState(() {
          _isOpeningVerification = false;
          _errorMessage = e.message;
          _needsVerification = false;
        });
        return;
      }
      note = 'Use the code we sent to {email} a moment ago.';
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isOpeningVerification = false;
        _errorMessage = 'Something went wrong. Please try again.';
      });
      return;
    }

    if (!mounted) return;
    setState(() => _isOpeningVerification = false);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(context.tr(note, {'email': email}))));
    context.push(
      AppRouter.otp,
      extra: <String, dynamic>{'email': email, 'password': password},
    );
  }

  void _showForgotPasswordDialog() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.lock_reset_rounded, color: AppColors.primary, size: 32),
        title: Text(dialogContext.tr('Reset your password')),
        content: Text(
          dialogContext.tr(
            'Password resets are handled by your local agriculture office. '
            'Contact your Municipal Agriculture Office or your assigned '
            'agricultural technician and they will help you regain access '
            'to your account.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(dialogContext.tr('Got it')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final double top = MediaQuery.paddingOf(context).top;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: AppColors.surface,
        body: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: AutofillGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(top),
                // The form sheet overlaps the photo's bottom edge.
                Transform.translate(
                  offset: const Offset(0, -28),
                  child: Container(
                    decoration: const BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                    ),
                    padding: const EdgeInsets.fromLTRB(AppSpacing.hPad, AppSpacing.xl, AppSpacing.hPad, AppSpacing.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: staggered([
                        Text(
                          context.tr('Sign in'),
                          style: const TextStyle(fontFamily: AppFonts.display, fontSize: 24, fontWeight: FontWeight.w800),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(top: 2, bottom: AppSpacing.lg),
                          child: Text(
                            context.tr('Log in with the email you registered with'),
                            style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
                          ),
                        ),
                        if (_sessionExpired)
                          Padding(
                            padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                            child: _buildSessionExpiredBanner(),
                          ),
                        _buildEmailField(),
                        Padding(
                          padding: const EdgeInsets.only(top: AppSpacing.md, bottom: AppSpacing.xs),
                          child: _buildPasswordField(),
                        ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: _showForgotPasswordDialog,
                            child: Text(
                              context.tr('Forgot password?'),
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                        _buildAnimatedError(),
                        Padding(
                          padding: const EdgeInsets.only(top: AppSpacing.lg),
                          child: AppPrimaryButton(
                            label: _isLoggingIn ? context.tr('Logging in...') : context.tr('Log In'),
                            icon: _isLoggingIn ? null : Icons.login_rounded,
                            loading: _isLoggingIn,
                            onPressed: _handleLogin,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(top: AppSpacing.md),
                          child: _buildRegisterRow(),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(top: AppSpacing.sm),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.shield_outlined, size: 14, color: AppColors.textMuted),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  context.tr('For farmers and agricultural technicians'),
                                  style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ]),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Rice-planting photo (as on the web dashboard) with the logo and greeting.
  Widget _buildHeader(double top) {
    return SizedBox(
      height: 290 + top,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Shows while the photo decodes.
          const ColoredBox(color: AppColors.primaryDark),
          Image.asset(
            kFieldPhotoAsset,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => const DecoratedBox(decoration: BoxDecoration(gradient: kHeroGradient)),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppColors.primaryDeep.withValues(alpha: 0.55),
                  AppColors.primaryDeep.withValues(alpha: 0.35),
                  AppColors.primaryDeep.withValues(alpha: 0.9),
                ],
                stops: const [0, 0.4, 1],
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(AppSpacing.hPad, top + AppSpacing.lg, AppSpacing.hPad, 52),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    BrandMark(size: 52),
                    SizedBox(width: AppSpacing.md),
                    BrandWordmark(fontSize: 22),
                    Spacer(),
                    // Language picker, so people can switch before signing in.
                    LanguageButton(dark: true),
                  ],
                ),
                const Spacer(),
                Text(
                  context.tr('Welcome Back'),
                  style: const TextStyle(
                    fontFamily: AppFonts.display,
                    color: Colors.white,
                    fontSize: 34,
                    fontWeight: FontWeight.w800,
                    height: 1.05,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  context.tr('Report pests, follow treatments and keep your field healthy.'),
                  style: const TextStyle(color: Color(0xDDFFFFFF), fontSize: 14.5, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSessionExpiredBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.orangeLight,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.orange.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.schedule_rounded, size: 18, color: AppColors.orange),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              context.tr('Your session expired. Please log in again.'),
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmailField() {
    return TextField(
      controller: _emailController,
      keyboardType: TextInputType.emailAddress,
      textInputAction: TextInputAction.next,
      autofillHints: const [AutofillHints.email, AutofillHints.username],
      autocorrect: false,
      enableSuggestions: false,
      onSubmitted: (_) => _passwordFocus.requestFocus(),
      style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
      decoration: InputDecoration(
        hintText: context.tr('Email address'),
        prefixIcon: const Icon(Icons.mail_outline_rounded, color: AppColors.textMuted, size: 20),
      ),
    );
  }

  Widget _buildPasswordField() {
    return TextField(
      controller: _passwordController,
      focusNode: _passwordFocus,
      obscureText: _obscurePassword,
      textInputAction: TextInputAction.done,
      autofillHints: const [AutofillHints.password],
      autocorrect: false,
      enableSuggestions: false,
      onSubmitted: (_) => _handleLogin(),
      style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
      decoration: InputDecoration(
        hintText: context.tr('Password'),
        prefixIcon: const Icon(Icons.lock_outline_rounded, color: AppColors.textMuted, size: 20),
        suffixIcon: IconButton(
          tooltip: _obscurePassword ? context.tr('Show password') : context.tr('Hide password'),
          icon: AppSwitcher(
            duration: AppMotion.fast,
            alignment: Alignment.center,
            child: Icon(
              _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
              key: ValueKey(_obscurePassword),
              color: AppColors.textMuted,
              size: 20,
            ),
          ),
          onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
        ),
      ),
    );
  }

  /// Error banner grows in / collapses out, and a new message cross-fades
  /// over the previous one instead of snapping.
  Widget _buildAnimatedError() {
    final String? message = _errorMessage;
    final Widget banner = AppSwitcher(
      child: message == null
          ? const SizedBox(key: ValueKey('no-error'), width: double.infinity)
          : Padding(
              key: ValueKey('error:$message:$_needsVerification:$_serverUnreachable'),
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: _buildErrorBanner(),
            ),
    );
    // AnimatedSize can't take a zero duration (it re-dirties itself during
    // layout), so reduced motion skips it instead.
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return banner;
    return AnimatedSize(
      duration: AppMotion.medium,
      curve: AppMotion.curve,
      alignment: Alignment.topCenter,
      child: banner,
    );
  }

  Widget _buildErrorBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 1),
                child: Icon(Icons.error_outline, size: 18, color: AppColors.danger),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  context.tr(_errorMessage!),
                  style: const TextStyle(
                    color: AppColors.danger,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          ValueListenableBuilder<bool>(
            valueListenable: ApiConfig.connected,
            builder: (context, connected, _) => Padding(
              padding: const EdgeInsets.only(top: AppSpacing.md),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    connected ? Icons.cloud_done_rounded : Icons.cloud_sync_rounded,
                    size: 16,
                    color: connected ? AppColors.success : AppColors.textMuted,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Flexible(
                    child: Text(
                      connected
                          ? context.tr('Connected to the server')
                          : _serverUnreachable
                              ? context.tr('Searching this network; sync will resume automatically.')
                              : context.tr('Finding the server on Wi-Fi, Ethernet, or hotspot…'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: connected ? AppColors.success : AppColors.textMuted,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_serverUnreachable) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              context.tr(
                'Keep this device on the same local network as the server. The app retries discovery automatically.',
              ),
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textMuted, fontSize: 12, height: 1.4),
            ),
          ],
          if (_needsVerification) ...[
            const SizedBox(height: AppSpacing.md),
            AppSecondaryButton(
              label: _isOpeningVerification ? context.tr('Sending code...') : context.tr('Verify my email'),
              icon: Icons.mark_email_read_outlined,
              compact: true,
              expanded: false,
              onPressed: _isOpeningVerification ? null : _openVerification,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRegisterRow() {
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          context.tr("Don't have an account?"),
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
        ),
        TextButton(
          onPressed: () => context.go(AppRouter.register),
          child: Text(
            context.tr('Sign Up'),
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
