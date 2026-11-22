import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../l10n/app_language.dart';
import '../platform/local_files.dart';
import '../services/api_client.dart';
import '../services/local_store.dart';
import '../theme.dart';
import '../widgets/app_widgets.dart';
import '../widgets/motion.dart';

/// "What to look for": the four pests and the damage symptoms the system
/// handles, with the crop stage when each appears and an example photo.
/// The content comes from the server (GET /guide, same as the dashboard)
/// and is kept on the phone, photos included, so it works without signal.
class F27Guide extends StatefulWidget {
  const F27Guide({super.key});

  @override
  State<F27Guide> createState() => _F27GuideState();
}

class _F27GuideState extends State<F27Guide> {
  static const _cacheKey = 'guide';

  Map<String, dynamic>? _guide;
  String? _error;
  bool _offline = false;
  final Map<String, String> _photos = {}; // entry key -> file on this phone

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await ApiClient.get('/guide') as Map<String, dynamic>;
      await LocalStore.instance.putCache(_cacheKey, data);
      if (!mounted) return;
      setState(() {
        _guide = data;
        _error = null;
        _offline = false;
      });
    } on ApiException catch (e) {
      final cached = await LocalStore.instance.getCache(_cacheKey);
      if (!mounted) return;
      if (cached is Map<String, dynamic>) {
        setState(() {
          _guide = cached;
          _offline = e.isOffline;
        });
      } else {
        setState(() => _error = e.isOffline ? 'No signal, and the guide has not been saved on this phone yet.' : e.message);
      }
    }
    await _loadPhotos();
  }

  /// Example photos are saved once and reused offline.
  Future<void> _loadPhotos() async {
    final g = _guide;
    if (g == null) return;
    final dir = p.join(await supportDirPath(), 'guide_photos');
    await createLocalDir(dir);
    final entries = [...(g['pests'] as List? ?? const []), ...(g['symptoms'] as List? ?? const [])];
    for (final e in entries) {
      final m = e as Map;
      final key = '${m['key']}';
      final file = p.join(dir, '$key.img');
      final path = m['photo'] as String?;
      try {
        if (path != null && !localFileExistsSync(file)) {
          await writeLocalFile(file, await ApiClient.downloadImage(path));
        }
      } catch (_) {
        // no signal or no photo yet: the placeholder stays
      }
      if (localFileExistsSync(file) && mounted) setState(() => _photos[key] = file);
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = _guide;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            AppHeader(title: context.tr('What to look for'), subtitle: context.tr('Pests and the damage they cause')),
            Expanded(
              child: g == null
                  ? (_error == null
                      ? const Padding(
                          padding: EdgeInsets.all(AppSpacing.hPad),
                          child: SkeletonList(rows: 4, cards: true),
                        )
                      : ListView(children: [
                          AppEmptyState(
                            icon: Icons.menu_book_outlined,
                            title: context.tr('Can\'t load the guide'),
                            message: context.tr(_error!),
                            actionLabel: context.tr('Try again'),
                            onAction: _load,
                          ),
                        ]))
                  : RefreshIndicator(onRefresh: _load, child: _body(g)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(Map<String, dynamic> g) {
    final pests = [for (final x in (g['pests'] as List? ?? const [])) (x as Map).cast<String, dynamic>()];
    final symptoms = [for (final x in (g['symptoms'] as List? ?? const [])) (x as Map).cast<String, dynamic>()];
    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.hPad, AppSpacing.xs, AppSpacing.hPad, AppSpacing.xl),
      children: [
        if (_offline) ...[
          InfoBanner(
            icon: Icons.cloud_off_rounded,
            color: AppColors.textSecondary,
            message: context.tr('No signal. Showing the guide saved on this phone.'),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        InfoBanner(icon: Icons.info_outline_rounded, color: AppColors.primary, message: '${g['model_note'] ?? ''}'),
        const SizedBox(height: AppSpacing.lg),
        for (final (i, pest) in pests.indexed) ...[
          FadeSlideIn(
            index: i,
            child: _PestCard(
              pest: pest,
              symptoms: symptoms.where((s) => s['pest'] == pest['key']).toList(),
              photos: _photos,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
      ],
    );
  }
}

List<String> _strings(Object? v) => [for (final x in (v as List? ?? const [])) '$x'];

class _PestCard extends StatelessWidget {
  final Map<String, dynamic> pest;
  final List<Map<String, dynamic>> symptoms;
  final Map<String, String> photos;
  const _PestCard({required this.pest, required this.symptoms, required this.photos});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Photo(path: photos['${pest['key']}'], height: 170, top: true),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${pest['name']}', style: const TextStyle(fontFamily: AppFonts.display, fontSize: 21, fontWeight: FontWeight.w800)),
                const SizedBox(height: AppSpacing.sm),
                for (final s in _strings(pest['signs']))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 7, right: 8),
                          child: Icon(Icons.circle, size: 6, color: AppColors.primary),
                        ),
                        Expanded(child: Text(s, style: const TextStyle(fontSize: 14.5, height: 1.4))),
                      ],
                    ),
                  ),
                const SizedBox(height: AppSpacing.sm),
                _Stages(stages: _strings(pest['stages'])),
                const SizedBox(height: 4),
                Text('${pest['stage_note'] ?? ''}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.4)),
                const SizedBox(height: AppSpacing.lg),
                Text(context.tr('Damage to look for'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                for (final s in symptoms) ...[
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(width: 92, child: _Photo(path: photos['${s['key']}'], height: 76)),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${s['name']}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
                            const SizedBox(height: 2),
                            Text('${s['signs']}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 13.5, height: 1.4)),
                            const SizedBox(height: 6),
                            _Stages(stages: _strings(s['stages'])),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Stages extends StatelessWidget {
  final List<String> stages;
  const _Stages({required this.stages});

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 6,
        runSpacing: 4,
        children: [
          for (final s in stages)
            AppChip(
              label: s,
              color: const {'Vegetative': AppColors.primary, 'Reproductive': AppColors.orange}[s] ?? AppColors.textSecondary,
            ),
        ],
      );
}

/// The example photo, or a placeholder until the group adds one.
class _Photo extends StatelessWidget {
  final String? path;
  final double height;
  final bool top;
  const _Photo({required this.path, required this.height, this.top = false});

  @override
  Widget build(BuildContext context) {
    final radius = top
        ? const BorderRadius.vertical(top: Radius.circular(AppRadius.md))
        : BorderRadius.circular(AppRadius.sm);
    return ClipRRect(
      borderRadius: radius,
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: path != null
            ? localImage(path!, fit: BoxFit.cover)
            : ColoredBox(
                color: AppColors.surfaceMuted,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.image_outlined, color: AppColors.textMuted),
                      if (height > 100)
                        Text(context.tr('Example photo not added yet'),
                            style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}

