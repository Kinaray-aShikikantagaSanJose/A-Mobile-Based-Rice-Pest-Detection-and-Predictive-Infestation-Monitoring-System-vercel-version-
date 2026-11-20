// Android / iOS (and desktop) implementation of local_files.dart: real files.
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Nothing to prepare on a phone.
Future<void> initLocalFiles() async {}

/// path_provider's documents folder.
Future<String> documentsDirPath() async => (await getApplicationDocumentsDirectory()).path;

/// path_provider's application support folder.
Future<String> supportDirPath() async => (await getApplicationSupportDirectory()).path;

Future<void> createLocalDir(String path) async {
  await Directory(path).create(recursive: true);
}

/// Copies [from] (a saved file or a picked/captured photo) to [to].
Future<void> copyLocalFile(String from, String to) async {
  await File(from).copy(to);
}

Future<void> writeLocalFile(String path, List<int> bytes) async {
  await File(path).writeAsBytes(bytes, flush: true);
}

bool localFileExistsSync(String path) => File(path).existsSync();

Future<bool> localFileExists(String path) => File(path).exists();

/// Deletes [path] if it exists.
Future<void> deleteLocalFile(String path) async {
  final f = File(path);
  if (await f.exists()) await f.delete();
}

/// Deletes [path] if it exists (synchronously).
void deleteLocalFileSync(String path) {
  final f = File(path);
  if (f.existsSync()) f.deleteSync();
}

/// The file at [path] as a multipart upload part.
Future<http.MultipartFile> localMultipartFile(String field, String path, {String? filename}) =>
    http.MultipartFile.fromPath(field, path, filename: filename);

ImageProvider localImageProvider(String path) => FileImage(File(path));

/// `Image.file` for a local path.
Widget localImage(
  String path, {
  Key? key,
  BoxFit? fit,
  int? cacheWidth,
  ImageErrorWidgetBuilder? errorBuilder,
}) =>
    Image.file(File(path), key: key, fit: fit, cacheWidth: cacheWidth, errorBuilder: errorBuilder);
