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

  testWidgets('a bare caret is shown as a power in rich text', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(child: _PowerSample()),
        ),
      ),
    );

    expect(find.textContaining('^'), findsNothing);

    final script = tester.widget<Text>(find.text('2'));
    final children = (script.textSpan! as TextSpan).children!;
    final power = children.whereType<TextSpan>().firstWhere(
          (span) => span.text == '2',
        );
    expect(power.style!.fontSize, lessThan(20),
        reason: 'the power is set smaller than the base text');
  });
}

class _PowerSample extends StatelessWidget {
  const _PowerSample();

  @override
  Widget build(BuildContext context) {
    return mathText(
      'x^2 + 3',
      style: const TextStyle(fontSize: 20),
    );
  }
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
