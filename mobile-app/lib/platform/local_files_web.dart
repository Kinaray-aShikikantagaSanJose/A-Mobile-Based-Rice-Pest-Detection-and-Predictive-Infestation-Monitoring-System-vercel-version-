// Browser implementation of local_files.dart.
//
// There is no file system on the web: a "path" is just a key under a virtual
// root ([_root]) and the bytes are kept in IndexedDB, which survives reloads
// (per browser and per site). An in-memory index of the stored keys answers
// the synchronous "does this photo still exist?" checks. If IndexedDB is not
// available (some private-browsing modes) the files are kept in memory for
// the current tab only.
//
// Photos picked or captured in the browser arrive as `blob:` URLs; reading
// such a path fetches the blob, so it can be copied, shown and uploaded like
// a stored file.
import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart' show XFile;
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart' show databaseFactory;
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart' show databaseFactoryFfiWeb;
import 'package:web/web.dart' as web;

const String _root = '/palay_patrol';
const String _dbName = 'palay_patrol_files';
const String _storeName = 'files';

web.IDBDatabase? _db;
bool _idbFailed = false;

/// Keys stored in IndexedDB (or [_memory]).
final Set<String> _index = <String>{};

/// Fallback storage when IndexedDB can't be opened.
final Map<String, Uint8List> _memory = <String, Uint8List>{};

/// Points sqflite at SQLite-on-WebAssembly (web/sqlite3.wasm, run in the
/// web/sqflite_sw.js worker) and loads the list of stored files.
Future<void> initLocalFiles() async {
  databaseFactory = databaseFactoryFfiWeb;
  try {
    final db = await _open();
    final store = db.transaction(_storeName.toJS, 'readonly').objectStore(_storeName);
    final keys = (await _request(store.getAllKeys())).dartify();
    if (keys is List) {
      for (final k in keys) {
        if (k is String) _index.add(k);
      }
    }
  } catch (e) {
    _idbFailed = true;
    debugPrint('[Files] IndexedDB unavailable, keeping files in memory: $e');
  }
}

Future<JSAny?> _request(web.IDBRequest request) {
  final done = Completer<JSAny?>();
  request.onsuccess = ((web.Event _) {
    if (!done.isCompleted) done.complete(request.result);
  }).toJS;
  request.onerror = ((web.Event _) {
    if (!done.isCompleted) {
      done.completeError(StateError('IndexedDB request failed: ${request.error?.message}'));
    }
  }).toJS;
  return done.future;
}

Future<web.IDBDatabase> _open() async {
  final existing = _db;
  if (existing != null) return existing;
  final request = web.window.indexedDB.open(_dbName, 1);
  request.onupgradeneeded = ((web.Event _) {
    final db = request.result as web.IDBDatabase;
    if (!db.objectStoreNames.contains(_storeName)) db.createObjectStore(_storeName);
  }).toJS;
  final db = (await _request(request)) as web.IDBDatabase;
  _db = db;
  return db;
}

web.IDBObjectStore _store(web.IDBDatabase db, String mode) =>
    db.transaction(_storeName.toJS, mode).objectStore(_storeName);

bool _isUrl(String path) =>
    path.startsWith('blob:') || path.startsWith('data:') || path.startsWith('http:') || path.startsWith('https:');

/// Bytes stored under [path], or null.
Future<Uint8List?> _readStored(String path) async {
  if (_idbFailed) return _memory[path];
  if (!_index.contains(path)) return null;
  final db = await _open();
  final value = await _request(_store(db, 'readonly').get(path.toJS));
  if (value == null) return null;
  final data = value.dartify();
  if (data is Uint8List) return data;
  if (data is ByteBuffer) return data.asUint8List();
  if (data is List) return Uint8List.fromList(data.cast<int>());
  return null;
}

/// Bytes of a stored file or of a picked/captured photo (`blob:` URL).
Future<Uint8List?> _readAny(String path) async {
  final stored = await _readStored(path);
  if (stored != null) return stored;
  if (_isUrl(path)) return XFile(path).readAsBytes();
  return null;
}

/// Virtual documents folder.
Future<String> documentsDirPath() async => p.url.join(_root, 'documents');

/// Virtual application support folder.
Future<String> supportDirPath() async => p.url.join(_root, 'support');

/// Folders don't exist on the web; keys just carry the folder name.
Future<void> createLocalDir(String path) async {}

/// Copies [from] (a stored file or a `blob:` URL from the camera/gallery).
Future<void> copyLocalFile(String from, String to) async {
  final bytes = await _readAny(from);
  if (bytes == null) throw StateError('No such file: $from');
  await writeLocalFile(to, bytes);
}

Future<void> writeLocalFile(String path, List<int> bytes) async {
  final data = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
  if (_idbFailed) {
    _memory[path] = data;
  } else {
    final db = await _open();
    await _request(_store(db, 'readwrite').put(data.toJS, path.toJS));
  }
  _index.add(path);
}

bool localFileExistsSync(String path) => _index.contains(path);

Future<bool> localFileExists(String path) async => _index.contains(path);

Future<void> deleteLocalFile(String path) async {
  if (!_index.remove(path)) return;
  if (_idbFailed) {
    _memory.remove(path);
    return;
  }
  final db = await _open();
  await _request(_store(db, 'readwrite').delete(path.toJS));
}

void deleteLocalFileSync(String path) {
  unawaited(deleteLocalFile(path).catchError((Object e) {
    debugPrint('[Files] could not delete $path: $e');
  }));
}

/// The bytes at [path] as a multipart upload part (`fromPath` needs dart:io).
Future<http.MultipartFile> localMultipartFile(String field, String path, {String? filename}) async {
  final bytes = await _readAny(path);
  if (bytes == null) throw StateError('No such file: $path');
  return http.MultipartFile.fromBytes(field, bytes, filename: filename ?? p.url.basename(path));
}

ImageProvider localImageProvider(String path) => _StoredFileImage(path);

/// The web counterpart of `Image.file`.
Widget localImage(
  String path, {
  Key? key,
  BoxFit? fit,
  int? cacheWidth,
  ImageErrorWidgetBuilder? errorBuilder,
}) =>
    Image(
      key: key,
      image: ResizeImage.resizeIfNeeded(cacheWidth, null, _StoredFileImage(path)),
      fit: fit,
      errorBuilder: errorBuilder,
    );

/// Like `FileImage`, but reads the bytes from the browser storage (or from a
/// `blob:` URL of a photo just picked or captured).
@immutable
class _StoredFileImage extends ImageProvider<_StoredFileImage> {
  const _StoredFileImage(this.path);

  final String path;

  @override
  Future<_StoredFileImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<_StoredFileImage>(this);

  @override
  ImageStreamCompleter loadImage(_StoredFileImage key, ImageDecoderCallback decode) =>
      MultiFrameImageStreamCompleter(codec: _load(key, decode), scale: 1.0, debugLabel: path);

  Future<ui.Codec> _load(_StoredFileImage key, ImageDecoderCallback decode) async {
    final bytes = await _readAny(path);
    if (bytes == null || bytes.isEmpty) {
      // Don't keep the failure cached: the file may be written later.
      PaintingBinding.instance.imageCache.evict(key);
      throw StateError('$path is not stored in this browser.');
    }
    return decode(await ui.ImmutableBuffer.fromUint8List(bytes));
  }

  @override
  bool operator ==(Object other) => other is _StoredFileImage && other.path == path;

  @override
  int get hashCode => path.hashCode;

  @override
  String toString() => '${objectRuntimeType(this, '_StoredFileImage')}("$path")';
}
