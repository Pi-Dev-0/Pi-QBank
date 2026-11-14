import 'package:flutter/material.dart';

import 'math_text.dart';

/// Builds Flutter inline spans from the same LaTeX-lite parser used by the
/// PDF and HTML exporters. This keeps imported questions from showing raw
/// `\frac`, `\sqrt`, or `\(...\)` markup in the browser question list.
List<InlineSpan> mathInlineSpans(
  String raw, {
  required TextStyle style,
}) {
  final size = style.fontSize ?? 14;

  // Rich text is the one surface where a bare caret is a power: the question
  // banks write forms such as `x^2` without wrapping every one in `$...$`.
  List<MathSegment> parse(String value) =>
      parseMath(value, allowBareSuperscript: true);

  List<InlineSpan> renderSegments(
    List<MathSegment> segments, {
    required TextStyle currentStyle,
  }) {
    final result = <InlineSpan>[];
    for (final segment in segments) {
      switch (segment) {
        case MathText(:final text, :final math):
          result.add(TextSpan(
            text: text,
            style: math
                ? currentStyle.copyWith(fontStyle: FontStyle.italic)
                : currentStyle,
          ));
        case MathScript(:final text, :final superscript, :final math):
          final scriptStyle = (math
                  ? currentStyle.copyWith(fontStyle: FontStyle.italic)
                  : currentStyle)
              .copyWith(fontSize: size * scriptFontScale);
          result.add(WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: Transform.translate(
              offset: Offset(0, superscript ? -size * 0.3 : size * 0.12),
              child: Text.rich(TextSpan(
                children:
                    renderSegments(parse(text), currentStyle: scriptStyle),
              )),
            ),
          ));
        case MathRadical(:final body, :final math):
          final radicalStyle = math
              ? currentStyle.copyWith(fontStyle: FontStyle.italic)
              : currentStyle;
          final radicalColor = radicalStyle.color ?? Colors.black;
          result.add(WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: IntrinsicHeight(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: (radicalStyle.fontSize ?? 14) * 0.55,
                    child: CustomPaint(
                      painter: _RadicalSignPainter(color: radicalColor),
                    ),
                  ),
                  Container(
                    decoration: BoxDecoration(
                      border: Border(
                          top: BorderSide(
                              width: 1.5, color: radicalColor)),
                    ),
                    padding:
                        const EdgeInsets.only(left: 3, right: 2, top: 2),
                    child: Text.rich(TextSpan(
                        children: renderSegments(
                      parse(body),
                      currentStyle: radicalStyle,
                    ))),
                  ),
                ],
              ),
            ),
          ));
        case MathFraction(:final numerator, :final denominator, :final math):
          final fractionStyle = (math
                  ? currentStyle.copyWith(fontStyle: FontStyle.italic)
                  : currentStyle)
              .copyWith(fontSize: size * fracFontScale, height: 1.0);
          final ruleColor = fractionStyle.color ?? Colors.black;
          result.add(WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              // IntrinsicWidth keeps the rule as wide as the wider of the
              // numerator and denominator. Without it the rule is a childless
              // Container inside a Column, which expands to the full line and
              // draws a fraction bar right across the card.
              child: IntrinsicWidth(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text.rich(TextSpan(
                        children: renderSegments(
                      parse(numerator),
                      currentStyle: fractionStyle,
                    ))),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 1),
                      child: Container(
                        key: const ValueKey('math-fraction-rule'),
                        height: 1,
                        color: ruleColor,
                      ),
                    ),
                    Text.rich(TextSpan(
                        children: renderSegments(
                      parse(denominator),
                      currentStyle: fractionStyle,
                    ))),
                  ],
                ),
              ),
            ),
          ));
      }
    }
    return result;
  }

  return renderSegments(parse(raw), currentStyle: style);
}

Widget mathText(
  String text, {
  required TextStyle style,
  TextAlign? textAlign,
  int? maxLines,
  TextOverflow? overflow,
}) {
  return Text.rich(
    TextSpan(children: mathInlineSpans(text, style: style)),
    textAlign: textAlign,
    maxLines: maxLines,
    overflow: overflow ?? TextOverflow.clip,
  );
}


/// Draws a scalable radical (√) sign that stretches to match the content height.
///
/// The shape mirrors the SVG path used by the HTML/Word exports:
/// a small hook at the bottom-left, then a long ascending stroke to the
/// top-right corner where the overline begins.
class _RadicalSignPainter extends CustomPainter {
  const _RadicalSignPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeJoin = StrokeJoin.miter;

    // Mirrors SVG viewBox 0 0 26 48, path: M0,30 L7,30 L11,46 L26,0
    final path = Path()
      ..moveTo(0, size.height * 30 / 48)
      ..lineTo(size.width * 7 / 26, size.height * 30 / 48)
      ..lineTo(size.width * 11 / 26, size.height * 46 / 48)
      ..lineTo(size.width, 0);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_RadicalSignPainter oldDelegate) =>
      color != oldDelegate.color;
}
