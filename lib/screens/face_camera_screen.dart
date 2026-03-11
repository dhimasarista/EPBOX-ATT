import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

/// Full-screen camera with real-time face detection.
///
/// The countdown (3→2→1) only runs while a face is detected.
/// If the face disappears before countdown finishes, it resets.
/// When countdown reaches 0, a photo is captured automatically and returned as [XFile].
class FaceCameraScreen extends StatefulWidget {
  const FaceCameraScreen({super.key});

  @override
  State<FaceCameraScreen> createState() => _FaceCameraScreenState();
}

class _FaceCameraScreenState extends State<FaceCameraScreen> {
  CameraController? _controller;
  bool _isInitialized = false;
  bool _isBusy = false;
  bool _faceDetected = false;
  bool _isCapturing = false;

  int _countdown = 3;
  Timer? _countdownTimer;
  String? _error;

  late final FaceDetector _faceDetector;

  @override
  void initState() {
    super.initState();
    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(performanceMode: FaceDetectorMode.fast),
    );
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() => _error = 'No camera available.');
        return;
      }
      final front = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      _controller = CameraController(
        front,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.nv21
            : ImageFormatGroup.bgra8888,
      );

      await _controller!.initialize();
      if (!mounted) return;

      await _controller!.startImageStream(_processFrame);
      setState(() => _isInitialized = true);
    } catch (e) {
      setState(() => _error = 'Failed to initialize camera:\n$e');
    }
  }

  Future<void> _processFrame(CameraImage image) async {
    if (_isBusy || _isCapturing) return;
    _isBusy = true;

    try {
      final inputImage = _buildInputImage(image);
      if (inputImage == null) {
        _isBusy = false;
        return;
      }

      final faces = await _faceDetector.processImage(inputImage);
      if (!mounted) {
        _isBusy = false;
        return;
      }

      final detected = faces.isNotEmpty;
      if (detected != _faceDetected) {
        setState(() => _faceDetected = detected);
        if (detected) {
          _startCountdown();
        } else {
          _resetCountdown();
        }
      }
    } catch (_) {
      // Abaikan error per-frame
    }

    _isBusy = false;
  }

  InputImage? _buildInputImage(CameraImage image) {
    final camera = _controller?.description;
    if (camera == null) return null;

    final rotation =
        InputImageRotationValue.fromRawValue(camera.sensorOrientation) ??
        InputImageRotation.rotation0deg;

    final format = InputImageFormatValue.fromRawValue(image.format.raw);

    if (format == null) return null;

    // NV21 (Android) dan BGRA8888 (iOS) → single plane
    if (image.planes.length == 1) {
      final plane = image.planes.first;
      return InputImage.fromBytes(
        bytes: plane.bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: rotation,
          format: format,
          bytesPerRow: plane.bytesPerRow,
        ),
      );
    }

    // Fallback YUV420 multi-plane → gabung semua bytes
    final WriteBuffer allBytes = WriteBuffer();
    for (final plane in image.planes) {
      allBytes.putUint8List(plane.bytes);
    }
    return InputImage.fromBytes(
      bytes: allBytes.done().buffer.asUint8List(),
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: InputImageFormat.yuv_420_888,
        bytesPerRow: image.planes.first.bytesPerRow,
      ),
    );
  }

  void _startCountdown() {
    if (_countdownTimer != null) return; // sudah berjalan
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _countdown--);
      if (_countdown <= 0) {
        timer.cancel();
        _countdownTimer = null;
        _captureAndReturn();
      }
    });
  }

  void _resetCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
    if (mounted) setState(() => _countdown = 3);
  }

  Future<void> _captureAndReturn() async {
    if (_isCapturing) return;
    _isCapturing = true;

    try {
      await _controller?.stopImageStream();
      final xfile = await _controller?.takePicture();
      if (mounted) {
        Navigator.of(context).pop(xfile != null ? XFile(xfile.path) : null);
      }
    } catch (e) {
      if (mounted) Navigator.of(context).pop(null);
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _faceDetector.close();
    _controller?.stopImageStream().whenComplete(() => _controller?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(backgroundColor: Colors.black, body: _buildBody());
  }

  Widget _buildBody() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 48),
              const SizedBox(height: 16),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(null),
                child: const Text('Back'),
              ),
            ],
          ),
        ),
      );
    }

    if (!_isInitialized) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: 16),
            Text('Starting camera…', style: TextStyle(color: Colors.white70)),
          ],
        ),
      );
    }

    final size = MediaQuery.of(context).size;
    final frameSize = size.width * 0.72; // square

    return Stack(
      fit: StackFit.expand,
      children: [
        // Live camera preview
        CameraPreview(_controller!),

        // Overlay gelap + oval guide
        CustomPaint(
          painter: _FaceOvalPainter(
            ovalWidth: frameSize,
            ovalHeight: frameSize,
            faceDetected: _faceDetected,
          ),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // push frame slightly above center
                SizedBox(height: size.height * 0.08),

                // Square frame — show countdown inside
                SizedBox(
                  width: frameSize,
                  height: frameSize,
                  child: Center(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      child: _faceDetected
                          ? Text(
                              '$_countdown',
                              key: const ValueKey('countdown'),
                              style: const TextStyle(
                                fontSize: 100,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                                height: 1,
                                shadows: [
                                  Shadow(blurRadius: 16, color: Colors.black54),
                                ],
                              ),
                            )
                          : const _FaceScanIcon(key: ValueKey('icon')),
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // Status badge
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: _faceDetected
                        ? Colors.green.withOpacity(0.85)
                        : Colors.black.withOpacity(0.65),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: _faceDetected
                          ? Colors.greenAccent
                          : Colors.white38,
                      width: 1.2,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _faceDetected
                            ? Icons.face_retouching_natural
                            : Icons.face_outlined,
                        color: Colors.white,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _faceDetected
                            ? 'Face detected'
                            : 'Position your face in the frame',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        // Tombol kembali
        Positioned(
          top: MediaQuery.of(context).padding.top + 8,
          left: 8,
          child: IconButton(
            onPressed: () => Navigator.of(context).pop(null),
            icon: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.black45,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close, color: Colors.white, size: 24),
            ),
          ),
        ),

        // Label instruksi di atas
        Positioned(
          top: MediaQuery.of(context).padding.top + 16,
          left: 0,
          right: 0,
          child: const Center(
            child: Text(
              'Attendance Selfie',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
                shadows: [Shadow(blurRadius: 8, color: Colors.black)],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Custom painter: dark overlay with a rounded-square cutout for face guidance
// ─────────────────────────────────────────────────────────────────────────────
class _FaceOvalPainter extends CustomPainter {
  final double ovalWidth;
  final double ovalHeight;
  final bool faceDetected;

  const _FaceOvalPainter({
    required this.ovalWidth,
    required this.ovalHeight,
    required this.faceDetected,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final centerX = size.width / 2;
    // Shift frame slightly above center
    final centerY = size.height / 2 - size.height * 0.04;

    final frameRect = Rect.fromCenter(
      center: Offset(centerX, centerY),
      width: ovalWidth,
      height: ovalHeight,
    );
    final rRect = RRect.fromRectAndRadius(frameRect, const Radius.circular(16));

    // Dark overlay with square cutout
    final overlayPath = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRRect(rRect)
      ..fillType = PathFillType.evenOdd;

    canvas.drawPath(
      overlayPath,
      Paint()..color = Colors.black.withOpacity(0.55),
    );

    // Border — green when face detected, white otherwise
    canvas.drawRRect(
      rRect,
      Paint()
        ..color = faceDetected ? Colors.greenAccent : Colors.white60
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
  }

  @override
  bool shouldRepaint(_FaceOvalPainter old) => old.faceDetected != faceDetected;
}

// ─────────────────────────────────────────────────────────────────────────────
// Animated face-scan icon shown inside the frame when no face is detected
// ─────────────────────────────────────────────────────────────────────────────
class _FaceScanIcon extends StatefulWidget {
  const _FaceScanIcon({super.key});

  @override
  State<_FaceScanIcon> createState() => _FaceScanIconState();
}

class _FaceScanIconState extends State<_FaceScanIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _opacity;
  late final Animation<double> _scale;

  static const _svg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
  <path fill="currentColor"
    d="M9.367 2.25H9.4a.75.75 0 0 1 0 1.5c-1.132 0-1.937 0-2.566.052c-.62.05-1.005.147-1.31.302
       a3.25 3.25 0 0 0-1.42 1.42c-.155.305-.251.69-.302 1.31c-.051.63-.052 1.434-.052 2.566
       a.75.75 0 0 1-1.5 0v-.033c0-1.092 0-1.958.057-2.655c.058-.714.18-1.317.46-1.868
       a4.75 4.75 0 0 1 2.077-2.076c.55-.281 1.154-.403 1.868-.461c.697-.057 1.563-.057 2.655-.057
    m7.8 1.552c-.63-.051-1.435-.052-2.567-.052a.75.75 0 0 1 0-1.5h.033c1.092 0 1.958 0 2.655.057
       c.714.058 1.317.18 1.869.46a4.75 4.75 0 0 1 2.075 2.077c.281.55.403 1.154.461 1.868
       c.057.697.057 1.563.057 2.655V9.4a.75.75 0 0 1-1.5 0c0-1.132 0-1.937-.052-2.566
       c-.05-.62-.147-1.005-.302-1.31a3.25 3.25 0 0 0-1.42-1.42c-.305-.155-.69-.251-1.31-.302
    M8 7.25a.75.75 0 0 1 .75.75v1.5a.75.75 0 0 1-1.5 0V8A.75.75 0 0 1 8 7.25
    m8 0a.75.75 0 0 1 .75.75v1.5a.75.75 0 0 1-1.5 0V8a.75.75 0 0 1 .75-.75
    M12 9a.75.75 0 0 1 .75.75v4a.75.75 0 0 1-.75.75h-1a.75.75 0 0 1 0-1.5h.25V9.75A.75.75 0 0 1 12 9
    m-9 4.85a.75.75 0 0 1 .75.75c0 1.133 0 1.937.052 2.566c.05.62.147 1.005.302 1.31
       a3.25 3.25 0 0 0 1.42 1.42c.305.155.69.251 1.31.302c.63.051 1.434.052 2.566.052
       a.75.75 0 0 1 0 1.5h-.033c-1.092 0-1.958 0-2.655-.057c-.714-.058-1.317-.18-1.868-.46
       a4.75 4.75 0 0 1-2.076-2.076c-.281-.552-.403-1.155-.461-1.869c-.057-.697-.057-1.563-.057-2.655
       V14.6a.75.75 0 0 1 .75-.75
    m18 0a.75.75 0 0 1 .75.75v.033c0 1.092 0 1.958-.057 2.655c-.058.714-.18 1.317-.46 1.869
       a4.75 4.75 0 0 1-2.076 2.075c-.552.281-1.155.403-1.869.461c-.697.057-1.563.057-2.655.057
       H14.6a.75.75 0 0 1 0-1.5c1.133 0 1.937 0 2.566-.052c.62-.05 1.005-.147 1.31-.302
       a3.25 3.25 0 0 0 1.42-1.42c.155-.305.251-.69.302-1.31c.051-.63.052-1.434.052-2.566
       a.75.75 0 0 1 .75-.75
    M8.47 15.97a.75.75 0 0 1 1.06 0c.578.577 1.494.905 2.47.905s1.892-.328 2.47-.905
       a.75.75 0 1 1 1.06 1.06c-.922.923-2.256 1.345-3.53 1.345s-2.608-.422-3.53-1.345
       a.75.75 0 0 1 0-1.06"/>
</svg>''';

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _opacity = Tween<double>(
      begin: 0.35,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
    _scale = Tween<double>(
      begin: 0.88,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Opacity(
        opacity: _opacity.value,
        child: Transform.scale(
          scale: _scale.value,
          child: SvgPicture.string(
            _svg,
            width: 96,
            height: 96,
            colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
          ),
        ),
      ),
    );
  }
}
