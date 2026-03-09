import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../helpers/web_camera.dart';
import '../helpers/web_camera_capture.dart';
import '../models/user.dart';
import '../services/location_service.dart';
import '../services/api_service.dart';
import 'login_screen.dart';

class HomeScreen extends StatefulWidget {
  final User user;
  const HomeScreen({super.key, required this.user});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  String _currentTime = '';
  Timer? _timer;
  Map<String, dynamic>? _todayAttendance;
  bool _isLoading = true;
  String? _attendanceError;

  // Foto lokal yang diambil saat check-in / check-out
  XFile? _checkInPhoto;
  XFile? _checkOutPhoto;

  // Live location
  LocationResult? _liveLocation;
  bool _liveLocationLoading = true;
  String? _liveLocationError;
  StreamSubscription<LocationResult>? _locationSub;

  // Status Absensi
  bool get _hasCheckedIn => _todayAttendance != null && _todayAttendance!['check_in_time'] != null;
  bool get _hasCheckedOut => _todayAttendance != null && _todayAttendance!['check_out_time'] != null;
  bool get _hasLeaveRequest => _todayAttendance != null && (_todayAttendance!['status'] == 'Izin' || _todayAttendance!['status'] == 'Sakit');

  // Animations
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();

    // Realtime clock
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _currentTime = DateFormat('HH:mm:ss').format(DateTime.now());
        });
      }
    });

    // Subtle pulse animation for header clock
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.0, end: 6.0).animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

    // Fetch today attendance
    _fetchTodayAttendance();

    // Start live location stream
    _startLocationStream();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pulseCtrl.dispose();
    _locationSub?.cancel();
    super.dispose();
  }

  Future<void> _fetchTodayAttendance() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _attendanceError = null;
    });
    final result = await ApiService.getTodayAttendance();
    if (mounted) {
      setState(() {
        _isLoading = false;
        if (result['error'] != null) {
          _attendanceError = result['error'] as String;
          _todayAttendance = null;
        } else {
          _attendanceError = null;
          _todayAttendance = result['data'] as Map<String, dynamic>?;
        }
      });
    }
  }

  /// Mulai (atau restart) live location stream.
  Future<void> _startLocationStream() async {
    if (!mounted) return;
    // Batalkan langganan lama jika ada
    await _locationSub?.cancel();
    _locationSub = null;
    setState(() {
      _liveLocationLoading = true;
      _liveLocationError = null;
    });
    try {
      final avail = await LocationService.checkAndRequestPermission();
      if (!avail.isAvailable) {
        if (mounted) {
          setState(() {
            _liveLocationLoading = false;
            _liveLocationError = avail.message;
          });
        }
        return;
      }
      _locationSub = LocationService.getLocationStream().listen(
        (loc) {
          if (mounted) {
            setState(() {
              _liveLocation = loc;
              _liveLocationLoading = false;
              _liveLocationError = null;
            });
          }
        },
        onError: (e) {
          if (mounted) {
            setState(() {
              _liveLocationLoading = false;
              _liveLocationError = e.toString().replaceFirst('Exception: ', '');
            });
          }
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _liveLocationLoading = false;
          _liveLocationError = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  /// Tampilkan dialog error lokasi dengan tombol aksi yang sesuai.
  void _showLocationErrorDialog(LocationAvailability avail) {
    if (!mounted) return;
    final bool canOpenSettings =
        avail.status == LocationStatus.permissionDeniedForever ||
        avail.status == LocationStatus.serviceDisabled;

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.location_off, color: Colors.red),
            const SizedBox(width: 8),
            const Text('Lokasi Tidak Tersedia'),
          ],
        ),
        content: Text(avail.message),
        actions: [
          if (canOpenSettings)
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                if (avail.status == LocationStatus.permissionDeniedForever) {
                  LocationService.openAppSettings();
                } else {
                  LocationService.openLocationSettings();
                }
              },
              child: const Text('Buka Pengaturan'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Tutup'),
          ),
        ],
      ),
    );
  }

  /// Tampilkan warning jika terdeteksi mock / fake GPS.
  Future<bool> _confirmMockLocation() async {
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (_) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.orange),
                SizedBox(width: 8),
                Text('Fake GPS Terdeteksi'),
              ],
            ),
            content: const Text(
              'Aplikasi mendeteksi bahwa lokasi Anda berasal dari aplikasi Mock/Fake GPS.\n\n'
              'Penggunaan Fake GPS dapat melanggar kebijakan absensi perusahaan.\n\n'
              'Apakah Anda ingin tetap melanjutkan?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Batal'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Tetap Lanjutkan'),
              ),
            ],
          ),
        ) ??
        false;
  }

  void _handleApiResponse(Map<String, dynamic> result) {
    if (!mounted) return;
    if (result['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(result['message'] ?? 'Berhasil!'),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 3),
      ));
      _fetchTodayAttendance();
    } else {
      // Error → tampilkan dialog permanen agar tidak terlewat
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: const [
              Icon(Icons.error_outline, color: Colors.red),
              SizedBox(width: 8),
              Text('Terjadi Kesalahan'),
            ],
          ),
          content: Text(
            result['message'] ?? 'Terjadi kesalahan yang tidak diketahui.',
            style: GoogleFonts.poppins(fontSize: 14),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  /// File picker native Windows via PowerShell (bypass Flutter plugin channel).
  Future<String?> _pickFileWindows() async {
    try {
      final result = await Process.run('powershell', [
        '-NonInteractive',
        '-Command',
        // Buat form tersembunyi sebagai TopMost owner agar dialog muncul di depan Flutter window
        'Add-Type -AssemblyName System.Windows.Forms; '
            r'$owner = New-Object System.Windows.Forms.Form; '
            r'$owner.TopMost = $true; $owner.WindowState = "Minimized"; $owner.ShowInTaskbar = $false; $owner.Show(); '
            r'$d = New-Object System.Windows.Forms.OpenFileDialog; '
            r'$d.Filter = "Image Files|*.jpg;*.jpeg;*.png;*.webp"; '
            r'$d.Title = "Pilih Foto Absensi"; '
            r'if ($d.ShowDialog($owner) -eq "OK") { Write-Output $d.FileName } else { Write-Output "" }; '
            r'$owner.Dispose()',
      ]);
      final path = result.stdout.toString().trim();
      return path.isNotEmpty ? path : null;
    } catch (e) {
      print('[_pickFileWindows] error: $e');
      return null;
    }
  }

  /// Tampilkan overlay countdown 2...1 → flash, lalu tutup otomatis.
  /// Hanya untuk web & mobile (ada kamera fisik).
  Future<void> _showCaptureCountdown() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black87,
      builder: (ctx) => const _CaptureCountdownOverlay(),
    );
  }

  /// Buka kamera → tampilkan preview → kembalikan XFile jika dikonfirmasi, null jika dibatalkan.
  Future<XFile?> _capturePhoto() async {
    final picker = ImagePicker();
    XFile? photo;

    final isWindows = !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
    final isDesktopNonWindows = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.linux ||
            defaultTargetPlatform == TargetPlatform.macOS);
    final isDesktop = isWindows || isDesktopNonWindows;

    // Web & Android/iOS → kamera + countdown
    // Windows → PowerShell file picker
    // Linux/macOS → gallery

    while (true) {
      try {
        if (isWindows) {
          final path = await _pickFileWindows();
          photo = path == null ? null : XFile(path);
        } else if (isDesktopNonWindows) {
          photo = await picker.pickImage(
            source: ImageSource.gallery,
            imageQuality: 75,
            maxWidth: 900,
          );
        } else if (kIsWeb) {
          // Web → gunakan HTML getUserMedia + canvas capture (bukan image_picker)
          // agar tidak bergantung pada user-gesture aktif saat .click() dipanggil.
          photo = await captureWebPhoto();
        } else {
          // Android / iOS → countdown Flutter lalu kamera native
          await requestWebCameraPermission();
          if (!mounted) return null;
          await _showCaptureCountdown();
          if (!mounted) return null;
          photo = await picker.pickImage(
            source: ImageSource.camera,
            preferredCameraDevice: CameraDevice.front,
            imageQuality: 75,
            maxWidth: 900,
          );
        }
      } catch (e) {
        print('[_capturePhoto] gagal ambil foto: $e');
        return null;
      }

      if (photo == null) return null; // User batal

      // Tampilkan preview — user bisa konfirmasi atau ambil ulang
      if (!mounted) return null;
      final action = await _showPhotoPreviewDialog(photo, isDesktop: isDesktop);
      if (action == _PhotoAction.confirm) return photo;
      if (action == _PhotoAction.cancel) return null;
      // action == retake → ulangi loop
    }
  }

  /// Dialog preview foto setelah capture.
  Future<_PhotoAction> _showPhotoPreviewDialog(XFile photo, {bool isDesktop = false}) async {
    return await showDialog<_PhotoAction>(
          context: context,
          barrierDismissible: false,
          builder: (_) => Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Icon(isDesktop ? Icons.image : Icons.camera_alt, color: Color(0xFF2563EB)),
                        const SizedBox(width: 8),
                        Text(isDesktop ? 'Foto Absensi' : 'Foto Selfie Absensi',
                            style: GoogleFonts.poppins(
                                fontWeight: FontWeight.w700, fontSize: 16)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: kIsWeb
                          ? Image.network(photo.path,
                              height: 280, width: double.infinity, fit: BoxFit.cover)
                          : Image.file(File(photo.path),
                              height: 280, width: double.infinity, fit: BoxFit.cover),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () =>
                                Navigator.pop(context, _PhotoAction.retake),
                            icon: const Icon(Icons.refresh, size: 16),
                            label: Text(isDesktop ? 'Pilih Ulang' : 'Ambil Ulang',
                                style: GoogleFonts.poppins(fontSize: 13)),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(44),
                              side: const BorderSide(color: Color(0xFF93C5FD)),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () =>
                                Navigator.pop(context, _PhotoAction.confirm),
                            icon: const Icon(Icons.check, size: 16),
                            label: Text('Gunakan',
                                style: GoogleFonts.poppins(
                                    fontSize: 13, fontWeight: FontWeight.w600)),
                            style: ElevatedButton.styleFrom(
                              minimumSize: const Size.fromHeight(44),
                              elevation: 0,
                              backgroundColor: const Color(0xFF2563EB),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        IconButton(
                          onPressed: () =>
                              Navigator.pop(context, _PhotoAction.cancel),
                          icon:
                              const Icon(Icons.close, color: Colors.grey),
                          tooltip: 'Batalkan',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ) ??
        _PhotoAction.cancel;
  }

  void _onCheckIn() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      // 1. Cek ketersediaan GPS & izin sebelum mulai
      final avail = await LocationService.checkAndRequestPermission();
      if (!avail.isAvailable) {
        if (mounted) setState(() => _isLoading = false);
        _showLocationErrorDialog(avail);
        return;
      }

      // 2. Ambil posisi
      final loc = await LocationService.getCurrentLocation();

      // 3. Jika mock GPS terdeteksi (Android), tampilkan warning
      if (loc.isMockLocation) {
        if (mounted) setState(() => _isLoading = false);
        final proceed = await _confirmMockLocation();
        if (!proceed) return;
        if (mounted) setState(() => _isLoading = true);
      }

      // 4. Ambil foto selfie (opsional — lanjut meski tidak ada foto)
      if (mounted) setState(() => _isLoading = false);
      final photo = await _capturePhoto();
      print('[checkIn] foto: ${photo?.path ?? "tidak ada"}');
      if (mounted) setState(() => _isLoading = true);

      // 5. Kirim ke API
      print('[checkIn] mengirim ke API...');
      final result = await ApiService.checkIn(
        latitude: loc.latitude,
        longitude: loc.longitude,
        deviceType: loc.deviceType,
        isMockLocation: loc.isMockLocation,
        photo: photo,
      );
      print('[checkIn] response: $result');
      if (result['success'] == true && photo != null) {
        setState(() => _checkInPhoto = photo);
      }
      _handleApiResponse(result);
    } catch (e, st) {
      print('[checkIn] exception: $e\n$st');
      _handleApiResponse({'success': false, 'message': e.toString().replaceFirst('Exception: ', '')});
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _onCheckOut() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      // 1. Cek ketersediaan GPS & izin sebelum mulai
      final avail = await LocationService.checkAndRequestPermission();
      if (!avail.isAvailable) {
        if (mounted) setState(() => _isLoading = false);
        _showLocationErrorDialog(avail);
        return;
      }

      // 2. Ambil posisi
      final loc = await LocationService.getCurrentLocation();

      // 3. Jika mock GPS terdeteksi (Android), tampilkan warning
      if (loc.isMockLocation) {
        if (mounted) setState(() => _isLoading = false);
        final proceed = await _confirmMockLocation();
        if (!proceed) return;
        if (mounted) setState(() => _isLoading = true);
      }

      // 4. Ambil foto selfie (opsional — lanjut meski tidak ada foto)
      if (mounted) setState(() => _isLoading = false);
      final photo = await _capturePhoto();
      print('[checkOut] foto: ${photo?.path ?? "tidak ada"}');
      if (mounted) setState(() => _isLoading = true);

      // 5. Kirim ke API
      print('[checkOut] mengirim ke API...');
      final result = await ApiService.checkOut(
        latitude: loc.latitude,
        longitude: loc.longitude,
        deviceType: loc.deviceType,
        isMockLocation: loc.isMockLocation,
        photo: photo,
      );
      print('[checkOut] response: $result');
      if (result['success'] == true && photo != null) {
        setState(() => _checkOutPhoto = photo);
      }
      _handleApiResponse(result);
    } catch (e, st) {
      print('[checkOut] exception: $e\n$st');
      _handleApiResponse({'success': false, 'message': e.toString().replaceFirst('Exception: ', '')});
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _onLeaveRequest() {
    final reasonController = TextEditingController();
    String? leaveType = 'Izin';

    showDialog(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(colors: [Color(0xFF2563EB), Color(0xFF60A5FA)]),
                      ),
                      padding: const EdgeInsets.all(10),
                      child: const Icon(Icons.event_note, color: Colors.white),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text('Ajukan Izin/Sakit',
                        style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 18)),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: leaveType,
                  items: ['Izin', 'Sakit'].map((String value) {
                    return DropdownMenuItem<String>(value: value, child: Text(value));
                  }).toList(),
                  onChanged: (newValue) => leaveType = newValue,
                  decoration: InputDecoration(
                    labelText: 'Jenis Pengajuan',
                    filled: true,
                    fillColor: Colors.blue.withOpacity(0.05),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: reasonController,
                  decoration: InputDecoration(
                    labelText: 'Alasan',
                    alignLabelWithHint: true,
                    filled: true,
                    fillColor: Colors.blue.withOpacity(0.05),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                          side: BorderSide(color: Colors.blue.shade300),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        child: Text('Batal', style: GoogleFonts.poppins()),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () async {
                          if (reasonController.text.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Alasan tidak boleh kosong.')),
                            );
                            return;
                          }
                          Navigator.pop(context);
                          setState(() => _isLoading = true);
                          final result = await ApiService.submitLeave(leaveType!, reasonController.text);
                          _handleApiResponse(result);
                          setState(() => _isLoading = false);
                        },
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          backgroundColor: const Color(0xFF2563EB),
                          foregroundColor: Colors.white,
                        ),
                        child: Text('Kirim', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ],
                )
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _logout() async {
    // Konfirmasi logout (desain baru)
    bool? confirmLogout = await showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(colors: [Color(0xFF3B82F6), Color(0xFF93C5FD)]),
                  ),
                  padding: const EdgeInsets.all(12),
                  child: const Icon(Icons.logout, color: Colors.white),
                ),
                const SizedBox(height: 12),
                Text('Konfirmasi Logout', style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 18)),
                const SizedBox(height: 8),
                Text('Anda yakin ingin keluar dari aplikasi?', style: GoogleFonts.poppins(color: Colors.black54)),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                          side: BorderSide(color: Colors.blue.shade300),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        child: Text('Batal', style: GoogleFonts.poppins()),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                          elevation: 0,
                          backgroundColor: const Color(0xFFEF4444),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        child: Text('Logout', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ],
                )
              ],
            ),
          ),
        );
      },
    );

    if (confirmLogout == true) {
      await ApiService.logout();
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const LoginScreen()),
          (Route<dynamic> route) => false,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scaffoldBackground = const Color(0xFFF7FAFF);

    return Scaffold(
      backgroundColor: scaffoldBackground,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SvgPicture.asset(
              'assets/EPBOX CONDUCTOR.svg',
              width: 32,
              height: 32,
              colorFilter: const ColorFilter.mode(Color(0xFF0F172A), BlendMode.srcIn),
            ),
            const SizedBox(width: 8),
            Text('Absensi Karyawan', style: GoogleFonts.poppins(fontWeight: FontWeight.bold, color: const Color(0xFF0F172A))),
          ],
        ),
        actions: [
          IconButton(
            onPressed: _logout,
            icon: const Icon(Icons.logout, color: Color(0xFF64748B)),
            tooltip: 'Logout',
          )
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _fetchTodayAttendance,
        color: const Color(0xFF2563EB),
        child: ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            _buildHeader(),
            const SizedBox(height: 20),
            _buildQuickStats(),
            const SizedBox(height: 16),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              switchInCurve: Curves.easeOutBack,
              switchOutCurve: Curves.easeIn,
              child: _isLoading
                  ? const _LoadingCard(key: ValueKey('loading'))
                  : _buildActionButtons(key: const ValueKey('actions')),
            ),
            const SizedBox(height: 16),
            _buildAttendanceInfo(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final loc = _liveLocation;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2563EB), Color(0xFF60A5FA)],
        ),
        boxShadow: [
          BoxShadow(color: Colors.blue.shade200.withOpacity(0.5), blurRadius: 20, offset: const Offset(0, 10)),
        ],
      ),
      child: Stack(
        children: [
          Positioned(right: -30, top: -30, child: _bubble(120, 0.08)),
          Positioned(left: -20, bottom: -20, child: _bubble(180, 0.06)),
          Positioned(right: 30, bottom: 20, child: _bubble(40, 0.10)),

          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Baris 1: Halo nama + tanggal ──
                Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withOpacity(0.2),
                        border: Border.all(color: Colors.white.withOpacity(0.4)),
                      ),
                      child: const Icon(Icons.person, color: Colors.white, size: 26),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Halo, ${widget.user.name}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.poppins(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            DateFormat('EEEE, d MMMM yyyy', 'id_ID').format(DateTime.now()),
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              color: Colors.white.withOpacity(0.8),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // ── Baris 2: Kiri = Lokasi | Kanan = Jam ──
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // ── KIRI: Lokasi & Akurasi ──
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.location_on, color: Colors.white70, size: 13),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Lokasi',
                                    style: GoogleFonts.poppins(
                                      fontSize: 11,
                                      color: Colors.white70,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              if (_liveLocationLoading && loc == null)
                                Text(
                                  'Mencari...',
                                  style: GoogleFonts.spaceMono(
                                    fontSize: 11,
                                    color: Colors.white.withOpacity(0.7),
                                  ),
                                )
                              else if (loc == null)
                                Text(
                                  'Tidak tersedia',
                                  style: GoogleFonts.spaceMono(
                                    fontSize: 11,
                                    color: Colors.white.withOpacity(0.6),
                                  ),
                                )
                              else ...[
                                Text(
                                  '${loc.latitude.toStringAsFixed(5)}',
                                  style: GoogleFonts.spaceMono(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
                                Text(
                                  '${loc.longitude.toStringAsFixed(5)}',
                                  style: GoogleFonts.spaceMono(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    const Icon(Icons.radar, color: Colors.white60, size: 12),
                                    const SizedBox(width: 3),
                                    Text(
                                      loc.accuracy != null
                                          ? '±${loc.accuracy!.toStringAsFixed(0)} m'
                                          : '±- m',
                                      style: GoogleFonts.poppins(
                                        fontSize: 11,
                                        color: Colors.white70,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(width: 10),

                      // ── KANAN: Jam ──
                      AnimatedBuilder(
                        animation: _pulse,
                        builder: (context, _) {
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.white.withOpacity(0.30),
                                  blurRadius: 4 + _pulse.value,
                                  spreadRadius: 0.5,
                                ),
                              ],
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.access_time_rounded,
                                    color: Colors.white70, size: 14),
                                const SizedBox(height: 4),
                                Text(
                                  _currentTime,
                                  style: GoogleFonts.spaceMono(
                                    fontSize: 26,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                    letterSpacing: 1.5,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _bubble(double size, double opacity) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withOpacity(opacity),
      ),
    );
  }

  Widget _buildQuickStats() {
    // Small blue/white cards for quick hints
    final items = <_StatItem>[
      _StatItem(icon: Icons.place, label: 'Geo-Check', note: 'Aktif'),
      _StatItem(icon: Icons.verified, label: 'Status', note: _statusText()),
      _StatItem(icon: Icons.calendar_today, label: 'Hari Ini', note: DateFormat('dd/MM').format(DateTime.now())),
    ];

    return Row(
      children: items
          .map((e) => Expanded(
                child: _FrostCard(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(e.icon, color: const Color(0xFF2563EB)),
                      const SizedBox(height: 8),
                      Text(e.label, style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 13)),
                      const SizedBox(height: 2),
                      Text(e.note, style: GoogleFonts.poppins(color: Colors.black54, fontSize: 12)),
                    ],
                  ),
                ),
              ))
          .toList(),
    );
  }

  String _statusText() {
    if (_hasLeaveRequest) return _todayAttendance!['status'];
    if (_hasCheckedOut) return 'Selesai';
    if (_hasCheckedIn) return 'Sedang Bekerja';
    return 'Belum Check-In';
    }

  Widget _buildActionButtons({Key? key}) {
    if (_hasCheckedOut || _hasLeaveRequest) {
      return _FrostCard(
        key: key,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Text(
            'Aktivitas absensi hari ini sudah selesai.',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(fontSize: 15, color: Colors.grey.shade700, fontWeight: FontWeight.w500),
          ),
        ),
      );
    }

    return _FrostCard(
      key: key,
      child: Column(
        children: [
          if (!_hasCheckedIn) _primaryButton(
            label: 'CHECK IN',
            icon: Icons.login_rounded,
            onPressed: _onCheckIn,
          ),
          if (_hasCheckedIn && !_hasCheckedOut)
            _primaryButton(
              label: 'CHECK OUT',
              icon: Icons.logout_rounded,
              onPressed: _onCheckOut,
              isWarning: true,
            ),
          const SizedBox(height: 10),
          if (!_hasCheckedIn)
            _ghostButton(
              label: 'Tidak Masuk? Ajukan Izin/Sakit',
              icon: Icons.edit_document,
              onPressed: _onLeaveRequest,
            ),
        ],
      ),
    );
  }

  Widget _primaryButton({
    required String label,
    required IconData icon,
    required VoidCallback onPressed,
    bool isWarning = false,
  }) {
    final bg = isWarning ? const Color(0xFFF59E0B) : const Color(0xFF2563EB);
    return _TapScale(
      child: ElevatedButton.icon(
        icon: Icon(icon),
        label: Text(label, style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: bg,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(54),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }

  Widget _ghostButton({
    required String label,
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return _TapScale(
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, color: const Color(0xFF2563EB)),
        label: Text(label, style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: const Color(0xFF2563EB))),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(50),
          side: const BorderSide(color: Color(0xFF93C5FD)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          backgroundColor: Colors.white,
        ),
      ),
    );
  }

  Widget _buildAttendanceInfo() {
    // ── Error state ──
    if (_attendanceError != null) {
      return _FrostCard(
        child: Column(
          children: [
            ListTile(
              leading: _iconBadge(Icons.error_outline),
              title: Text('Gagal memuat data absensi',
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: Colors.red)),
              subtitle: Text(_attendanceError!,
                  style: GoogleFonts.poppins(color: Colors.red.shade300, fontSize: 12)),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _fetchTodayAttendance,
                icon: const Icon(Icons.refresh, size: 16),
                label: Text('Coba Lagi', style: GoogleFonts.poppins(fontSize: 13)),
                style: TextButton.styleFrom(foregroundColor: const Color(0xFF2563EB)),
              ),
            ),
          ],
        ),
      );
    }

    // ── Empty state ──
    if (_todayAttendance == null) {
      return _FrostCard(
        child: ListTile(
          leading: _iconBadge(Icons.info_outline),
          title: Text('Belum ada data absensi hari ini.', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
          subtitle: Text('Silakan lakukan Check-In atau ajukan izin/sakit.',
              style: GoogleFonts.poppins(color: Colors.black54)),
        ),
      );
    }

    return _FrostCard(
      child: Padding(
        padding: const EdgeInsets.all(2.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: _iconBadge(Icons.timeline_rounded),
              title: Text('Ringkasan Hari Ini',
                  style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700)),
            ),
            const Divider(height: 20),
            _infoRow('Status', _todayAttendance!['status']),
            if (_hasCheckedIn)
              _infoRow('Jam Masuk',
                  DateFormat('HH:mm:ss').format(DateTime.parse(_todayAttendance!['check_in_time']))),
            if (_hasCheckedOut)
              _infoRow('Jam Pulang',
                  DateFormat('HH:mm:ss').format(DateTime.parse(_todayAttendance!['check_out_time']))),
            if (_hasLeaveRequest) _infoRow('Alasan', _todayAttendance!['reason'] ?? '-'),

            // ── Foto Check-In ──
            if (_checkInPhotoWidget() != null) ...
            [
              const SizedBox(height: 14),
              _photoSection('Foto Check-In', _checkInPhotoWidget()!),
            ],

            // ── Foto Check-Out ──
            if (_checkOutPhotoWidget() != null) ...
            [
              const SizedBox(height: 10),
              _photoSection('Foto Check-Out', _checkOutPhotoWidget()!),
            ],
          ],
        ),
      ),
    );
  }

  /// Kembalikan widget gambar untuk foto check-in (lokal atau URL dari API).
  Widget? _checkInPhotoWidget() {
    // Prioritas 1: file lokal yang baru diambil
    if (_checkInPhoto != null) {
      return kIsWeb
          ? Image.network(_checkInPhoto!.path, fit: BoxFit.cover)
          : Image.file(File(_checkInPhoto!.path), fit: BoxFit.cover);
    }
    // Prioritas 2: path dari server (check_in_image)
    final raw = _todayAttendance?['check_in_image'] as String?;
    if (raw != null && raw.isNotEmpty) {
      final url = raw.startsWith('http') ? raw : '${ApiService.storageBaseUrl}/$raw';
      return Image.network(url, fit: BoxFit.cover,
          errorBuilder: (_, __, ___) =>
              const Icon(Icons.broken_image, color: Colors.grey));
    }
    return null;
  }

  /// Kembalikan widget gambar untuk foto check-out (lokal atau URL dari API).
  Widget? _checkOutPhotoWidget() {
    if (_checkOutPhoto != null) {
      return kIsWeb
          ? Image.network(_checkOutPhoto!.path, fit: BoxFit.cover)
          : Image.file(File(_checkOutPhoto!.path), fit: BoxFit.cover);
    }
    // path dari server (check_out_image)
    final raw = _todayAttendance?['check_out_image'] as String?;
    if (raw != null && raw.isNotEmpty) {
      final url = raw.startsWith('http') ? raw : '${ApiService.storageBaseUrl}/$raw';
      return Image.network(url, fit: BoxFit.cover,
          errorBuilder: (_, __, ___) =>
              const Icon(Icons.broken_image, color: Colors.grey));
    }
    return null;
  }

  Widget _photoSection(String label, Widget image) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.black54)),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            height: 180,
            width: double.infinity,
            child: image,
          ),
        ),
      ],
    );
  }

  Widget _infoRow(String title, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        children: [
          Expanded(child: Text(title, style: GoogleFonts.poppins(color: Colors.black54))),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(value, style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: const Color(0xFF1E40AF))),
          ),
        ],
      ),
    );
  }

  Widget _iconBadge(IconData icon) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(colors: [Color(0xFF3B82F6), Color(0xFF93C5FD)]),
      ),
      padding: const EdgeInsets.all(10),
      child: Icon(icon, color: Colors.white),
    );
  }
}

/// Small frosted/white card with soft shadow & rounded corners
class _FrostCard extends StatelessWidget {
  final Widget child;
  const _FrostCard({Key? key, required this.child}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(color: Color(0x1A000000), blurRadius: 12, offset: Offset(0, 6)),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: child,
    );
  }
}


/// Tap scale interaction for buttons/cards (subtle animation)
class _TapScale extends StatefulWidget {
  final Widget child;
  const _TapScale({required this.child});

  @override
  State<_TapScale> createState() => _TapScaleState();
}

class _TapScaleState extends State<_TapScale> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 120), lowerBound: 0.0, upperBound: 0.05);
    _anim = Tween<double>(begin: 1.0, end: 0.95).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _ctrl.forward(),
      onTapCancel: () => _ctrl.reverse(),
      onTapUp: (_) => _ctrl.reverse(),
      child: AnimatedBuilder(
        animation: _anim,
        builder: (context, child) => Transform.scale(scale: _anim.value, child: child),
        child: widget.child,
      ),
    );
  }
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard({super.key});

  @override
  Widget build(BuildContext context) {
    return const _FrostCard(
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 14.0),
        child: Center(child: CircularProgressIndicator(color: Color(0xFF2563EB))),
      ),
    );
  }
}

class _StatItem {
  final IconData icon;
  final String label;
  final String note;
  _StatItem({required this.icon, required this.label, required this.note});
}

enum _PhotoAction { confirm, retake, cancel }

/// Overlay countdown penuh layar (2…1 → flash) sebelum kamera terbuka.
class _CaptureCountdownOverlay extends StatefulWidget {
  const _CaptureCountdownOverlay();

  @override
  State<_CaptureCountdownOverlay> createState() => _CaptureCountdownOverlayState();
}

class _CaptureCountdownOverlayState extends State<_CaptureCountdownOverlay>
    with SingleTickerProviderStateMixin {
  int _count = 2;
  bool _flash = false;
  late final AnimationController _scaleCtrl;
  late final Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _scaleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _scaleAnim = Tween<double>(begin: 1.4, end: 1.0).animate(
      CurvedAnimation(parent: _scaleCtrl, curve: Curves.easeOutBack),
    );
    _runCountdown();
  }

  Future<void> _runCountdown() async {
    // Angka 2
    _scaleCtrl.forward(from: 0);
    await Future.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;

    // Angka 1
    setState(() => _count = 1);
    _scaleCtrl.forward(from: 0);
    await Future.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;

    // Flash putih
    setState(() => _flash = true);
    await Future.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;

    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _scaleCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      color: _flash ? Colors.white : Colors.transparent,
      child: _flash
          ? const SizedBox.expand()
          : Center(
              child: ScaleTransition(
                scale: _scaleAnim,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.camera_alt_rounded,
                        color: Colors.white, size: 56),
                    const SizedBox(height: 12),
                    Text(
                      '$_count',
                      style: const TextStyle(
                        fontSize: 96,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        height: 1,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Siap untuk foto absensi…',
                      style: TextStyle(
                        fontSize: 15,
                        color: Colors.white.withOpacity(0.75),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
