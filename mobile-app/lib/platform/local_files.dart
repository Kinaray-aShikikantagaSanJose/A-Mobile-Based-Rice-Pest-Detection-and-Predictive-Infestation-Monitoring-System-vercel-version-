/// The few local-file operations the app needs (photos taken or picked,
/// cached server photos, guide pictures), on every platform.
///
/// - Android / iOS: plain `dart:io` files under path_provider's folders,
///   exactly as before (see local_files_io.dart).
/// - Web: there is no file system, so "paths" are keys under a virtual root
///   and the bytes live in the browser's IndexedDB (see local_files_web.dart).
///   Photos picked or captured in the browser arrive as `blob:` URLs; they
///   can be copied, shown and uploaded like any other path.
library;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image_picker/image_picker.dart' show XFile;
import 'package:path/path.dart' as p;

export 'local_files_io.dart' if (dart.library.js_interop) 'local_files_web.dart';

/// Extension (with the dot) to give a copy of a picked/captured photo.
/// On the web the path is a `blob:` URL without one, so use the file name.
String pickedFileExtension(XFile file) {
  if (!kIsWeb) return p.extension(file.path);
  final ext = p.extension(file.name);
  return ext.isEmpty ? '.jpg' : ext;
}

/// File name to send with an upload of [file]: null keeps the default (the
/// path's base name) on phones; on the web the blob URL has no useful name.
String? uploadFileName(XFile file) => kIsWeb ? file.name : null;
