import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/auth_service.dart';
import 'home_screen.dart';

class OtpScreen extends StatefulWidget {
  final String phone;
  const OtpScreen({super.key, required this.phone});

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final List<TextEditingController> _controllers = List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());
  final _nameController = TextEditingController();
  final _nameFocus = FocusNode();
  bool _verifying = false;
  bool _needName = false;
  bool _savingName = false;
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
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    _nameController.dispose();
    _nameFocus.dispose();
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
    if (value.length == 1 && index < 5) {
      _focusNodes[index + 1].requestFocus();
    }
    if (value.isEmpty && index > 0) {
      _focusNodes[index - 1].requestFocus();
    }
    setState(() => _error = null);
    if (_otp.length == 6) _verify();
  }

  Future<void> _verify() async {
    setState(() { _verifying = true; _error = null; });
    try {
      final isNewUser = await AuthService().verifyOtpFirebase(widget.phone, _otp);
      if (!mounted) return;
      if (isNewUser) {
        setState(() { _needName = true; _verifying = false; });
        WidgetsBinding.instance.addPostFrameCallback((_) => _nameFocus.requestFocus());
      } else {
        _goHome();
      }
    } catch (e) {
      String errorMsg = e.toString().replaceFirst('Exception: ', '');
      if (errorMsg.contains('invalid-verification-code') || errorMsg.contains('invalid-sms-code')) {
        errorMsg = 'Invalid OTP. Please try again.';
      } else if (errorMsg.contains('session-expired')) {
        errorMsg = 'OTP expired. Please request a new one.';
      }
      setState(() {
        _error = errorMsg;
        _verifying = false;
        for (final c in _controllers) {
          c.clear();
        }
        _focusNodes[0].requestFocus();
      });
    }
  }

  Future<void> _submitName() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Please enter your name');
      return;
    }
    setState(() { _savingName = true; _error = null; });
    try {
      await AuthService().updateProfile(name: name);
      _goHome();
    } catch (e) {
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _savingName = false;
      });
    }
  }

  void _goHome() {
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const HomeScreen()),
      (route) => false,
    );
  }

  Future<void> _resend() async {
    if (_resendSeconds > 0) return;
    setState(() => _error = null);
    await AuthService().sendOtpFirebase(
      widget.phone,
      onCodeSent: (_) {
        _startTimer();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('OTP sent again'), behavior: SnackBarBehavior.floating));
        }
      },
      onError: (error) {
        if (mounted) setState(() => _error = error);
      },
      onAutoVerified: () => _goHome(),
    );
  }

  Widget _buildNameStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("What's your name?", style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text('Looks like you are new here. Tell us your name to finish setting up your account.',
            style: TextStyle(fontSize: 15, color: Colors.grey[600])),
        const SizedBox(height: 36),
        TextField(
          controller: _nameController,
          focusNode: _nameFocus,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.done,
          onChanged: (_) => setState(() => _error = null),
          onSubmitted: (_) => _submitName(),
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          decoration: InputDecoration(
            hintText: 'Full name',
            prefixIcon: const Icon(Icons.person_outline),
            filled: true,
            fillColor: Colors.grey[100],
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Colors.blue, width: 2)),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: TextStyle(color: Colors.red[700], fontSize: 14)),
        ],
        const SizedBox(height: 28),
        SizedBox(
          width: double.infinity,
          height: 54,
          child: ElevatedButton(
            onPressed: _savingName ? null : _submitName,
            child: _savingName
                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Continue'),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final maskedPhone = '${widget.phone.substring(0, 4)} •••• ${widget.phone.substring(widget.phone.length - 3)}';

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(backgroundColor: Colors.white, elevation: 0, foregroundColor: Colors.black),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: _needName ? _buildNameStep() : Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Verify OTP', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            RichText(text: TextSpan(
              style: TextStyle(fontSize: 15, color: Colors.grey[600]),
              children: [
                const TextSpan(text: 'Enter the 6-digit code sent to '),
                TextSpan(text: maskedPhone, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87)),
              ],
            )),
            const SizedBox(height: 36),

            // OTP boxes (6 digits for Firebase)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(6, (i) => Container(
                width: 48,
                height: 58,
                margin: EdgeInsets.only(right: i < 5 ? 8 : 0),
                child: TextField(
                  controller: _controllers[i],
                  focusNode: _focusNodes[i],
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  maxLength: 1,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: (v) => _onDigitChanged(i, v),
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  decoration: InputDecoration(
                    counterText: '',
                    filled: true,
                    fillColor: _focusNodes[i].hasFocus ? Colors.blue[50] : Colors.grey[100],
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Colors.blue, width: 2)),
                  ),
                ),
              )),
            ),

            if (_error != null) ...[
              const SizedBox(height: 16),
              Center(child: Text(_error!, style: TextStyle(color: Colors.red[700], fontSize: 14))),
            ],

            const SizedBox(height: 28),

            if (_verifying)
              const Center(child: CircularProgressIndicator()),

            const SizedBox(height: 24),

            // Resend
            Center(
              child: _resendSeconds > 0
                  ? Text('Resend OTP in ${_resendSeconds}s', style: TextStyle(fontSize: 14, color: Colors.grey[500]))
                  : GestureDetector(
                      onTap: _resend,
                      child: Text('Resend OTP', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.blue[700])),
                    ),
            ),

            const Spacer(),
          ],
        ),
      ),
    );
  }
}
