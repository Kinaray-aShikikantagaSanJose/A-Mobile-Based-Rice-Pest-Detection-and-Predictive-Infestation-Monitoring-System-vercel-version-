import 'package:flutter/material.dart';

import '../l10n/app_language.dart';
import '../theme.dart';

// Labels below are English; the helpers return them in the chosen language
// (lib/l10n). Values that are stored or sent to the API (trap types, target
// pests, crop stage keys, ...) stay English: translate those only where shown.

const List<String> kMonthNames = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

// ---------------------------------------------------------------- domain values
// Same keys and labels as the API (rice-pest-api/app/levels.py, detector.py).

const List<String> kCropStages = ['Vegetative', 'Reproductive', 'Ripening'];

Map<String, String> get kCropStageHints => {
      'Vegetative': tr('Seedling to tillering'),
      'Reproductive': tr('Booting to flowering'),
      'Ripening': tr('Grain filling to harvest'),
    };

const Map<String, String> kPestNames = {
  'brown_planthopper': 'Brown Planthopper',
  'green_leafhopper': 'Green Leafhopper',
  'rice_bug': 'Rice Bug',
  'rice_stem_borer': 'Rice Stem Borer',
  'other': 'Outside the supported pests',
};

/// The four pests the model knows, then "outside the supported set".
const List<String> kPestKeys = [
  'brown_planthopper',
  'green_leafhopper',
  'rice_bug',
  'rice_stem_borer',
  'other',
];

String pestName(String? key, {String fallback = 'Not identified'}) {
  if (key == null || key.trim().isEmpty) return tr(fallback);
  if (key == 'other') return tr(kPestNames['other']!);
  // The four pest names are kept as they are (proper names).
  return kPestNames[key] ?? key.replaceAll('_', ' ');
}

/// Land type of the field (same keys as the API, app/land.py). The
/// definitions are in docs/land-type-definition.md.
List<(String, String, String)> get kLandTypes => [
      ('upland', tr('Upland'), tr('Sloping or high ground, no bunds, no standing water. Rain is the only water.')),
      ('rainfed_lowland', tr('Rainfed lowland'), tr('Bunded, flat paddy that holds water from rain or run-off only.')),
      ('irrigated_lowland', tr('Irrigated lowland'), tr('Bunded, flat paddy with water from an irrigation canal or pump.')),
    ];

/// 'Upland', 'Rainfed lowland', 'Irrigated lowland', or 'Not recorded' (translated).
String landTypeLabel(String? key) {
  for (final (k, label, _) in kLandTypes) {
    if (k == key) return label;
  }
  return tr('Not recorded');
}

const List<String> kTrapTypes = [
  'Sticky trap (yellow)',
  'Sticky trap (blue)',
  'Light trap',
  'Pheromone lure',
  'Other trap',
];

const List<String> kTargetPests = [
  'Brown Planthopper',
  'Green Leafhopper',
  'Rice Bug',
  'Rice Stem Borer',
  'Not sure',
];

const List<String> kTargetSexes = ['Male', 'Female', 'Not known'];

Map<String, String> get kOptionTypeNames => {
      'cultural': tr('Cultural'),
      'biological': tr('Biological'),
      'ecological': tr('Ecological'),
      'chemical': tr('Chemical'),
      'own': tr('My own method'),
    };

const Map<String, IconData> kOptionTypeIcons = {
  'cultural': Icons.agriculture_rounded,
  'biological': Icons.bug_report_outlined,
  'ecological': Icons.eco_rounded,
  'chemical': Icons.science_outlined,
  'own': Icons.edit_note_rounded,
};

// ---------------------------------------------------------------- levels

String levelLabel(String? level) {
  switch ((level ?? '').toUpperCase()) {
    case 'HIGH':
      return tr('High');
    case 'MEDIUM':
      return tr('Medium');
    case 'LOW':
      return tr('Low');
    default:
      return '—';
  }
}

Color levelColor(String? level) => severityColor(level ?? '');

// ---------------------------------------------------------------- status

/// What a farmer sees on a record. [waiting] = still on the phone (no signal yet).
/// [noPests] = the model confidently found no insect on a clear photo; the
/// observation is closed (no review) and its photo was removed from the server.
enum RecordState { waiting, forValidation, sentForReview, withAgriculturist, returned, validated, noPests }

RecordState recordState({required bool uploaded, required String status, required bool isDisease}) {
  if (!uploaded) return RecordState.waiting;
  switch (status) {
    case 'no_pests':
      return RecordState.noPests;
    case 'validated':
      return RecordState.validated;
    case 'returned':
      return RecordState.returned;
    case 'escalated':
      return RecordState.withAgriculturist;
    default:
      return isDisease ? RecordState.sentForReview : RecordState.forValidation;
  }
}

String recordStateLabel(RecordState s) {
  switch (s) {
    case RecordState.waiting:
      return tr('Waiting for signal');
    case RecordState.forValidation:
      return tr('For technician validation');
    case RecordState.sentForReview:
      return tr('Sent for review');
    case RecordState.withAgriculturist:
      return tr('With an agriculturist');
    case RecordState.returned:
      return tr('Please send a new photo');
    case RecordState.validated:
      return tr('Validated');
    case RecordState.noPests:
      return tr('No pests found');
  }
}

Color recordStateColor(RecordState s) {
  switch (s) {
    case RecordState.waiting:
      return AppColors.textMuted;
    case RecordState.forValidation:
    case RecordState.sentForReview:
      return AppColors.orange;
    case RecordState.withAgriculturist:
      return const Color(0xFF7C3AED);
    case RecordState.returned:
      return AppColors.danger;
    case RecordState.validated:
      return AppColors.primary;
    case RecordState.noPests:
      return AppColors.sky;
  }
}

IconData recordStateIcon(RecordState s) {
  switch (s) {
    case RecordState.waiting:
      return Icons.signal_cellular_connected_no_internet_0_bar_rounded;
    case RecordState.forValidation:
    case RecordState.sentForReview:
      return Icons.hourglass_top_rounded;
    case RecordState.withAgriculturist:
      return Icons.forward_to_inbox_rounded;
    case RecordState.returned:
      return Icons.replay_rounded;
    case RecordState.validated:
      return Icons.verified_rounded;
    case RecordState.noPests:
      return Icons.eco_rounded;
  }
}

// ---------------------------------------------------------------- dates

DateTime? parseLocal(String? iso) => iso == null ? null : DateTime.tryParse(iso.trim())?.toLocal();

String formatShortDate(String? iso) {
  final d = parseLocal(iso);
  if (d == null) return '—';
  return '${tr(kMonthNames[d.month - 1])} ${d.day}, ${d.year}';
}

String formatDateTime(String? iso) {
  final d = parseLocal(iso);
  if (d == null) return '—';
  final hour = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final minute = d.minute.toString().padLeft(2, '0');
  final ampm = d.hour < 12 ? 'AM' : 'PM';
  return '${tr(kMonthNames[d.month - 1])} ${d.day}, ${d.year} · $hour:$minute $ampm';
}

/// "Today", "Yesterday", "3 days ago", or a date.
String formatRelativeDay(String? iso) {
  final d = parseLocal(iso);
  if (d == null) return '—';
  final today = DateUtils.dateOnly(DateTime.now());
  final days = today.difference(DateUtils.dateOnly(d)).inDays;
  if (days == 0) return tr('Today');
  if (days == 1) return tr('Yesterday');
  if (days > 1 && days < 7) return tr('{n} days ago', {'n': days});
  return formatShortDate(iso);
}

/// How long something has waited: "25 min", "5 h", "3 days".
String waitingLabel(String? iso) {
  final d = parseLocal(iso);
  if (d == null) return '—';
  final mins = DateTime.now().difference(d).inMinutes.clamp(0, 1 << 31);
  if (mins < 60) return tr('{n} min', {'n': mins});
  final hours = mins ~/ 60;
  if (hours < 24) return tr('{n} h', {'n': hours});
  final days = hours ~/ 24;
  return tr(days == 1 ? '{n} day' : '{n} days', {'n': days});
}

/// "1 insect", "3 insects" (translated: keys '{n} insect' / '{n} insects').
String plural(int n, String noun) => tr(n == 1 ? '{n} $noun' : '{n} ${noun}s', {'n': n});

/// yyyy-mm-dd for the API.
String isoDate(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
