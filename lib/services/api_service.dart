import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user.dart';

class ApiService {
  // Gunakan 10.0.2.2 jika menggunakan Android Emulator, atau alamat IP WiFi lokal jika menggunakan device riil.
  // Untuk mencoba di device lokal (web/windows desktop), gunakan http://localhost:8000/api
  static const String _baseUrl = 'http://localhost:8000/api';

  /// Base URL untuk mengakses file yang di-upload (storage/app/public).
  static const String storageBaseUrl = 'http://localhost:8000/storage';

  // --- FUNGSI HELPER (PRIBADI) ---

  /// Mengambil token autentikasi dari penyimpanan lokal.
  static Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('auth_token');
  }

  /// Membuat header standar untuk permintaan API yang memerlukan autentikasi.
  static Future<Map<String, String>> _getHeaders() async {
    final token = await _getToken();
    return {
      'Content-Type': 'application/json; charset=UTF-8',
      'Accept': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  /// Header khusus untuk multipart request (tanpa Content-Type, diset otomatis).
  static Future<Map<String, String>> _getMultipartHeaders() async {
    final token = await _getToken();
    return {
      'Accept': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  /// Menangani respons error dari API secara umum.
  static Map<String, dynamic> _handleError(dynamic e) {
    if (e is TimeoutException) {
      return {'success': false, 'message': 'Koneksi timeout. Pastikan server berjalan.'};
    }
    if (e is SocketException) {
      return {'success': false, 'message': 'Tidak dapat terhubung ke server. Periksa koneksi dan alamat IP.'};
    }
    print('Error tidak diketahui di ApiService: $e');
    return {'success': false, 'message': 'Terjadi kesalahan yang tidak diketahui: $e'};
  }

  static String _extractErrorMessage(dynamic decodedBody) {
    if (decodedBody is Map<String, dynamic>) {
      final message = decodedBody['message'];
      if (message is String && message.isNotEmpty) return message;

      final errors = decodedBody['errors'];
      if (errors is Map) {
        for (final entry in errors.entries) {
          final value = entry.value;
          if (value is List && value.isNotEmpty && value.first is String) {
            return value.first as String;
          }
          if (value is String && value.isNotEmpty) return value;
        }
      }
    }
    return 'Terjadi kesalahan saat memproses permintaan.';
  }

  // --- FUNGSI UTAMA (PUBLIK) ---

  /// Mengirim permintaan login ke server.
  static Future<Map<String, dynamic>> login(String email, String password, {String? employeeId}) async {
    try {
      final body = employeeId != null && employeeId.isNotEmpty
          ? {'employee_id': employeeId, 'password': password}
          : {'email': email, 'password': password};
        print(body);
      final response = await http.post(
        Uri.parse('$_baseUrl/login'),
        headers: {
          'Content-Type': 'application/json; charset=UTF-8',
          'Accept': 'application/json',
        },
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 15));

      dynamic data;
      try {
        data = jsonDecode(response.body);
      } catch (_) {
        data = null;
      }
      if (response.statusCode == 200) {
        if (data is! Map<String, dynamic>) {
          return {'success': false, 'message': 'Respons server tidak valid.'};
        }
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('auth_token', data['access_token']);
        return {'success': true, 'user': User.fromJson(data['user'])};
      } else {
        return {'success': false, 'message': _extractErrorMessage(data)};
      }
    } catch (e) {
      return _handleError(e);
    }
  }

  /// Mengirim permintaan logout ke server.
  static Future<void> logout() async {
    try {
      await http.post(
        Uri.parse('$_baseUrl/logout'),
        headers: await _getHeaders(),
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('auth_token');
    } catch (e) {
      print('Error saat logout: $e');
    }
  }

  /// Mengirim data check-in ke server (multipart/form-data).
  /// [deviceType] : 'mobile' | 'web' | 'desktop'
  /// [isMockLocation] : true jika terdeteksi fake GPS (Android)
  /// [photo] : file foto selfie dari kamera depan
  static Future<Map<String, dynamic>> checkIn({
    required double latitude,
    required double longitude,
    String deviceType = 'unknown',
    bool isMockLocation = false,
    XFile? photo,
  }) async {
    try {
      final uri = Uri.parse('$_baseUrl/check-in');
      final request = http.MultipartRequest('POST', uri);
      request.headers.addAll(await _getMultipartHeaders());
      request.fields['latitude'] = latitude.toString();
      request.fields['longitude'] = longitude.toString();
      request.fields['device_type'] = deviceType;
      request.fields['is_mock_location'] = isMockLocation.toString();

      if (photo != null) {
        final bytes = await photo.readAsBytes();
        request.files.add(http.MultipartFile.fromBytes(
          'photo',
          bytes,
          filename: 'checkin_${DateTime.now().millisecondsSinceEpoch}.jpg',
        ));
      }

      final streamed = await request.send().timeout(const Duration(seconds: 30));
      final response = await http.Response.fromStream(streamed);
      print('[checkIn] status=${response.statusCode} body=${response.body}');
      final data = jsonDecode(response.body);
      return {
        'success': response.statusCode == 200 || response.statusCode == 201,
        'message': data['message'] ?? 'Check-in berhasil.',
      };
    } catch (e) {
      print('Error saat check-in: $e');
      return _handleError(e);
    }
  }

  /// Mengirim data check-out ke server (multipart/form-data).
  /// [deviceType] : 'mobile' | 'web' | 'desktop'
  /// [isMockLocation] : true jika terdeteksi fake GPS (Android)
  /// [photo] : file foto selfie dari kamera depan
  static Future<Map<String, dynamic>> checkOut({
    required double latitude,
    required double longitude,
    String deviceType = 'unknown',
    bool isMockLocation = false,
    XFile? photo,
  }) async {
    try {
      final uri = Uri.parse('$_baseUrl/check-out');
      final request = http.MultipartRequest('POST', uri);
      request.headers.addAll(await _getMultipartHeaders());
      request.fields['latitude'] = latitude.toString();
      request.fields['longitude'] = longitude.toString();
      request.fields['device_type'] = deviceType;
      request.fields['is_mock_location'] = isMockLocation.toString();

      if (photo != null) {
        final bytes = await photo.readAsBytes();
        request.files.add(http.MultipartFile.fromBytes(
          'photo',
          bytes,
          filename: 'checkout_${DateTime.now().millisecondsSinceEpoch}.jpg',
        ));
      }

      final streamed = await request.send().timeout(const Duration(seconds: 30));
      final response = await http.Response.fromStream(streamed);
      print('[checkOut] status=${response.statusCode} body=${response.body}');
      final data = jsonDecode(response.body);
      return {
        'success': response.statusCode == 200 || response.statusCode == 201,
        'message': data['message'] ?? 'Check-out berhasil.',
      };
    } catch (e) {
      return _handleError(e);
    }
  }

  /// Mengirim pengajuan izin atau sakit ke server.
  static Future<Map<String, dynamic>> submitLeave(String status, String reason) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/leave'),
        headers: await _getHeaders(),
        body: jsonEncode({'status': status, 'reason': reason}),
      ).timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);
      return {'success': response.statusCode == 200, 'message': data['message']};
    } catch (e) {
      return _handleError(e);
    }
  }

  /// Mengambil data absensi hari ini dari server.
  /// Kembalian: {'data': Map?} jika sukses, {'error': String} jika gagal.
  static Future<Map<String, dynamic>> getTodayAttendance() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/today'),
        headers: await _getHeaders(),
      ).timeout(const Duration(seconds: 15));

      print('[getTodayAttendance] status=${response.statusCode} body=${response.body}');

      dynamic decoded;
      try {
        decoded = jsonDecode(response.body);
      } catch (_) {
        return {'error': 'Respons server tidak valid (bukan JSON). Status: ${response.statusCode}'};
      }

      if (response.statusCode == 200 || response.statusCode == 201) {
        if (decoded is! Map<String, dynamic>) {
          return {'error': 'Format respons tidak dikenali.'};
        }
        // Coba berbagai key yang umum dipakai di Laravel
        final attendance =
            decoded['data'] ?? decoded['attendance'] ?? decoded['absensi'];

        // Jika key ada tapi isinya bukan Map, berarti belum absen (null OK)
        if (attendance != null && attendance is! Map<String, dynamic>) {
          return {'data': null};
        }
        return {'data': attendance as Map<String, dynamic>?};
      }

      // Non-200: kembalikan pesan error dari API
      final errMsg = _extractErrorMessage(decoded);
      return {'error': 'Server error ${response.statusCode}: $errMsg'};
    } catch (e) {
      return {'error': _handleError(e)['message'] as String};
    }
  }
}