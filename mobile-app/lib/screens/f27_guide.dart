import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../l10n/app_language.dart';
import '../models/guide.dart';
import '../platform/local_files.dart';
import '../services/api_client.dart';
import '../services/local_store.dart';
import '../theme.dart';
import '../widgets/app_widgets.dart';
import '../widgets/motion.dart';

/// "What to look for", in two clearly separate parts: the four insects the
/// photo model detects, and the damage people check in the field. With the
/// crop stage when each appears, example photos and a glossary. The content
/// comes from the server (GET /guide, in the app language) and is kept on
/// the phone, photos included, so it works without signal.
class F27Guide extends StatefulWidget {
  /// Shows this guide (GET /guide JSON) without loading anything: for
  /// widget tests and previews only.
  @visibleForTesting
  final Map<String, dynamic>? preview;

  const F27Guide({super.key, this.preview});

  @override
  State<F27Guide> createState() => _F27GuideState();
}

class _F27GuideState extends State<F27Guide> {
  /// Older builds kept one copy under this key (whatever the language).
  static const _legacyCacheKey = 'guide';

  GuideContent? _guide;
  String? _error;
  bool _offline = false;
  bool _loading = false;
  DateTime? _savedAt; // set while showing the copy saved on the phone
  final Map<String, String> _photos = {}; // entry key -> file on this phone
  late String _lang;

  String get _cacheKey => 'guide_$_lang';

  @override
  void initState() {
    super.initState();
    _lang = AppLanguage.instance.code;
    if (widget.preview != null) {
      _guide = GuideContent.fromJson(widget.preview!);
      return;
    }
    AppLanguage.instance.addListener(_onLanguage);
    _load();
  }

  @override
  void dispose() {
    AppLanguage.instance.removeListener(_onLanguage);
    super.dispose();
  }

  /// The language changed: show that language's saved copy and fetch it again.
  void _onLanguage() {
    final code = AppLanguage.instance.code;
    if (code == _lang) return;
    _lang = code;
    _guide = null;
    _load();
  }

  /// Cache first: the saved copy shows at once, then the server's replaces it.
  Future<void> _load() async {
    final lang = _lang;
    setState(() {
      _loading = true;
      _error = null;
    });
    if (_guide == null) {
      try {
        final entry = await LocalStore.instance.getCacheEntry(_cacheKey) ??
            (lang == 'en' ? await LocalStore.instance.getCacheEntry(_legacyCacheKey) : null);
        if (entry?.data is Map<String, dynamic> && mounted && _guide == null && lang == _lang) {
          setState(() {
            _guide = GuideContent.fromJson(entry!.data as Map<String, dynamic>);
            _savedAt = entry.savedAt;
          });
          await _loadPhotos();
        }
      } catch (e) {
        debugPrint('[Guide] no saved copy: $e');
      }
    }
    try {
      final data = await ApiClient.get('/guide', query: {'lang': lang}) as Map<String, dynamic>;
      await LocalStore.instance.putCache('guide_$lang', data);
      if (!mounted || lang != _lang) return;
      setState(() {
        _guide = GuideContent.fromJson(data);
        _error = null;
        _offline = false;
        _savedAt = null;
      });
    } on ApiException catch (e) {
      if (!mounted || lang != _lang) return;
      setState(() {
        _offline = e.isOffline;
        _error = e.isOffline ? 'No signal, and the guide has not been saved on this phone yet.' : e.message;
      });
    } catch (e) {
      debugPrint('[Guide] could not load: $e');
      if (mounted) setState(() => _error = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
    await _loadPhotos();
  }

  /// Example photos are saved once and reused offline.
  Future<void> _loadPhotos() async {
    final g = _guide;
    if (g == null) return;
    try {
      final dir = p.join(await supportDirPath(), 'guide_photos');
      await createLocalDir(dir);
      for (final e in g.allEntries) {
        if (e.key.isEmpty || _photos.containsKey(e.key)) continue;
        final file = p.join(dir, '${e.key}.img');
        try {
          if (e.photo != null && !localFileExistsSync(file)) {
            await writeLocalFile(file, await ApiClient.downloadImage(e.photo!));
          }
        } catch (_) {
          // no signal or no photo yet: the placeholder stays
        }
        if (localFileExistsSync(file) && mounted) setState(() => _photos[e.key] = file);
      }
    } catch (e) {
      debugPrint('[Guide] photos unavailable: $e');
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

  Widget _body(GuideContent g) {
    final byPest = <String, List<GuideEntry>>{};
    for (final s in g.observedSymptoms) {
      byPest.putIfAbsent(s.pest, () => []).add(s);
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.hPad, AppSpacing.xs, AppSpacing.hPad, AppSpacing.xl),
      children: [
        MaxContentWidth(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_savedAt != null) SavedDataNote(savedAt: _savedAt!, refreshing: _loading),
              if (_error != null && _offline) ...[
                InfoBanner(
                  icon: Icons.cloud_off_rounded,
                  color: AppColors.textSecondary,
                  message: context.tr('No signal. Showing the guide saved on this phone.'),
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              if (g.translationNote.isNotEmpty) ...[
                InfoBanner(
                  key: const ValueKey('guide-translation-note'),
                  icon: Icons.translate_rounded,
                  color: AppColors.sky,
                  message: g.translationNote,
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              if (g.modelNote.isNotEmpty) ...[
                InfoBanner(icon: Icons.info_outline_rounded, color: AppColors.primary, message: g.modelNote),
                const SizedBox(height: AppSpacing.lg),
              ],
              _SectionTitle(
                key: const ValueKey('guide-model-section'),
                icon: Icons.document_scanner_rounded,
                color: AppColors.primary,
                title: g.modelHeading,
              ),
              const SizedBox(height: AppSpacing.md),
              for (final (i, pest) in g.modelDetected.indexed) ...[
                FadeSlideIn(index: i, child: _PestCard(pest: pest, photos: _photos)),
                const SizedBox(height: AppSpacing.lg),
              ],
              if (g.confirmNote.isNotEmpty) ...[
                InfoBanner(icon: Icons.verified_user_outlined, color: AppColors.orange, message: g.confirmNote),
                const SizedBox(height: AppSpacing.xl),
              ],
              _SectionTitle(
                key: const ValueKey('guide-people-section'),
                icon: Icons.visibility_rounded,
                color: AppColors.orange,
                title: g.peopleHeading,
              ),
              const SizedBox(height: AppSpacing.md),
              for (final entry in byPest.entries) ...[
                _SymptomGroup(
                  pestName: entry.value.first.pestName.isNotEmpty ? entry.value.first.pestName : entry.key,
                  symptoms: entry.value,
                  photos: _photos,
                ),
                const SizedBox(height: AppSpacing.lg),
              ],
              if (g.glossary.isNotEmpty)
                AppCard(
                  padding: EdgeInsets.zero,
                  child: Theme(
                    data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      key: const ValueKey('guide-glossary'),
                      leading: const Icon(Icons.menu_book_rounded, color: AppColors.primary),
                      title: Text(context.tr('Glossary'), style: const TextStyle(fontWeight: FontWeight.w800)),
                      childrenPadding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.md),
                      expandedCrossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final item in g.glossary)
                          Padding(
                            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                            child: Text.rich(
                              TextSpan(children: [
                                TextSpan(text: '${item.term}: ', style: const TextStyle(fontWeight: FontWeight.w800)),
                                TextSpan(text: item.meaning),
                              ]),
                              style: const TextStyle(fontSize: 14, height: 1.4),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  const _SectionTitle({super.key, required this.icon, required this.color, required this.title});

  @override
  Widget build(BuildContext context) => Row(
        children: [
          IconTile(icon: icon, color: color, size: 34, filled: true),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(title, style: const TextStyle(fontFamily: AppFonts.display, fontSize: 19, fontWeight: FontWeight.w800)),
          ),
        ],
      );
}

class _Bullets extends StatelessWidget {
  final List<String> items;
  const _Bullets({required this.items});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final s in items)
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
        ],
      );
}

/// An insect the photo model detects.
class _PestCard extends StatelessWidget {
  final GuideEntry pest;
  final Map<String, String> photos;
  const _PestCard({required this.pest, required this.photos});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Photo(path: photos[pest.key], height: 170, top: true),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(pest.name, style: const TextStyle(fontFamily: AppFonts.display, fontSize: 21, fontWeight: FontWeight.w800)),
                if (pest.modelLabel.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(context.tr('Model label: {label}', {'label': pest.modelLabel}),
                        style: const TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
                  ),
                const SizedBox(height: AppSpacing.sm),
                _Bullets(items: pest.signs),
                const SizedBox(height: AppSpacing.sm),
                _Stages(labels: pest.stageLabels, stages: pest.stages),
                if (pest.stageNote.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(pest.stageNote, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.4)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Damage people check in the field, grouped by the pest that causes it.
class _SymptomGroup extends StatelessWidget {
  final String pestName;
  final List<GuideEntry> symptoms;
  final Map<String, String> photos;
  const _SymptomGroup({required this.pestName, required this.symptoms, required this.photos});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.tr('Damage from {pest}', {'pest': pestName}),
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
          for (final s in symptoms) ...[
            const SizedBox(height: AppSpacing.md),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 92, child: _Photo(path: photos[s.key], height: 76)),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
                      const SizedBox(height: 2),
                      Text(s.signs.join(' '),
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13.5, height: 1.4)),
                      if (s.indicatorLabel.isNotEmpty && s.indicatorLabel != s.name) ...[
                        const SizedBox(height: 2),
                        Text(context.tr('Damage checkbox: {label}', {'label': s.indicatorLabel}),
                            style: const TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
                      ],
                      const SizedBox(height: 6),
                      _Stages(labels: s.stageLabels, stages: s.stages),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Crop stage chips: the translated labels, coloured by the English stage.
class _Stages extends StatelessWidget {
  final List<String> labels;
  final List<String> stages;
  const _Stages({required this.labels, required this.stages});

  static const _colors = {'Vegetative': AppColors.primary, 'Reproductive': AppColors.orange};

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 6,
        runSpacing: 4,
        children: [
          for (final (i, label) in labels.indexed)
            AppChip(
              label: label,
              color: _colors[i < stages.length ? stages[i] : label] ?? AppColors.textSecondary,
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
