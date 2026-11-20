import 'package:flutter/material.dart';

import '../theme.dart';

const List<String> kMonthNames = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

// ---------------------------------------------------------------- domain values
// Same keys and labels as the API (rice-pest-api/app/levels.py, detector.py).

const List<String> kCropStages = ['Vegetative', 'Reproductive', 'Ripening'];

const Map<String, String> kCropStageHints = {
  'Vegetative': 'Seedling to tillering',
  'Reproductive': 'Booting to flowering',
  'Ripening': 'Grain filling to harvest',
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
  if (key == null || key.trim().isEmpty) return fallback;
  return kPestNames[key] ?? key.replaceAll('_', ' ');
}

/// Land type of the field (same keys as the API, app/land.py). The
/// definitions are in docs/land-type-definition.md.
const List<(String, String, String)> kLandTypes = [
  ('upland', 'Upland', 'Sloping or high ground, no bunds, no standing water. Rain is the only water.'),
  ('rainfed_lowland', 'Rainfed lowland', 'Bunded, flat paddy that holds water from rain or run-off only.'),
  ('irrigated_lowland', 'Irrigated lowland', 'Bunded, flat paddy with water from an irrigation canal or pump.'),
];

/// 'Upland', 'Rainfed lowland', 'Irrigated lowland', or 'Not recorded'.
String landTypeLabel(String? key) {
  for (final (k, label, _) in kLandTypes) {
    if (k == key) return label;
  }
  return 'Not recorded';
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

const Map<String, String> kOptionTypeNames = {
  'cultural': 'Cultural',
  'biological': 'Biological',
  'ecological': 'Ecological',
  'chemical': 'Chemical',
  'own': 'My own method',
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
      return 'High';
    case 'MEDIUM':
      return 'Medium';
    case 'LOW':
      return 'Low';
    default:
      return '—';
  }
}

Color levelColor(String? level) => severityColor(level ?? '');

// ---------------------------------------------------------------- status

/// What a farmer sees on a record. [waiting] = still on the phone (no signal yet).
enum RecordState { waiting, forValidation, sentForReview, withAgriculturist, returned, validated }

RecordState recordState({required bool uploaded, required String status, required bool isDisease}) {
  if (!uploaded) return RecordState.waiting;
  switch (status) {
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
      return 'Waiting for signal';
    case RecordState.forValidation:
      return 'For technician validation';
    case RecordState.sentForReview:
      return 'Sent for review';
    case RecordState.withAgriculturist:
      return 'With an agriculturist';
    case RecordState.returned:
      return 'Please send a new photo';
    case RecordState.validated:
      return 'Validated';
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
  }
}

// ---------------------------------------------------------------- dates

DateTime? parseLocal(String? iso) => iso == null ? null : DateTime.tryParse(iso.trim())?.toLocal();

String formatShortDate(String? iso) {
  final d = parseLocal(iso);
  if (d == null) return '—';
  return '${kMonthNames[d.month - 1]} ${d.day}, ${d.year}';
}

String formatDateTime(String? iso) {
  final d = parseLocal(iso);
  if (d == null) return '—';
  final hour = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final minute = d.minute.toString().padLeft(2, '0');
  final ampm = d.hour < 12 ? 'AM' : 'PM';
  return '${kMonthNames[d.month - 1]} ${d.day}, ${d.year} · $hour:$minute $ampm';
}

/// "Today", "Yesterday", "3 days ago", or a date.
String formatRelativeDay(String? iso) {
  final d = parseLocal(iso);
  if (d == null) return '—';
  final today = DateUtils.dateOnly(DateTime.now());
  final days = today.difference(DateUtils.dateOnly(d)).inDays;
  if (days == 0) return 'Today';
  if (days == 1) return 'Yesterday';
  if (days > 1 && days < 7) return '$days days ago';
  return formatShortDate(iso);
}

/// How long something has waited: "25 min", "5 h", "3 days".
String waitingLabel(String? iso) {
  final d = parseLocal(iso);
  if (d == null) return '—';
  final mins = DateTime.now().difference(d).inMinutes.clamp(0, 1 << 31);
  if (mins < 60) return '$mins min';
  final hours = mins ~/ 60;
  if (hours < 24) return '$hours h';
  final days = hours ~/ 24;
  return '$days day${days == 1 ? '' : 's'}';
}

String plural(int n, String noun) => '$n $noun${n == 1 ? '' : 's'}';

/// yyyy-mm-dd for the API.
String isoDate(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
