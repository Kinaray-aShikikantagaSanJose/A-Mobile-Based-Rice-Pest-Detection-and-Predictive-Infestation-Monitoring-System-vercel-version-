/// In-browser camera for the photo screen (Flutter web only).
///
/// The `camera` plugin keeps working on Android / iOS. In a browser this
/// module talks to `getUserMedia` directly and shows a real `<video>` element
/// (see web_camera_web.dart), so:
///
/// - the preview is drawn by the browser at screen resolution (crisp, no
///   Flutter scaling of the video),
/// - the saved photo is exactly the part of the frame that is visible in the
///   preview (same crop, never digitally zoomed),
/// - continuous autofocus / exposure / white balance are switched on where the
///   browser allows it, with tap-to-focus on browsers that support
///   `pointsOfInterest` (Chrome on Android),
/// - the photo is a JPEG of at most [kMaxPhotoSide] px on the long side and
///   normally well under [kMaxPhotoBytes], so uploads stay below the 4.5 MB
///   request limit of the server.
///
/// On other platforms [WebCameraController] is a stub that reports
/// [WebCameraError.unsupported] (see web_camera_stub.dart).
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/widgets.dart';

export 'web_camera_stub.dart' if (dart.library.js_interop) 'web_camera_web.dart';

/// Why the camera could not start (or stopped).
enum WebCameraError {
  /// The person (or the browser settings) blocked the camera for this site.
  notAllowed,

  /// No camera, even after retrying without any constraints.
  notFound,

  /// The camera is used by another app / tab (`NotReadableError`).
  inUse,

  /// The page is not served over HTTPS (or localhost).
  insecureContext,

  /// The browser has no `getUserMedia`.
  unsupported,

  /// `stop()` / `dispose()` was called while starting. Nothing to show.
  stopped,

  /// Anything else (no video frames, the camera was unplugged, ...).
  failed,
}

class WebCameraException implements Exception {
  const WebCameraException(this.kind, [this.detail]);

  final WebCameraError kind;

  /// Browser error name/message, for logs only.
  final String? detail;

  @override
  String toString() => 'WebCameraException(${kind.name}${detail == null ? '' : ': $detail'})';
}

/// How the video fills the preview (CSS `object-fit`).
enum WebCameraFit { cover, contain }

/// Longest side of a saved photo (the server keeps 2048 px as well).
const int kMaxPhotoSide = 2048;

/// Above this the JPEG is encoded again at a lower quality (Vercel rejects
/// request bodies over 4.5 MB).
const int kMaxPhotoBytes = 4 * 1024 * 1024;

/// JPEG qualities tried in order until the photo fits [kMaxPhotoBytes].
const List<double> kJpegQualities = <double>[0.92, 0.85, 0.8];

/// `cover` hides at most this share of the video frame, else `contain`.
const double kMaxCoverCrop = 0.35;

/// The controller API shared by the browser implementation and the stub.
abstract interface class WebCameraApi implements Listenable {
  /// True once frames are playing; false before [start], after [stop].
  bool get isStarted;

  /// Set when the camera stopped on its own (unplugged, taken by another app).
  WebCameraError? get error;

  /// Intrinsic size of the video frames (upright, e.g. 1080x1920 on a phone
  /// held in portrait). Null until the first frame is known.
  Size? get videoSize;

  /// The fit used by the preview for its current size.
  WebCameraFit get fit;

  /// The preview is mirrored (front camera / laptop webcam). Photos never are.
  bool get mirrored;

  bool get torchSupported;
  bool get torchOn;

  /// Tapping can move the focus point (`pointsOfInterest`).
  bool get focusPointSupported;

  /// Continuous autofocus was switched on.
  bool get continuousFocus;

  /// Asks for the camera (rear camera preferred) and starts the preview.
  /// Throws [WebCameraException].
  Future<void> start();

  /// Stops all tracks (camera light off). [start] may be called again.
  Future<void> stop();

  /// The live preview. It fills the space it is given.
  Widget buildPreview({Key? key});

  /// Focuses on [normalized] ((0,0) top-left, (1,1) bottom-right of the
  /// preview widget). Returns false where the browser can't move the focus
  /// point (continuous autofocus keeps working). Never throws.
  Future<bool> focusAt(Offset normalized);

  /// Torch on/off. Returns false if not supported or refused. Never throws.
  Future<bool> setTorch(bool on);

  /// The visible part of the current frame as JPEG bytes (upright, not
  /// mirrored). Throws [WebCameraException].
  Future<Uint8List> capture();

  /// Stops the camera and frees the preview element.
  void dispose();
}

// ---------------------------------------------------------------------------
// Framing math (pure Dart, shared with the native path for tap-to-focus).
// ---------------------------------------------------------------------------

bool _usable(Size s) => s.width > 0 && s.height > 0 && s.width.isFinite && s.height.isFinite;

/// Share of the video frame that `object-fit: cover` cuts away in [view].
double coverCropFraction(Size view, Size video) {
  if (!_usable(view) || !_usable(video)) return 0;
  final double viewAspect = view.width / view.height;
  final double videoAspect = video.width / video.height;
  final double visible = viewAspect < videoAspect ? viewAspect / videoAspect : videoAspect / viewAspect;
  return 1 - visible;
}

/// `cover`, unless covering would hide more than [kMaxCoverCrop] of the frame
/// (e.g. a landscape laptop webcam in a tall phone-width window).
WebCameraFit chooseWebCameraFit(Size view, Size video) =>
    coverCropFraction(view, video) > kMaxCoverCrop ? WebCameraFit.contain : WebCameraFit.cover;

/// The rectangle of the video frame (in video pixels) that is visible in a
/// preview of size [view] (CSS `object-fit` with the default centred
/// `object-position`). Mirroring flips around the centre, so it doesn't
/// change this rectangle.
Rect visibleSourceRect(Size view, Size video, WebCameraFit fit) {
  final Rect full = Offset.zero & video;
  if (fit == WebCameraFit.contain || !_usable(view) || !_usable(video)) return full;
  final double scale = math.max(view.width / video.width, view.height / video.height);
  final double w = math.min(video.width, view.width / scale);
  final double h = math.min(video.height, view.height / scale);
  return Rect.fromLTWH((video.width - w) / 2, (video.height - h) / 2, w, h);
}

/// Output size for a crop of [source] px: unchanged, or scaled down so the
/// long side is at most [maxSide]. Never scaled up.
Size photoOutputSize(Size source, {int maxSide = kMaxPhotoSide}) {
  if (!_usable(source)) return Size.zero;
  final double longSide = math.max(source.width, source.height);
  final double scale = longSide > maxSide ? maxSide / longSide : 1.0;
  return Size(
    math.max(1, (source.width * scale).round()).toDouble(),
    math.max(1, (source.height * scale).round()).toDouble(),
  );
}

/// Maps [local] (a point in a preview of size [view]) to the video frame,
/// normalized to 0..1 ((0,0) = top-left of the frame). Returns null for a
/// point on the black bars of a `contain` preview.
Offset? previewPointToFrame(
  Offset local,
  Size view,
  Size video,
  WebCameraFit fit, {
  bool mirrored = false,
}) {
  if (!_usable(view) || !_usable(video)) return null;
  final double x = mirrored ? view.width - local.dx : local.dx;
  final double y = local.dy;
  final double scale = fit == WebCameraFit.cover
      ? math.max(view.width / video.width, view.height / video.height)
      : math.min(view.width / video.width, view.height / video.height);
  // Where the (scaled) frame's top-left corner sits in the view.
  final double left = (view.width - video.width * scale) / 2;
  final double top = (view.height - video.height * scale) / 2;
  final double fx = (x - left) / scale / video.width;
  final double fy = (y - top) / scale / video.height;
  if (fx < 0 || fx > 1 || fy < 0 || fy > 1) return null;
  return Offset(fx, fy);
}
