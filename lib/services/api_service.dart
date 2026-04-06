import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user.dart';
import 'package:flutter/foundation.dart';

class ApiService {
  static const String _authTokenKey = 'auth_token';
  static const String _authUserKey = 'auth_user';

  static const String _baseUrl = false
      ? 'http://127.0.0.1:8000/api'
      : 'https://prime.pre-test.my.id/api';

  static const String storageBaseUrl = false
      ? 'http://127.0.0.1:8000/api/storage'
      : 'https://prime.pre-test.my.id/api/storage';

  static Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_authTokenKey);
  }

  static Future<bool> hasSavedSession() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_authTokenKey);
    final userJson = prefs.getString(_authUserKey);
    return token != null &&
        token.isNotEmpty &&
        userJson != null &&
        userJson.isNotEmpty;
  }

  static Future<User?> getSavedUser() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_authUserKey);
    if (raw == null || raw.isEmpty) return null;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return User.fromJson(decoded);
      }
    } catch (_) {}

    return null;
  }

  static Future<Map<String, String>> _getHeaders() async {
    final token = await _getToken();
    return {
      'Content-Type': 'application/json; charset=UTF-8',
      'Accept': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  static Future<Map<String, String>> _getMultipartHeaders() async {
    final token = await _getToken();
    return {'Accept': 'application/json', 'Authorization': 'Bearer $token'};
  }

  static Map<String, dynamic> _handleError(dynamic e) {
    if (e is TimeoutException) {
      return {
        'success': false,
        'message': 'Connection timeout. Make sure the server is running.',
      };
    }
    if (e is SocketException) {
      return {
        'success': false,
        'message':
            'Cannot connect to server. Check your connection and server address.',
      };
    }
    print('Error tidak diketahui di ApiService: $e');
    return {
      'success': false,
      'message': 'Terjadi kesalahan yang tidak diketahui: $e',
    };
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

  static Future<Map<String, dynamic>> login(
    String email,
    String password, {
    String? employeeId,
  }) async {
    try {
      final body = employeeId != null && employeeId.isNotEmpty
          ? {'employee_id': employeeId, 'password': password}
          : {'email': email, 'password': password};
      final response = await http
          .post(
            Uri.parse('$_baseUrl/login'),
            headers: {
              'Content-Type': 'application/json; charset=UTF-8',
              'Accept': 'application/json',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 15));

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
        final user = User.fromJson(data['user']);

        await prefs.setString(_authTokenKey, data['access_token']);
        await prefs.setString(_authUserKey, jsonEncode(user.toJson()));

        return {'success': true, 'user': user};
      } else {
        return {'success': false, 'message': _extractErrorMessage(data)};
      }
    } catch (e) {
      return _handleError(e);
    }
  }

  static Future<void> logout() async {
    try {
      await http.post(
        Uri.parse('$_baseUrl/logout'),
        headers: await _getHeaders(),
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_authTokenKey);
      await prefs.remove(_authUserKey);
    } catch (e) {
      print('Error saat logout: $e');
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_authTokenKey);
      await prefs.remove(_authUserKey);
    }
  }

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
        request.files.add(
          http.MultipartFile.fromBytes(
            'photo',
            bytes,
            filename: 'checkin_${DateTime.now().millisecondsSinceEpoch}.jpg',
          ),
        );
      }

      final streamed = await request.send().timeout(
        const Duration(seconds: 30),
      );
      final response = await http.Response.fromStream(streamed);
      print('[checkIn] status=${response.statusCode} body=${response.body}');
      final data = jsonDecode(response.body);
      return {
        'success': response.statusCode == 200 || response.statusCode == 201,
        'message': data['message'] ?? 'Check-in successful.',
      };
    } catch (e) {
      print('Error saat check-in: $e');
      return _handleError(e);
    }
  }

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
        request.files.add(
          http.MultipartFile.fromBytes(
            'photo',
            bytes,
            filename: 'checkout_${DateTime.now().millisecondsSinceEpoch}.jpg',
          ),
        );
      }

      final streamed = await request.send().timeout(
        const Duration(seconds: 30),
      );
      final response = await http.Response.fromStream(streamed);
      print('[checkOut] status=${response.statusCode} body=${response.body}');
      final data = jsonDecode(response.body);
      return {
        'success': response.statusCode == 200 || response.statusCode == 201,
        'message': data['message'] ?? 'Check-out successful.',
      };
    } catch (e) {
      return _handleError(e);
    }
  }

  static Future<Map<String, dynamic>> submitLeave(
    String type,
    String reason, {
    XFile? photo,
    XFile? proof,
    double? latitude,
    double? longitude,
    String deviceType = 'unknown',
  }) async {
    try {
      final uri = Uri.parse('$_baseUrl/leave');
      final request = http.MultipartRequest('POST', uri);
      request.headers.addAll(await _getMultipartHeaders());
      request.fields['type'] = type;
      request.fields['reason'] = reason;
      if (latitude != null) request.fields['latitude'] = latitude.toString();
      if (longitude != null) request.fields['longitude'] = longitude.toString();
      request.fields['device_type'] = deviceType;

      if (photo != null) {
        final bytes = await photo.readAsBytes();
        final filename = photo.name.isNotEmpty
            ? photo.name
            : 'photo_${DateTime.now().millisecondsSinceEpoch}.jpg';
        request.files.add(
          http.MultipartFile.fromBytes('photo', bytes, filename: filename),
        );
        print(
          '[submitLeave] attaching photo: $filename (${bytes.length} bytes)',
        );
      }

      if (proof != null) {
        final bytes = await proof.readAsBytes();
        final filename = proof.name.isNotEmpty
            ? proof.name
            : 'proof_${DateTime.now().millisecondsSinceEpoch}.jpg';
        request.files.add(
          http.MultipartFile.fromBytes('proof', bytes, filename: filename),
        );
        print(
          '[submitLeave] attaching proof: $filename (${bytes.length} bytes)',
        );
      }

      final streamed = await request.send().timeout(
        const Duration(seconds: 30),
      );
      final response = await http.Response.fromStream(streamed);
      print(
        '[submitLeave] status=${response.statusCode} body=${response.body}',
      );
      final data = jsonDecode(response.body);
      return {
        'success': response.statusCode == 200 || response.statusCode == 201,
        'message': data['message'] ?? 'Pengajuan berhasil dikirim.',
      };
    } catch (e) {
      print('[submitLeave] error: $e');
      return _handleError(e);
    }
  }

  static Future<Map<String, dynamic>> getTodayAttendance() async {
    try {
      final response = await http
          .get(Uri.parse('$_baseUrl/today'), headers: await _getHeaders())
          .timeout(const Duration(seconds: 15));

      print(
        '[getTodayAttendance] status=${response.statusCode} body=${response.body}',
      );

      dynamic decoded;
      try {
        decoded = jsonDecode(response.body);
      } catch (_) {
        return {
          'error':
              'Respons server tidak valid (bukan JSON). Status: ${response.statusCode}',
        };
      }

      if (response.statusCode == 200 || response.statusCode == 201) {
        if (decoded is! Map<String, dynamic>) {
          return {'error': 'Format respons tidak dikenali.'};
        }

        final attendance =
            decoded['data'] ?? decoded['attendance'] ?? decoded['absensi'];

        if (attendance != null && attendance is! Map<String, dynamic>) {
          return {'data': null};
        }
        return {'data': attendance as Map<String, dynamic>?};
      }

      final errMsg = _extractErrorMessage(decoded);
      return {'error': 'Server error ${response.statusCode}: $errMsg'};
    } catch (e) {
      return {'error': _handleError(e)['message'] as String};
    }
  }

  static Future<Map<String, dynamic>> getAttendanceHistory() async {
    try {
      final response = await http
          .get(Uri.parse('$_baseUrl/attendances'), headers: await _getHeaders())
          .timeout(const Duration(seconds: 15));

      print(
        '[getAttendanceHistory] status=${response.statusCode} body=${response.body}',
      );

      dynamic decoded;
      try {
        decoded = jsonDecode(response.body);
      } catch (_) {
        return {
          'error': 'Respons server tidak valid. Status: ${response.statusCode}',
        };
      }

      if (response.statusCode == 200 || response.statusCode == 201) {
        if (decoded is! Map<String, dynamic>) {
          return {'error': 'Format respons tidak dikenali.'};
        }

        final list =
            decoded['data'] ??
            decoded['attendances'] ??
            decoded['history'] ??
            [];
        return {'data': list is List ? list : []};
      }

      return {
        'error':
            'Server error ${response.statusCode}: ${_extractErrorMessage(decoded)}',
      };
    } catch (e) {
      return {'error': _handleError(e)['message'] as String};
    }
  }
}
