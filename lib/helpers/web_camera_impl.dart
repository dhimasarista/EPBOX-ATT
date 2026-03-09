// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

/// Meminta izin kamera di browser via getUserMedia sebelum image_picker dipanggil.
/// Ini memastikan browser menampilkan dialog izin kamera (bukan file picker).
Future<void> requestWebCameraPermission() async {
  try {
    final stream = await html.window.navigator.mediaDevices?.getUserMedia({
      'video': {'facingMode': 'user'},
      'audio': false,
    });
    // Langsung stop semua track — kita hanya butuh izin, bukan stream-nya.
    stream?.getTracks().forEach((track) => track.stop());
  } catch (_) {
    // Permission ditolak atau tidak tersedia — lanjutkan saja,
    // image_picker akan menampilkan pesan error sendiri.
  }
}
