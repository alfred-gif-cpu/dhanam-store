import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/auth_service.dart';

class OtpScreen extends StatefulWidget {
  final String phone;
  const OtpScreen({super.key, required this.phone});

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final List<TextEditingController> _controllers = List.generate(4, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(4, (_) => FocusNode());
  bool _verifying = false;
  String? _error;
  int _resendSeconds = 30;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startTimer();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusNodes[0].requestFocus());
  }

  @override
  void dispose() {
    for (final c in _controllers) c.dispose();
    for (final f in _focusNodes) f.dispose();
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    _resendSeconds = 30;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_resendSeconds <= 0) { t.cancel(); return; }
      setState(() => _resendSeconds--);
    });
  }

  String get _otp => _controllers.map((c) => c.text).join();

  void _onDigitChanged(int index, String value) {
    if (value.length == 1 && index < 3) {
      _focusNodes[index + 1].requestFocus();
    }
    if (value.isEmpty && index > 0) {
      _focusNodes[index - 1].requestFocus();
    }
    setState(() => _error = null);
    if (_otp.length == 4) _verify();
  }

  Future<void> _verify() async {
    setState(() { _verifying = true; _error = null; });
    try {
      final isNew = await AuthService().verifyOtp(widget.phone, _otp);
      if (mounted) {
        if (isNew) {
          Navigator.pushReplacementNamed(context, '/');
        } else {
          Navigator.popUntil(context, (route) => route.isFirst);
        }
      }
    } catch (e) {
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _verifying = false;
        for (final c in _controllers) c.clear();
        _focusNodes[0].requestFocus();
      });
    }
  }

  Future<void> _resend() async {
    if (_resendSeconds > 0) return;
    try {
      await AuthService().sendOtp(widget.phone);
      _startTimer();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('OTP sent again'), behavior: SnackBarBehavior.floating));
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final maskedPhone = '${widget.phone.substring(0, 4)} •••• ${widget.phone.substring(widget.phone.length - 3)}';

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(backgroundColor: Colors.white, elevation: 0, foregroundColor: Colors.black),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Verify OTP', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            RichText(text: TextSpan(
              style: TextStyle(fontSize: 15, color: Colors.grey[600]),
              children: [
                const TextSpan(text: 'Enter the 4-digit code sent to '),
                TextSpan(text: maskedPhone, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87)),
              ],
            )),
            const SizedBox(height: 36),

            // OTP boxes
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(4, (i) => Container(
                width: 60,
                height: 64,
                margin: EdgeInsets.only(right: i < 3 ? 14 : 0),
                child: TextField(
                  controller: _controllers[i],
                  focusNode: _focusNodes[i],
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  maxLength: 1,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: (v) => _onDigitChanged(i, v),
                  style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
                  decoration: InputDecoration(
                    counterText: '',
                    filled: true,
                    fillColor: _focusNodes[i].hasFocus ? Colors.green[50] : Colors.grey[100],
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: Colors.green, width: 2)),
                    errorBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: Colors.red, width: 2)),
                  ),
                ),
              )),
            ),

            if (_error != null) ...[
              const SizedBox(height: 16),
              Center(child: Text(_error!, style: TextStyle(color: Colors.red[700], fontSize: 14))),
            ],

            const SizedBox(height: 28),

            // Verifying indicator
            if (_verifying)
              const Center(child: CircularProgressIndicator()),

            const SizedBox(height: 24),

            // Resend
            Center(
              child: _resendSeconds > 0
                  ? Text('Resend OTP in ${_resendSeconds}s', style: TextStyle(fontSize: 14, color: Colors.grey[500]))
                  : GestureDetector(
                      onTap: _resend,
                      child: Text('Resend OTP', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.green[700])),
                    ),
            ),

            const Spacer(),

            // Hint for dev
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: Colors.amber[50], borderRadius: BorderRadius.circular(12)),
              child: Row(children: [
                Icon(Icons.info_outline, size: 20, color: Colors.amber[800]),
                const SizedBox(width: 8),
                Expanded(child: Text('Dev mode: Check console for OTP',
                    style: TextStyle(fontSize: 13, color: Colors.amber[900]))),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}
