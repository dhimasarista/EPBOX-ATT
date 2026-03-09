import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/api_service.dart';
import 'home_screen.dart';
import '../models/user.dart';
import '../components/uppercase_text.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with TickerProviderStateMixin {
  final _emailController = TextEditingController();
  final _employeeIdController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _isPasswordVisible = false;
  bool _isLoading = false;
  bool _useEmployeeId = false; // false = email, true = nomor karyawan

  late final AnimationController _introCtrl;
  late final Animation<double> _introOpacity;
  late final Animation<Offset> _introOffset;

  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();

    // Intro fade + slide
    _introCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    )..forward();
    _introOpacity = CurvedAnimation(
      parent: _introCtrl,
      curve: Curves.easeOutCubic,
    );
    _introOffset = Tween<Offset>(
      begin: const Offset(0, .06),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _introCtrl, curve: Curves.easeOutCubic));

    // Subtle pulse for header emblem
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _pulse = Tween<double>(
      begin: .0,
      end: 6.0,
    ).animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _emailController.dispose();
    _employeeIdController.dispose();
    _passwordController.dispose();
    _introCtrl.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  Future<void> _performLogin() async {
    FocusScope.of(context).unfocus();

    // Validasi ringan (tidak mengubah alur)
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final result = _useEmployeeId
          ? await ApiService.login(
              '',
              _passwordController.text,
              employeeId: _employeeIdController.text.trim(),
            )
          : await ApiService.login(
              _emailController.text.trim(),
              _passwordController.text,
            );

      if (!mounted) return;

      if (result['success']) {
        final User user = result['user'];
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => HomeScreen(user: user)),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message']),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            margin: const EdgeInsets.all(16),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const scaffoldBg = Color(0xFFF7FAFF);

    return Scaffold(
      backgroundColor: scaffoldBg,
      body: Stack(
        children: [
          // Background gradient & bubbles
          const _GradientBackground(),
          // Content
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 22.0,
                  vertical: 12,
                ),
                child: FadeTransition(
                  opacity: _introOpacity,
                  child: SlideTransition(
                    position: _introOffset,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 480),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildHeader(),
                          const SizedBox(height: 18),
                          _FrostCard(
                            child: Form(
                              key: _formKey,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    'Welcome Back!',
                                    textAlign: TextAlign.center,
                                    style: GoogleFonts.poppins(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w700,
                                      color: const Color(0xFF0F172A),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Please Login for Attendance',
                                    textAlign: TextAlign.center,
                                    style: GoogleFonts.poppins(
                                      fontSize: 14,
                                      color: Colors.black54,
                                    ),
                                  ),
                                  const SizedBox(height: 24),

                                  // Toggle Email / Nomor Karyawan
                                  Container(
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF1F5F9),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    padding: const EdgeInsets.all(4),
                                    child: Row(
                                      children: [
                                        _loginTab(
                                          'EMAIL',
                                          Icons.email_outlined,
                                          !_useEmployeeId,
                                          () {
                                            setState(() {
                                              _useEmployeeId = false;
                                              _formKey.currentState?.reset();
                                            });
                                          },
                                        ),
                                        _loginTab(
                                          'EMPLOYEE ID',
                                          Icons.badge_outlined,
                                          _useEmployeeId,
                                          () {
                                            setState(() {
                                              _useEmployeeId = true;
                                              _formKey.currentState?.reset();
                                            });
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 16),

                                  // Input field (berganti sesuai mode)
                                  AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 220),
                                    transitionBuilder: (child, anim) =>
                                        FadeTransition(
                                          opacity: anim,
                                          child: SlideTransition(
                                            position: Tween<Offset>(
                                              begin: const Offset(0, .05),
                                              end: Offset.zero,
                                            ).animate(anim),
                                            child: child,
                                          ),
                                        ),
                                    child: _useEmployeeId
                                        ? _buildTextField(
                                            key: const ValueKey('empid'),
                                            controller: _employeeIdController,
                                            labelText: 'Enter Your Employee ID',
                                            hintText: 'Example: EP0040',
                                            prefixIcon: Icons.badge_outlined,
                                            keyboardType: TextInputType.text,
                                            validator: (v) {
                                              if ((v ?? '').trim().isEmpty)
                                                return 'Employee ID required fields';
                                              return null;
                                            },
                                          )
                                        : _buildTextField(
                                            key: const ValueKey('email'),
                                            controller: _emailController,
                                            labelText: 'Enter Your Email',
                                            hintText: 'user@epbox-engg.com',
                                            prefixIcon: Icons.email_outlined,
                                            keyboardType:
                                                TextInputType.emailAddress,
                                            validator: (v) {
                                              final value = (v ?? '').trim();
                                              if (value.isEmpty)
                                                return 'Email required fields';
                                              if (!RegExp(
                                                r'^[^@]+@[^@]+\.[^@]+',
                                              ).hasMatch(value))
                                                return 'Format email not valid';
                                              return null;
                                            },
                                          ),
                                  ),
                                  const SizedBox(height: 14),

                                  // Password
                                  _buildPasswordField(),

                                  const SizedBox(height: 18),
                                  _TapScale(
                                    child: ElevatedButton(
                                      onPressed: _isLoading
                                          ? null
                                          : _performLogin,
                                      style: ElevatedButton.styleFrom(
                                        elevation: 0,
                                        backgroundColor: const Color(
                                          0xFF0F1C3F,
                                        ),
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 16,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                        ),
                                      ),
                                      child: AnimatedSwitcher(
                                        duration: const Duration(
                                          milliseconds: 250,
                                        ),
                                        switchInCurve: Curves.easeOutBack,
                                        switchOutCurve: Curves.easeIn,
                                        child: _isLoading
                                            ? const SizedBox(
                                                key: ValueKey('loader'),
                                                height: 22,
                                                width: 22,
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2.4,
                                                      color: Colors.white,
                                                    ),
                                              )
                                            : Text(
                                                'Login',
                                                key: const ValueKey('text'),
                                                style: GoogleFonts.poppins(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          // Tips / footer kecil
                          Center(
                            child: Text(
                              'Make sure ${_useEmployeeId ? 'Employee ID' : 'Email'} & Password match HR data',
                              style: GoogleFonts.poppins(
                                fontSize: 12,
                                color: Colors.black45,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Pulse emblem (kanan atas)
          Positioned(
            right: 18,
            top: 18,
            child: AnimatedBuilder(
              animation: _pulse,
              builder: (context, _) {
                return Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [Color(0xFF0F1C3F), Color(0xFF4A7ABF)],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF1E3A6E).withOpacity(0.4),
                        blurRadius: 4 + _pulse.value,
                      ),
                    ],
                  ),
                  child: const Icon(Icons.verified_user, color: Colors.white),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 160,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0F1C3F), Color(0xFF1E3A6E)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF4A7ABF).withOpacity(0.5),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(right: -30, top: -30, child: _bubble(120, .08)),
          Positioned(left: -20, bottom: -20, child: _bubble(180, .06)),
          Positioned(right: 30, bottom: 20, child: _bubble(40, .10)),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(0.2),
                    border: Border.all(color: Colors.white.withOpacity(0.4)),
                  ),
                  child: SvgPicture.asset(
                    'assets/EPBOX LOGO.svg',
                    width: 30,
                    height: 30,
                    colorFilter: const ColorFilter.mode(
                      Colors.white,
                      BlendMode.srcIn,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'EPBOX ENGINEERING',
                    style: GoogleFonts.poppins(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Login',
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                      letterSpacing: .8,
                    ),
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

  Widget _loginTab(
    String label,
    IconData icon,
    bool active,
    VoidCallback onTap,
  ) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: active ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            boxShadow: active
                ? [
                    const BoxShadow(
                      color: Color(0x1A000000),
                      blurRadius: 6,
                      offset: Offset(0, 2),
                    ),
                  ]
                : [],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: active ? const Color(0xFF0F1C3F) : Colors.grey.shade500,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                  color: active
                      ? const Color(0xFF0F1C3F)
                      : Colors.grey.shade500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    Key? key,
    required TextEditingController controller,
    required String labelText,
    required String hintText,
    required IconData prefixIcon,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      key: key,
      controller: controller,
      keyboardType: keyboardType,
      validator: validator,
      decoration: _inputDecoration(
        labelText: labelText,
        hintText: hintText,
        prefixIcon: prefixIcon,
      ),
      style: GoogleFonts.poppins(),
      inputFormatters: [UpperCaseTextFormatter()],
    );
  }

  Widget _buildPasswordField() {
    return TextFormField(
      controller: _passwordController,
      obscureText: !_isPasswordVisible,
      validator: (v) =>
          (v == null || v.isEmpty) ? 'Password required fields' : null,
      decoration: _inputDecoration(
        labelText: 'Enter Your Password',
        hintText: 'Must be at least 6 characters',
        prefixIcon: Icons.lock_outline,
        suffix: IconButton(
          icon: Icon(
            _isPasswordVisible ? Icons.visibility_off : Icons.visibility,
            color: Colors.grey.shade500,
          ),
          onPressed: () =>
              setState(() => _isPasswordVisible = !_isPasswordVisible),
        ),
      ),
      style: GoogleFonts.poppins(),
    );
  }

  InputDecoration _inputDecoration({
    required String labelText,
    required String hintText,
    required IconData prefixIcon,
    Widget? suffix,
  }) {
    return InputDecoration(
      labelText: labelText,
      hintText: hintText,
      prefixIcon: Icon(prefixIcon, color: Colors.grey.shade500),
      suffixIcon: suffix,
      filled: true,
      fillColor: const Color(0xFFF8FAFF),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFF0F1C3F), width: 2),
      ),
      labelStyle: GoogleFonts.poppins(color: Colors.grey.shade700),
      hintStyle: GoogleFonts.poppins(color: Colors.grey.shade400),
    );
  }
}

/// Frosted card (putih, shadow lembut) agar konsisten dengan HomeScreen
class _FrostCard extends StatelessWidget {
  final Widget child;
  const _FrostCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A000000),
            blurRadius: 12,
            offset: Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: child,
    );
  }
}

/// Background gradient + dekorasi gelembung agar senada dengan HomeScreen
class _GradientBackground extends StatelessWidget {
  const _GradientBackground();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // layer gradient tipis
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment(0, -1.0),
              end: Alignment(0, 0.2),
              colors: [Color(0xFFEEF2F9), Colors.white],
            ),
          ),
        ),
        // dekorasi bubble
        Positioned(top: -60, left: -40, child: _bubble(160, .12)),
        Positioned(top: 40, right: -30, child: _bubble(120, .1)),
        Positioned(bottom: -50, right: -40, child: _bubble(180, .08)),
      ],
    );
  }

  Widget _bubble(double size, double opacity) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF0F1C3F).withOpacity(opacity),
      ),
    );
  }
}

/// Tap-scale effect untuk tombol (interaksi halus)
class _TapScale extends StatefulWidget {
  final Widget child;
  const _TapScale({required this.child});

  @override
  State<_TapScale> createState() => _TapScaleState();
}

class _TapScaleState extends State<_TapScale>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 110),
      lowerBound: 0.0,
      upperBound: 0.04,
    );
    _anim = Tween<double>(
      begin: 1.0,
      end: 0.96,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
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
        builder: (context, child) =>
            Transform.scale(scale: _anim.value, child: child),
        child: widget.child,
      ),
    );
  }
}
