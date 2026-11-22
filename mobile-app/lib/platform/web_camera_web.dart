// Browser camera: getUserMedia + a real <video> element shown through an
// HtmlElementView. See web_camera.dart for the API and the reasons.
//
// - The <video> is drawn by the browser itself (playsinline/muted/autoplay
//   for iOS Safari) and sized with CSS `object-fit`, so the preview is sharp.
// - A photo is drawn from the <video> into a canvas at the full frame
//   resolution, cropped to exactly what the preview shows, then encoded as
//   JPEG (canvas frames are upright, so no EXIF rotation is needed).
// - Focus / exposure / white balance / zoom / torch use the Image Capture
//   constraints where the browser has them (mostly Chrome on Android). Each
//   one is optional: Safari and Firefox simply skip them.
import 'dart:async';
import 'dart:convert' show base64Decode;
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:ui_web' as ui_web;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart' show PlatformViewHitTestBehavior;
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

import 'web_camera.dart';

/// True: this browser build has the camera module (the browser itself may
/// still lack getUserMedia; [WebCameraController.start] reports that).
bool get webCameraAvailable => true;

// Unique per app start, so a hot restart (debug) registers a fresh factory.
final String _viewType = 'palay-patrol-camera-${DateTime.now().microsecondsSinceEpoch}';
bool _factoryRegistered = false;

/// Live controllers by id; the platform view factory looks them up from the
/// HtmlElementView's creationParams, so one factory serves every controller.
final Map<int, WebCameraController> _controllers = <int, WebCameraController>{};
int _nextControllerId = 0;

Object _createView(int viewId, {Object? params}) {
  final WebCameraController? controller = params is int ? _controllers[params] : null;
  if (controller != null && !controller._disposed) {
    controller._viewCreated();
    return controller._host;
  }
  return web.HTMLDivElement()..style.cssText = 'width:100%;height:100%;background:#000;';
}

// ---------------------------------------------------------------------------
// Small JS helpers
// ---------------------------------------------------------------------------

/// A rejected promise / thrown JS error, with its `name` (e.g. NotAllowedError).
class _JsError implements Exception {
  _JsError(this.name, this.message);

  factory _JsError.from(JSAny? reason) {
    String name = '';
    String message = '';
    try {
      if (reason != null && reason.isA<JSObject>()) {
        final JSObject error = reason as JSObject;
        name = _string(error.getProperty<JSAny?>('name'.toJS)) ?? '';
        message = _string(error.getProperty<JSAny?>('message'.toJS)) ?? '';
      } else {
        message = _string(reason) ?? '';
      }
    } catch (_) {}
    return _JsError(name, message);
  }

  final String name;
  final String message;

  @override
  String toString() => message.isEmpty ? name : '$name: $message';
}

String? _string(JSAny? value) => value != null && value.isA<JSString>() ? (value as JSString).toDart : null;

extension on JSPromise<JSAny?> {
  @JS('then')
  external JSAny? _then(JSFunction onFulfilled, JSFunction onRejected);
}

/// Awaits [promise]; a rejection becomes a [_JsError] carrying the error name.
Future<JSAny?> _settle(JSPromise<JSAny?> promise) {
  final Completer<JSAny?> done = Completer<JSAny?>();
  promise._then(
    ((JSAny? value) {
      if (!done.isCompleted) done.complete(value);
    }).toJS,
    ((JSAny? reason) {
      if (!done.isCompleted) done.completeError(_JsError.from(reason));
    }).toJS,
  );
  return done.future;
}

JSObject _js(Map<String, Object?> map) => map.jsify()! as JSObject;

/// A JS dictionary (capabilities, settings) as a Dart map; empty on failure.
Map<String, Object?> _toMap(JSAny? object) {
  try {
    final Object? value = object.dartify();
    if (value is Map) return <String, Object?>{for (final e in value.entries) '${e.key}': e.value};
  } catch (_) {}
  return const <String, Object?>{};
}

List<String> _strings(Object? value) =>
    value is List ? <String>[for (final v in value) if (v is String) v] : const <String>[];

bool _secureContext() {
  try {
    final JSAny? value = web.window.getProperty<JSAny?>('isSecureContext'.toJS);
    if (value != null && value.isA<JSBoolean>()) return (value as JSBoolean).toDart;
  } catch (_) {}
  final web.Location location = web.window.location;
  return location.protocol == 'https:' || location.hostname == 'localhost' || location.hostname == '127.0.0.1';
}

/// navigator.mediaDevices, or null (old browser, or not a secure page).
web.MediaDevices? _mediaDevices() {
  try {
    final JSAny? value = web.window.navigator.getProperty<JSAny?>('mediaDevices'.toJS);
    if (value == null || !value.isA<JSObject>()) return null;
    final web.MediaDevices devices = value as web.MediaDevices;
    return devices.has('getUserMedia') ? devices : null;
  } catch (_) {
    return null;
  }
}

const Set<String> _notFoundErrors = <String>{
  'NotFoundError',
  'DevicesNotFoundError',
  'OverconstrainedError',
  'ConstraintNotSatisfiedError',
};

WebCameraException _mapError(_JsError e) {
  final WebCameraError kind = switch (e.name) {
    'NotAllowedError' || 'PermissionDeniedError' || 'SecurityError' => WebCameraError.notAllowed,
    'NotReadableError' || 'TrackStartError' || 'AbortError' => WebCameraError.inUse,
    _ when _notFoundErrors.contains(e.name) => WebCameraError.notFound,
    _ => WebCameraError.failed,
  };
  return WebCameraException(kind, e.toString());
}

void _stopTracks(web.MediaStream stream) {
  try {
    for (final web.MediaStreamTrack track in stream.getTracks().toDart) {
      try {
        track.stop();
      } catch (_) {}
    }
  } catch (_) {}
}

// ---------------------------------------------------------------------------
// Controller
// ---------------------------------------------------------------------------

class WebCameraController extends ChangeNotifier implements WebCameraApi {
  WebCameraController() : _id = _nextControllerId++ {
    if (!_factoryRegistered) {
      _factoryRegistered = true;
      ui_web.platformViewRegistry.registerViewFactory(_viewType, _createView);
    }
    _controllers[_id] = this;

    _video = web.HTMLVideoElement()
      ..muted = true
      ..autoplay = true
      ..playsInline = true
      ..controls = false;
    // Attributes too: iOS Safari only plays inline (not fullscreen) and
    // without a tap when these are present.
    for (final String attribute in const <String>[
      'playsinline',
      'webkit-playsinline',
      'muted',
      'autoplay',
      'disablepictureinpicture',
      'disableremoteplayback',
    ]) {
      _video.setAttribute(attribute, '');
    }
    _video.style.cssText = 'display:block;width:100%;height:100%;object-fit:cover;'
        'object-position:50% 50%;background:#000;pointer-events:none;';

    // pointer-events:none lets Flutter see taps on the preview (tap-to-focus).
    _host = web.HTMLDivElement()
      ..style.cssText = 'width:100%;height:100%;overflow:hidden;background:#000;pointer-events:none;';
    _host.append(_video);

    _subscriptions = <StreamSubscription<web.Event>>[
      web.EventStreamProviders.loadedMetadataEvent.forTarget(_video).listen((_) => _readVideoSize()),
      // Fires when the frame size changes, e.g. the phone is rotated.
      web.EventStreamProviders.resizeEvent.forTarget(_video).listen((_) => _readVideoSize()),
      web.EventStreamProviders.playingEvent.forTarget(_video).listen((_) => _resumeTries = 0),
      // Moving the element between platform views pauses it; play again.
      web.EventStreamProviders.pauseEvent.forTarget(_video).listen((_) => _schedulePlay()),
    ];
  }

  final int _id;
  late final web.HTMLVideoElement _video;
  late final web.HTMLDivElement _host;
  late final List<StreamSubscription<web.Event>> _subscriptions;

  web.MediaStream? _stream;
  web.MediaStreamTrack? _track;

  /// Bumped by start/stop so a late result of an old start is dropped.
  int _session = 0;
  bool _started = false;
  bool _disposed = false;
  WebCameraError? _error;

  Size? _videoSize;
  Size? _viewSize;
  WebCameraFit _fit = WebCameraFit.cover;
  bool _mirrored = false;

  bool _torchSupported = false;
  bool _torchOn = false;
  bool _pointsOfInterest = false;
  bool _singleShot = false;
  bool _continuousFocus = false;

  Timer? _refocusTimer;
  Timer? _playTimer;
  Timer? _capabilityTimer;
  int _resumeTries = 0;
  bool _notifyScheduled = false;

  @override
  bool get isStarted => _started;

  @override
  WebCameraError? get error => _error;

  @override
  Size? get videoSize => _videoSize;

  @override
  WebCameraFit get fit => _fit;

  @override
  bool get mirrored => _mirrored;

  @override
  bool get torchSupported => _torchSupported;

  @override
  bool get torchOn => _torchOn;

  @override
  bool get focusPointSupported => _pointsOfInterest;

  @override
  bool get continuousFocus => _continuousFocus;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  // ---- start / stop -------------------------------------------------------

  @override
  Future<void> start() async {
    if (_disposed) throw const WebCameraException(WebCameraError.stopped);
    if (_stream != null) return;
    final int session = ++_session;
    _error = null;

    if (!_secureContext()) throw const WebCameraException(WebCameraError.insecureContext);
    final web.MediaDevices? devices = _mediaDevices();
    if (devices == null) throw const WebCameraException(WebCameraError.unsupported);

    web.MediaStream stream;
    try {
      // Mobile browsers turn 1920x1080 into 1080x1920 in portrait; the real
      // size is read from the <video> once frames arrive.
      stream = await _getUserMedia(devices, <String, Object?>{
        'audio': false,
        'video': <String, Object?>{
          'facingMode': <String, Object?>{'ideal': 'environment'},
          'width': <String, Object?>{'ideal': 1920},
          'height': <String, Object?>{'ideal': 1080},
        },
      });
    } on _JsError catch (e) {
      if (!_notFoundErrors.contains(e.name)) throw _mapError(e);
      debugPrint('[Camera] $e - trying again without constraints');
      try {
        stream = await _getUserMedia(devices, <String, Object?>{'audio': false, 'video': true});
      } on _JsError catch (e2) {
        throw _notFoundErrors.contains(e2.name)
            ? WebCameraException(WebCameraError.notFound, e2.toString())
            : _mapError(e2);
      }
    }

    if (_disposed || session != _session) {
      _stopTracks(stream);
      throw const WebCameraException(WebCameraError.stopped);
    }
    _stream = stream;
    final List<web.MediaStreamTrack> tracks = stream.getVideoTracks().toDart;
    if (tracks.isEmpty) {
      await stop();
      throw const WebCameraException(WebCameraError.notFound, 'no video track');
    }
    final web.MediaStreamTrack track = tracks.first;
    _track = track;
    // The camera went away (unplugged, or taken by another app).
    track.onended = ((web.Event _) => _onTrackEnded(session)).toJS;

    _video.srcObject = stream;
    unawaited(_play());
    try {
      await _waitForFrames(session);
    } on TimeoutException {
      if (session == _session) await stop();
      throw const WebCameraException(WebCameraError.failed, 'no video frames');
    }
    if (_disposed || session != _session) throw const WebCameraException(WebCameraError.stopped);
    _readVideoSize();

    await _setupTrack(devices, track, session);
    if (_disposed || session != _session) throw const WebCameraException(WebCameraError.stopped);
    _started = true;
    _notify();
  }

  Future<web.MediaStream> _getUserMedia(web.MediaDevices devices, Map<String, Object?> constraints) async {
    final JSPromise<JSAny?> promise;
    try {
      promise = devices.getUserMedia(_js(constraints) as web.MediaStreamConstraints);
    } catch (e) {
      throw _JsError('TypeError', '$e');
    }
    final JSAny? result = await _settle(promise);
    if (result == null || !result.isA<JSObject>()) throw _JsError('NotFoundError', 'no stream');
    return result as web.MediaStream;
  }

  /// Waits (up to 10 s) until the <video> knows its frame size.
  Future<void> _waitForFrames(int session) async {
    final DateTime deadline = DateTime.now().add(const Duration(seconds: 10));
    while (!(_video.readyState >= 1 && _video.videoWidth > 0 && _video.videoHeight > 0)) {
      if (_disposed || session != _session) return;
      if (DateTime.now().isAfter(deadline)) throw TimeoutException('no video frames');
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  void _onTrackEnded(int session) {
    if (_disposed || session != _session) return;
    debugPrint('[Camera] the video track ended');
    _error = WebCameraError.failed;
    unawaited(stop());
    _notify();
  }

  @override
  Future<void> stop() async {
    _session++;
    _refocusTimer?.cancel();
    _playTimer?.cancel();
    _capabilityTimer?.cancel();
    final web.MediaStreamTrack? track = _track;
    final web.MediaStream? stream = _stream;
    _track = null;
    _stream = null;
    if (track != null) track.onended = null;
    if (stream != null) _stopTracks(stream);
    try {
      _video.pause();
    } catch (_) {}
    _video.srcObject = null;
    final bool wasStarted = _started;
    _started = false;
    _torchOn = false;
    if (wasStarted) _notify();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    unawaited(stop());
    for (final StreamSubscription<web.Event> subscription in _subscriptions) {
      subscription.cancel();
    }
    _controllers.remove(_id);
    _video.remove();
    _host.remove();
    super.dispose();
  }

  // ---- capabilities -------------------------------------------------------

  /// Continuous AF / exposure / white balance, no digital zoom, torch and
  /// focus-point support. Everything is optional and never throws.
  Future<void> _setupTrack(web.MediaDevices devices, web.MediaStreamTrack track, int session,
      {bool retry = false}) async {
    Map<String, Object?> caps = const <String, Object?>{};
    Map<String, Object?> settings = const <String, Object?>{};
    Map<String, Object?> supported = const <String, Object?>{};
    try {
      if (track.has('getCapabilities')) caps = _toMap(track.getCapabilities());
    } catch (_) {}
    try {
      if (track.has('getSettings')) settings = _toMap(track.getSettings());
    } catch (_) {}
    try {
      if (devices.has('getSupportedConstraints')) supported = _toMap(devices.getSupportedConstraints());
    } catch (_) {}

    final List<String> focusModes = _strings(caps['focusMode']);
    _singleShot = focusModes.contains('single-shot');
    if (focusModes.contains('continuous')) {
      _continuousFocus = await _apply(<String, Object?>{'focusMode': 'continuous'});
    }
    if (session != _session) return;
    if (_strings(caps['exposureMode']).contains('continuous')) {
      await _apply(<String, Object?>{'exposureMode': 'continuous'});
    }
    if (_strings(caps['whiteBalanceMode']).contains('continuous')) {
      await _apply(<String, Object?>{'whiteBalanceMode': 'continuous'});
    }
    // Never digitally zoomed: the preview and the photo show the whole lens view.
    final Object? zoom = caps['zoom'];
    if (zoom is Map && zoom['min'] is num) {
      final num min = zoom['min'] as num;
      final Object? current = settings['zoom'];
      if (current is! num || current != min) await _apply(<String, Object?>{'zoom': min});
    }
    if (session != _session) return;
    _torchSupported = caps['torch'] == true;
    _pointsOfInterest = supported['pointsOfInterest'] == true &&
        (settings.containsKey('pointsOfInterest') || _singleShot);

    if (!retry) {
      // Mirror only a front / laptop camera, like a mirror; photos never are.
      final Object? facing = settings['facingMode'];
      final String label = track.label.toLowerCase();
      final bool rear = facing == 'environment' ||
          label.contains('back') ||
          label.contains('rear') ||
          label.contains('environment');
      _mirrored = !rear && (facing == null || facing == '' || facing == 'user');
      _video.style.transform = _mirrored ? 'scaleX(-1)' : 'none';

      // Chrome sometimes fills in the Image Capture capabilities a moment
      // after the stream starts; look once more without holding up the preview.
      final bool hasImageCaps = caps.containsKey('focusMode') ||
          caps.containsKey('torch') ||
          caps.containsKey('zoom') ||
          caps.containsKey('exposureMode');
      if (!hasImageCaps && track.has('getCapabilities')) {
        _capabilityTimer?.cancel();
        _capabilityTimer = Timer(const Duration(milliseconds: 800), () async {
          if (_disposed || session != _session) return;
          await _setupTrack(devices, track, session, retry: true);
          if (session == _session) _notify();
        });
      }
    }
  }

  /// `applyConstraints({advanced: [set]})`; false if refused. Never throws.
  Future<bool> _apply(Map<String, Object?> set) async {
    final web.MediaStreamTrack? track = _track;
    if (track == null) return false;
    try {
      if (!track.has('applyConstraints')) return false;
      await _settle(track.applyConstraints(_js(<String, Object?>{
        'advanced': <Object?>[set],
      }) as web.MediaTrackConstraints));
      return true;
    } catch (e) {
      debugPrint('[Camera] applyConstraints $set refused: $e');
      return false;
    }
  }

  // ---- playback -----------------------------------------------------------

  void _viewCreated() {
    _playTimer?.cancel();
    _playTimer = Timer(const Duration(milliseconds: 60), _ensurePlaying);
  }

  void _schedulePlay() {
    if (_disposed || _stream == null || _resumeTries > 20) return;
    _resumeTries++;
    _playTimer?.cancel();
    _playTimer = Timer(const Duration(milliseconds: 120), _ensurePlaying);
  }

  void _ensurePlaying() {
    if (_disposed || _stream == null) return;
    if (_video.paused) unawaited(_play());
  }

  Future<void> _play() async {
    try {
      await _settle(_video.play()).timeout(const Duration(seconds: 3));
    } catch (e) {
      debugPrint('[Camera] play() did not start: $e');
    }
  }

  void _readVideoSize() {
    if (_disposed) return;
    final int w = _video.videoWidth;
    final int h = _video.videoHeight;
    if (w <= 0 || h <= 0) return;
    final Size size = Size(w.toDouble(), h.toDouble());
    if (size == _videoSize) return;
    _videoSize = size;
    _notify();
  }

  /// Called by the preview while it lays out: picks cover/contain for
  /// [view] and applies it to the <video> right away.
  void _layout(Size view) {
    if (_disposed || !view.width.isFinite || !view.height.isFinite || view.isEmpty) return;
    _viewSize = view;
    final Size? video = _videoSize;
    final WebCameraFit fit = video == null ? WebCameraFit.cover : chooseWebCameraFit(view, video);
    _video.style.setProperty('object-fit', fit.name);
    if (fit == _fit) return;
    _fit = fit;
    // Listeners (the brackets) rebuild after this frame, not during build.
    if (_notifyScheduled) return;
    _notifyScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _notifyScheduled = false;
      _notify();
    });
  }

  // ---- focus / torch ------------------------------------------------------

  @override
  Future<bool> focusAt(Offset normalized) async {
    try {
      // A tap is a user gesture: a good moment to start a blocked video.
      _ensurePlaying();
      final Size? video = _videoSize;
      final Size? view = _viewSize;
      if (!_started || !_pointsOfInterest || video == null || view == null) return false;
      final Offset? point = previewPointToFrame(
        Offset(normalized.dx * view.width, normalized.dy * view.height),
        view,
        video,
        _fit,
        mirrored: _mirrored,
      );
      if (point == null) return false;
      _refocusTimer?.cancel();
      final bool ok = await _apply(<String, Object?>{
        'pointsOfInterest': <Object?>[
          <String, Object?>{'x': point.dx, 'y': point.dy},
        ],
        if (_singleShot) 'focusMode': 'single-shot',
      });
      if (_singleShot && _continuousFocus) {
        final int session = _session;
        _refocusTimer = Timer(const Duration(seconds: 2), () {
          if (!_disposed && session == _session) {
            unawaited(_apply(<String, Object?>{'focusMode': 'continuous'}));
          }
        });
      }
      return ok;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> setTorch(bool on) async {
    if (!_started || !_torchSupported) return false;
    final bool ok = await _apply(<String, Object?>{'torch': on});
    if (ok && !_disposed) {
      _torchOn = on;
      _notify();
    }
    return ok;
  }

  // ---- capture ------------------------------------------------------------

  @override
  Future<Uint8List> capture() async {
    if (_disposed || !_started || _stream == null) {
      throw const WebCameraException(WebCameraError.failed, 'camera not started');
    }
    if (_video.paused) await _play();
    final int vw = _video.videoWidth;
    final int vh = _video.videoHeight;
    if (vw <= 0 || vh <= 0 || _video.readyState < 2) {
      throw const WebCameraException(WebCameraError.failed, 'no video frame yet');
    }
    final Size video = Size(vw.toDouble(), vh.toDouble());
    // The preview's CSS size; the Flutter layout size if it is not in the DOM.
    Size view = Size(_video.clientWidth.toDouble(), _video.clientHeight.toDouble());
    if (view.isEmpty) view = _viewSize ?? video;
    // Exactly what the preview shows (same object-fit, centred).
    final Rect source = visibleSourceRect(view, video, _fit);
    final Size out = photoOutputSize(source.size);

    final web.HTMLCanvasElement canvas = web.HTMLCanvasElement()
      ..width = out.width.toInt()
      ..height = out.height.toInt();
    try {
      final web.CanvasRenderingContext2D? context = canvas.getContext('2d') as web.CanvasRenderingContext2D?;
      if (context == null) throw const WebCameraException(WebCameraError.failed, 'no 2d canvas');
      context
        ..imageSmoothingEnabled = true
        ..imageSmoothingQuality = 'high';
      // Draws the un-mirrored frame (the CSS mirror only affects the preview).
      context.drawImage(
        _video,
        source.left,
        source.top,
        source.width,
        source.height,
        0,
        0,
        out.width,
        out.height,
      );
      Uint8List? bytes;
      for (final double quality in kJpegQualities) {
        bytes = await _encodeJpeg(canvas, quality);
        if (bytes.length <= kMaxPhotoBytes) break;
      }
      return bytes!;
    } on WebCameraException {
      rethrow;
    } catch (e) {
      throw WebCameraException(WebCameraError.failed, '$e');
    } finally {
      // Frees the canvas memory right away (matters on iOS).
      canvas
        ..width = 0
        ..height = 0;
    }
  }

  Future<Uint8List> _encodeJpeg(web.HTMLCanvasElement canvas, double quality) async {
    if (canvas.has('toBlob')) {
      final Completer<web.Blob?> done = Completer<web.Blob?>();
      canvas.toBlob(
        ((web.Blob? blob) {
          if (!done.isCompleted) done.complete(blob);
        }).toJS,
        'image/jpeg',
        quality.toJS,
      );
      final web.Blob? blob = await done.future.timeout(const Duration(seconds: 20), onTimeout: () => null);
      if (blob != null && blob.size > 0 && blob.has('arrayBuffer')) {
        final JSArrayBuffer buffer = await blob.arrayBuffer().toDart;
        return buffer.toDart.asUint8List();
      }
    }
    // Older browsers: a data URL.
    final String url = canvas.toDataURL('image/jpeg', quality.toJS);
    final int comma = url.indexOf(',');
    if (comma < 0) throw const WebCameraException(WebCameraError.failed, 'JPEG encoding failed');
    return base64Decode(url.substring(comma + 1));
  }

  // ---- preview ------------------------------------------------------------

  @override
  Widget buildPreview({Key? key}) => _WebCameraPreview(key: key ?? ValueKey<int>(_id), controller: this);
}

class _WebCameraPreview extends StatefulWidget {
  const _WebCameraPreview({super.key, required this.controller});

  final WebCameraController controller;

  @override
  State<_WebCameraPreview> createState() => _WebCameraPreviewState();
}

class _WebCameraPreviewState extends State<_WebCameraPreview> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
  }

  @override
  void didUpdateWidget(covariant _WebCameraPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final WebCameraController controller = widget.controller;
    return LayoutBuilder(
      builder: (context, constraints) {
        controller._layout(constraints.biggest);
        return HtmlElementView(
          key: ValueKey<int>(controller._id),
          viewType: _viewType,
          creationParams: controller._id,
          // Taps go to Flutter (tap-to-focus), not to the <video>.
          hitTestBehavior: PlatformViewHitTestBehavior.transparent,
        );
      },
    );
  }
}
