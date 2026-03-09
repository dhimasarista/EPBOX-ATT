// ignore: avoid_web_libraries_in_flutter
import 'dart:async';
import 'dart:convert';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';

/// Membuka kamera browser, menampilkan overlay countdown 3→2→1,
/// mengambil foto otomatis saat countdown selesai, lalu mengembalikan XFile.
///
/// Seluruh proses terjadi di layer HTML/JS sehingga tidak bergantung pada
/// [ImagePicker] (yang membutuhkan user-gesture aktif saat .click() dipanggil).
///
/// Mengembalikan `null` jika izin kamera ditolak atau terjadi error.
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
    return null; // Izin ditolak atau tidak ada kamera
  }
  if (stream == null) return null;

  // ── 2. Buat overlay HTML ───────────────────────────────────────────────
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

  final video = html.VideoElement()
    ..autoplay = true
    ..muted = true
    ..style.cssText = '''
      max-width: min(100%, 420px);
      max-height: 60vh;
      border-radius: 16px;
      transform: scaleX(-1);
      box-shadow: 0 8px 32px rgba(0,0,0,0.6);
    ''';

  final countdownText = html.DivElement()
    ..style.cssText = '''
      font-size: 96px; font-weight: 900;
      color: white; line-height: 1;
      margin-top: 24px;
      text-shadow: 0 4px 24px rgba(0,0,0,0.7);
      transition: transform 0.1s ease;
    ''';

  final hintText = html.DivElement()
    ..text = 'Siap untuk foto absensi…'
    ..style.cssText = '''
      color: rgba(255,255,255,0.75);
      font-size: 16px; margin-top: 8px;
    ''';

  overlay
    ..append(video)
    ..append(countdownText)
    ..append(hintText);
  html.document.body!.append(overlay);

  // ── 3. Pasang stream ke video ──────────────────────────────────────────
  video.srcObject = stream;
  try {
    await video.play();
  } catch (_) {}
  // Tunggu metadata video tersedia
  await Future.delayed(const Duration(milliseconds: 400));

  // ── 4. Countdown 3 → 2 → 1 ────────────────────────────────────────────
  for (int i = 3; i >= 1; i--) {
    if (!html.document.body!.contains(overlay)) {
      _cleanupStream(stream);
      return null;
    }
    countdownText
      ..text = '$i'
      ..style.transform = 'scale(1.4)';
    await Future.delayed(const Duration(milliseconds: 80));
    countdownText.style.transform = 'scale(1.0)';
    await Future.delayed(const Duration(milliseconds: 820));
  }

  // ── 5. Flash putih sesaat sebelum capture ──────────────────────────────
  overlay.style.background = 'white';
  await Future.delayed(const Duration(milliseconds: 180));

  // ── 6. Ambil frame ke canvas ───────────────────────────────────────────
  final w = video.videoWidth > 0 ? video.videoWidth : 640;
  final h = video.videoHeight > 0 ? video.videoHeight : 480;
  final canvas = html.CanvasElement(width: w, height: h);
  final ctx = canvas.context2D;
  // Mirror horizontal (selfie style)
  ctx
    ..translate(w.toDouble(), 0)
    ..scale(-1, 1)
    ..drawImage(video, 0, 0);

  // Bersihkan
  _cleanupStream(stream);
  overlay.remove();

  // ── 7. Canvas → Uint8List via toDataUrl (selalu tersedia di dart:html) ──
  // toBlob() tidak dibind dengan benar di dart:html, pakai toDataUrl sebagai
  // gantinya — sinkron, tidak butuh callback, cross-browser.
  final dataUrl = canvas.toDataUrl('image/jpeg');
  // Format: "data:image/jpeg;base64,<data>"
  final commaIdx = dataUrl.indexOf(',');
  if (commaIdx < 0) return null;
  final Uint8List bytes;
  try {
    bytes = base64Decode(dataUrl.substring(commaIdx + 1));
  } catch (_) {
    return null;
  }

  return XFile.fromData(
    bytes,
    mimeType: 'image/jpeg',
    name: 'capture_${DateTime.now().millisecondsSinceEpoch}.jpg',
  );
}

void _cleanupStream(html.MediaStream? stream) {
  stream?.getTracks().forEach((t) => t.stop());
}
