import 'package:pdf/widgets.dart' as pw;

import '../bijoy_helper/bijoy_helper.dart' as bh;

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

  final segments = bh.BanglaTextProcessor.processText(text);
  if (segments.isEmpty) {
    return pw.TextSpan(text: '', style: banglaStyle);
  }

  return pw.TextSpan(
    children: segments
        .map((seg) => pw.TextSpan(
              text: seg.text,
              style: seg.isBangla
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
