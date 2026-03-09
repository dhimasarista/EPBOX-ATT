import 'dart:async';
import 'package:flutter/foundation.dart'; // kIsWeb, defaultTargetPlatform
import 'package:geolocator/geolocator.dart';
import '../helpers/web_location.dart';

// ─────────────────────────────────────────────────────────────────
// Enum: status ketersediaan lokasi
// ─────────────────────────────────────────────────────────────────
enum LocationStatus {
  available,
  serviceDisabled,     // GPS / Location Service mati di OS
  permissionDenied,    // User menolak izin (bisa diminta ulang)
  permissionDeniedForever, // User menolak permanen → harus buka Settings
}

// ─────────────────────────────────────────────────────────────────
// Model kembalian availability check
// ─────────────────────────────────────────────────────────────────
class LocationAvailability {
  final LocationStatus status;
  final String message;

  const LocationAvailability({required this.status, required this.message});

  bool get isAvailable => status == LocationStatus.available;
}

// ─────────────────────────────────────────────────────────────────
// Model hasil pengambilan posisi
// ─────────────────────────────────────────────────────────────────
class LocationResult {
  final double latitude;
  final double longitude;

  /// 'mobile' | 'web' | 'desktop'
  final String deviceType;

  /// true jika aplikasi mendeteksi fake/mock GPS (Android only).
  /// Selalu false pada web & desktop karena tidak dapat dideteksi.
  final bool isMockLocation;

  /// Akurasi dalam meter (null jika tidak tersedia)
  final double? accuracy;

  const LocationResult({
    required this.latitude,
    required this.longitude,
    required this.deviceType,
    required this.isMockLocation,
    this.accuracy,
  });
}

// ─────────────────────────────────────────────────────────────────
// LocationService – utility class (semua method static)
// ─────────────────────────────────────────────────────────────────
class LocationService {
  // ------------------------------------------------------------------
  // Deteksi tipe perangkat (mobile | web | desktop)
  // Menggunakan defaultTargetPlatform agar aman di semua platform.
  // ------------------------------------------------------------------
  static String getDeviceType() {
    if (kIsWeb) return 'web';
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
        return 'mobile';
      case TargetPlatform.windows:
      case TargetPlatform.macOS:
      case TargetPlatform.linux:
        return 'desktop';
      default:
        return 'unknown';
    }
  }

  // ------------------------------------------------------------------
  // Cek ketersediaan layanan lokasi + izin secara bertahap.
  // Jika izin belum diberikan, metode ini MEMINTA izin ke pengguna.
  // ------------------------------------------------------------------
  static Future<LocationAvailability> checkAndRequestPermission() async {
    // 1. Apakah Location Service aktif di OS?
    bool serviceEnabled;
    try {
      serviceEnabled = await Geolocator.isLocationServiceEnabled()
          .timeout(const Duration(seconds: 5), onTimeout: () => false);
    } catch (_) {
      serviceEnabled = false;
    }
    if (!serviceEnabled) {
      return const LocationAvailability(
        status: LocationStatus.serviceDisabled,
        message:
            'Layanan lokasi (GPS) tidak aktif.\n\nAktifkan GPS di pengaturan perangkat Anda, lalu coba lagi.',
      );
    }

    // 2. Cek status izin saat ini
    LocationPermission permission = await Geolocator.checkPermission();

    // 3. Jika belum pernah diminta, minta sekarang
    if (permission == LocationPermission.denied) {
      try {
        permission = await Geolocator.requestPermission()
            .timeout(const Duration(seconds: 30), onTimeout: () => LocationPermission.denied);
      } catch (_) {
        permission = LocationPermission.denied;
      }
    }

    // 4. Evaluasi hasil izin
    switch (permission) {
      case LocationPermission.denied:
        return const LocationAvailability(
          status: LocationStatus.permissionDenied,
          message:
              'Izin akses lokasi ditolak.\n\nIzin lokasi diperlukan untuk fitur absensi.',
        );
      case LocationPermission.deniedForever:
        return const LocationAvailability(
          status: LocationStatus.permissionDeniedForever,
          message:
              'Izin lokasi ditolak secara permanen.\n\nSilakan buka Pengaturan → Aplikasi → Izin Lokasi dan aktifkan secara manual.',
        );
      default:
        // whileInUse atau always → OK
        return const LocationAvailability(
          status: LocationStatus.available,
          message: 'Lokasi tersedia.',
        );
    }
  }

  // ------------------------------------------------------------------
  // Ambil posisi saat ini.
  // - Web    : gunakan dart:html Geolocation API langsung (ada maximumAge
  //            + timeout di PositionOptions → jauh lebih cepat & andal)
  // - Mobile : Geolocator high accuracy + fallback medium
  // - Desktop: Geolocator low accuracy
  // Throws Exception jika layanan/izin tidak tersedia atau semua upaya gagal.
  // ------------------------------------------------------------------
  static Future<LocationResult> getCurrentLocation() async {
    final availability = await checkAndRequestPermission();
    if (!availability.isAvailable) {
      throw Exception(availability.message);
    }

    final deviceType = getDeviceType();
    final isMobile = deviceType == 'mobile';

    // ── Web: gunakan Browser Geolocation API langsung ─────────────────
    if (kIsWeb) {
      final result = await getWebLocation();
      if (result != null) return result;
      throw Exception(
          'Tidak dapat mendapatkan lokasi.\nPastikan izin lokasi browser diizinkan dan coba lagi.');
    }

    // ── Langkah 1: Cek posisi terakhir yang diketahui (instant) ───────
    // Jika masih segar (< 2 menit), langsung pakai.
    try {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null) {
        final age = DateTime.now().difference(last.timestamp);
        if (age.inMinutes < 2) return _toResult(last, deviceType);
      }
    } catch (_) {}

    // ── Langkah 2: getCurrentPosition akurasi utama ───────────────────
    //   Mobile  : high  (GPS chip), timeout 35 detik
    //   Desktop : low   (Wi-Fi), timeout 15 detik
    final primaryAccuracy =
        isMobile ? LocationAccuracy.high : LocationAccuracy.low;
    final primaryTimeout =
        isMobile ? const Duration(seconds: 35) : const Duration(seconds: 15);

    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: primaryAccuracy,
        timeLimit: primaryTimeout,
      ).timeout(
        Duration(seconds: primaryTimeout.inSeconds + 5),
        onTimeout: () => throw TimeoutException('primary_timeout'),
      );
      return _toResult(position, deviceType);
    } on TimeoutException {
      // lanjut ke fallback
    } on Exception {
      // lanjut ke fallback
    }

    // ── Langkah 3: Fallback ke akurasi lebih rendah ───────────────────
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 20),
      ).timeout(
        const Duration(seconds: 25),
        onTimeout: () => throw TimeoutException(
            'Tidak dapat mendapatkan lokasi. Pastikan GPS aktif dan sinyal cukup.'),
      );
      return _toResult(position, deviceType);
    } catch (e) {
      if (e is TimeoutException) rethrow;
      throw Exception('Gagal mendapatkan lokasi: $e');
    }
  }

  /// Konversi [Position] ke [LocationResult].
  static LocationResult _toResult(Position position, String deviceType) {
    bool isMock = false;
    try {
      isMock = position.isMocked;
    } catch (_) {}
    return LocationResult(
      latitude: position.latitude,
      longitude: position.longitude,
      deviceType: deviceType,
      isMockLocation: isMock,
      accuracy: position.accuracy,
    );
  }

  // ------------------------------------------------------------------
  // Buka halaman pengaturan lokasi OS (berguna jika izin ditolak permanen)
  // ------------------------------------------------------------------
  static Future<void> openLocationSettings() async {
    await Geolocator.openLocationSettings();
  }

  // ------------------------------------------------------------------
  // Buka halaman pengaturan aplikasi (untuk izin yang ditolak permanen)
  // ------------------------------------------------------------------
  static Future<void> openAppSettings() async {
    await Geolocator.openAppSettings();
  }

  // ------------------------------------------------------------------
  // Stream posisi live – cocok untuk widget yang selalu update.
  // Melempar Exception jika izin tidak tersedia.
  // ------------------------------------------------------------------
  static Stream<LocationResult> getLocationStream() async* {
    final avail = await checkAndRequestPermission();
    if (!avail.isAvailable) {
      throw Exception(avail.message);
    }

    final deviceType = getDeviceType();
    final isMobile = deviceType == 'mobile';
    final desiredAccuracy = isMobile
        ? LocationAccuracy.high
        : LocationAccuracy.lowest;

    final posStream = Geolocator.getPositionStream(
      locationSettings: LocationSettings(accuracy: desiredAccuracy),
    );

    await for (final position in posStream) {
      yield _toResult(position, deviceType);
    }
  }
}
