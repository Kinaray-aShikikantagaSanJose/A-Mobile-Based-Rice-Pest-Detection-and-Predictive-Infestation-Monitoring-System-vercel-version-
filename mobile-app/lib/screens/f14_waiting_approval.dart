import 'dart:async';

import 'package:flutter/material.dart';

import '../controllers/auth_controller.dart';
import '../l10n/app_language.dart';
import '../services/api_client.dart';
import '../theme.dart';
import '../widgets/app_widgets.dart';
import '../widgets/brand.dart';
import '../widgets/motion.dart';

/// Shown after email verification until an agriculturist approves the
/// account on the dashboard. Checks again on its own; the router moves on as
/// soon as the status changes.
class F14WaitingApproval extends StatefulWidget {
  const F14WaitingApproval({super.key});

  @override
  State<F14WaitingApproval> createState() => _F14WaitingApprovalState();
}

class _F14WaitingApprovalState extends State<F14WaitingApproval> with WidgetsBindingObserver {
  static const Duration _every = Duration(seconds: 30);
  Timer? _timer;
  bool _checking = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(_every, (_) => _check(quiet: true));
    WidgetsBinding.instance.addPostFrameCallback((_) => _check(quiet: true));
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check(quiet: true);
  }

  Future<void> _check({bool quiet = false}) async {
    if (_checking) return;
    setState(() {
      _checking = true;
      if (!quiet) _message = null;
    });
    try {
      final s = await ApiClient.refreshProfile();
      if (!mounted) return;
      if (s != null && s.status == AccountStatus.pending && !quiet) {
        _message = 'Not approved yet. We\'ll keep checking.';
      }
    } on ApiException catch (e) {
      if (mounted && !quiet) _message = e.message;
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = AuthControllerImpl.instance;
    final rejected = auth.status == AccountStatus.rejected;
    final s = auth.session;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.hPad),
          children: [
            const SizedBox(height: AppSpacing.xl),
            const Center(child: BrandMark(size: 72)),
            const SizedBox(height: AppSpacing.xl),
            FadeSlideIn(
              child: Column(
                children: [
                  Container(
                    width: 84,
                    height: 84,
                    decoration: BoxDecoration(
                      color: rejected ? AppColors.danger.withValues(alpha: 0.1) : AppColors.orangeLight,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      rejected ? Icons.block_rounded : Icons.hourglass_top_rounded,
                      size: 40,
                      color: rejected ? AppColors.danger : AppColors.orange,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    rejected ? context.tr('Your account was not approved') : context.tr('Waiting for approval'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontFamily: AppFonts.display,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    rejected
                        ? context.tr('Please visit or call your Municipal Agriculture Office if you think this is a mistake.')
                        : context.tr(
                            'Your email is verified. An agriculturist from your municipal agriculture '
                            'office will check and approve your account. You can close the app; '
                            'we\'ll let you in as soon as it\'s approved.',
                          ),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 15, height: 1.5),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            if (s != null)
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _row(Icons.person_outline_rounded, s.name),
                    _row(Icons.badge_outlined, switch (s.role) {
                      AppRole.technician => context.tr('Requested role: Agricultural technician'),
                      AppRole.agriculturist => context.tr('Requested role: Agriculturist'),
                      AppRole.farmer => context.tr('Requested role: Farmer'),
                    }),
                    _row(Icons.mail_outline_rounded, s.email),
                    if (s.phone.isNotEmpty) _row(Icons.phone_outlined, s.phone),
                    _row(Icons.place_outlined,
                        [s.barangay, s.municipality].where((x) => x.isNotEmpty).join(', ')),
                  ],
                ),
              ),
            const SizedBox(height: AppSpacing.xl),
            if (!rejected)
              AppPrimaryButton(
                label: context.tr('Check again'),
                icon: Icons.refresh_rounded,
                loading: _checking,
                onPressed: () => _check(),
              ),
            if (_message != null) ...[
              const SizedBox(height: AppSpacing.md),
              Text(context.tr(_message!), textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textSecondary)),
            ],
            const SizedBox(height: AppSpacing.md),
            // Same confirmation as the account sheet; also ends the session on the server.
            AppSecondaryButton(
              label: context.tr('Sign out'),
              icon: Icons.logout_rounded,
              onPressed: () => confirmAndSignOut(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(IconData icon, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Icon(icon, size: 18, color: AppColors.textMuted),
            const SizedBox(width: AppSpacing.md),
            Expanded(child: Text(text, style: const TextStyle(color: AppColors.textPrimary, fontSize: 14))),
          ],
        ),
      );
}
