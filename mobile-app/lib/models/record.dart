import '../services/local_store.dart';
import '../utils/formatters.dart';

double? _d(Object? v) => v is num ? v.toDouble() : null;
int? _i(Object? v) => v is num ? v.toInt() : null;
String _s(Object? v) => v is String ? v : '';

/// One detection box, as a fraction (0-1) of the stored photo.
class DetectionBox {
  final double x1, y1, x2, y2, conf;
  final String pest;
  const DetectionBox(this.x1, this.y1, this.x2, this.y2, this.conf, this.pest);

  factory DetectionBox.fromJson(Map<String, dynamic> j) => DetectionBox(
      _d(j['x1']) ?? 0, _d(j['y1']) ?? 0, _d(j['x2']) ?? 0, _d(j['y2']) ?? 0, _d(j['conf']) ?? 0, _s(j['pest']));
}

/// The server's automatic analysis (pest reports only).
class AiResult {
  final String status; // done | failed | skipped
  final String? pest;
  final double? confidence;
  final int? count; // null = not countable
  final bool countable;
  final String message;
  final List<DetectionBox> detections; // staff only

  const AiResult({
    required this.status,
    this.pest,
    this.confidence,
    this.count,
    this.countable = false,
    this.message = '',
    this.detections = const [],
  });

  factory AiResult.fromJson(Map<String, dynamic> j) => AiResult(
        status: _s(j['status']),
        pest: j['pest'] as String?,
        confidence: _d(j['confidence']),
        count: _i(j['count']),
        countable: j['countable'] == true,
        message: _s(j['message']),
        detections: [
          for (final b in (j['detections'] as List? ?? const []))
            DetectionBox.fromJson(b as Map<String, dynamic>),
        ],
      );

  bool get recognized => status == 'done' && pest != null;
  String get pestLabel => pestName(pest, fallback: 'No supported pest recognized');
  String get confidenceLabel => confidence == null ? '' : '${(confidence! * 100).round()}% sure';
}

/// What the technician (or agriculturist) confirmed.
class Confirmed {
  final String? pest;
  final int? count; // null = not countable
  final String? level;
  final List<String> indicators;

  const Confirmed({this.pest, this.count, this.level, this.indicators = const []});

  factory Confirmed.fromJson(Map<String, dynamic> j) => Confirmed(
        pest: j['pest'] as String?,
        count: _i(j['count']),
        level: j['level'] as String?,
        indicators: [for (final i in (j['indicators'] as List? ?? const [])) '$i'],
      );

  String get pestLabel => pestName(pest);
}

class TreatmentInfo {
  final int? id;
  final String clientUuid;
  final String treatment;
  final String optionType;
  final String appliedAt;
  final String? followUpDue;
  final int? followUpScanId;

  /// Set when a technician or agriculturist chose the follow-up date.
  final String? followUpSetBy;

  /// Logged on the phone, not yet on the server.
  final bool pending;

  const TreatmentInfo({
    this.id,
    required this.clientUuid,
    required this.treatment,
    required this.optionType,
    required this.appliedAt,
    this.followUpDue,
    this.followUpScanId,
    this.followUpSetBy,
    this.pending = false,
  });

  factory TreatmentInfo.fromJson(Map<String, dynamic> j) => TreatmentInfo(
        id: _i(j['id']),
        clientUuid: _s(j['client_uuid']),
        treatment: _s(j['treatment']),
        optionType: _s(j['option_type']),
        appliedAt: _s(j['applied_at']),
        followUpDue: j['follow_up_due'] as String?,
        followUpScanId: _i(j['follow_up_scan_id']),
        followUpSetBy: j['follow_up_set_by'] as String?,
      );

  /// "How is the field now?" is due (and not answered yet).
  bool get followUpIsDue {
    if (pending || id == null || followUpScanId != null || followUpDue == null) return false;
    final due = DateTime.tryParse(followUpDue!);
    return due != null && !due.isAfter(DateTime.now());
  }
}

class TreatmentOption {
  final int id;
  final String type;
  final String title;
  final String description;
  final String sourceReference;
  const TreatmentOption(this.id, this.type, this.title, this.description, this.sourceReference);
}

/// Approved options for a validated record, grouped by type
/// (cultural, biological, ecological, chemical).
class Recommendations {
  final Map<String, List<TreatmentOption>> groups;
  final String chemicalNote;
  const Recommendations(this.groups, this.chemicalNote, [this.alreadyTried = const []]);

  factory Recommendations.fromJson(Map<String, dynamic> j) {
    final groups = <String, List<TreatmentOption>>{};
    (j['groups'] as Map? ?? const {}).forEach((type, list) {
      groups['$type'] = [
        for (final o in (list as List))
          TreatmentOption(_i((o as Map)['id']) ?? 0, '$type', _s(o['title']), _s(o['description']),
              _s(o['source_reference'])),
      ];
    });
    return Recommendations(groups, _s(j['chemical_note']), [
      for (final t in (j['already_tried'] as List? ?? const [])) _s((t as Map)['title']),
    ]);
  }

  /// Options the farmer already applied and reported back on: no longer
  /// recommended unless their technician or agriculturist allows them again.
  final List<String> alreadyTried;

  List<TreatmentOption> get all => [for (final list in groups.values) ...list];
  bool get isEmpty => all.isEmpty;
}

class HistoryEntry {
  final String action, reviewer, reviewerRole, note, createdAt;
  final String? pest, level;
  final int? count;
  const HistoryEntry(this.action, this.reviewer, this.reviewerRole, this.note, this.createdAt, this.pest,
      this.level, this.count);

  factory HistoryEntry.fromJson(Map<String, dynamic> j) => HistoryEntry(_s(j['action']), _s(j['reviewer']),
      _s(j['reviewer_role']), _s(j['note']), _s(j['created_at']), j['pest'] as String?, j['level'] as String?,
      _i(j['count']));
}

/// An observation: either still on the phone ([pending]) or the server's copy.
class Record {
  final Map<String, dynamic>? server;
  final OutboxObservation? pending;
  final String? localPhoto;

  const Record({this.server, this.pending, this.localPhoto});

  bool get uploaded => server != null;
  int? get id => _i(server?['id']);
  String get clientUuid => server != null ? _s(server!['client_uuid']) : pending!.clientUuid;
  String get reportType => server != null ? _s(server!['report_type']) : pending!.reportType;
  bool get isDisease => reportType == 'disease';
  String get createdAt => server != null ? _s(server!['created_at']) : pending!.createdAt;
  String get cropStage => server != null ? _s(server!['crop_stage']) : pending!.cropStage;
  String get monitoringMethod {
    if (server != null) return _s(server!['monitoring_method']);
    if (isDisease) return '';
    return pending!.method == 'trap' ? 'Trap-based' : 'Direct field observation';
  }

  String get trapType => server != null ? _s(server!['trap_type']) : pending!.trapType;
  String get targetPest => server != null ? _s(server!['target_pest']) : pending!.targetPest;
  String get targetSex => server != null ? _s(server!['target_sex']) : pending!.targetSex;
  String get notes => server != null ? _s(server!['notes']) : pending!.notes;

  /// upland | rainfed_lowland | irrigated_lowland ('' = recorded before the field existed).
  String get landType => server != null ? _s(server!['land_type']) : pending!.landType;
  double? get lat => server != null ? _d(server!['lat']) : pending!.lat;
  double? get lng => server != null ? _d(server!['lng']) : pending!.lng;
  int? get followUpOf => server != null ? _i(server!['follow_up_of']) : pending!.followUpOf;

  /// This observation retakes a returned one (its server id).
  int? get resubmissionOf => server != null ? _i(server!['resubmission_of']) : pending!.resubmissionOf;

  /// The retake sent after this one was returned, if any.
  int? get resubmittedAs => _i(server?['resubmitted_as']);

  /// Confirmed infestation level (pest and disease reports), once validated.
  String? get level => server?['level'] as String?;

  /// Why it is in an agriculturist's queue: 'escalated' or 'no_technician'.
  String get queueReason => _s(server?['queue_reason']);
  String get status => server != null ? _s(server!['status']) : '';
  String get municipality => _s(server?['municipality']);
  String get barangay => _s(server?['barangay']);
  String get diagnosis => _s(server?['diagnosis']);
  String get guidance => _s(server?['guidance']);
  String get returnReason => _s(server?['return_reason']);
  String get escalationReason => _s(server?['escalation_reason']);
  String get uploadError => pending?.lastError ?? '';
  bool get isMine => server?['is_mine'] != false;

  AiResult? get ai => server?['ai'] is Map ? AiResult.fromJson(server!['ai'] as Map<String, dynamic>) : null;
  Confirmed? get confirmed =>
      server?['confirmed'] is Map ? Confirmed.fromJson(server!['confirmed'] as Map<String, dynamic>) : null;
  Recommendations? get recommendations => server?['recommendations'] is Map
      ? Recommendations.fromJson(server!['recommendations'] as Map<String, dynamic>)
      : null;
  List<TreatmentInfo> get treatments => [
        for (final t in (server?['treatments'] as List? ?? const []))
          TreatmentInfo.fromJson(t as Map<String, dynamic>),
      ];
  List<HistoryEntry> get history => [
        for (final h in (server?['history'] as List? ?? const [])) HistoryEntry.fromJson(h as Map<String, dynamic>),
      ];

  // Staff views
  String get submitterName => _s((server?['submitter'] as Map?)?['name']);
  String get submitterPhone => _s((server?['submitter'] as Map?)?['phone']);
  String get submitterRole => _s((server?['submitter'] as Map?)?['role']);
  String? get suggestedLevel => server?['suggested_level'] as String?;

  RecordState get state => recordState(uploaded: uploaded, status: status, isDisease: isDisease);

  /// Short title for lists: confirmed pest, else the model result, else the type.
  String get title {
    if (isDisease) return 'Disease report';
    final c = confirmed;
    if (c != null) return c.pestLabel;
    final a = ai;
    if (a != null && a.recognized) return a.pestLabel;
    return 'Pest report';
  }
}
