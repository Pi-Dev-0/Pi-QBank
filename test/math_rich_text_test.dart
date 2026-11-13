import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pi_qbank/utils/math_rich_text.dart';

void main() {
  testWidgets('a fraction bar stays as wide as its numerator and denominator',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 400,
              child: _FractionSample(),
            ),
          ),
        ),
      ),
    );

    final rule = find.byKey(const ValueKey('math-fraction-rule'));
    expect(rule, findsOneWidget);
    expect(tester.getSize(rule).width, lessThan(80),
        reason: 'the bar belongs to the fraction, not the whole line');
  });
}

class _FractionSample extends StatelessWidget {
  const _FractionSample();

  @override
  Widget build(BuildContext context) {
    return mathText(
      r'$\frac{1}{2}x + 3$',
      style: const TextStyle(fontSize: 20),
    );
  }
}
