import 'package:pdf/widgets.dart' as pw;

import '../bijoy_helper/bijoy_helper.dart' as bh;

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
/// never disagree with the rendered one. Splitting the logic would let a
/// stray soft hyphen or a differently-classified run silently desynchronise
/// the two.
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

/// Build a [pw.TextSpan] for text that mixes Bangla and Latin in the PDF.
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
}) {
  final latin = bold ? pw.Font.helveticaBold() : pw.Font.helvetica();

  final runs = splitPdfTextRuns(text);
  if (runs.isEmpty || (runs.length == 1 && runs.first.isEmpty)) {
    return pw.TextSpan(text: '', style: banglaStyle);
  }

  return pw.TextSpan(
    children: runs
        .map((run) => pw.TextSpan(
              text: run.text,
              style: run.isBangla
                  ? banglaStyle
                  : banglaStyle.copyWith(
                      // `font:` alone would be discarded — see the note above.
                      fontNormal: latin,
                      fontBold: latin,
                      fontItalic: latin,
                      fontBoldItalic: latin,
                    ),
            ))
        .toList(),
  );
}
