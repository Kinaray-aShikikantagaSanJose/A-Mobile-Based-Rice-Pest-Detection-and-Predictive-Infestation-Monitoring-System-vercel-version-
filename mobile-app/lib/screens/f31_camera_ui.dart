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
import '../main.dart' show cameras;
import '../platform/local_files.dart';
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

String _flashLabel(FlashMode m) => switch (m) {
      FlashMode.auto => 'Auto',
      FlashMode.always => 'On',
      FlashMode.torch => 'Light',
      _ => 'Off',
    };

IconData _flashIcon(FlashMode m) => switch (m) {
      FlashMode.auto => Icons.flash_auto_rounded,
      FlashMode.always => Icons.flash_on_rounded,
      FlashMode.torch => Icons.flashlight_on_rounded,
      _ => Icons.flash_off_rounded,
    };

class F31CameraUi extends StatefulWidget {
  const F31CameraUi({super.key});

  @override
  F31CameraUiState createState() => F31CameraUiState();
}

class F31CameraUiState extends State<F31CameraUi>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  CameraController? _controller;
  Future<void>? _initializeControllerFuture;
  bool _isCapturing = false;
  bool _isPicking = false;
  bool _isNavigating = false;
  bool _showFlash = false;
  bool _wasPaused = false;
  // Web: the camera list is only read when this screen opens (reading it
  // asks for camera permission), see _setupCamera.
  bool _lookingForCameras = false;
  bool _webCamerasChecked = false;
  FlashMode _flashMode = FlashMode.off;
  String? _errorMessage;
  String? _capturedImagePath;
  Timer? _flashTimer;

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
    if (kIsWeb && cameras.isEmpty && !_webCamerasChecked) {
      _findWebCameras();
      return;
    }
    // A later retry (e.g. after allowing the camera) looks again.
    _webCamerasChecked = false;
    if (cameras.isEmpty) {
      _errorMessage = kIsWeb
          ? 'No camera found, or camera access is blocked for this site. Allow it in the browser settings, then try again.'
          : 'No camera was found on this device.';
      if (mounted) setState(() {});
      return;
    }
    final CameraDescription backCamera = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );
    final controller = CameraController(
      backCamera,
      kIsWeb ? ResolutionPreset.veryHigh : ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );
    _controller = controller;
    _errorMessage = null;
    _initializeControllerFuture = controller.initialize().then((_) async {
      // The plugin defaults to auto flash; apply the mode the button shows.
      try {
        await controller.setFlashMode(_flashMode);
      } catch (_) {}
      if (!mounted || _controller != controller) return;
      setState(() => _errorMessage = null);
    }).catchError((Object e) {
      if (!mounted || _controller != controller) return;
      setState(() {
        _errorMessage = e is CameraException
            ? (e.code.contains('AccessDenied')
                ? 'Camera access is off. Allow it in your phone settings, then try again.'
                : 'Camera error: ${e.description ?? e.code}')
            : 'Could not start the camera.';
      });
    });
    if (mounted) setState(() {});
  }

  Future<void> _findWebCameras() async {
    if (_lookingForCameras) return;
    _lookingForCameras = true;
    try {
      cameras = await availableCameras();
    } catch (e) {
      debugPrint('Camera init error: $e');
    }
    _lookingForCameras = false;
    _webCamerasChecked = true;
    if (mounted) _setupCamera();
  }

  /// Frees the camera (app backgrounded) so other apps can use it.
  void _releaseCamera() {
    final controller = _controller;
    _controller = null;
    _initializeControllerFuture = null;
    if (mounted) setState(() {});
    controller?.dispose();
  }

  void _retryCamera() {
    final old = _controller;
    _controller = null;
    old?.dispose();
    _setupCamera();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
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

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _flashTimer?.cancel();
    _controller?.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  /// Off -> Auto -> On -> Light (torch, stays on for dark spots and traps).
  Future<void> _cycleFlash() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    final FlashMode next = _flashCycle[(_flashCycle.indexOf(_flashMode) + 1) % _flashCycle.length];
    HapticFeedback.selectionClick();
    try {
      await controller.setFlashMode(next);
      if (!mounted) return;
      setState(() => _flashMode = next);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text('Flash: ${_flashLabel(next)}'),
          duration: const Duration(milliseconds: 900),
        ));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Flash is not available on this camera.')));
    }
  }

  /// The torch would stay lit while the photo is checked; switch it off then.
  Future<void> _lightOffForReview() async {
    final controller = _controller;
    if (_flashMode != FlashMode.torch || controller == null || !controller.value.isInitialized) return;
    try {
      await controller.setFlashMode(FlashMode.off);
    } catch (_) {}
  }

  Future<void> _restoreFlash() async {
    final controller = _controller;
    if (_flashMode != FlashMode.torch || controller == null || !controller.value.isInitialized) return;
    try {
      await controller.setFlashMode(_flashMode);
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
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Could not open the gallery.')));
    } finally {
      if (mounted) setState(() => _isPicking = false);
    }
  }

  Future<void> _captureAndSave() async {
    final controller = _controller;
    if (controller == null ||
        !controller.value.isInitialized ||
        controller.value.isTakingPicture ||
        _isCapturing) {
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
      final XFile shot = await controller.takePicture();
      final String trapDir = p.join(await documentsDirPath(), 'observations');
      await createLocalDir(trapDir);
      final String fileName = 'obs_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final String savedPath = p.join(trapDir, fileName);
      await copyLocalFile(shot.path, savedPath);

      if (!mounted) return;
      setState(() {
        _capturedImagePath = savedPath;
      });
      _lightOffForReview();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Could not save the photo. Please try again.')));
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
    context.pop(path);
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
              _errorMessage!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.4),
            ),
            if (cameras.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.lg),
              AppPrimaryButton(
                label: 'Try again',
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
        // Browser captures the raw video frame, so preserve its native aspect ratio.
        return FittedBox(
          fit: kIsWeb ? BoxFit.contain : BoxFit.cover,
          child: SizedBox(
            width: previewSize == null
                ? 1
                : (kIsWeb ? previewSize.width : previewSize.height),
            height: previewSize == null
                ? 1
                : (kIsWeb ? previewSize.height : previewSize.width),
            child: CameraPreview(controller),
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
                tooltip: 'Back',
                onTap: () => popOrGoHome(context),
              ),
              const SizedBox(width: AppSpacing.md),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Take a Photo',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: AppFonts.display,
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      _stepLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.white70, fontSize: 12.5),
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
        final previewSize = _controller?.value.previewSize;
        final double previewAspect = kIsWeb &&
                previewSize != null &&
                previewSize.width > 0 &&
                previewSize.height > 0
            ? previewSize.width / previewSize.height
            : 3 / 4;
        final double width = kIsWeb
            ? (maxWidth < maxHeight * previewAspect ? maxWidth : maxHeight * previewAspect)
            : maxWidth;
        final double height = kIsWeb ? width / previewAspect : maxHeight;
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
            child: const Text(
              'Fit the trap or plant inside the frame',
              textAlign: TextAlign.center,
              style: TextStyle(
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
    final bool ready = _errorMessage == null && (_controller?.value.isInitialized ?? false);
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
                  label: 'Insert image',
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
                  label: 'Flash: ${_flashLabel(_flashMode)}',
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
              const Expanded(
                child: Text(
                  'Photo captured',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              _GlassIconButton(
                icon: Icons.close,
                tooltip: 'Discard photo',
                onTap: _resetCapture,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: AppSecondaryButton(
                  label: 'Retake',
                  icon: Icons.refresh_rounded,
                  onPressed: _resetCapture,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: AppPrimaryButton(
                  label: 'Use Photo',
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
      label: 'Take photo',
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
