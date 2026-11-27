// All app translations, merged from ./parts (one file per area so they can
// be reviewed separately). Built at runtime, so a key repeated in two parts
// is fine (the later part wins).
import 'parts/auth.dart';
import 'parts/camera.dart';
import 'parts/common.dart';
import 'parts/field.dart';
import 'parts/home.dart';
import 'parts/maps.dart';
import 'parts/observe.dart';
import 'parts/profile.dart';
import 'parts/records.dart';
import 'parts/server.dart';
import 'parts/update.dart';

final Map<String, Map<String, String>> kStrings = {
  ...kServerStrings,
  ...kCommonStrings,
  ...kAuthStrings,
  ...kHomeStrings,
  ...kRecordsStrings,
  ...kObserveStrings,
  ...kProfileStrings,
  ...kFieldStrings,
  ...kMapsStrings,
  ...kCameraStrings,
  ...kUpdateStrings,
};
