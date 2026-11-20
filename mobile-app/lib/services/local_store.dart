import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../platform/local_files.dart';

/// An observation captured on this phone that hasn't reached the server yet.
class OutboxObservation {
  final int? id;
  final String clientUuid;
  final String reportType; // pest | disease
  final String imagePath;
  final double? lat;
  final double? lng;
  final String cropStage;
  final String method; // direct | trap
  final String trapType;
  final String targetPest;
  final String targetSex;
  final String notes;
  final int? followUpOf; // server id of the treatment this follow-up checks on
  final int? resubmissionOf; // server id of the returned observation this retakes
  final String landType; // upland | rainfed_lowland | irrigated_lowland
  final double? elevationM; // looked up for the land type suggestion, if any
  final String createdAt; // ISO 8601 with offset
  final String lastError;

  const OutboxObservation({
    this.id,
    required this.clientUuid,
    required this.reportType,
    required this.imagePath,
    this.lat,
    this.lng,
    required this.cropStage,
    this.method = 'direct',
    this.trapType = '',
    this.targetPest = '',
    this.targetSex = '',
    this.notes = '',
    this.followUpOf,
    this.resubmissionOf,
    this.landType = '',
    this.elevationM,
    required this.createdAt,
    this.lastError = '',
  });

  bool get isDisease => reportType == 'disease';

  Map<String, Object?> toMap() => {
        'id': id,
        'client_uuid': clientUuid,
        'report_type': reportType,
        'image_path': imagePath,
        'lat': lat,
        'lng': lng,
        'crop_stage': cropStage,
        'method': method,
        'trap_type': trapType,
        'target_pest': targetPest,
        'target_sex': targetSex,
        'notes': notes,
        'follow_up_of': followUpOf,
        'resubmission_of': resubmissionOf,
        'land_type': landType,
        'elevation_m': elevationM,
        'created_at': createdAt,
        'last_error': lastError,
      };

  factory OutboxObservation.fromMap(Map<String, Object?> m) => OutboxObservation(
        id: m['id'] as int?,
        clientUuid: m['client_uuid'] as String,
        reportType: m['report_type'] as String,
        imagePath: m['image_path'] as String,
        lat: (m['lat'] as num?)?.toDouble(),
        lng: (m['lng'] as num?)?.toDouble(),
        cropStage: m['crop_stage'] as String,
        method: m['method'] as String? ?? 'direct',
        trapType: m['trap_type'] as String? ?? '',
        targetPest: m['target_pest'] as String? ?? '',
        targetSex: m['target_sex'] as String? ?? '',
        notes: m['notes'] as String? ?? '',
        followUpOf: m['follow_up_of'] as int?,
        resubmissionOf: m['resubmission_of'] as int?,
        landType: m['land_type'] as String? ?? '',
        elevationM: (m['elevation_m'] as num?)?.toDouble(),
        createdAt: m['created_at'] as String,
        lastError: m['last_error'] as String? ?? '',
      );
}

/// A treatment the farmer logged that hasn't reached the server yet.
class OutboxTreatment {
  final int? id;
  final String clientUuid;
  final int scanId; // server id of the validated observation
  final int? libraryId;
  final String label; // what the farmer picked or typed, for display
  final String customText;
  final String appliedAt; // yyyy-mm-dd

  const OutboxTreatment({
    this.id,
    required this.clientUuid,
    required this.scanId,
    this.libraryId,
    required this.label,
    this.customText = '',
    required this.appliedAt,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'client_uuid': clientUuid,
        'scan_id': scanId,
        'library_id': libraryId,
        'label': label,
        'custom_text': customText,
        'applied_at': appliedAt,
      };

  factory OutboxTreatment.fromMap(Map<String, Object?> m) => OutboxTreatment(
        id: m['id'] as int?,
        clientUuid: m['client_uuid'] as String,
        scanId: m['scan_id'] as int,
        libraryId: m['library_id'] as int?,
        label: m['label'] as String? ?? '',
        customText: m['custom_text'] as String? ?? '',
        appliedAt: m['applied_at'] as String,
      );
}

/// Phone-side storage: the outbox (work waiting for signal), a cache of the
/// user's server records so My Records works offline, and where each
/// observation's photo lives on this phone.
class LocalStore {
  LocalStore._();
  static final LocalStore instance = LocalStore._();

  static const int _version = 12;
  Database? _db;

  Future<Database> _open() async {
    if (_db != null) return _db!;
    final dir = await getDatabasesPath();
    _db = await openDatabase(
      p.join(dir, 'rice_pest.db'),
      version: _version,
      onCreate: (db, _) => _create(db),
      // v9 replaced on-device analysis with server-side analysis and the old
      // scans/fields tables with an outbox + record cache. Old local data
      // can't be migrated meaningfully, so start fresh.
      onUpgrade: (db, oldVersion, _) async {
        if (oldVersion < 9) {
          for (final t in ['scans', 'treatments', 'fields']) {
            await db.execute('DROP TABLE IF EXISTS $t');
          }
          await _create(db);
          return;
        }
        // v10: retakes of returned observations.
        if (oldVersion < 10) {
          await db.execute('ALTER TABLE outbox ADD COLUMN resubmission_of INTEGER');
        }
        // v11: last server copy of lists shown offline (notifications, queue).
        if (oldVersion < 11) await _createCache(db);
        // v12: land type of the field (and the elevation used to suggest it).
        if (oldVersion < 12) {
          await db.execute("ALTER TABLE outbox ADD COLUMN land_type TEXT NOT NULL DEFAULT ''");
          await db.execute('ALTER TABLE outbox ADD COLUMN elevation_m REAL');
        }
      },
    );
    return _db!;
  }

  static Future<void> _create(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS outbox (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        client_uuid TEXT NOT NULL UNIQUE,
        report_type TEXT NOT NULL,
        image_path TEXT NOT NULL,
        lat REAL,
        lng REAL,
        crop_stage TEXT NOT NULL,
        method TEXT NOT NULL DEFAULT 'direct',
        trap_type TEXT NOT NULL DEFAULT '',
        target_pest TEXT NOT NULL DEFAULT '',
        target_sex TEXT NOT NULL DEFAULT '',
        notes TEXT NOT NULL DEFAULT '',
        follow_up_of INTEGER,
        resubmission_of INTEGER,
        land_type TEXT NOT NULL DEFAULT '',
        elevation_m REAL,
        created_at TEXT NOT NULL,
        last_error TEXT NOT NULL DEFAULT ''
      )''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS treatment_outbox (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        client_uuid TEXT NOT NULL UNIQUE,
        scan_id INTEGER NOT NULL,
        library_id INTEGER,
        label TEXT NOT NULL DEFAULT '',
        custom_text TEXT NOT NULL DEFAULT '',
        applied_at TEXT NOT NULL
      )''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS records (
        server_id INTEGER PRIMARY KEY,
        client_uuid TEXT,
        json TEXT NOT NULL
      )''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS photos (
        client_uuid TEXT PRIMARY KEY,
        image_path TEXT NOT NULL
      )''');
    await _createCache(db);
  }

  static Future<void> _createCache(Database db) => db.execute('''
      CREATE TABLE IF NOT EXISTS cache (
        key TEXT PRIMARY KEY,
        json TEXT NOT NULL,
        saved_at TEXT NOT NULL
      )''');

  // ---------------------------------------------------------------- cache

  /// Keeps the server's latest answer for [key] so the screen works offline.
  Future<void> putCache(String key, Object? data) async {
    final db = await _open();
    await db.insert(
      'cache',
      {'key': key, 'json': jsonEncode(data), 'saved_at': DateTime.now().toIso8601String()},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// The last saved answer for [key], or null if there never was one.
  Future<Object?> getCache(String key) async {
    final db = await _open();
    final rows = await db.query('cache', where: 'key = ?', whereArgs: [key]);
    return rows.isEmpty ? null : jsonDecode(rows.first['json'] as String);
  }

  // ---------------------------------------------------------------- outbox

  Future<void> addObservation(OutboxObservation o) async {
    final db = await _open();
    await db.transaction((txn) async {
      await txn.insert('outbox', o.toMap()..remove('id'));
      await txn.insert('photos', {'client_uuid': o.clientUuid, 'image_path': o.imagePath},
          conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  Future<List<OutboxObservation>> pendingObservations() async {
    final db = await _open();
    final rows = await db.query('outbox', orderBy: 'id ASC');
    return rows.map(OutboxObservation.fromMap).toList();
  }

  Future<void> setObservationError(String clientUuid, String error) async {
    final db = await _open();
    await db.update('outbox', {'last_error': error}, where: 'client_uuid = ?', whereArgs: [clientUuid]);
  }

  /// Drops an observation the farmer chose to discard (it could not be sent).
  Future<void> removeObservation(String clientUuid) async {
    final db = await _open();
    await db.transaction((txn) async {
      await txn.delete('outbox', where: 'client_uuid = ?', whereArgs: [clientUuid]);
      await txn.delete('photos', where: 'client_uuid = ?', whereArgs: [clientUuid]);
    });
  }

  Future<void> addTreatment(OutboxTreatment t) async {
    final db = await _open();
    await db.insert('treatment_outbox', t.toMap()..remove('id'));
  }

  Future<void> removeTreatment(String clientUuid) async {
    final db = await _open();
    await db.delete('treatment_outbox', where: 'client_uuid = ?', whereArgs: [clientUuid]);
  }

  Future<List<OutboxTreatment>> pendingTreatments() async {
    final db = await _open();
    final rows = await db.query('treatment_outbox', orderBy: 'id ASC');
    return rows.map(OutboxTreatment.fromMap).toList();
  }

  Future<bool> hasPendingWork() async {
    final db = await _open();
    final a = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM outbox')) ?? 0;
    final b = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM treatment_outbox')) ?? 0;
    return a + b > 0;
  }

  // ---------------------------------------------------------------- records

  /// Stores the server's copy and, if it came from the outbox, removes it
  /// there (the photo mapping stays so the record shows the local photo).
  Future<void> saveRecord(Map<String, dynamic> record) async {
    final db = await _open();
    await db.transaction((txn) async {
      await txn.insert(
        'records',
        {'server_id': record['id'], 'client_uuid': record['client_uuid'], 'json': jsonEncode(record)},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      final uuid = record['client_uuid'];
      if (uuid is String) await txn.delete('outbox', where: 'client_uuid = ?', whereArgs: [uuid]);
      for (final t in (record['treatments'] as List? ?? const [])) {
        final tu = (t as Map)['client_uuid'];
        if (tu is String) await txn.delete('treatment_outbox', where: 'client_uuid = ?', whereArgs: [tu]);
      }
    });
  }

  /// Replaces the cache with the server's full list of the user's records.
  Future<void> replaceRecords(List<Map<String, dynamic>> records) async {
    final db = await _open();
    await db.transaction((txn) async {
      await txn.delete('records');
      for (final r in records) {
        await txn.insert('records',
            {'server_id': r['id'], 'client_uuid': r['client_uuid'], 'json': jsonEncode(r)});
      }
    });
  }

  Future<List<Map<String, dynamic>>> cachedRecords() async {
    final db = await _open();
    final rows = await db.query('records', orderBy: 'server_id DESC');
    return rows.map((r) => jsonDecode(r['json'] as String) as Map<String, dynamic>).toList();
  }

  Future<Map<String, dynamic>?> cachedRecord(int serverId) async {
    final db = await _open();
    final rows = await db.query('records', where: 'server_id = ?', whereArgs: [serverId]);
    return rows.isEmpty ? null : jsonDecode(rows.first['json'] as String) as Map<String, dynamic>;
  }

  /// The photo taken on this phone for an observation, if it still exists.
  Future<String?> localPhoto(String? clientUuid) async {
    if (clientUuid == null) return null;
    final db = await _open();
    final rows = await db.query('photos', where: 'client_uuid = ?', whereArgs: [clientUuid]);
    if (rows.isEmpty) return null;
    final path = rows.first['image_path'] as String;
    return localFileExistsSync(path) ? path : null;
  }

  /// Persists a server photo on disk and indexes it in SQLite for offline use.
  Future<String> cacheServerPhoto(String clientUuid, int serverId, List<int> bytes) async {
    final dir = p.join(await supportDirPath(), 'server_photos');
    await createLocalDir(dir);
    final path = p.join(dir, 'scan_$serverId.jpg');
    await writeLocalFile(path, bytes);
    final db = await _open();
    await db.insert(
      'photos',
      {'client_uuid': clientUuid, 'image_path': path},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return path;
  }

  /// Wipes everything local (another account signed in on this phone).
  Future<void> clearAll() async {
    final db = await _open();
    final photos = await db.query('photos', columns: ['image_path']);
    await db.transaction((txn) async {
      for (final t in ['outbox', 'treatment_outbox', 'records', 'photos', 'cache']) {
        await txn.delete(t);
      }
    });
    for (final r in photos) {
      try {
        await deleteLocalFile(r['image_path'] as String);
      } catch (e) {
        debugPrint('Could not delete photo: $e');
      }
    }
  }
}
