import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config.dart';

class AuthService extends ChangeNotifier {
  static const _tokenKey = 'auth_token';
  static const _userKey = 'auth_user';
  static final String _baseUrl = AppConfig.baseUrl;

  /// The session token is a 30-day credential, so it lives in the platform
  /// keystore rather than SharedPreferences.
  ///
  /// Every call falls back to SharedPreferences if the secure store throws.
  /// Encrypted storage fails on a small number of Android devices with broken
  /// keystore implementations, and being logged out is a worse outcome for
  /// those users than the storage we were already using.
  static const _secure = FlutterSecureStorage();

  Future<String?> _readToken() async {
    try {
      final fromSecure = await _secure.read(key: _tokenKey);
      if (fromSecure != null) return fromSecure;
    } catch (_) {
      // fall through to the legacy location
    }

    // Migrate anyone still holding a token from before this change, so
    // updating the app does not sign them out.
    final prefs = await SharedPreferences.getInstance();
    final legacy = prefs.getString(_tokenKey);
    if (legacy != null) {
      try {
        await _secure.write(key: _tokenKey, value: legacy);
        await prefs.remove(_tokenKey);
      } catch (_) {
        // Secure storage unavailable — leave it where it is.
      }
    }
    return legacy;
  }

  Future<void> _writeToken(String token) async {
    try {
      await _secure.write(key: _tokenKey, value: token);
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_tokenKey); // never leave a copy behind
      return;
    } catch (_) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_tokenKey, token);
    }
  }

  Future<void> _clearToken() async {
    try {
      await _secure.delete(key: _tokenKey);
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
  }

  static final AuthService _instance = AuthService._();
  factory AuthService() => _instance;
  AuthService._();

  final HttpClient _client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
  // `late` deliberately: FirebaseAuth.instance throws unless
  // Firebase.initializeApp has run, and as an eager field that made merely
  // touching this singleton — reading userId, say, which CartService does when
  // it saves — require Firebase. Production initialises Firebase in main()
  // before anything else, so nothing changes there; it means the rest of the
  // class can be exercised without it.
  late final fb.FirebaseAuth _fbAuth = fb.FirebaseAuth.instance;
  String? _token;
  Map<String, dynamic>? _user;
  bool _loaded = false;

  // Callback for when user changes — set by CartService
  static VoidCallback? onUserSwitch;

  // Firebase Phone Auth state
  String? _verificationId;
  int? _resendToken;

  bool get isLoggedIn => _token != null;
  String? get token => _token;
  String get userId => _user?['id'] ?? '';
  String get phone => _user?['phone'] ?? '';
  String get name => _user?['name'] ?? '';
  String get email => _user?['email'] ?? '';

  Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    _token = await _readToken();
    final userData = prefs.getString(_userKey);
    if (userData != null) {
      _user = jsonDecode(userData);
    }
    _loaded = true;
    if (_token != null) _fetchProfile();
    notifyListeners();
  }

  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body) async {
    final request = await _client.postUrl(Uri.parse('$_baseUrl$path'));
    request.headers.contentType = ContentType.json;
    if (_token != null) request.headers.set('Authorization', 'Bearer $_token');
    request.write(jsonEncode(body));
    final response = await request.close();
    final data = await response.transform(utf8.decoder).join();
    final result = jsonDecode(data) as Map<String, dynamic>;
    if (response.statusCode >= 400) {
      throw Exception(result['detail'] ?? 'Request failed');
    }
    return result;
  }

  Future<Map<String, dynamic>> _get(String path) async {
    final request = await _client.getUrl(Uri.parse('$_baseUrl$path'));
    if (_token != null) request.headers.set('Authorization', 'Bearer $_token');
    final response = await request.close();
    final data = await response.transform(utf8.decoder).join();
    return jsonDecode(data) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> _put(String path, Map<String, dynamic> body) async {
    final request = await _client.putUrl(Uri.parse('$_baseUrl$path'));
    request.headers.contentType = ContentType.json;
    if (_token != null) request.headers.set('Authorization', 'Bearer $_token');
    request.write(jsonEncode(body));
    final response = await request.close();
    final data = await response.transform(utf8.decoder).join();
    return jsonDecode(data) as Map<String, dynamic>;
  }

  /// Send OTP via Firebase Phone Auth.
  /// Returns a completer that resolves when verification completes.
  Future<void> sendOtpFirebase(
    String phone, {
    required void Function(String verificationId) onCodeSent,
    required void Function(String error) onError,
    required void Function() onAutoVerified,
  }) async {
    await _fbAuth.verifyPhoneNumber(
      phoneNumber: phone,
      forceResendingToken: _resendToken,
      timeout: const Duration(seconds: 60),
      verificationCompleted: (fb.PhoneAuthCredential credential) async {
        // Auto-verification (Android only — auto-reads the SMS)
        try {
          await _fbAuth.signInWithCredential(credential);
          await _loginWithFirebasePhone(phone);
          onAutoVerified();
        } catch (e) {
          onError(e.toString());
        }
      },
      verificationFailed: (fb.FirebaseAuthException e) {
        onError(_friendlyFirebaseError(e));
      },
      codeSent: (String verificationId, int? resendToken) {
        _verificationId = verificationId;
        _resendToken = resendToken;
        onCodeSent(verificationId);
      },
      codeAutoRetrievalTimeout: (String verificationId) {
        _verificationId = verificationId;
      },
    );
  }

  /// Verify the OTP code entered by the user.
  /// Returns true if the user is new (needs name).
  Future<bool> verifyOtpFirebase(String phone, String otp) async {
    if (_verificationId == null) {
      throw Exception('No verification in progress. Please request OTP again.');
    }
    final credential = fb.PhoneAuthProvider.credential(
      verificationId: _verificationId!,
      smsCode: otp,
    );
    await _fbAuth.signInWithCredential(credential);
    return _loginWithFirebasePhone(phone);
  }

  /// Sign in with a Google account.
  ///
  /// Free and unlimited, where the OTP path bills per SMS and leans on Play
  /// Integrity — which cannot vouch for an app the Play Store has never seen,
  /// so a sideloaded build falls back to reCAPTCHA and gets rate-limited.
  /// Nothing here needs an SMS, a captcha or an app attestation.
  ///
  /// What it proves is an email, not a phone number. The shop is cash on
  /// delivery, so a phone is still needed to hand goods over — the backend
  /// returns needsPhone and checkout asks for it.
  ///
  /// Returns true if this created a new customer.
  Future<bool> signInWithGoogle() async {
    await GoogleSignIn.instance.initialize();

    final GoogleSignInAccount account;
    try {
      account = await GoogleSignIn.instance.authenticate();
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        throw Exception('Sign-in cancelled');
      }
      rethrow;
    }

    final googleIdToken = account.authentication.idToken;
    if (googleIdToken == null) {
      throw Exception('Google did not return a sign-in token. Please try again.');
    }

    // Exchange Google's token for a Firebase one, so the backend verifies a
    // single kind of token however the customer signed in.
    final credential = fb.GoogleAuthProvider.credential(idToken: googleIdToken);
    await _fbAuth.signInWithCredential(credential);

    final idToken = await _fbAuth.currentUser?.getIdToken();
    if (idToken == null) {
      throw Exception('Sign-in failed. Please try again.');
    }

    final result = await _post('/auth/google-login', {'id_token': idToken});
    _token = result['token'];
    _user = {
      'id': result['user_id'],
      'phone': '',
      'name': account.displayName ?? '',
      'email': account.email,
    };
    needsPhone = result['needs_phone'] == true;

    await _writeToken(_token!);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userKey, jsonEncode(_user));

    notifyListeners();
    onUserSwitch?.call();
    _fetchProfile();
    return result['is_new_user'] == true;
  }

  /// True when the signed-in customer has no phone number on file. They can
  /// browse, but an order cannot be delivered without one.
  bool needsPhone = false;

  /// After Firebase verifies the phone, call our backend to get a JWT.
  /// Sends the Firebase ID token — the backend derives the phone number from
  /// it, so a client can never claim to be an arbitrary number.
  Future<bool> _loginWithFirebasePhone(String phone) async {
    final idToken = await _fbAuth.currentUser?.getIdToken();
    if (idToken == null) {
      throw Exception('Verification failed. Please try again.');
    }
    final result = await _post('/auth/firebase-login', {'id_token': idToken});
    _token = result['token'];
    _user = {'id': result['user_id'], 'phone': phone, 'name': '', 'email': ''};

    await _writeToken(_token!);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userKey, jsonEncode(_user));

    notifyListeners();
    onUserSwitch?.call();
    _fetchProfile();
    return result['is_new_user'] == true;
  }

  String _friendlyFirebaseError(fb.FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-phone-number':
        return 'Invalid phone number format';
      case 'too-many-requests':
        return 'Too many attempts. Please try again later';
      case 'quota-exceeded':
        return 'SMS quota exceeded. Try again tomorrow';
      case 'network-request-failed':
        return 'Network error. Check your connection';
      default:
        return e.message ?? 'Verification failed';
    }
  }

  // Keep old methods for backward compatibility (dev mode fallback)
  Future<String?> sendOtp(String phone) async {
    final result = await _post('/auth/send-otp', {'phone': phone});
    return result['otp']?.toString();
  }

  Future<bool> verifyOtp(String phone, String otp) async {
    final result = await _post('/auth/verify-otp', {'phone': phone, 'otp': otp});
    _token = result['token'];
    _user = {'id': result['user_id'], 'phone': phone, 'name': '', 'email': ''};

    await _writeToken(_token!);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userKey, jsonEncode(_user));

    notifyListeners();
    onUserSwitch?.call();
    _fetchProfile();
    return result['is_new_user'] == true;
  }

  Future<void> _fetchProfile() async {
    try {
      final data = await _get('/auth/me');
      _user = data;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_userKey, jsonEncode(_user));
      notifyListeners();
    } catch (_) {}
  }

  Future<void> updateProfile({String? name, String? email}) async {
    final body = <String, dynamic>{};
    if (name != null) body['name'] = name;
    if (email != null) body['email'] = email;
    await _put('/auth/profile', body);
    if (name != null) _user?['name'] = name;
    if (email != null) _user?['email'] = email;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userKey, jsonEncode(_user));
    notifyListeners();
  }

  /// Permanently delete the user's account and all data (backend + Firebase),
  /// then clear the local session. Required by Google Play policy.
  Future<void> deleteAccount() async {
    final request = await _client.deleteUrl(Uri.parse('$_baseUrl/auth/account'));
    if (_token != null) request.headers.set('Authorization', 'Bearer $_token');
    final response = await request.close();
    final data = await response.transform(utf8.decoder).join();
    if (response.statusCode >= 400) {
      final result = jsonDecode(data) as Map<String, dynamic>;
      throw Exception(result['detail'] ?? 'Failed to delete account');
    }
    try { await _fbAuth.currentUser?.delete(); } catch (_) {}
    await logout();
  }

  Future<void> logout() async {
    _token = null;
    _user = null;
    _verificationId = null;
    _resendToken = null;
    try { await _fbAuth.signOut(); } catch (_) {}
    // Without this the chooser never appears again and the same
    // account is reused, which looks like sign-out failing.
    try { await GoogleSignIn.instance.signOut(); } catch (_) {}
    needsPhone = false;
    await _clearToken();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_userKey);
    notifyListeners();
    onUserSwitch?.call();
  }
}
