// Non-web stand-in for web_camera_web.dart. Android / iOS use the camera
// plugin, so nothing here is ever started; it only keeps the API compiling
// (and the VM tests running).
import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import 'web_camera.dart';

/// False: the browser camera only exists on the web.
bool get webCameraAvailable => false;

class WebCameraController extends ChangeNotifier implements WebCameraApi {
  WebCameraController();

  @override
  bool get isStarted => false;

  @override
  WebCameraError? get error => WebCameraError.unsupported;

  @override
  Size? get videoSize => null;

  @override
  WebCameraFit get fit => WebCameraFit.cover;

  @override
  bool get mirrored => false;

  @override
  bool get torchSupported => false;

  @override
  bool get torchOn => false;

  @override
  bool get focusPointSupported => false;

  @override
  bool get continuousFocus => false;

  @override
  Future<void> start() async => throw const WebCameraException(WebCameraError.unsupported);

  @override
  Future<void> stop() async {}

  @override
  Widget buildPreview({Key? key}) => SizedBox.expand(key: key);

  @override
  Future<bool> focusAt(Offset normalized) async => false;

  @override
  Future<bool> setTorch(bool on) async => false;

  @override
  Future<Uint8List> capture() async => throw const WebCameraException(WebCameraError.unsupported);
}
