// ignore: avoid_web_libraries_in_flutter
import 'dart:async';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import '../services/location_service.dart';

/// Ambil posisi menggunakan Browser Geolocation API secara langsung.
///
/// Keunggulan vs Geolocator di web:
/// - Bisa set [maximumAge] → browser pakai cached position (instant)
/// - Bisa set [timeout] di level PositionOptions → tidak perlu outer .timeout()
/// - Tidak butuh GPS chip; pakai Wi-Fi / IP geolocation
///
/// Mengembalikan null jika browser menolak izin atau tidak bisa dapat lokasi.
Future<LocationResult?> getWebLocation() async {
  final geolocation = html.window.navigator.geolocation;

  // ── 1. Coba posisi cached dulu (maximumAge 2 menit, timeout 5 detik) ──
  try {
    final cached = await _getPosition(
      geolocation,
      enableHighAccuracy: false,
      timeout: 5000,       // ms — browser timeout, bukan Dart
      maximumAge: 120000,  // 2 menit — pakai cached jika ada
    );
    if (cached != null) return _toResult(cached);
  } catch (_) {
    // Tidak ada cached position → lanjut
  }

  // ── 2. Minta posisi baru dengan timeout 10 detik ────────────────────
  try {
    final fresh = await _getPosition(
      geolocation,
      enableHighAccuracy: false,
      timeout: 10000,  // ms
      maximumAge: 0,
    );
    if (fresh != null) return _toResult(fresh);
  } catch (_) {
    // Gagal total
  }

  return null;
}

/// Wrapper Promise → Future untuk navigator.geolocation.getCurrentPosition.
Future<html.Geoposition?> _getPosition(
  html.Geolocation geo, {
  required bool enableHighAccuracy,
  required int timeout,
  required int maximumAge,
}) {
  final completer = Completer<html.Geoposition?>();
  geo.getCurrentPosition(
    (pos) {
      if (!completer.isCompleted) completer.complete(pos);
    },
    (err) {
      if (!completer.isCompleted) completer.complete(null);
    },
    {
      'enableHighAccuracy': enableHighAccuracy,
      'timeout': timeout,
      'maximumAge': maximumAge,
    },
  );
  // Safety net sedikit lebih lama dari browser timeout
  return completer.future.timeout(
    Duration(milliseconds: timeout + 3000),
    onTimeout: () => null,
  );
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
