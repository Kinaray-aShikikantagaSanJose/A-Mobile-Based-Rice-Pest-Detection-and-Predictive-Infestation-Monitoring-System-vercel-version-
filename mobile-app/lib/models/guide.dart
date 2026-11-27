import '../l10n/app_language.dart';

String _s(Object? v) => v is String ? v : (v == null ? '' : '$v');

List<String> _strings(Object? v) {
  if (v is List) return [for (final x in v) if (x != null && '$x'.trim().isNotEmpty) '$x'];
  if (v is String && v.trim().isNotEmpty) return [v];
  return const [];
}

/// One entry of the guide: an insect the photo model detects, or damage
/// people check in the field.
class GuideEntry {
  final String key;
  final String name;
  final String nameEn;
  final List<String> signs;

  /// Crop stages, already in the app language when the server sent
  /// `stage_labels`; otherwise the English stage names translated here.
  final List<String> stageLabels;

  /// English stage names (for colours), when known.
  final List<String> stages;
  final String stageNote;
  final String? photo;

  /// 'model' (the photo model can find it) or 'people' (checked in the field).
  final String detectedBy;

  // Model entries
  final String modelLabel;

  // Symptom entries
  final String pest;
  final String pestName;
  final String indicatorLabel;

  const GuideEntry({
    required this.key,
    required this.name,
    this.nameEn = '',
    this.signs = const [],
    this.stageLabels = const [],
    this.stages = const [],
    this.stageNote = '',
    this.photo,
    this.detectedBy = '',
    this.modelLabel = '',
    this.pest = '',
    this.pestName = '',
    this.indicatorLabel = '',
  });

  factory GuideEntry.fromJson(Map<String, dynamic> j, {required String detectedBy}) {
    final stages = _strings(j['stages']);
    final labels = _strings(j['stage_labels']);
    return GuideEntry(
      key: _s(j['key']),
      name: _s(j['name']),
      nameEn: _s(j['name_en']),
      signs: _strings(j['signs']),
      stageLabels: labels.isNotEmpty ? labels : [for (final s in stages) tr(s)],
      stages: stages,
      stageNote: _s(j['stage_note']),
      photo: j['photo'] is String ? j['photo'] as String : null,
      detectedBy: _s(j['detected_by']).isEmpty ? detectedBy : _s(j['detected_by']),
      modelLabel: _s(j['model_label']),
      pest: _s(j['pest']),
      pestName: _s(j['pest_name']),
      indicatorLabel: _s(j['indicator_label']),
    );
  }
}

class GlossaryItem {
  final String term;
  final String meaning;
  const GlossaryItem(this.term, this.meaning);
}

/// GET /guide, in the language it was asked for. Newer servers split what
/// the photo model detects from what people check in the field; older ones
/// only send `pests` and `symptoms` (used as the fallback).
class GuideContent {
  final String language;

  /// 'source' (English) or 'machine_assisted_unreviewed'.
  final String translationStatus;
  final String translationNote;
  final String modelNote;
  final String confirmNote;
  final String modelHeading;
  final String peopleHeading;
  final List<GuideEntry> modelDetected;
  final List<GuideEntry> observedSymptoms;
  final List<GlossaryItem> glossary;

  const GuideContent({
    this.language = 'en',
    this.translationStatus = 'source',
    this.translationNote = '',
    this.modelNote = '',
    this.confirmNote = '',
    required this.modelHeading,
    required this.peopleHeading,
    this.modelDetected = const [],
    this.observedSymptoms = const [],
    this.glossary = const [],
  });

  factory GuideContent.fromJson(Map<String, dynamic> j) {
    List<Map<String, dynamic>> maps(Object? v) =>
        [for (final x in (v as List? ?? const [])) if (x is Map) x.cast<String, dynamic>()];
    final sections = j['sections'] is Map ? (j['sections'] as Map).cast<String, dynamic>() : const <String, dynamic>{};
    final model = maps(j['model_detected'] ?? j['pests']);
    final people = maps(j['observed_symptoms'] ?? j['symptoms']);
    final modelHeading = _s(sections['model_detected']);
    final peopleHeading = _s(sections['observed_symptoms']);
    return GuideContent(
      language: _s(j['language']).isEmpty ? 'en' : _s(j['language']),
      translationStatus: _s(j['translation_status']).isEmpty ? 'source' : _s(j['translation_status']),
      translationNote: _s(j['translation_note']),
      modelNote: _s(j['model_note']),
      confirmNote: _s(j['confirm_note']),
      modelHeading: modelHeading.isEmpty ? tr('Detected by the photo model') : modelHeading,
      peopleHeading: peopleHeading.isEmpty ? tr('Checked by people in the field') : peopleHeading,
      modelDetected: [for (final m in model) GuideEntry.fromJson(m, detectedBy: 'model')],
      observedSymptoms: [for (final m in people) GuideEntry.fromJson(m, detectedBy: 'people')],
      glossary: [
        for (final g in maps(j['glossary']))
          if (_s(g['term']).isNotEmpty) GlossaryItem(_s(g['term']), _s(g['meaning'])),
      ],
    );
  }

  /// Every entry with a photo, for downloading them once.
  List<GuideEntry> get allEntries => [...modelDetected, ...observedSymptoms];
}
