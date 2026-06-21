import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/auth_service.dart';
import 'otp_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phoneController = TextEditingController();
  bool _sending = false;
  String? _error;

  String get _phone => _phoneController.text.trim();
  bool get _valid => _phone.length == 10;

  Future<void> _sendOtp() async {
    if (!_valid) return;
    setState(() { _sending = true; _error = null; });
    try {
      await AuthService().sendOtp('+91$_phone');
      if (mounted) {
        Navigator.push(context, MaterialPageRoute(builder: (_) => OtpScreen(phone: '+91$_phone')));
      }
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),

              // Logo
              Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(color: Colors.green[50], shape: BoxShape.circle),
                child: Icon(Icons.storefront, size: 44, color: Colors.green[700]),
              ),
              const SizedBox(height: 28),
              const Text('Welcome to\nDhanam Store',
                  style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold, height: 1.2)),
              const SizedBox(height: 8),
              Text('Fresh groceries delivered to your door in 10 minutes',
                  style: TextStyle(fontSize: 15, color: Colors.grey[600])),
              const SizedBox(height: 40),

              // Phone input
              Text('Mobile Number', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey[700])),
              const SizedBox(height: 8),
              TextField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                maxLength: 10,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Enter 10-digit number',
                  prefixIcon: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Text('🇮🇳', style: TextStyle(fontSize: 20)),
                      const SizedBox(width: 6),
                      Text('+91', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.grey[700])),
                      Container(width: 1, height: 24, margin: const EdgeInsets.only(left: 10), color: Colors.grey[300]),
                    ]),
                  ),
                  counterText: '',
                  filled: true,
                  fillColor: Colors.grey[50],
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Colors.green, width: 2)),
                ),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, letterSpacing: 2),
              ),

              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: TextStyle(fontSize: 13, color: Colors.red[700])),
              ],

              const SizedBox(height: 20),

              // Send OTP button
              SizedBox(
                height: 54,
                child: ElevatedButton(
                  onPressed: _valid && !_sending ? _sendOtp : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.grey[300],
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 0,
                  ),
                  child: _sending
                      ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Get OTP', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                ),
              ),

              const Spacer(),

              // Terms
              Text(
                'By continuing, you agree to our Terms of Service and Privacy Policy',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.grey[500]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
