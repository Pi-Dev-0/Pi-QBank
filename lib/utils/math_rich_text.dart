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
        case MathFraction(:final numerator, :final denominator, :final math):
          final fractionStyle = (math
                  ? currentStyle.copyWith(fontStyle: FontStyle.italic)
                  : currentStyle)
              .copyWith(fontSize: size * fracFontScale);
          final ruleColor = fractionStyle.color ?? Colors.black;
          result.add(WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text.rich(TextSpan(
                      children: renderSegments(
                    parseMath(numerator),
                    currentStyle: fractionStyle,
                  ))),
                  Container(
                    height: 1,
                    constraints: const BoxConstraints(minWidth: 8),
                    color: ruleColor,
                  ),
                  Text.rich(TextSpan(
                      children: renderSegments(
                    parseMath(denominator),
                    currentStyle: fractionStyle,
                  ))),
                ],
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
