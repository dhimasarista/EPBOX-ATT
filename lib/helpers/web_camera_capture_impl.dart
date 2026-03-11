// ignore: avoid_web_libraries_in_flutter
import 'dart:async';
import 'dart:convert';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:js_util' as js_util;
import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';

/// Opens the browser camera with real-time face detection via MediaPipe JS.
///
/// - Countdown (3→2→1) only runs while a face is detected.
/// - If the face disappears, the countdown resets.
/// - Uses window.mpDetectFaces() injected in web/index.html (MediaPipe CDN).
/// - Returns `null` if camera permission is denied, user closes the overlay, or an error occurs.
Future<XFile?> captureWebPhoto() async {
  // ── 1. Minta akses kamera ──────────────────────────────────────────────
  html.MediaStream? stream;
  try {
    stream = await html.window.navigator.mediaDevices?.getUserMedia({
      'video': {
        'facingMode': 'user',
        'width': {'ideal': 640},
        'height': {'ideal': 480},
      },
      'audio': false,
    });
  } catch (_) {
    return null;
  }
  if (stream == null) return null;

  // ── 2. Wait for MediaPipe to finish loading (max 8 s) ────────────────
  final bool mpReady = await _waitForMp();

  // ── 3. Build overlay HTML ─────────────────────────────────────────────
  // Inject pulse keyframe once into document head
  if (html.document.getElementById('_faceScanKf') == null) {
    (html.document.head!.append(
      html.StyleElement()
        ..id = '_faceScanKf'
        ..text = '''
        @keyframes _faceScanPulse {
          0%, 100% { opacity: 0.35; transform: translate(-50%, -50%) scale(0.88); }
          50%       { opacity: 1.0;  transform: translate(-50%, -50%) scale(1.00); }
        }
      ''',
    ));
  }

  final overlay = html.DivElement()
    ..id = '_web_cam_overlay'
    ..style.cssText = '''
      position: fixed; top: 0; left: 0;
      width: 100vw; height: 100vh;
      background: rgba(0,0,0,0.92);
      z-index: 99999;
      display: flex; flex-direction: column;
      align-items: center; justify-content: center;
      font-family: sans-serif;
      transition: background 0.15s ease;
    ''';

  // Frame container — everything overlaid on the camera is relative to this
  final frameContainer = html.DivElement()
    ..style.cssText = '''
      position: relative;
      width: min(72vw, 320px);
      height: min(72vw, 320px);
      flex-shrink: 0;
    ''';

  // Oval guide (CSS border-radius) — covers the entire frame
  final ovalGuide = html.DivElement()
    ..style.cssText = '''
      position: absolute;
      inset: 0;
      border: 2.5px solid rgba(255,255,255,0.5);
      border-radius: 16px;
      pointer-events: none;
      transition: border-color 0.3s ease;
    ''';

  // Close button (×)
  final closeBtn = html.ButtonElement()
    ..text = '×'
    ..style.cssText = '''
      position: absolute; top: 16px; left: 16px;
      background: rgba(0,0,0,0.45); color: white;
      border: none; border-radius: 50%;
      width: 40px; height: 40px;
      font-size: 24px; line-height: 1;
      cursor: pointer;
    ''';

  // Title label
  final titleLabel = html.DivElement()
    ..text = 'Attendance Selfie'
    ..style.cssText = '''
      position: absolute; top: 20px;
      width: 100%; text-align: center;
      color: white; font-size: 16px; font-weight: 600;
    ''';

  final video = html.VideoElement()
    ..autoplay = true
    ..muted = true
    ..style.cssText = '''
      width: 100%;
      height: 100%;
      object-fit: cover;
      border-radius: 16px;
      transform: scaleX(-1);
      display: block;
    ''';

  final countdownText = html.DivElement()
    ..style.cssText = '''
      position: absolute;
      top: 50%; left: 50%;
      transform: translate(-50%, -50%);
      font-size: 96px; font-weight: 900;
      color: white; line-height: 1;
      text-shadow: 0 4px 24px rgba(0,0,0,0.7);
      pointer-events: none;
    ''';

  // Face-scan icon (shown when no face is detected)
  final faceScanIcon = html.DivElement()
    ..style.cssText = '''
      position: absolute;
      top: 50%; left: 50%;
      transform: translate(-50%, -50%);
      width: 96px; height: 96px;
      pointer-events: none;
      display: block;
      animation: _faceScanPulse 1.4s ease-in-out infinite;
    '''
    ..setInnerHtml(
      '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"
            width="96" height="96">
        <path fill="white"
          d="M9.367 2.25H9.4a.75.75 0 0 1 0 1.5c-1.132 0-1.937 0-2.566.052
             c-.62.05-1.005.147-1.31.302a3.25 3.25 0 0 0-1.42 1.42
             c-.155.305-.251.69-.302 1.31c-.051.63-.052 1.434-.052 2.566
             a.75.75 0 0 1-1.5 0v-.033c0-1.092 0-1.958.057-2.655
             c.058-.714.18-1.317.46-1.868a4.75 4.75 0 0 1 2.077-2.076
             c.55-.281 1.154-.403 1.868-.461c.697-.057 1.563-.057 2.655-.057
             m7.8 1.552c-.63-.051-1.435-.052-2.567-.052a.75.75 0 0 1 0-1.5h.033
             c1.092 0 1.958 0 2.655.057c.714.058 1.317.18 1.869.46
             a4.75 4.75 0 0 1 2.075 2.077c.281.55.403 1.154.461 1.868
             c.057.697.057 1.563.057 2.655V9.4a.75.75 0 0 1-1.5 0
             c0-1.132 0-1.937-.052-2.566c-.05-.62-.147-1.005-.302-1.31
             a3.25 3.25 0 0 0-1.42-1.42c-.305-.155-.69-.251-1.31-.302
             M8 7.25a.75.75 0 0 1 .75.75v1.5a.75.75 0 0 1-1.5 0V8A.75.75 0 0 1 8 7.25
             m8 0a.75.75 0 0 1 .75.75v1.5a.75.75 0 0 1-1.5 0V8a.75.75 0 0 1 .75-.75
             M12 9a.75.75 0 0 1 .75.75v4a.75.75 0 0 1-.75.75h-1a.75.75 0 0 1 0-1.5
             h.25V9.75A.75.75 0 0 1 12 9
             m-9 4.85a.75.75 0 0 1 .75.75c0 1.133 0 1.937.052 2.566
             c.05.62.147 1.005.302 1.31a3.25 3.25 0 0 0 1.42 1.42
             c.305.155.69.251 1.31.302c.63.051 1.434.052 2.566.052
             a.75.75 0 0 1 0 1.5h-.033c-1.092 0-1.958 0-2.655-.057
             c-.714-.058-1.317-.18-1.868-.46a4.75 4.75 0 0 1-2.076-2.076
             c-.281-.552-.403-1.155-.461-1.869c-.057-.697-.057-1.563-.057-2.655
             V14.6a.75.75 0 0 1 .75-.75
             m18 0a.75.75 0 0 1 .75.75v.033c0 1.092 0 1.958-.057 2.655
             c-.058.714-.18 1.317-.46 1.869a4.75 4.75 0 0 1-2.076 2.075
             c-.552.281-1.155.403-1.869.461c-.697.057-1.563.057-2.655.057
             H14.6a.75.75 0 0 1 0-1.5c1.133 0 1.937 0 2.566-.052
             c.62-.05 1.005-.147 1.31-.302a3.25 3.25 0 0 0 1.42-1.42
             c.155-.305.251-.69.302-1.31c.051-.63.052-1.434.052-2.566
             a.75.75 0 0 1 .75-.75
             M8.47 15.97a.75.75 0 0 1 1.06 0c.578.577 1.494.905 2.47.905
             s1.892-.328 2.47-.905a.75.75 0 1 1 1.06 1.06
             c-.922.923-2.256 1.345-3.53 1.345s-2.608-.422-3.53-1.345
             a.75.75 0 0 1 0-1.06"/>
      </svg>''',
      treeSanitizer: html.NodeTreeSanitizer.trusted,
    );

  // Status badge bawah
  final statusBadge = html.DivElement()
    ..style.cssText = '''
      margin-top: 16px;
      padding: 10px 20px;
      background: rgba(0,0,0,0.65);
      border: 1.2px solid rgba(255,255,255,0.3);
      border-radius: 24px;
      color: white; font-size: 14px; font-weight: 600;
      display: flex; align-items: center; gap: 8px;
      transition: background 0.3s ease, border-color 0.3s ease;
    ''';

  final statusIcon = html.SpanElement()..text = '○';
  final statusMsg = html.SpanElement()
    ..text = 'Position your face in the frame';
  statusBadge
    ..append(statusIcon)
    ..append(statusMsg);

  frameContainer
    ..append(video)
    ..append(ovalGuide)
    ..append(faceScanIcon)
    ..append(countdownText);

  overlay
    ..append(titleLabel)
    ..append(closeBtn)
    ..append(frameContainer)
    ..append(statusBadge);
  html.document.body!.append(overlay);

  // ── 4. Attach stream to video ─────────────────────────────────────────
  video.srcObject = stream;
  try {
    await video.play();
  } catch (_) {}
  await Future.delayed(const Duration(milliseconds: 400));

  // ── 5. State machine: face gate → countdown → capture ─────────────────────
  final completer = Completer<XFile?>();
  int countdown = 3;
  bool facePresent = false;
  Timer? countdownTimer;
  Timer? detectTimer;

  void cleanup() {
    detectTimer?.cancel();
    countdownTimer?.cancel();
    _cleanupStream(stream);
    overlay.remove();
  }

  // Close button (×)
  closeBtn.onClick.listen((_) {
    if (!completer.isCompleted) {
      cleanup();
      completer.complete(null);
    }
  });

  void updateBadge() {
    if (facePresent) {
      statusBadge.style.background = 'rgba(34,197,94,0.85)';
      statusBadge.style.borderColor = '#4ade80';
      statusIcon.text = '◉';
      statusMsg.text = 'Face detected';
      ovalGuide.style.borderColor = '#4ade80';
      countdownText.text = '$countdown';
      faceScanIcon.style.display = 'none';
    } else {
      statusBadge.style.background = 'rgba(0,0,0,0.65)';
      statusBadge.style.borderColor = 'rgba(255,255,255,0.3)';
      statusIcon.text = '○';
      statusMsg.text = 'Position your face in the frame';
      ovalGuide.style.borderColor = 'rgba(255,255,255,0.5)';
      countdownText.text = '';
      faceScanIcon.style.display = 'block';
    }
  }

  Future<void> captureNow() async {
    if (completer.isCompleted) return;
    detectTimer?.cancel();
    countdownTimer?.cancel();

    // Flash white
    overlay.style.background = 'white';
    await Future.delayed(const Duration(milliseconds: 180));

    // Capture frame to canvas
    final w = video.videoWidth > 0 ? video.videoWidth : 640;
    final h = video.videoHeight > 0 ? video.videoHeight : 480;
    final canvas = html.CanvasElement(width: w, height: h);
    final ctx = canvas.context2D;
    ctx
      ..translate(w.toDouble(), 0)
      ..scale(-1, 1)
      ..drawImage(video, 0, 0);

    cleanup();

    final dataUrl = canvas.toDataUrl('image/jpeg');
    final commaIdx = dataUrl.indexOf(',');
    if (commaIdx < 0) {
      completer.complete(null);
      return;
    }
    Uint8List bytes;
    try {
      bytes = base64Decode(dataUrl.substring(commaIdx + 1));
    } catch (_) {
      completer.complete(null);
      return;
    }

    completer.complete(
      XFile.fromData(
        bytes,
        mimeType: 'image/jpeg',
        name: 'capture_${DateTime.now().millisecondsSinceEpoch}.jpg',
      ),
    );
  }

  void startCountdown() {
    if (countdownTimer != null) return;
    countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (completer.isCompleted) {
        t.cancel();
        return;
      }
      if (!facePresent) {
        // Face disappeared → reset countdown
        t.cancel();
        countdownTimer = null;
        countdown = 3;
        updateBadge();
        return;
      }
      countdown--;
      updateBadge();
      if (countdown <= 0) {
        t.cancel();
        countdownTimer = null;
        captureNow();
      }
    });
  }

  if (mpReady) {
    // Real-time face detection via MediaPipe (every 500 ms)
    detectTimer = Timer.periodic(const Duration(milliseconds: 500), (t) async {
      if (completer.isCompleted) {
        t.cancel();
        return;
      }
      try {
        final int count = await js_util.promiseToFuture<int>(
          js_util.callMethod(js_util.globalThis, 'mpDetectFaces', [video])
              as Object,
        );
        final detected = count > 0;
        if (detected != facePresent) {
          facePresent = detected;
          updateBadge();
          if (detected) {
            startCountdown();
          } else {
            countdownTimer?.cancel();
            countdownTimer = null;
            countdown = 3;
            updateBadge();
          }
        }
      } catch (_) {
        // Per-frame failure — ignore, wait for next tick
      }
    });
  } else {
    // MediaPipe failed to load (e.g. offline / CDN blocked).
    statusBadge.style.background = 'rgba(220,38,38,0.85)';
    statusBadge.style.borderColor = '#f87171';
    statusIcon.text = '✕';
    statusMsg.text = 'Face detection unavailable';

    final errorNote = html.DivElement()
      ..text = 'Could not load MediaPipe. Check your internet connection.'
      ..style.cssText = '''
        margin-top: 12px;
        color: rgba(255,255,255,0.7);
        font-size: 13px; text-align: center; max-width: 320px;
      ''';
    overlay.append(errorNote);
    // Overlay stays open — user closes with ×.
  }

  return completer.future;
}

/// Waits up to [maxWait] for MediaPipe to finish loading.
Future<bool> _waitForMp({Duration maxWait = const Duration(seconds: 8)}) async {
  final deadline = DateTime.now().add(maxWait);
  while (DateTime.now().isBefore(deadline)) {
    final ready = js_util.getProperty<bool>(
      js_util.globalThis,
      '_mpFaceDetectorReady',
    );
    if (ready) return true;
    await Future.delayed(const Duration(milliseconds: 200));
  }
  return false;
}

void _cleanupStream(html.MediaStream? stream) {
  stream?.getTracks().forEach((t) => t.stop());
}
