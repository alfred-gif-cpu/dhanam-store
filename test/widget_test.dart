// Widget tests for the customer login flow:
//   - phone-number validation gating the "Get OTP" button
//   - the new "Login as Staff / Owner" entry and its navigation
//   - OTP screen rendering (boxes, masked phone, dev-OTP hint)

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dhanam_store/screens/login_screen.dart';
import 'package:dhanam_store/screens/otp_screen.dart';

ElevatedButton _getOtpButton(WidgetTester tester) {
  final finder = find.widgetWithText(ElevatedButton, 'Get OTP');
  expect(finder, findsOneWidget);
  return tester.widget<ElevatedButton>(finder);
}

void main() {
  group('LoginScreen', () {
    testWidgets('renders header, phone field and staff-login entry', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
      await tester.pump();

      expect(find.text('Dhanam Store'), findsOneWidget);
      expect(find.text('Mobile Number'), findsOneWidget);
      expect(find.text('Get OTP'), findsOneWidget);
      expect(find.text('Login as Staff / Owner'), findsOneWidget);
    });

    testWidgets('Get OTP is disabled until exactly 10 digits are entered', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
      await tester.pump();

      // Initially disabled (no input)
      expect(_getOtpButton(tester).onPressed, isNull);

      // Partial number -> still disabled
      await tester.enterText(find.byType(TextField), '98765');
      await tester.pump();
      expect(_getOtpButton(tester).onPressed, isNull);

      // Full 10-digit number -> enabled
      await tester.enterText(find.byType(TextField), '9876543210');
      await tester.pump();
      expect(_getOtpButton(tester).onPressed, isNotNull);
    });

    testWidgets('phone field rejects non-digits and caps at 10 chars', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
      await tester.pump();

      final field = find.byType(TextField);
      await tester.enterText(field, 'ab12cd34ef56gh78'); // letters + >10 digits
      await tester.pump();

      final widget = tester.widget<TextField>(field);
      final text = widget.controller!.text;
      expect(text, '12345678'); // letters stripped, digits kept
      expect(text.length <= 10, isTrue);
    });

    testWidgets('tapping "Login as Staff / Owner" navigates to the admin login', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
      await tester.pump();

      await tester.tap(find.text('Login as Staff / Owner'));
      await tester.pumpAndSettle();

      // AdminLoginScreen shows this header
      expect(find.text('Admin Panel'), findsOneWidget);
    });
  });

  group('OtpScreen', () {
    testWidgets('renders 4 OTP boxes, masked phone and dev hint', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: OtpScreen(phone: '+919876543210', devOtp: '1234'),
      ));
      await tester.pump();

      expect(find.text('Verify OTP'), findsOneWidget);
      // 4 single-digit entry boxes
      expect(find.byType(TextField), findsNWidgets(4));
      // masked phone keeps the +91 prefix and last 3 digits (rendered in a RichText)
      expect(find.textContaining('+919', findRichText: true), findsOneWidget);
      expect(find.textContaining('210', findRichText: true), findsOneWidget);
      // dev OTP hint surfaced when provided
      expect(find.textContaining('Dev OTP: 1234'), findsOneWidget);
    });

    testWidgets('hides dev hint when no dev OTP is provided', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: OtpScreen(phone: '+919876543210'),
      ));
      await tester.pump();

      expect(find.textContaining('Dev OTP'), findsNothing);
    });
  });
}
