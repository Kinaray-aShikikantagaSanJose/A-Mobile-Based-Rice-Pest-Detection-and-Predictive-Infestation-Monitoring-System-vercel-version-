import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../app_router.dart';
import '../controllers/auth_controller.dart';
import '../l10n/app_language.dart';
import '../services/local_store.dart';
import '../services/sync_service.dart';
import '../theme.dart';
import 'app_widgets.dart';
import 'brand.dart';
import 'user_avatar.dart';

/// The user's profile picture (or initials) that opens the account sheet
/// (who is signed in, edit profile, send waiting observations, sign out).
/// The language is changed with the button on Home or in the profile, so
/// the sheet has no language control of its own.
/// [onDark] styles it for the gradient hero header.
class AccountButton extends StatelessWidget {
  final bool onDark;
  const AccountButton({super.key, this.onDark = false});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: context.tr('Account'),
      child: InkResponse(
        onTap: () => showAccountSheet(context),
        radius: 28,
        child: UserAvatar(size: 48, onDark: onDark),
      ),
    );
  }
}

Future<void> showAccountSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    builder: (_) => const _AccountSheet(),
  );
}

class _AccountSheet extends StatefulWidget {
  const _AccountSheet();

  @override
  State<_AccountSheet> createState() => _AccountSheetState();
}

class _AccountSheetState extends State<_AccountSheet> {
  bool _syncing = false;
  bool? _hasWaiting;

  @override
  void initState() {
    super.initState();
    LocalStore.instance.hasPendingWork().then((v) {
      if (mounted) setState(() => _hasWaiting = v);
    }).catchError((_) {
      if (mounted) setState(() => _hasWaiting = false);
    });
  }

  Future<void> _syncNow() async {
    setState(() => _syncing = true);
    // The person asked: also retry items the server refused before.
    await SyncService.syncAll(retryRefused: true);
    final waiting = await LocalStore.instance.hasPendingWork();
    if (!mounted) return;
    setState(() {
      _syncing = false;
      _hasWaiting = waiting;
    });
  }

  /// Always asks first, with what is still on this phone; closes the sheet
  /// and ends the session (on the server too, best effort) when confirmed.
  Future<void> _signOut() async {
    final navigator = Navigator.of(context);
    await confirmAndSignOut(context, beforeSignOut: () => navigator.pop());
  }

  @override
  Widget build(BuildContext context) {
    final s = AuthControllerImpl.instance.session;
    final roleLabel = context.tr(switch (s?.role) {
      AppRole.technician => 'Agricultural technician',
      AppRole.agriculturist => 'Agriculturist',
      _ => 'Farmer',
    });
    final place = [s?.barangay ?? '', s?.municipality ?? ''].where((x) => x.isNotEmpty).join(', ');
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.hPad, 0, AppSpacing.hPad, AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const UserAvatar(size: 58),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s?.name ?? '', style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
                      Text(s?.email ?? '', style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                AppChip(label: roleLabel, color: AppColors.primary, icon: Icons.badge_outlined),
                if (place.isNotEmpty) AppChip(label: place, color: AppColors.textSecondary, icon: Icons.location_on_outlined),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            AppCard(
              child: Row(
                children: [
                  IconTile(
                    icon: _hasWaiting == true ? Icons.cloud_upload_outlined : Icons.cloud_done_outlined,
                    color: _hasWaiting == true ? AppColors.orange : AppColors.primary,
                    size: 40,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      context.tr(_hasWaiting == null
                          ? 'Checking…'
                          : _hasWaiting!
                              ? 'Some observations are waiting for signal.'
                              : 'Everything is sent.'),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (_hasWaiting == true)
                    AppPrimaryButton(
                      label: context.tr('Send now'),
                      compact: true,
                      expanded: false,
                      loading: _syncing,
                      onPressed: _syncNow,
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            AppPrimaryButton(
              label: context.tr('Edit profile'),
              icon: Icons.manage_accounts_rounded,
              onPressed: () {
                final router = GoRouter.of(context);
                Navigator.of(context).pop();
                router.push(AppRouter.profile);
              },
            ),
            const SizedBox(height: AppSpacing.md),
            AppSecondaryButton(
              label: context.tr('Sign out'),
              icon: Icons.logout_rounded,
              color: AppColors.danger,
              onPressed: _signOut,
            ),
            const SizedBox(height: AppSpacing.md),
            Center(
              child: Text('$kAppName · ${context.tr('Mobile')}', style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
            ),
          ],
        ),
      ),
    );
  }
}
