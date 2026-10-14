import 'package:flutter_test/flutter_test.dart';

import 'package:pi_qbank/utils/math_text.dart';

/// Your question bank is authored in LaTeX, so these are the forms that
/// actually appear in it — `\frac`, `$...$`, `\text{}`, `\quad`,
/// `\left`/`\right` — not an invented subset.
void main() {
  group('fractions', () {
    test('a frac marker becomes a fraction segment', () {
      final f = parseMath(r'\frac{2+x}{3}').single as MathFraction;
      expect(f.numerator, '2+x');
      expect(f.denominator, '3');
    });

    test('several in one line', () {
      final segs = parseMath(r'\frac{a}{b} = \frac{c}{d}');
      expect(segs.whereType<MathFraction>(), hasLength(2));
    });

    test('braces nest', () {
      final f = parseMath(r'\frac{x+{1}}{y_{2}}').single as MathFraction;
      expect(f.numerator, 'x+{1}');
      expect(f.denominator, 'y_{2}');
    });

    test('empty groups are allowed', () {
      final f = parseMath(r'\frac{}{3}').single as MathFraction;
      expect(f.numerator, '');
      expect(f.denominator, '3');
    });

    test('a malformed marker never swallows the rest of the question', () {
      // The important property: a typo must cost one marker, not the question.
      expect(parseMath(r'\frac{x'), hasLength(1));
      expect(parseMath(r'\frac{x+2}'), hasLength(1));
      expect(parseMath(r'\frac{x+2}{'), hasLength(1));
      final segs = parseMath(r'\frac{x+2}{3} পরে');
      expect(segs, hasLength(2));
    });
  });

  group('inline math delimiters', () {
    test('dollars are removed and the content marked as maths', () {
      final segs = parseMath(r'$3x - 2y = 4$');
      expect(
          segs.whereType<MathText>().map((t) => t.text).join(), '3x - 2y = 4');
      expect(segs.first.isMath, isTrue);
    });

    test('a maths span around plain Bangla stays upright', () {
      final segs = parseMath(r'সমীকরণ $x + y$ জোট।');
      final maths = segs.whereType<MathText>().where((t) => t.isMath);
      expect(maths.map((t) => t.text).join(), 'x + y');
      final plain = segs.whereType<MathText>().where((t) => !t.isMath);
      expect(plain.map((t) => t.text).join(), 'সমীকরণ  জোট।');
    });

    test('an unclosed dollar does not lose the text', () {
      expect(latexToPlainText(r'$x + 1'), 'x + 1');
    });
  });

  group('commands the question bank uses', () {
    test(r'\quad becomes whitespace, not the literal command', () {
      final plain = latexToPlainText(r'2 = 3; \quad 5 = 2');
      expect(plain, isNot(contains(r'\quad')));
      expect(plain, matches(RegExp(r'2 = 3;\s+5 = 2')));
    });

    test(r'\text{...} becomes upright text', () {
      // The inner space is the author's and is kept, as LaTeX would.
      final plain = latexToPlainText(r'2\text{ একটি জোট}');
      expect(plain, matches(RegExp(r'2\s*একটি জোট')));
      expect(plain, isNot(contains(r'\text')));
    });

    test(r'\left and \right disappear, the delimiters stay', () {
      expect(latexToPlainText(r'\left(\frac{1}{2}, 7\right)'), '((1)/(2), 7)');
    });

    test('symbol commands', () {
      expect(latexToPlainText(r'a \times b'), 'a × b');
      expect(latexToPlainText(r'a \leq b'), 'a ≤ b');
      expect(latexToPlainText(r'a \geq b'), 'a ≥ b');
      expect(latexToPlainText(r'a \neq b'), 'a ≠ b');
      expect(latexToPlainText(r'\pi r^2'), 'π r^2');
      expect(latexToPlainText(r'\sqrt{2}'), '√2');
    });

    test('an unknown command stays visible instead of vanishing', () {
      expect(latexToPlainText(r'\notacommand x'), r'\notacommand x');
    });
  });

  group('super and subscripts', () {
    test('braced and single-character forms', () {
      final segs = parseMath('x^{2} + a_n');
      final scripts = segs.whereType<MathScript>().toList();
      expect(scripts.map((s) => s.text), ['2', 'n']);
      expect(scripts.map((s) => s.superscript), [true, false]);
    });

    test('flattens to a caret form for text outputs', () {
      expect(latexToPlainText('x^{2}'), 'x^2');
      expect(latexToPlainText('a_{n}'), 'a_n');
    });
  });

  group('bare typed fractions', () {
    test('single digit over single digit becomes a glyph', () {
      expect(normaliseTypedFractions('1/2'), '½');
      expect(normaliseTypedFractions('7/8'), '⅞');
    });

    test('expressions are left exactly as typed', () {
      // The real case from the bank.
      expect(normaliseTypedFractions('(2-x)/3'), '(2-x)/3');
      expect(normaliseTypedFractions('(2)/3'), '(2)/3');
      expect(normaliseTypedFractions('12/3'), '12/3');
      expect(normaliseTypedFractions('a/2'), 'a/2');
    });

    test('a fraction with no glyph keeps its digits', () {
      expect(normaliseTypedFractions('4/7'), '4/7');
    });

    test('already-converted text is not converted again', () {
      expect(normaliseTypedFractions('½'), '½');
    });
  });

  test('the first question of the bank flattens to something readable', () {
    const stem = r'\frac{2+x}{3} + \frac{y-1}{4} = 3; \quad '
        r'\frac{2x-3}{5} - \frac{2(1-2y)}{10} = 2 '
        r'\text{ একটি দুই চলকবিশিষ্ট সমীকরণ জোট।}';
    final plain = latexToPlainText(stem);
    expect(plain, contains('(2+x)/(3)'));
    expect(plain, contains('(2(1-2y))/(10)'));
    expect(plain, contains('একটি দুই চলকবিশিষ্ট সমীকরণ জোট'));
    expect(plain, isNot(contains(r'\frac')));
    expect(plain, isNot(contains(r'\quad')));
    expect(plain, isNot(contains(r'\text')));
  });

  test('every symbol glyph is one character', () {
    for (final e in kLatexSymbols.entries) {
      if (e.key.endsWith(' ')) continue;
      expect(e.value.runes.length, 1, reason: e.key);
    }
  });
}
