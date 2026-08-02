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

      expect(find.text('Dhanam Stores'), findsOneWidget);
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
    // These tests stopped compiling when the screen dropped its devOtp
    // parameter and moved from four boxes to six, and nothing was running
    // them, so the rot went unnoticed. They now assert what the screen
    // actually does.
    testWidgets('renders the header and the masked phone number', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: OtpScreen(phone: '+919876543210'),
      ));
      await tester.pump();

      expect(find.text('Verify OTP'), findsOneWidget);
      expect(find.textContaining('6-digit', findRichText: true), findsOneWidget);
      // The masked form keeps the +91 prefix and the last digits, so the
      // customer can tell which number the code went to.
      expect(find.textContaining('+919', findRichText: true), findsOneWidget);
      expect(find.textContaining('210', findRichText: true), findsOneWidget);
    });

    testWidgets('takes six digits through one hidden field', (tester) async {
      // The six boxes on screen are display-only Text widgets: per-box
      // TextFields corrupted the typed glyph on some devices. Input goes to a
      // single invisible field stacked over them, so there is exactly one.
      await tester.pumpWidget(const MaterialApp(
        home: OtpScreen(phone: '+919876543210'),
      ));
      await tester.pump();

      final field = find.byType(TextField);
      expect(field, findsOneWidget);
      expect(tester.widget<TextField>(field).maxLength, 6);
    });

    testWidgets('shows the typed code in the boxes', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: OtpScreen(phone: '+919876543210'),
      ));
      await tester.pump();

      await tester.enterText(find.byType(TextField), '1234');
      await tester.pump();

      for (final digit in ['1', '2', '3', '4']) {
        expect(find.text(digit), findsWidgets, reason: 'digit $digit is not displayed');
      }
    });
  });
}
