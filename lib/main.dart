import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart'; // <-- 1. Import ini
import 'package:absensi_app/screens/login_screen.dart';

void main() async { // <-- 2. Ubah menjadi async
  // 3. Tambahkan dua baris ini sebelum runApp
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('id_ID', null); 

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Aplikasi Absensi',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        fontFamily: 'Poppins', // Opsional: jika Anda ingin Poppins jadi default
      ),
      home: const LoginScreen(),
      debugShowCheckedModeBanner: false,
      // Wrap semua halaman dalam frame mobile di desktop/tablet landscape
      builder: (context, child) => _MobileFrame(child: child!),
    );
  }
}

/// Membatasi lebar konten ke ukuran mobile (maks 430 px).
/// Di desktop / tablet landscape, sisi kiri-kanan diisi background kosong.
class _MobileFrame extends StatelessWidget {
  final Widget child;
  const _MobileFrame({required this.child});

  static const double _maxMobileWidth = 430.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Jika layar lebih lebar dari ukuran mobile, tampilkan frame
        if (constraints.maxWidth > _maxMobileWidth) {
          return Container(
            color: const Color(0xFFE2E8F0), // abu-abu terang sebagai background
            child: Row(
              // stretch memaksa semua child setinggi layar penuh
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Spacer(),
                SizedBox(
                  width: _maxMobileWidth,
                  child: Material(
                    elevation: 8,
                    shadowColor: Colors.black38,
                    child: child,
                  ),
                ),
                const Spacer(),
              ],
            ),
          );
        }
        // Mobile / tablet portrait → tampil normal full-width
        return child;
      },
    );
  }
}
