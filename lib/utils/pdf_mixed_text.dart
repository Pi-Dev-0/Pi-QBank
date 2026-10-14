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
}) {
  final latin = bold ? pw.Font.helveticaBold() : pw.Font.helvetica();

  final runs = splitPdfTextRuns(text);
  if (runs.isEmpty || (runs.length == 1 && runs.first.isEmpty)) {
    return pw.TextSpan(text: '', style: banglaStyle);
  }

  return pw.TextSpan(
    children: [
      for (final run in runs)
        ..._buildRunChildren(run, banglaStyle, latin, bold, measure),
    ],
  );
}

/// The spans for one Bangla/Latin run, including any LaTeX it contains.
List<pw.InlineSpan> _buildRunChildren(
  PdfTextRun run,
  pw.TextStyle banglaStyle,
  pw.Font latin,
  bool bold,
  MathTextMeasurer? measure,
) {
  final base = run.isBangla
      ? banglaStyle
      : banglaStyle.copyWith(
          // `font:` alone would be discarded — see the note above.
          fontNormal: latin,
          fontBold: latin,
          fontItalic: latin,
          fontBoldItalic: latin,
        );

  final children = <pw.InlineSpan>[];

  for (final segment in parseMath(run.text)) {
    switch (segment) {
      case MathFraction(:final numerator, :final denominator, :final math):
        children.add(_fractionSpan(numerator, denominator,
            style: base,
            latin: latin,
            bold: bold,
            math: math,
            measure: measure));

      case MathScript(:final text, :final superscript, :final math):
        children.add(_scriptSpan(text,
            superscript: superscript,
            style: base,
            latin: latin,
            bold: bold,
            math: math));

      case MathText(:final text, :final math):
        final style =
            math ? base.copyWith(fontStyle: pw.FontStyle.italic) : base;
        children.add(pw.TextSpan(text: text, style: style));
    }
  }

  return children;
}

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
  required pw.Font latin,
  required bool bold,
  required bool math,
  MathTextMeasurer? measure,
}) {
  final size = style.fontSize ?? 11;
  final small = style.copyWith(fontSize: size * fracFontScale);

  pw.Text line(String t) => pw.Text(t, style: small);
  pw.Row centred(String t) => pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.center, children: [line(t)]);

  double? ruleWidth;
  if (measure != null) {
    final n = measure(numerator, size * fracFontScale, bold);
    final d = measure(denominator, size * fracFontScale, bold);
    ruleWidth = (n > d ? n : d) + fracPaddingX * 2;
  }

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
          if (ruleWidth == null)
            centred(numerator)
          else
            pw.SizedBox(width: ruleWidth, child: centred(numerator)),
          rule,
          if (ruleWidth == null)
            centred(denominator)
          else
            pw.SizedBox(width: ruleWidth, child: centred(denominator)),
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
  required pw.Font latin,
  required bool bold,
  required bool math,
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
      child: pw.Text(text, style: small),
    ),
  );
}
