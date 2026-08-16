// The bounce is an overshoot: the value travels past where it is going and
// comes back. That is the property worth pinning, because a later "tidy up" of
// AppMotion.entrance to a plain easeOut would still compile, still animate, and
// silently take the spring back out.
//
// The second half matters more. Overshoot curves belong on movement and never
// on opacity — Flutter clamps an opacity outside 0..1, so the fade stalls at
// the ends and the entrance looks broken rather than lively. AppMotion.fade
// exists to be the safe one, so it is asserted to stay in range.

import 'package:flutter_test/flutter_test.dart';

import 'package:dhanam_store/theme.dart';

/// Curves are only defined on 0..1; sample densely across it.
Iterable<double> _samples() sync* {
  for (var i = 0; i <= 200; i++) {
    yield i / 200;
  }
}

void main() {
  group('AppMotion.entrance', () {
    test('overshoots its end value — this is the bounce', () {
      final peak = _samples()
          .map(AppMotion.entrance.transform)
          .reduce((a, b) => a > b ? a : b);

      expect(peak, greaterThan(1.0),
          reason: 'entrance never travels past its end value, so nothing springs');
    });

    test('starts and ends where it should', () {
      expect(AppMotion.entrance.transform(0), closeTo(0.0, 0.001));
      expect(AppMotion.entrance.transform(1), closeTo(1.0, 0.001));
    });
  });

  group('AppMotion.pop', () {
    test('overshoots, and never inverts what it scales', () {
      final values = _samples().map(AppMotion.pop.transform).toList();

      expect(values.reduce((a, b) => a > b ? a : b), greaterThan(1.0));
      // Applied as Transform.scale on the heart and the cart quantity. A
      // negative multiplier would mirror them.
      expect(values.every((v) => v >= 0.0), isTrue,
          reason: 'pop goes negative, which would flip whatever it scales');
    });
  });

  group('AppMotion.fade', () {
    test('never leaves 0..1, because it is applied to opacity', () {
      for (final t in _samples()) {
        final v = AppMotion.fade.transform(t);
        expect(v, inInclusiveRange(0.0, 1.0),
            reason: 'fade reached $v at t=$t — Flutter clamps opacity, so the '
                'fade would stall at the ends instead of easing');
      }
    });

    test('is not an overshoot curve', () {
      expect(AppMotion.fade, isNot(same(AppMotion.entrance)));
      expect(AppMotion.fade, isNot(same(AppMotion.pop)));
    });
  });
}
