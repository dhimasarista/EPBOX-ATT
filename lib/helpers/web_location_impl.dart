// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import '../services/location_service.dart';

/// Ambil posisi menggunakan Browser Geolocation API secara langsung.
///
/// dart:html binds getCurrentPosition as Future<Geoposition> with named
/// Duration params — jauh lebih mudah dari callback JS.
///
/// Strategi:
///   1. Coba cached position (maximumAge=2 menit, timeout=5 detik) → instant
///   2. Jika tidak ada cache, minta posisi baru (timeout=10 detik)
///
/// Mengembalikan null jika izin ditolak atau gagal total.
Future<LocationResult?> getWebLocation() async {
  final geo = html.window.navigator.geolocation;

  // ── 1. Pakai cached position jika segar (< 2 menit) ──────────────────
  try {
    final pos = await geo.getCurrentPosition(
      enableHighAccuracy: false,
      timeout: const Duration(seconds: 5),
      maximumAge: const Duration(minutes: 2),
    );
    return _toResult(pos);
  } catch (_) {
    // Tidak ada cache atau timeout → lanjut ke fresh request
  }

  // ── 2. Fresh position request ─────────────────────────────────────────
  try {
    final pos = await geo.getCurrentPosition(
      enableHighAccuracy: false,
      timeout: const Duration(seconds: 10),
      maximumAge: Duration.zero,
    );
    return _toResult(pos);
  } catch (_) {
    return null; // Izin ditolak atau sinyal tidak ada
  }
}

LocationResult _toResult(html.Geoposition pos) {
  return LocationResult(
    latitude: (pos.coords!.latitude ?? 0).toDouble(),
    longitude: (pos.coords!.longitude ?? 0).toDouble(),
    deviceType: 'web',
    isMockLocation: false,
    accuracy: pos.coords!.accuracy?.toDouble(),
  );
}
