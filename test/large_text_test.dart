// These screens were built at the default system font size and broke at a
// larger one, on a real phone, in a way nothing in the suite could see.
//
// The order confirmation was a Column with Spacers — which cannot scroll. Once
// the content grew past the screen the Spacers collapsed to zero and everything
// after them, Continue Shopping included, was clipped off the bottom with no
// way to reach it. The order number wrapped after its seventh character in the
// same screen, because the label sized itself first and left the value the
// remainder.
//
// Flutter fails a test on a render overflow, so rendering these at a large
// scale is the check. 2.0 is roughly the largest a phone offers.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dhanam_store/screens/order_success_screen.dart';

Widget _at(double scale, Widget child) => MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(scale)),
      child: MaterialApp(home: child),
    );

const _screen = OrderSuccessScreen(
  orderNumber: 'ORD000022',
  grandTotal: 40.0,
  deliverySlot: '2026-08-18 9 AM - 12 PM',
  paymentMethod: 'Cash on Delivery',
);

void main() {
  group('Order confirmation survives a large font scale', () {
    for (final scale in [1.0, 1.3, 1.6, 2.0]) {
      testWidgets('lays out at ${scale}x without overflowing', (tester) async {
        await tester.pumpWidget(_at(scale, _screen));
        await tester.pump(const Duration(milliseconds: 700));
        expect(tester.takeException(), isNull,
            reason: 'the confirmation screen overflows at ${scale}x — on a '
                'phone that is the button sliced off the bottom');
      });
    }

    testWidgets('Continue Shopping stays reachable at 2x', (tester) async {
      await tester.pumpWidget(_at(2.0, _screen));
      await tester.pump(const Duration(milliseconds: 700));

      final button = find.text('Continue Shopping');
      expect(button, findsOneWidget);
      // Scrollable is what makes it reachable when it no longer fits.
      await tester.ensureVisible(button);
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('the order number is not broken across lines', (tester) async {
      await tester.pumpWidget(_at(1.6, _screen));
      await tester.pump(const Duration(milliseconds: 700));

      final text = tester.widget<Text>(find.text('ORD000022'));
      final painter = TextPainter(
        text: TextSpan(text: text.data, style: text.style),
        textDirection: TextDirection.ltr,
        textScaler: const TextScaler.linear(1.6),
      )..layout();
      expect(painter.computeLineMetrics().length, 1,
          reason: 'the order number wrapped — a customer reading it back over '
              'the phone sees it split mid-number');
    });
  });
}
