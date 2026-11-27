import 'package:flutter/material.dart';

import '../l10n/app_language.dart';
import '../models/record.dart';
import '../platform/local_files.dart';
import '../services/api_client.dart';
import '../services/local_store.dart';
import '../theme.dart';

/// The server photo with the model result's detection boxes drawn on top. The image is
/// shown at its own aspect ratio so the (0-1) box coordinates line up.
/// Tap for full screen with zoom.
class DetectionPhoto extends StatefulWidget {
  final int scanId;
  final String? clientUuid;
  final List<DetectionBox> boxes;

  /// Boxes of this pest are drawn in the accent colour; others in blue.
  final String? mainPest;
  final bool fullScreenOnTap;

  const DetectionPhoto({
    super.key,
    required this.scanId,
    this.clientUuid,
    this.boxes = const [],
    this.mainPest,
    this.fullScreenOnTap = true,
  });

  @override
  State<DetectionPhoto> createState() => _DetectionPhotoState();
}

class _DetectionPhotoState extends State<DetectionPhoto> {
  ImageProvider? _image;
  double? _aspect;
  bool _failed = false;
  ImageStream? _stream;
  ImageStreamListener? _listener;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  Future<void> _resolve() async {
    final uuid = widget.clientUuid ?? 'server_${widget.scanId}';
    final String path;
    try {
      final cached = await LocalStore.instance.localPhoto(uuid);
      path = cached ??
          await LocalStore.instance.cacheServerPhoto(
            uuid,
            widget.scanId,
            await ApiClient.downloadImage('/sync/scans/${widget.scanId}/image'),
          );
    } catch (e) {
      // No signal and no copy on the phone: show "Photo unavailable", not a
      // spinner that never ends.
      if (mounted) setState(() => _failed = true);
      return;
    }
    if (!mounted) return;
    final provider = localImageProvider(path);
    final stream = provider.resolve(const ImageConfiguration());
    final listener = ImageStreamListener(
      (info, _) {
        if (mounted) setState(() => _aspect = info.image.width / info.image.height);
      },
      onError: (_, _) {
        if (mounted) setState(() => _failed = true);
      },
    );
    stream.addListener(listener);
    setState(() {
      _image = provider;
      _stream = stream;
      _listener = listener;
    });
  }

  @override
  void dispose() {
    if (_listener != null) _stream?.removeListener(_listener!);
    super.dispose();
  }

  void _openFull() {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (ctx) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: Text(ctx.tr('{n} boxes', {'n': widget.boxes.length}), style: const TextStyle(fontSize: 16)),
        ),
        body: InteractiveViewer(
          maxScale: 6,
          child: Center(
            child: DetectionPhoto(
              scanId: widget.scanId,
              clientUuid: widget.clientUuid,
              boxes: widget.boxes,
              mainPest: widget.mainPest,
              fullScreenOnTap: false,
            ),
          ),
        ),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return AspectRatio(
        aspectRatio: 4 / 3,
        child: ColoredBox(
          color: AppColors.accentLight,
          child: Center(
            child: Text(context.tr('Photo unavailable'), style: const TextStyle(color: AppColors.textSecondary)),
          ),
        ),
      );
    }
    if (_image == null || _aspect == null) {
      return const AspectRatio(
        aspectRatio: 4 / 3,
        child: ColoredBox(color: AppColors.accentLight, child: Center(child: CircularProgressIndicator())),
      );
    }
    final photo = AspectRatio(
      aspectRatio: _aspect!,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image(image: _image!, fit: BoxFit.fill),
          CustomPaint(painter: _BoxPainter(widget.boxes, widget.mainPest)),
        ],
      ),
    );
    if (!widget.fullScreenOnTap) return photo;
    return GestureDetector(onTap: _openFull, child: photo);
  }
}

class _BoxPainter extends CustomPainter {
  final List<DetectionBox> boxes;
  final String? mainPest;
  _BoxPainter(this.boxes, this.mainPest);

  @override
  void paint(Canvas canvas, Size size) {
    for (final b in boxes) {
      final color = b.pest == mainPest ? AppColors.orange : const Color(0xFF0EA5E9);
      final rect = Rect.fromLTRB(b.x1 * size.width, b.y1 * size.height, b.x2 * size.width, b.y2 * size.height);
      canvas.drawRect(
        rect,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
      if (rect.width > 28) {
        final tp = TextPainter(
          text: TextSpan(
            text: '${(b.conf * 100).round()}%',
            style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        final label = Rect.fromLTWH(rect.left, (rect.top - tp.height - 2).clamp(0, size.height), tp.width + 6, tp.height + 2);
        canvas.drawRect(label, Paint()..color = color);
        tp.paint(canvas, Offset(label.left + 3, label.top + 1));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BoxPainter old) => old.boxes != boxes || old.mainPest != mainPest;
}
