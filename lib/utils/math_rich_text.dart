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
                    renderSegments(parseMath(text), currentStyle: scriptStyle),
              )),
            ),
          ));
        case MathRadical(:final body, :final math):
          final radicalStyle = math
              ? currentStyle.copyWith(fontStyle: FontStyle.italic)
              : currentStyle;
          result.add(WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('√', style: radicalStyle),
                Container(
                  decoration: BoxDecoration(
                    border: Border(
                        top: BorderSide(
                            color: radicalStyle.color ?? Colors.black)),
                  ),
                  padding: const EdgeInsets.only(left: 2, right: 2),
                  child: Text.rich(TextSpan(
                      children: renderSegments(
                    parseMath(body),
                    currentStyle: radicalStyle,
                  ))),
                ),
              ],
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
                      parseMath(numerator),
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
                      parseMath(denominator),
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

  return renderSegments(parseMath(raw), currentStyle: style);
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
