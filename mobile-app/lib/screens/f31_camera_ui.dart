import 'dart:async';
import 'dart:ui';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widget_previews.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import '../app_router.dart';
import '../l10n/app_language.dart';
import '../main.dart' show cameras;
import '../platform/local_files.dart';
import '../platform/web_camera.dart';
import '../theme.dart';
import '../widgets/app_widgets.dart';
import '../widgets/motion.dart';

@Preview(name: 'F31CameraUi', size: Size(390.0, 844.0))
Widget previewF31CameraUi() {
  return const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: F31CameraUi(),
  );
}

const String _stepLabel = 'Photo';

/// Flash button order: each tap moves to the next mode.
const List<FlashMode> _flashCycle = [FlashMode.off, FlashMode.auto, FlashMode.always, FlashMode.torch];

/// Flash button caption (English; translated where it is shown). Whole
/// phrases, so short words like "On" don't clash with other screens.
String _flashLabel(FlashMode m) => switch (m) {
      FlashMode.auto => 'Flash: Auto',
      FlashMode.always => 'Flash: On',
      FlashMode.torch => 'Flash: Light',
      _ => 'Flash: Off',
    };

IconData _flashIcon(FlashMode m) => switch (m) {
      FlashMode.auto => Icons.flash_auto_rounded,
      FlashMode.always => Icons.flash_on_rounded,
      FlashMode.torch => Icons.flashlight_on_rounded,
      _ => Icons.flash_off_rounded,
    };

/// Why the browser camera could not start (English; translated when shown).
String _webCameraErrorText(WebCameraError kind) => switch (kind) {
      WebCameraError.notAllowed =>
        'Camera access is blocked for this site. Allow it in the browser settings, then try again.',
      WebCameraError.notFound => 'No camera was found on this device.',
      WebCameraError.inUse => 'The camera is being used by another app. Close it, then try again.',
      WebCameraError.insecureContext => 'The camera needs a secure (HTTPS) connection.',
      WebCameraError.unsupported => 'This browser cannot use the camera. Pick a photo from the gallery instead.',
      _ => 'Could not start the camera.',
    };

class F31CameraUi extends StatefulWidget {
  const F31CameraUi({super.key});

  @override
  F31CameraUiState createState() => F31CameraUiState();
}

class F31CameraUiState extends State<F31CameraUi>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  // Android / iOS: the camera plugin.
  CameraController? _controller;
  Future<void>? _initializeControllerFuture;
  // Web: a <video> fed by getUserMedia (lib/platform/web_camera.dart). The
  // browser asks for camera permission when it starts.
  WebCameraController? _webCamera;
  bool _isCapturing = false;
  bool _isPicking = false;
  bool _isNavigating = false;
  bool _showFlash = false;
  bool _wasPaused = false;
  FlashMode _flashMode = FlashMode.off;
  // English text (and placeholders); translated in build.
  String? _errorMessage;
  Map<String, Object?>? _errorVars;
  bool _canRetry = true;
  String? _capturedImagePath;
  Timer? _flashTimer;
  // Tap-to-focus ring (position in the preview, restarts on every tap).
  Offset? _focusPoint;
  int _focusTapId = 0;
  Timer? _focusRingTimer;

  // Breathing pulse animation for viewfinder corner brackets
  late final AnimationController _pulseController;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    // Started in didChangeDependencies so "remove animations" is honoured.
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _pulse = Tween<double>(begin: 0.55, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    WidgetsBinding.instance.addObserver(this);
    _setupCamera();
  }

  bool get _reduceMotion => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  /// The live camera is running and a photo can be taken.
  bool get _cameraReady {
    if (_errorMessage != null) return false;
    if (kIsWeb) return _webCamera?.isStarted ?? false;
    return _controller?.value.isInitialized ?? false;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_reduceMotion) {
      _pulseController
        ..stop()
        ..value = 1;
    } else if (!_pulseController.isAnimating) {
      _pulseController.repeat(reverse: true);
    }
  }

  void _setupCamera() {
    if (kIsWeb) {
      unawaited(_startWebCamera());
      return;
    }
    if (cameras.isEmpty) {
      _errorMessage = 'No camera was found on this device.';
      _errorVars = null;
      _canRetry = false;
      if (mounted) setState(() {});
      return;
    }
    final CameraDescription backCamera = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );
    final controller = CameraController(
      backCamera,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );
    _controller = controller;
    _errorMessage = null;
    _errorVars = null;
    _canRetry = true;
    _initializeControllerFuture = controller.initialize().then((_) async {
      // The plugin defaults to auto flash; apply the mode the button shows.
      try {
        await controller.setFlashMode(_flashMode);
      } catch (_) {}
      // Continuous autofocus and auto exposure (best effort: not every
      // camera supports them).
      try {
        await controller.setFocusMode(FocusMode.auto);
      } catch (_) {}
      try {
        await controller.setExposureMode(ExposureMode.auto);
      } catch (_) {}
      if (!mounted || _controller != controller) return;
      setState(() => _errorMessage = null);
    }).catchError((Object e) {
      if (!mounted || _controller != controller) return;
      setState(() {
        _errorVars = null;
        if (e is CameraException && e.code.contains('AccessDenied')) {
          _errorMessage = 'Camera access is off. Allow it in your phone settings, then try again.';
        } else if (e is CameraException) {
          _errorMessage = 'Camera error: {error}';
          _errorVars = {'error': e.description ?? e.code};
        } else {
          _errorMessage = 'Could not start the camera.';
        }
      });
    });
    if (mounted) setState(() {});
  }

  /// Browser: asks for the camera (rear camera preferred) and starts the
  /// live view. Errors (blocked, no camera, in use, no HTTPS) are shown with
  /// "Try again" where that can help.
  Future<void> _startWebCamera() async {
    final WebCameraController camera = WebCameraController();
    _webCamera = camera;
    _errorMessage = null;
    _errorVars = null;
    _canRetry = true;
    camera.addListener(_onWebCameraChanged);
    if (mounted) setState(() {});
    try {
      await camera.start();
    } catch (e) {
      if (!mounted || _webCamera != camera) return;
      final WebCameraError kind = e is WebCameraException ? e.kind : WebCameraError.failed;
      if (kind == WebCameraError.stopped) return;
      debugPrint('Camera init error: $e');
      setState(() => _showWebCameraError(kind));
      return;
    }
    if (!mounted || _webCamera != camera) return;
    // Keep the light on after the camera restarts (tab hidden and back).
    if (_flashMode == FlashMode.torch) {
      if (!camera.torchSupported) {
        _flashMode = FlashMode.off;
      } else if (_capturedImagePath == null) {
        await camera.setTorch(true);
      }
    }
    if (mounted && _webCamera == camera) setState(() {});
  }

  void _showWebCameraError(WebCameraError kind) {
    _errorMessage = _webCameraErrorText(kind);
    _errorVars = null;
    // Reloading won't add HTTPS or getUserMedia; everything else may work later.
    _canRetry = kind != WebCameraError.insecureContext && kind != WebCameraError.unsupported;
  }

  /// Browser camera changed: started, frame size / fit, torch, or it stopped
  /// on its own (unplugged, taken by another app).
  void _onWebCameraChanged() {
    if (!mounted) return;
    final WebCameraController? camera = _webCamera;
    setState(() {
      final WebCameraError? error = camera?.error;
      if (camera != null && error != null && !camera.isStarted && _errorMessage == null) {
        _showWebCameraError(error);
      }
    });
  }

  void _disposeWebCamera(WebCameraController? camera) {
    if (camera == null) return;
    camera.removeListener(_onWebCameraChanged);
    camera.dispose();
  }

  /// Frees the camera (app backgrounded) so other apps can use it.
  void _releaseCamera() {
    final controller = _controller;
    final webCamera = _webCamera;
    _controller = null;
    _webCamera = null;
    _initializeControllerFuture = null;
    if (mounted) setState(() {});
    controller?.dispose();
    _disposeWebCamera(webCamera);
  }

  void _retryCamera() {
    final old = _controller;
    final oldWeb = _webCamera;
    _controller = null;
    _webCamera = null;
    old?.dispose();
    _disposeWebCamera(oldWeb);
    _setupCamera();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (kIsWeb) {
      _onWebLifecycle(state);
      return;
    }
    if (state == AppLifecycleState.paused) _wasPaused = true;
    if (state == AppLifecycleState.inactive) {
      final controller = _controller;
      // Still starting (e.g. the camera-permission dialog is up): leave it
      // alone so initialization can finish once the dialog closes.
      if (controller == null || !controller.value.isInitialized) return;
      _releaseCamera();
    } else if (state == AppLifecycleState.resumed) {
      final bool cameBack = _wasPaused;
      _wasPaused = false;
      if (_controller == null) {
        _setupCamera();
      } else if (_errorMessage != null && cameBack) {
        // Back from the phone settings: the permission may be granted now.
        _retryCamera();
      }
    }
  }

  /// Browser: the camera stops while the tab is hidden (other tab or app,
  /// screen off) and starts again when it is visible. Only losing focus
  /// (address bar, file chooser, permission prompt) keeps it running.
  void _onWebLifecycle(AppLifecycleState state) {
    if (state == AppLifecycleState.hidden || state == AppLifecycleState.paused) {
      _wasPaused = true;
      if (_webCamera != null) _releaseCamera();
    } else if (state == AppLifecycleState.resumed) {
      final bool cameBack = _wasPaused;
      _wasPaused = false;
      if (_webCamera == null) {
        _setupCamera();
      } else if (_errorMessage != null && cameBack) {
        // Back from the browser settings: the camera may be allowed now.
        _retryCamera();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _flashTimer?.cancel();
    _focusRingTimer?.cancel();
    _controller?.dispose();
    _disposeWebCamera(_webCamera);
    _webCamera = null;
    _pulseController.dispose();
    super.dispose();
  }

  void _showSnack(String text, {Duration? duration}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(text),
        duration: duration ?? const Duration(milliseconds: 4000),
      ));
  }

  /// Off -> Auto -> On -> Light (torch, stays on for dark spots and traps).
  Future<void> _cycleFlash() async {
    if (kIsWeb) return _toggleWebLight();
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    final FlashMode next = _flashCycle[(_flashCycle.indexOf(_flashMode) + 1) % _flashCycle.length];
    HapticFeedback.selectionClick();
    try {
      await controller.setFlashMode(next);
      if (!mounted) return;
      setState(() => _flashMode = next);
      _showSnack(
        context.tr(_flashLabel(next)),
        duration: const Duration(milliseconds: 900),
      );
    } catch (_) {
      if (!mounted) return;
      _showSnack(context.tr('Flash is not available on this camera.'));
    }
  }

  /// Browser: only a torch (Off <-> Light), and only where the camera has one.
  Future<void> _toggleWebLight() async {
    final camera = _webCamera;
    if (camera == null || !camera.isStarted) return;
    HapticFeedback.selectionClick();
    if (!camera.torchSupported) {
      _showSnack(context.tr('Flash is not available on this camera.'));
      return;
    }
    final FlashMode next = _flashMode == FlashMode.torch ? FlashMode.off : FlashMode.torch;
    final bool ok = await camera.setTorch(next == FlashMode.torch);
    if (!mounted) return;
    if (!ok) {
      _showSnack(context.tr('Flash is not available on this camera.'));
      return;
    }
    setState(() => _flashMode = next);
    _showSnack(
      context.tr(_flashLabel(next)),
      duration: const Duration(milliseconds: 900),
    );
  }

  /// The torch would stay lit while the photo is checked; switch it off then.
  Future<void> _lightOffForReview() async {
    if (_flashMode != FlashMode.torch) return;
    if (kIsWeb) {
      await _webCamera?.setTorch(false);
      return;
    }
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    try {
      await controller.setFlashMode(FlashMode.off);
    } catch (_) {}
  }

  Future<void> _restoreFlash() async {
    if (_flashMode != FlashMode.torch) return;
    if (kIsWeb) {
      await _webCamera?.setTorch(true);
      return;
    }
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    try {
      await controller.setFlashMode(_flashMode);
    } catch (_) {}
  }

  /// Tap on the live view: focus there (where the camera allows it) and show
  /// a short focus ring. Continuous autofocus keeps running either way.
  void _onPreviewTap(Offset local, Size view) {
    if (!_cameraReady || _capturedImagePath != null || view.isEmpty) return;
    setState(() {
      _focusPoint = local;
      _focusTapId++;
    });
    _focusRingTimer?.cancel();
    _focusRingTimer = Timer(const Duration(milliseconds: 1300), () {
      if (mounted) setState(() => _focusPoint = null);
    });
    if (kIsWeb) {
      _webCamera?.focusAt(Offset(local.dx / view.width, local.dy / view.height));
    } else {
      _focusNativeAt(local, view);
    }
  }

  Future<void> _focusNativeAt(Offset local, Size view) async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    final Size? previewSize = controller.value.previewSize;
    if (previewSize == null) return;
    // The preview is shown in portrait (height x width) and covers the screen.
    final Offset? point = previewPointToFrame(
      local,
      view,
      Size(previewSize.height, previewSize.width),
      WebCameraFit.cover,
    );
    if (point == null) return;
    try {
      if (controller.value.focusPointSupported) await controller.setFocusPoint(point);
    } catch (_) {}
    try {
      if (controller.value.exposurePointSupported) await controller.setExposurePoint(point);
    } catch (_) {}
  }

  /// "Insert image": a photo already on the phone instead of a new one.
  Future<void> _pickFromGallery() async {
    if (_isPicking || _isCapturing) return;
    setState(() => _isPicking = true);
    try {
      final picked = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 2048, imageQuality: 90);
      if (picked == null || !mounted) return;
      final dir = p.join(await documentsDirPath(), 'observations');
      await createLocalDir(dir);
      final dest = p.join(dir, 'obs_${DateTime.now().millisecondsSinceEpoch}${pickedFileExtension(picked)}');
      await copyLocalFile(picked.path, dest);
      if (!mounted) return;
      setState(() {
        _discardCaptured();
        _capturedImagePath = dest;
      });
      _lightOffForReview();
    } catch (_) {
      if (!mounted) return;
      _showSnack(context.tr('Could not open the gallery.'));
    } finally {
      if (mounted) setState(() => _isPicking = false);
    }
  }

  Future<void> _captureAndSave() async {
    final controller = _controller;
    final webCamera = _webCamera;
    if (_isCapturing || !_cameraReady) return;
    if (kIsWeb ? webCamera == null : (controller == null || controller.value.isTakingPicture)) {
      return;
    }
    HapticFeedback.lightImpact();
    // Brief white "shutter" flash; skipped when animations are turned off.
    final bool flash = !_reduceMotion;
    setState(() {
      _isCapturing = true;
      _showFlash = flash;
    });

    _flashTimer?.cancel();
    if (flash) {
      _flashTimer = Timer(const Duration(milliseconds: 120), () {
        if (mounted) setState(() => _showFlash = false);
      });
    }

    try {
      // Browser: exactly the framing of the live view, as a JPEG of at most
      // 2048 px (see web_camera.dart). Phone: the camera plugin's photo.
      final XFile? shot = kIsWeb ? null : await controller!.takePicture();
      final webPhoto = kIsWeb ? await webCamera!.capture() : null;
      final String trapDir = p.join(await documentsDirPath(), 'observations');
      await createLocalDir(trapDir);
      final String fileName = 'obs_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final String savedPath = p.join(trapDir, fileName);
      if (webPhoto != null) {
        await writeLocalFile(savedPath, webPhoto);
      } else {
        await copyLocalFile(shot!.path, savedPath);
      }

      if (!mounted) return;
      setState(() {
        _capturedImagePath = savedPath;
      });
      _lightOffForReview();
    } catch (e) {
      debugPrint('Could not save the photo: $e');
      if (!mounted) return;
      _showSnack(context.tr('Could not save the photo. Please try again.'));
    } finally {
      if (mounted) setState(() => _isCapturing = false);
    }
  }

  /// Deletes a photo that never became a saved scan.
  void _discardCaptured() {
    final path = _capturedImagePath;
    if (path == null) return;
    _capturedImagePath = null;
    try {
      deleteLocalFileSync(path);
    } catch (e) {
      debugPrint('Could not delete discarded photo: $e');
    }
  }

  void _resetCapture() {
    setState(_discardCaptured);
    _restoreFlash();
  }

  /// Hands the photo back to the observation flow (the file is kept).
  void _confirmCapture() {
    final path = _capturedImagePath;
    if (path == null || _isNavigating) return;
    _isNavigating = true;
    if (context.canPop()) {
      context.pop(path);
    } else {
      // Opened directly (browser refresh / link to /observe/camera): nothing to
      // return the photo to, so start the observation flow instead.
      context.go(AppRouter.observe);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: PopScope(
        // Leaving the camera discards a photo that was never confirmed. While
        // the photo is handed to the next screens it is theirs, never deleted here.
        onPopInvokedWithResult: (didPop, _) {
          if (didPop && !_isNavigating) _discardCaptured();
        },
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            children: [
              // Live camera preview, cross-fading to the captured photo
              Positioned.fill(
                child: AnimatedSwitcher(
                  duration: _reduceMotion ? Duration.zero : AppMotion.medium,
                  switchInCurve: AppMotion.curve,
                  switchOutCurve: Curves.easeIn,
                  layoutBuilder: (current, previous) => Stack(
                    fit: StackFit.expand,
                    children: [...previous, ?current],
                  ),
                  child: _capturedImagePath != null
                      ? KeyedSubtree(
                          key: ValueKey<String>('photo:$_capturedImagePath'),
                          child: _buildCapturedPhoto(_capturedImagePath!),
                        )
                      : KeyedSubtree(
                          key: const ValueKey<String>('camera'),
                          child: _buildCameraPreview(),
                        ),
                ),
              ),

              // Shutter flash: snaps on, then fades out softly.
              Positioned.fill(
                child: IgnorePointer(
                  child: AnimatedOpacity(
                    opacity: _showFlash ? 0.85 : 0.0,
                    duration: _showFlash
                        ? const Duration(milliseconds: 60)
                        : const Duration(milliseconds: 280),
                    curve: Curves.easeOut,
                    child: const ColoredBox(color: Colors.white),
                  ),
                ),
              ),

              // UI Overlays & Controls
              SafeArea(
                child: Column(
                  children: [
                    _buildTopBar(),
                    Expanded(
                      child: _errorMessage != null && _capturedImagePath == null
                          ? const SizedBox.shrink()
                          : _buildAlignmentFrame(),
                    ),
                    // Shutter bar <-> "Photo captured" card, easing the
                    // height change so the viewfinder frame resizes smoothly.
                    AnimatedSize(
                      duration: _reduceMotion ? Duration.zero : AppMotion.medium,
                      curve: AppMotion.curve,
                      alignment: Alignment.bottomCenter,
                      child: AnimatedSwitcher(
                        duration: _reduceMotion ? Duration.zero : AppMotion.medium,
                        switchInCurve: AppMotion.curve,
                        switchOutCurve: Curves.easeIn,
                        transitionBuilder: (child, animation) => FadeTransition(
                          opacity: animation,
                          child: SlideTransition(
                            position: Tween<Offset>(
                              begin: const Offset(0, 0.12),
                              end: Offset.zero,
                            ).animate(animation),
                            child: child,
                          ),
                        ),
                        child: _capturedImagePath != null
                            ? KeyedSubtree(
                                key: const ValueKey<String>('confirm'),
                                child: _buildCapturedConfirmationCard(),
                              )
                            : KeyedSubtree(
                                key: const ValueKey<String>('controls'),
                                child: _buildBottomControls(),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCapturedPhoto(String path) {
    return localImage(
      path,
      // Web photos have the preview's exact framing, so "contain" shows the
      // same picture the live view showed.
      fit: kIsWeb ? BoxFit.contain : BoxFit.cover,
      errorBuilder: (context, error, stackTrace) => const ColoredBox(color: Colors.black),
    );
  }

  Widget _buildCameraPreview() {
    if (_errorMessage != null) {
      return Container(
        color: Colors.black,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.no_photography_outlined, color: Colors.white70, size: 40),
            const SizedBox(height: AppSpacing.md),
            Text(
              context.tr(_errorMessage!, _errorVars),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.4),
            ),
            if (_canRetry) ...[
              const SizedBox(height: AppSpacing.lg),
              AppPrimaryButton(
                label: context.tr('Try again'),
                icon: Icons.refresh_rounded,
                expanded: false,
                compact: true,
                onPressed: _retryCamera,
              ),
            ],
          ],
        ),
      );
    }
    if (kIsWeb) return _withTapToFocus(_buildWebPreview());
    final controller = _controller;
    if (controller == null || _initializeControllerFuture == null) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }
    return FutureBuilder<void>(
      future: _initializeControllerFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done ||
            !controller.value.isInitialized) {
          return const ColoredBox(
            color: Colors.black,
            child: Center(child: CircularProgressIndicator(color: Colors.white)),
          );
        }
        final previewSize = controller.value.previewSize;
        return _withTapToFocus(
          FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: previewSize == null ? 1 : previewSize.height,
              height: previewSize == null ? 1 : previewSize.width,
              child: CameraPreview(controller),
            ),
          ),
        );
      },
    );
  }

  /// Browser live view: the <video> itself, drawn by the browser at screen
  /// resolution (cover, or contain when covering would cut too much).
  Widget _buildWebPreview() {
    final camera = _webCamera;
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: Colors.black),
        if (camera != null) camera.buildPreview(),
        if (camera == null || !camera.isStarted)
          const Center(child: CircularProgressIndicator(color: Colors.white)),
      ],
    );
  }

  /// Tap anywhere on the live view to focus there; shows the focus ring.
  Widget _withTapToFocus(Widget preview) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final Size view = constraints.biggest;
        final Offset? ring = _focusPoint;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (details) => _onPreviewTap(details.localPosition, view),
          child: Stack(
            fit: StackFit.expand,
            children: [
              preview,
              if (ring != null)
                Positioned(
                  left: ring.dx - _FocusRing.size / 2,
                  top: ring.dy - _FocusRing.size / 2,
                  width: _FocusRing.size,
                  height: _FocusRing.size,
                  child: IgnorePointer(
                    child: _FocusRing(key: ValueKey<int>(_focusTapId)),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTopBar() {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          color: Colors.black.withValues(alpha: 0.35),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          child: Row(
            children: [
              _GlassIconButton(
                icon: Icons.arrow_back_rounded,
                tooltip: context.tr('Back'),
                onTap: () => popOrGoHome(context),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      context.tr('Take a Photo'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: AppFonts.display,
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      context.tr(_stepLabel),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white70, fontSize: 12.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAlignmentFrame() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double maxWidth = (constraints.maxWidth * 0.78).clamp(0.0, 280.0);
        final double maxHeight = (constraints.maxHeight * 0.9).clamp(0.0, 380.0);
        // Browser with a letterboxed ("contain") live view: match the frame to
        // the video's shape. Otherwise the video fills the screen.
        final WebCameraController? camera = _webCamera;
        final Size? videoSize = camera?.videoSize;
        final bool letterboxed = kIsWeb &&
            camera != null &&
            camera.fit == WebCameraFit.contain &&
            videoSize != null &&
            videoSize.width > 0 &&
            videoSize.height > 0;
        final double previewAspect = letterboxed ? videoSize.width / videoSize.height : 3 / 4;
        final double width = letterboxed
            ? (maxWidth < maxHeight * previewAspect ? maxWidth : maxHeight * previewAspect)
            : maxWidth;
        final double height = letterboxed ? width / previewAspect : maxHeight;
        return Center(
          child: SizedBox(
            width: width,
            height: height,
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (height > 120)
                  Positioned(
                    top: AppSpacing.xl,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: _buildHintPill(),
                    ),
                  ),
                // Pulsing orange corner brackets
                Positioned.fill(
                  child: FadeTransition(
                    opacity: _pulse,
                    child: const Stack(
                      children: [
                        Positioned(top: 0, left: 0, child: _CornerBracket(isTop: true, isLeft: true)),
                        Positioned(top: 0, right: 0, child: _CornerBracket(isTop: true, isLeft: false)),
                        Positioned(bottom: 0, left: 0, child: _CornerBracket(isTop: false, isLeft: true)),
                        Positioned(bottom: 0, right: 0, child: _CornerBracket(isTop: false, isLeft: false)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Framing hint over the live view; fades away once a photo is taken.
  Widget _buildHintPill() {
    final bool visible = _capturedImagePath == null;
    return ExcludeSemantics(
      excluding: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: _reduceMotion ? Duration.zero : AppMotion.medium,
        curve: AppMotion.curve,
        child: AnimatedSlide(
          offset: visible ? Offset.zero : const Offset(0, -0.3),
          duration: _reduceMotion ? Duration.zero : AppMotion.medium,
          curve: AppMotion.curve,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(AppRadius.pill),
              border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
            ),
            child: Text(
              context.tr('Fit the trap or plant inside the frame'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomControls() {
    final bool ready = _cameraReady;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          width: double.infinity,
          color: Colors.black.withValues(alpha: 0.35),
          padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.xl, AppSpacing.lg, AppSpacing.xxl),
          alignment: Alignment.center,
          // Insert image · shutter · flash
          child: Row(
            children: [
              Expanded(
                child: _SideControl(
                  icon: Icons.add_photo_alternate_rounded,
                  label: context.tr('Insert image'),
                  busy: _isPicking,
                  onTap: _isPicking || _isCapturing ? null : _pickFromGallery,
                ),
              ),
              _ShutterButton(
                ready: ready,
                busy: _isCapturing,
                onTap: _isCapturing || !ready ? null : _captureAndSave,
              ),
              Expanded(
                child: _SideControl(
                  icon: _flashIcon(_flashMode),
                  label: context.tr(_flashLabel(_flashMode)),
                  highlighted: _flashMode != FlashMode.off,
                  onTap: ready ? _cycleFlash : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCapturedConfirmationCard() {
    return Container(
      margin: const EdgeInsets.all(AppSpacing.lg),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  context.tr('Photo captured'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              _GlassIconButton(
                icon: Icons.close,
                tooltip: context.tr('Discard photo'),
                onTap: _resetCapture,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: AppSecondaryButton(
                  label: context.tr('Retake'),
                  icon: Icons.refresh_rounded,
                  onPressed: _resetCapture,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: AppPrimaryButton(
                  label: context.tr('Use Photo'),
                  icon: Icons.check_rounded,
                  onPressed: _isNavigating ? null : _confirmCapture,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Focus ring shown where the live view was tapped: shrinks into place, then
/// fades out. Static (no scaling) when animations are turned off.
class _FocusRing extends StatefulWidget {
  const _FocusRing({super.key});

  static const double size = 72;

  @override
  State<_FocusRing> createState() => _FocusRingState();
}

class _FocusRingState extends State<_FocusRing> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );
  late final Animation<double> _scale = Tween<double>(begin: 1.35, end: 1.0).animate(
    CurvedAnimation(parent: _controller, curve: const Interval(0, 0.3, curve: Curves.easeOutCubic)),
  );
  late final Animation<double> _opacity = Tween<double>(begin: 1.0, end: 0.0).animate(
    CurvedAnimation(parent: _controller, curve: const Interval(0.7, 1, curve: Curves.easeIn)),
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _controller.value = 0.5; // full size, fully visible
    } else {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: ScaleTransition(
        scale: _scale,
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.brandGold, width: 2),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 6),
            ],
          ),
          child: Center(
            child: Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(color: AppColors.brandGold, shape: BoxShape.circle),
            ),
          ),
        ),
      ),
    );
  }
}

/// Round button with a caption beside the shutter (gallery, flash).
class _SideControl extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool highlighted;
  final bool busy;

  const _SideControl({required this.icon, required this.label, required this.onTap, this.highlighted = false, this.busy = false});

  @override
  Widget build(BuildContext context) {
    final bool reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final bool enabled = onTap != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: AnimatedOpacity(
        opacity: enabled ? 1 : 0.4,
        duration: reduce ? Duration.zero : AppMotion.medium,
        child: PressScale(
          enabled: enabled,
          scale: 0.9,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedContainer(
                  duration: reduce ? Duration.zero : AppMotion.medium,
                  curve: AppMotion.curve,
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: highlighted
                        ? const LinearGradient(colors: [AppColors.brandGold, AppColors.orange])
                        : null,
                    color: highlighted ? null : Colors.white.withValues(alpha: 0.18),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
                  ),
                  alignment: Alignment.center,
                  child: busy
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : AnimatedSwitcher(
                          duration: reduce ? Duration.zero : AppMotion.fast,
                          child: Icon(icon, key: ValueKey<IconData>(icon), color: Colors.white, size: 24),
                        ),
                ),
                const SizedBox(height: 6),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Round shutter: dips while pressed, stays slightly down with a spinner
/// while the photo is being saved, and dims until the camera is ready.
class _ShutterButton extends StatefulWidget {
  final bool ready;
  final bool busy;
  final VoidCallback? onTap;

  const _ShutterButton({required this.ready, required this.busy, required this.onTap});

  @override
  State<_ShutterButton> createState() => _ShutterButtonState();
}

class _ShutterButtonState extends State<_ShutterButton> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed != value && mounted) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final bool reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final bool enabled = widget.onTap != null;
    final double scale = _pressed && enabled ? 0.88 : (widget.busy ? 0.94 : 1.0);
    return Semantics(
      button: true,
      enabled: enabled,
      label: context.tr('Take photo'),
      child: GestureDetector(
        onTapDown: enabled ? (_) => _setPressed(true) : null,
        onTapUp: enabled ? (_) => _setPressed(false) : null,
        onTapCancel: () => _setPressed(false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: scale,
          duration: reduce ? Duration.zero : AppMotion.fast,
          curve: Curves.easeOut,
          child: AnimatedOpacity(
            opacity: widget.ready ? 1 : 0.4,
            duration: reduce ? Duration.zero : AppMotion.medium,
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: Container(
                width: 64,
                height: 64,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: AnimatedSwitcher(
                  duration: reduce ? Duration.zero : AppMotion.fast,
                  child: widget.busy
                      ? const SizedBox(
                          key: ValueKey<String>('busy'),
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.primary,
                          ),
                        )
                      : const SizedBox.shrink(key: ValueKey<String>('idle')),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 40px translucent circular button for the dark camera chrome. The fill
/// eases between states and the icon cross-fades when it changes.
class _GlassIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _GlassIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bool reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return Tooltip(
      message: tooltip,
      child: PressScale(
        scale: 0.9,
        child: AnimatedContainer(
          duration: reduce ? Duration.zero : AppMotion.medium,
          curve: AppMotion.curve,
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.2),
            shape: BoxShape.circle,
          ),
          child: Material(
            type: MaterialType.transparency,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: Center(
                child: AnimatedSwitcher(
                  duration: reduce ? Duration.zero : AppMotion.medium,
                  switchInCurve: AppMotion.curve,
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: RotationTransition(
                      turns: Tween<double>(begin: -0.1, end: 0).animate(animation),
                      child: ScaleTransition(scale: animation, child: child),
                    ),
                  ),
                  child: Icon(icon, key: ValueKey<IconData>(icon), color: Colors.white, size: 20),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CornerBracket extends StatelessWidget {
  final bool isTop;
  final bool isLeft;

  const _CornerBracket({required this.isTop, required this.isLeft});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: AppSpacing.xl,
      height: AppSpacing.xl,
      child: CustomPaint(
        painter: _BracketPainter(isTop: isTop, isLeft: isLeft),
      ),
    );
  }
}

class _BracketPainter extends CustomPainter {
  final bool isTop;
  final bool isLeft;

  _BracketPainter({required this.isTop, required this.isLeft});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.orange
      ..strokeWidth = 3.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final double x = isLeft ? 0 : size.width;
    final double y = isTop ? 0 : size.height;
    final Offset corner = Offset(x, y);

    canvas.drawLine(corner, Offset(x, isTop ? size.height : 0), paint);
    canvas.drawLine(corner, Offset(isLeft ? size.width : 0, y), paint);
  }

  @override
  bool shouldRepaint(covariant _BracketPainter oldDelegate) => false;
}
