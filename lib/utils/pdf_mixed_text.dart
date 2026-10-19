import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../bijoy_helper/bijoy_helper.dart' as bh;
import 'math_text.dart';

/// Measures a string at a given font size, in points.
///
/// Passed in rather than importing the measurer, which would close an import
/// cycle. Without it a fraction's rule has no width to draw at, so the renderer
/// falls back to stretching — which puts a wide gap in the line.
typedef MathTextMeasurer = double Function(
    String text, double fontSize, bool bold);

/// One contiguous run of text drawn with a single font.
class PdfTextRun {
  const PdfTextRun(this.text, this.isBangla);

  final String text;

  /// True when the run is Bangla and must be drawn in the Bijoy-ANSI font.
  final bool isBangla;

  bool get isEmpty => text.isEmpty;
}

/// Split [text] into alternating Bangla / Latin runs, exactly as the PDF will
/// draw them.
///
/// Both the renderer ([buildPdfTextSpan]) and the layout estimator
/// ([PdfTextMetrics]) go through this function, so a measured line count can
/// never disagree with the rendered one. Splitting the logic would let a stray
/// soft hyphen or a differently-classified run silently desynchronise the two.
///
/// The Bijoy converter inserts U+00AD (soft hyphen) as a reordering marker. It
/// is invisible in normal text, but no font here has a glyph for it, so it
/// would render as a black box in the middle of a word ("প্ল্যাটফর্ম").
List<PdfTextRun> splitPdfTextRuns(String text) {
  final segments = bh.BanglaTextProcessor.processText(text);
  if (segments.isEmpty) {
    return const [PdfTextRun('', false)];
  }
  return segments
      .map((seg) => PdfTextRun(seg.text.replaceAll('­', ''), seg.isBangla))
      .toList();
}

/// Build a [pw.TextSpan] for text that mixes Bangla, Latin and LaTeX in the
/// PDF.
///
/// ## Why this exists
///
/// SutonnyMJ is a **Bijoy-ANSI** font, not a Unicode one: it has no Bengali
/// codepoints at all, and its cmap maps the ASCII range onto Bengali glyphs.
/// Rendering `ABC…` in it produces Bengali script, and `0123456789` produces
/// `০১২৩৪৫৬৭৮৯`. So English set in SutonnyMJ is unreadable ("Greenfield Public
/// School" -> "Gfeibvdtbdu bdqQ"), while Bangla is perfectly fine once it has
/// been converted to the Bijoy encoding.
///
/// The fix is per-segment fonts: Bangla stays in [banglaStyle] (SutonnyMJ), and
/// every Latin run is set in a standard Latin font.
///
/// ## Gotcha: copyWith(font:) is NOT sufficient
///
/// `pw.TextStyle.font` is a *derived getter*, not a stored field. `copyWith`
/// forwards `font` to the constructor, which only uses it to seed
/// `fontNormal` / `fontBold` / `fontItalic` / `fontBoldItalic` when those are
/// still null — and after `TextStyle(font: sutonny)` they are not. The
/// argument is therefore silently discarded and the Bangla font survives, so
/// `copyWith(font: other)` alone leaves every Latin run rendering as gibberish.
/// All four slots must be overridden explicitly.
///
/// ## Note on conversion
///
/// Bangla segments returned by [bh.BanglaTextProcessor.processText] are
/// *already* Bijoy-encoded, so they must not be converted a second time.
///
/// [bold] selects Helvetica Bold for Latin runs; otherwise Helvetica is used.
pw.TextSpan buildPdfTextSpan(
  String text,
  pw.TextStyle banglaStyle, {
  bool bold = false,
  MathTextMeasurer? measure,
  pw.Font? symbolFont,
  Set<int>? symbolCoverage,
}) {
  final latin = bold ? pw.Font.helveticaBold() : pw.Font.helvetica();

  final children = _spansForRaw(text,
      banglaStyle: banglaStyle,
      latin: latin,
      bold: bold,
      measure: measure,
      symbolFont: symbolFont,
      symbolCoverage: symbolCoverage);
  if (children.isEmpty) {
    return pw.TextSpan(text: '', style: banglaStyle);
  }
  return pw.TextSpan(children: children);
}

/// Spans for [raw], which is still ordinary Unicode text.
///
/// LaTeX is parsed here, **before** the Bangla conversion — see
/// [_spansForParsed] for why the order is not free.
List<pw.InlineSpan> _spansForRaw(
  String raw, {
  required pw.TextStyle banglaStyle,
  required pw.Font latin,
  required bool bold,
  MathTextMeasurer? measure,
  pw.Font? symbolFont,
  Set<int>? symbolCoverage,
}) =>
    _spansForParsed(parseMath(raw),
        banglaStyle: banglaStyle,
        latin: latin,
        bold: bold,
        measure: measure,
        symbolFont: symbolFont,
        symbolCoverage: symbolCoverage);

/// Spans for text already split into segments, still unconverted.
///
/// This is the only place the Bangla conversion happens, and it happens after
/// parsing. Doing it first corrupts the text: Bijoy encodes `থ` as `_` and the
/// `্ব` conjuncts (`ণ্ব`, `ন্ব`, `ম্ব`, `স্ব`) as `^`, which are precisely the
/// characters a script parser reads as a subscript and a superscript. Every
/// `থ` in every question was being swallowed and its following vowel sign drawn
/// as a lowered script.
List<pw.InlineSpan> _spansForParsed(
  List<MathSegment> segments, {
  required pw.TextStyle banglaStyle,
  required pw.Font latin,
  required bool bold,
  MathTextMeasurer? measure,
  pw.Font? symbolFont,
  Set<int>? symbolCoverage,
}) {
  final out = <pw.InlineSpan>[];

  for (final segment in segments) {
    switch (segment) {
      case MathFraction(:final numerator, :final denominator, :final math):
        if (measure == null) {
          // Without a measurement the rule has no width to draw at, and a rule
          // given the whole line draws a bar across the page. Fall back to the
          // inline form, which is always correct, rather than a stack that
          // looks broken.
          out.addAll(_textSpans('($numerator)/($denominator)',
              banglaStyle: banglaStyle, latin: latin, bold: bold, math: math,
              symbolFont: symbolFont, symbolCoverage: symbolCoverage));
          continue;
        }
        out.add(_fractionSpan(numerator, denominator,
            style: _anchorStyle(banglaStyle, math),
            bold: bold,
            measure: measure,
            render: (t, at) => pw.RichText(
                text: pw.TextSpan(
                    style: at,
                    children: _spansForRaw(t,
                        banglaStyle: at,
                        latin: latin,
                        bold: bold,
                        measure: measure,
                        symbolFont: symbolFont,
                        symbolCoverage: symbolCoverage)))));

      case MathScript(:final text, :final superscript, :final math):
        out.add(_scriptSpan(text,
            superscript: superscript,
            style: _anchorStyle(banglaStyle, math),
            bold: bold,
            render: (t, at) => pw.RichText(
                text: pw.TextSpan(
                    style: at,
                    children: _spansForRaw(t,
                        banglaStyle: at,
                        latin: latin,
                        bold: bold,
                        measure: measure,
                        symbolFont: symbolFont,
                        symbolCoverage: symbolCoverage)))));

      case MathText(:final text, :final math):
        out.addAll(_textSpans(text,
            banglaStyle: banglaStyle, latin: latin, bold: bold, math: math,
            symbolFont: symbolFont, symbolCoverage: symbolCoverage));
    }
  }
  return out;
}

/// Draws a string that is still ordinary Unicode text, splitting it into
/// Bangla and Latin runs and setting each in its own font.
/// Whitespace runes that stay in the run around them rather than being drawn
/// as an undrawable box. Mirrors the measurer's set, so the two agree.
bool _isPdfWhitespace(int rune) => const {
      0x09, 0x0a, 0x0d, 0x20, 0x00a0, 0x1680, 0x2000, 0x2001, 0x2002, //
      0x2003, 0x2004, 0x2005, 0x2006, 0x2007, 0x2008, 0x2009, 0x200a,
      0x202f, 0x205f, 0x3000,
    }.contains(rune);

List<pw.InlineSpan> _textSpans(
  String text, {
  required pw.TextStyle banglaStyle,
  required pw.Font latin,
  required bool bold,
  required bool math,
  pw.Font? symbolFont,
  Set<int>? symbolCoverage,
}) {
  final out = <pw.InlineSpan>[];
  final banglaFont = banglaStyle.fontNormal;

  for (final run in splitPdfTextRuns(text)) {
    if (run.isEmpty) continue;

    final buffer = StringBuffer();
    pw.Font? bufferFont;

    void flush() {
      final font = bufferFont;
      if (buffer.isEmpty || font == null) {
        buffer.clear();
        return;
      }
      var style = run.isBangla
          ? banglaStyle
          : banglaStyle.copyWith(
              fontNormal: font,
              fontBold: font,
              fontItalic: font,
              fontBoldItalic: font,
            );
      if (math && !run.isBangla) {
        style = style.copyWith(fontStyle: pw.FontStyle.italic);
      }
      out.add(pw.TextSpan(text: buffer.toString(), style: style));
      buffer.clear();
    }

    for (final rune in run.text.runes) {
      if (_isPdfWhitespace(rune)) {
        bufferFont ??= run.isBangla ? (banglaFont ?? latin) : latin;
        buffer.writeCharCode(rune);
        continue;
      }

      pw.Font match;
      if (run.isBangla) {
        match = banglaFont ?? latin;
      } else {
        final helveticaCovers =
            (rune >= 0x20 && rune <= 0x7e) || (rune >= 0xa0 && rune <= 0xff);
        if (helveticaCovers) {
          match = latin;
        } else if (symbolFont != null &&
            (symbolCoverage?.contains(rune) ?? false)) {
          match = symbolFont;
        } else {
          match = latin;
        }
      }

      if (bufferFont != null && !identical(bufferFont, match)) flush();
      bufferFont = match;
      buffer.writeCharCode(rune);
    }
    flush();
  }

  return out;
}

/// The style a typeset piece is anchored by.
///
/// Carries the size and colour of the surrounding text; which font actually
/// draws the glyphs is decided per run, inside [render].
pw.TextStyle _anchorStyle(pw.TextStyle banglaStyle, bool math) =>
    math ? banglaStyle.copyWith(fontStyle: pw.FontStyle.italic) : banglaStyle;

/// A stacked fraction, drawn inline as a widget so the rule lines up.
///
/// The rule spans the wider of numerator and denominator. That width is
/// measured rather than assumed: stretching the column to fill the line instead
/// would put a gap the width of the column between the fraction and the words
/// around it.
pw.WidgetSpan _fractionSpan(
  String numerator,
  String denominator, {
  required pw.TextStyle style,
  required bool bold,
  required pw.Widget Function(String, pw.TextStyle) render,
  required MathTextMeasurer measure,
}) {
  final size = style.fontSize ?? 11;
  // Numerator and denominator are set smaller than the surrounding text, which
  // is what keeps a stacked fraction from dominating its line.
  final small = style.copyWith(fontSize: size * fracFontScale);

  final n = measure(numerator, size * fracFontScale, bold);
  final d = measure(denominator, size * fracFontScale, bold);
  final ruleWidth = (n > d ? n : d) + fracPaddingX * 2;

  // A null colour would leave the rule invisible, which looks like a missing
  // fraction rather than a missing line.
  final rule = pw.Container(
    height: fracRuleHeight,
    color: style.color ?? PdfColors.black,
    width: ruleWidth,
  );

  return pw.WidgetSpan(
    // See fracBaselineShift: an inline widget is anchored by its bottom.
    baseline: -size * fracBaselineShift,
    style: style,
    child: pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: fracPaddingX),
      child: pw.Column(
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          pw.SizedBox(width: ruleWidth, child: render(numerator, small)),
          rule,
          pw.SizedBox(width: ruleWidth, child: render(denominator, small)),
        ],
      ),
    ),
  );
}

/// A raised or lowered run. The pdf package has no super/subscript, so the
/// size and the offset are done here.
pw.WidgetSpan _scriptSpan(
  String text, {
  required bool superscript,
  required pw.TextStyle style,
  required bool bold,
  required pw.Widget Function(String, pw.TextStyle) render,
}) {
  final size = style.fontSize ?? 11;
  final small = style.copyWith(fontSize: size * scriptFontScale);

  return pw.WidgetSpan(
    baseline: 0,
    style: style,
    child: pw.Transform.translate(
      // PDF y grows upward, so a positive offset is a rise.
      offset: PdfPoint(
          0, superscript ? size * superscriptRise : -size * subscriptDrop),
      child: render(text, small),
    ),
  );
}
