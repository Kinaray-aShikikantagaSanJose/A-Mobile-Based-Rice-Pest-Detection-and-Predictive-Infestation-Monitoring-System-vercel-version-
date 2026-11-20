import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../controllers/auth_controller.dart';
import '../platform/local_files.dart';
import '../services/api_client.dart';
import '../theme.dart';
import '../utils/places.dart';
import '../widgets/app_widgets.dart';
import '../widgets/user_avatar.dart';

final RegExp _phone = RegExp(r'^\+?[0-9][0-9 \-]{5,28}$');

/// The signed-in person's profile: picture, name, mobile number, area and
/// password. A technician's municipality and coverage are set by an
/// agriculturist (they decide which queue the technician works), so they are
/// shown read-only. Pull down to load changes made on the dashboard.
class F15Profile extends StatefulWidget {
  const F15Profile({super.key});

  @override
  State<F15Profile> createState() => _F15ProfileState();
}

class _F15ProfileState extends State<F15Profile> {
  final _auth = AuthControllerImpl.instance;
  final _name = TextEditingController();
  final _phoneCtl = TextEditingController();
  final _barangay = TextEditingController();
  final _current = TextEditingController();
  final _new = TextEditingController();
  final _confirm = TextEditingController();
  String _municipality = '';

  Map<String, String?> _errors = {};
  Map<String, String?> _pwErrors = {};
  bool _saving = false;
  bool _savingPw = false;
  bool _uploading = false;
  String? _preview; // path (on the web a blob: URL) of the picture being sent
  bool _showPw = false;

  bool get _isTech => _auth.role == AppRole.technician;

  @override
  void initState() {
    super.initState();
    _fill();
    for (final c in [_name, _phoneCtl, _barangay]) {
      c.addListener(_onEdit);
    }
    _auth.addListener(_onSession);
    // Pick up changes an agriculturist made since the last start.
    _refresh(quiet: true);
  }

  @override
  void dispose() {
    _auth.removeListener(_onSession);
    for (final c in [_name, _phoneCtl, _barangay, _current, _new, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  void _onEdit() => setState(() {});

  /// The session changed (refresh, upload): show it unless the person is editing.
  void _onSession() {
    if (!mounted) return;
    if (!_dirty) _fill();
    setState(() {});
  }

  void _fill() {
    final s = _auth.session;
    _name.text = s?.name ?? '';
    _phoneCtl.text = s?.phone ?? '';
    _barangay.text = s?.barangay ?? '';
    _municipality = s?.municipality ?? '';
  }

  bool get _dirty {
    final s = _auth.session;
    if (s == null) return false;
    return _name.text.trim() != s.name ||
        _phoneCtl.text.trim() != s.phone ||
        _barangay.text.trim() != s.barangay ||
        _municipality != s.municipality;
  }

  Future<void> _refresh({bool quiet = false}) async {
    try {
      await ApiClient.refreshProfile();
    } on ApiException catch (e) {
      if (!quiet) _snack(e.isOffline ? 'No signal. Showing the profile saved on this phone.' : e.message);
    }
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  // ---------------------------------------------------------------- details

  Future<void> _save() async {
    final s = _auth.session;
    if (s == null) return;
    final name = _name.text.trim();
    final phone = _phoneCtl.text.trim();
    final barangay = _barangay.text.trim();
    final errors = <String, String?>{
      if (name.length < 2) 'name': 'Enter your full name.',
      if (phone.isEmpty) 'phone': 'Enter your mobile number.' else if (!_phone.hasMatch(phone)) 'phone': 'Enter a valid mobile number, e.g. 0917 123 4567.',
      if (_municipality.isEmpty) 'municipality': 'Choose your municipality.',
      if (barangay.isEmpty) 'barangay': 'Enter your barangay.',
    };
    setState(() => _errors = errors);
    if (errors.isNotEmpty) {
      HapticFeedback.mediumImpact();
      return;
    }
    setState(() => _saving = true);
    try {
      final data = await ApiClient.put('/auth/me', {
        if (name != s.name) 'full_name': name,
        if (phone != s.phone) 'phone': phone,
        if (barangay != s.barangay) 'barangay': barangay,
        if (_municipality != s.municipality) 'municipality': _municipality,
      });
      await ApiClient.applyProfile(data);
      _fill();
      _snack('Profile saved.');
    } on ApiException catch (e) {
      _snack(e.isOffline ? 'No signal. Your changes were not saved; try again with signal.' : e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _changePassword() async {
    final errors = <String, String?>{
      if (_current.text.isEmpty) 'current': 'Enter your current password.',
      if (_new.text.length < 8) 'new': 'Use at least 8 characters.',
      if (_confirm.text != _new.text) 'confirm': "The passwords don't match.",
    };
    setState(() => _pwErrors = errors);
    if (errors.isNotEmpty) {
      HapticFeedback.mediumImpact();
      return;
    }
    setState(() => _savingPw = true);
    try {
      await ApiClient.put('/auth/me', {'current_password': _current.text, 'new_password': _new.text});
      for (final c in [_current, _new, _confirm]) {
        c.clear();
      }
      setState(() => _showPw = false);
      _snack('Password changed. Use the new one the next time you sign in.');
    } on ApiException catch (e) {
      if (e.message.toLowerCase().contains('current password')) {
        setState(() => _pwErrors = {'current': e.message});
      } else {
        _snack(e.isOffline ? 'No signal. The password was not changed.' : e.message);
      }
    } finally {
      if (mounted) setState(() => _savingPw = false);
    }
  }

  // ---------------------------------------------------------------- picture

  Future<void> _changePicture() async {
    final hasPicture = _auth.session?.avatarUrl != null;
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.hPad, 0, AppSpacing.hPad, AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Profile picture',
                  style: TextStyle(fontFamily: AppFonts.display, fontSize: 19, fontWeight: FontWeight.w800)),
              const SizedBox(height: AppSpacing.md),
              _SheetOption(icon: Icons.photo_camera_rounded, label: 'Take a photo', onTap: () => Navigator.pop(ctx, 'camera')),
              _SheetOption(icon: Icons.photo_library_rounded, label: 'Choose from gallery', onTap: () => Navigator.pop(ctx, 'gallery')),
              if (hasPicture)
                _SheetOption(
                  icon: Icons.delete_outline_rounded,
                  label: 'Remove picture',
                  color: AppColors.danger,
                  onTap: () => Navigator.pop(ctx, 'remove'),
                ),
            ],
          ),
        ),
      ),
    );
    if (choice == null || !mounted) return;
    if (choice == 'remove') return _removePicture();
    final XFile? picked;
    try {
      picked = await ImagePicker().pickImage(
        source: choice == 'camera' ? ImageSource.camera : ImageSource.gallery,
        preferredCameraDevice: CameraDevice.front,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
    } catch (_) {
      _snack(choice == 'camera' ? 'Could not open the camera.' : 'Could not open the gallery.');
      return;
    }
    if (picked == null || !mounted) return;
    final path = picked.path;
    setState(() {
      _preview = path;
      _uploading = true;
    });
    try {
      await ApiClient.applyProfile(
          await ApiClient.upload('/auth/me/avatar', const {}, path, filename: uploadFileName(picked)));
      _snack('Profile picture updated.');
    } on ApiException catch (e) {
      _snack(e.isOffline ? 'No signal. The picture was not uploaded.' : e.message);
    } finally {
      if (mounted) {
        setState(() {
          _preview = null;
          _uploading = false;
        });
      }
    }
  }

  Future<void> _removePicture() async {
    setState(() => _uploading = true);
    try {
      await ApiClient.applyProfile(await ApiClient.delete('/auth/me/avatar'));
      _snack('Profile picture removed.');
    } on ApiException catch (e) {
      _snack(e.isOffline ? 'No signal. Try again with signal.' : e.message);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  // ---------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    final s = _auth.session;
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _refresh,
        edgeOffset: MediaQuery.paddingOf(context).top,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            _header(s),
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.hPad, AppSpacing.lg, AppSpacing.hPad, AppSpacing.xxl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _detailsCard(s),
                  const SizedBox(height: AppSpacing.lg),
                  _passwordCard(),
                  const SizedBox(height: AppSpacing.lg),
                  const Center(
                    child: Text(
                      'Pull down to load changes made by your agriculturist.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textMuted, fontSize: 12.5),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(Session? s) {
    final roleLabel = switch (s?.role) {
      AppRole.technician => 'Agricultural technician',
      _ => 'Farmer',
    };
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Container(
        decoration: const BoxDecoration(
          gradient: kHeroGradient,
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(30)),
        ),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.hPad, AppSpacing.sm, AppSpacing.hPad, AppSpacing.xl),
            child: Column(
              children: [
                Row(
                  children: [
                    AppCircleButton(icon: Icons.arrow_back_rounded, tooltip: 'Back', dark: true, onTap: () => popOrGoHome(context)),
                    const SizedBox(width: AppSpacing.md),
                    const Expanded(
                      child: Text('My profile',
                          style: TextStyle(fontFamily: AppFonts.display, color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Semantics(
                  button: true,
                  label: 'Change profile picture',
                  child: GestureDetector(
                    onTap: _uploading ? null : _changePicture,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        UserAvatar(size: 112, onDark: true, preview: _preview),
                        if (_uploading)
                          Container(
                            width: 112,
                            height: 112,
                            decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.35), shape: BoxShape.circle),
                            alignment: Alignment.center,
                            child: const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3)),
                          ),
                        Positioned(
                          right: 0,
                          bottom: 2,
                          child: Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(colors: [AppColors.brandGold, Color(0xFFF5D66B)]),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 3),
                            ),
                            child: const Icon(Icons.photo_camera_rounded, size: 18, color: AppColors.primaryDeep),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  s?.name ?? '',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontFamily: AppFonts.display, color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800),
                ),
                Text(s?.email ?? '', style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 13.5)),
                const SizedBox(height: AppSpacing.sm),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_isTech ? Icons.engineering_rounded : Icons.agriculture_rounded, size: 15, color: AppColors.brandGold),
                      const SizedBox(width: 6),
                      Text(roleLabel, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12.5)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _detailsCard(Session? s) {
    final munis = {...kAntiqueMunicipalities, if (_municipality.isNotEmpty) _municipality}.toList();
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _CardTitle(icon: Icons.badge_rounded, color: AppColors.emerald, title: 'Personal information'),
          const SizedBox(height: AppSpacing.lg),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            maxLength: 100,
            decoration: InputDecoration(labelText: 'Full name', counterText: '', errorText: _errors['name']),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _phoneCtl,
            keyboardType: TextInputType.phone,
            maxLength: 30,
            decoration: InputDecoration(labelText: 'Mobile number', counterText: '', hintText: '0917 123 4567', errorText: _errors['phone']),
          ),
          const SizedBox(height: AppSpacing.md),
          if (_isTech)
            InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Municipality',
                suffixIcon: Icon(Icons.lock_outline_rounded, size: 18),
                helperText: 'Set by your agriculturist (it decides your queue).',
              ),
              child: Text(_municipality.isEmpty ? 'Not set' : _municipality),
            )
          else
            DropdownButtonFormField<String>(
              // Rebuilt when the saved value changes (e.g. refreshed from the server).
              key: ValueKey('municipality:${s?.municipality}'),
              initialValue: _municipality.isEmpty ? null : _municipality,
              isExpanded: true,
              decoration: InputDecoration(labelText: 'Municipality', errorText: _errors['municipality']),
              items: [for (final m in munis) DropdownMenuItem(value: m, child: Text(m))],
              onChanged: (v) => setState(() => _municipality = v ?? ''),
            ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _barangay,
            textCapitalization: TextCapitalization.words,
            maxLength: 100,
            decoration: InputDecoration(labelText: 'Barangay', counterText: '', errorText: _errors['barangay']),
          ),
          if (_isTech) ...[
            const SizedBox(height: AppSpacing.md),
            const Text('Coverage', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (s == null || s.coverage.isEmpty)
                  AppChip(label: _municipality.isEmpty ? 'Not set yet' : 'All of $_municipality', color: AppColors.teal, icon: Icons.map_rounded)
                else
                  for (final b in s.coverage) AppChip(label: b, color: AppColors.teal, icon: Icons.place_rounded),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          AppPrimaryButton(
            label: 'Save changes',
            icon: Icons.check_rounded,
            loading: _saving,
            onPressed: _dirty ? _save : null,
          ),
        ],
      ),
    );
  }

  Widget _passwordCard() {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            onTap: () => setState(() => _showPw = !_showPw),
            child: Row(
              children: [
                const Expanded(child: _CardTitle(icon: Icons.lock_rounded, color: AppColors.purple, title: 'Change password')),
                AnimatedRotation(
                  turns: _showPw ? 0.5 : 0,
                  duration: AppMotion.medium,
                  child: const Icon(Icons.expand_more_rounded, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
          AnimatedSize(
            duration: AppMotion.medium,
            curve: AppMotion.curve,
            alignment: Alignment.topCenter,
            child: !_showPw
                ? const SizedBox(width: double.infinity)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: AppSpacing.lg),
                      TextField(
                        controller: _current,
                        obscureText: true,
                        decoration: InputDecoration(labelText: 'Current password', errorText: _pwErrors['current']),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      TextField(
                        controller: _new,
                        obscureText: true,
                        maxLength: 72,
                        decoration: InputDecoration(labelText: 'New password', counterText: '', errorText: _pwErrors['new']),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      TextField(
                        controller: _confirm,
                        obscureText: true,
                        maxLength: 72,
                        decoration: InputDecoration(labelText: 'Type the new password again', counterText: '', errorText: _pwErrors['confirm']),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      AppPrimaryButton(
                        label: 'Update password',
                        icon: Icons.key_rounded,
                        color: AppColors.purple,
                        loading: _savingPw,
                        onPressed: _changePassword,
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _CardTitle extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  const _CardTitle({required this.icon, required this.color, required this.title});

  @override
  Widget build(BuildContext context) => Row(
        children: [
          IconTile(icon: icon, color: color, size: 38, filled: true),
          const SizedBox(width: AppSpacing.md),
          Text(title, style: const TextStyle(fontFamily: AppFonts.display, fontSize: 17, fontWeight: FontWeight.w800)),
        ],
      );
}

class _SheetOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;
  const _SheetOption({required this.icon, required this.label, required this.onTap, this.color = AppColors.primary});

  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: EdgeInsets.zero,
        leading: IconTile(icon: icon, color: color, size: 42),
        title: Text(label, style: TextStyle(fontWeight: FontWeight.w700, color: color == AppColors.danger ? color : AppColors.textPrimary)),
        onTap: onTap,
      );
}
