import 'dart:typed_data';

import 'package:pdf/pdf.dart' as pdf;

import 'pdf_mixed_text.dart';

/// Exact text measurement for the fonts the PDF question paper actually uses.
///
/// ## Why this exists
///
/// Multi-column layout has to decide *where the first column ends* before
/// anything is drawn, and that decision needs each question's rendered height.
/// Estimating it from character counts is unreliable here because the paper
/// mixes two very different scripts: Bangla runs through SutonnyMJ (Bijoy-ANSI,
/// wide conjuncts) and Latin runs through Helvetica (narrow ASCII). The same
/// 40 characters can differ by nearly a third in width, which is enough to
/// throw the column split badly off.
///
/// So this measures with the real font tables instead of guessing:
///
/// * [pdf.PdfTtfFont.stringMetrics] for Bangla, [pdf.PdfFont.helvetica] for
///   Latin, which is what `buildPdfTextSpan` pairs with them.
/// * `advanceWidth` comes back in **em units** (1/1000 em, normalised), so a
///   width in points is `advanceWidth * fontSize`.
/// * Line height is `ascent - descent` of the tallest font present on the
///   line, matching `_Word.height` -> `PdfFontMetrics.maxHeight` in the pdf
///   package. Mixing in Helvetica raises the line box, which the estimator has
///   to reproduce or every column drifts.
///
/// ## Cost
///
/// Building an instance parses the font tables, so keep one per export rather
/// than one per question. A throwaway [pdf.PdfDocument] backs the font objects
/// because the base-14 metrics are owned by a document; it is never saved.
class PdfTextMetrics {
  PdfTextMetrics._(this._bangla, this._symbol, this._latin, this._latinBold);

  /// Build a measurer.
  ///
  /// [banglaFontData] should be the bytes of the SutonnyMJ font used for
  /// rendering Bangla, and [symbolFontData] the bytes of the symbol font used
  /// as `fontFallback` (math glyphs such as ≤ √ π − →).
  ///
  /// Both matter for correctness, not just accuracy. A base-14 font throws on
  /// anything outside Latin-1: `PdfFont.stringMetrics` prints *"Cannot decode
  /// the string to Latin1"* and rethrows. So math symbols **cannot** be measured
  /// with Helvetica and must be routed to a TrueType font. When [symbolFontData]
  /// is omitted they fall back to the Bangla font, and failing that to a
  /// Helvetica measurement wrapped in a guard so a stray symbol can never abort
  /// an export.
  factory PdfTextMetrics({
    ByteData? banglaFontData,
    ByteData? symbolFontData,
  }) {
    final doc = pdf.PdfDocument();
    return PdfTextMetrics._(
      banglaFontData == null ? null : pdf.PdfTtfFont(doc, banglaFontData),
      symbolFontData == null ? null : pdf.PdfTtfFont(doc, symbolFontData),
      pdf.PdfFont.helvetica(doc),
      pdf.PdfFont.helveticaBold(doc),
    );
  }

  final pdf.PdfFont? _bangla;
  final pdf.PdfFont? _symbol;
  final pdf.PdfFont _latin;
  final pdf.PdfFont _latinBold;

  /// True when [text] contains a codepoint Latin-1 cannot encode.
  ///
  /// Latin-1 covers U+0000–U+00FF, so `× ÷ ± °` are fine but `≤ √ π − → ²`
  /// are not.
  static bool _needsUnicodeFont(String text) {
    for (final rune in text.runes) {
      if (rune > 0xFF) return true;
    }
    return false;
  }

  pdf.PdfFont _fontForRun(bool isBangla, String text, bool bold) {
    if (isBangla) return _bangla ?? _latin;
    if (!_needsUnicodeFont(text)) return bold ? _latinBold : _latin;
    return _symbol ?? _bangla ?? _latin;
  }

  /// Split [text] into pieces that each belong to a single measuring font.
  ///
  /// A single run can mix scripts — `"x ≤ 5"` is ASCII with a math symbol in
  /// the middle — and the symbol has to move to a different font, so runs are
  /// subdivided at the Latin-1 boundary rather than measured as a unit.
  List<_Segment> _segments(String text, bool bold) {
    final out = <_Segment>[];
    for (final run in splitPdfTextRuns(text)) {
      if (run.isEmpty) continue;
      var buffer = StringBuffer();
      bool? bufferNeedsUnicode;

      void flush(bool needsUnicode) {
        if (buffer.isEmpty) return;
        final chunk = buffer.toString();
        buffer = StringBuffer();
        out.add(_Segment(
            chunk, _fontForRun(run.isBangla, chunk, bold), needsUnicode));
      }

      for (final rune in run.text.runes) {
        final needsUnicode = rune > 0xFF;
        if (bufferNeedsUnicode == null) {
          bufferNeedsUnicode = needsUnicode;
        } else if (needsUnicode != bufferNeedsUnicode) {
          flush(bufferNeedsUnicode);
          bufferNeedsUnicode = needsUnicode;
        }
        buffer.writeCharCode(rune);
      }
      flush(bufferNeedsUnicode ?? false);
    }
    return out;
  }

  /// Measure [text] with a font, never throwing.
  ///
  /// A font can still reject a string it cannot encode, or one whose glyphs
  /// are all missing. Measurement only feeds column balancing, so degrading to
  /// a rough estimate is always better than failing the export.
  pdf.PdfFontMetrics _metricsOf(pdf.PdfFont font, String text) {
    try {
      return font.stringMetrics(text);
    } catch (_) {
      return pdf.PdfFontMetrics.zero;
    }
  }

  /// Width of [text] in points at [fontSize].
  double textWidth(String text, {required double fontSize, bool bold = false}) {
    if (text.isEmpty) return 0;
    var em = 0.0;
    for (final segment in _segments(text, bold)) {
      em += _metricsOf(segment.font, segment.text).advanceWidth;
    }
    return em * fontSize;
  }

  /// Height of one rendered line, in points.
  ///
  /// Derived from the same metrics the pdf package uses, so a line box that
  /// holds Latin text is correctly taller than one holding only Bangla.
  double lineHeight(String text,
      {required double fontSize, bool bold = false}) {
    var maxHeight = 0.0;
    final seen = <pdf.PdfFont>{};
    for (final segment in _segments(text, bold)) {
      if (!seen.add(segment.font)) continue;
      final h = _metricsOf(segment.font, segment.text).maxHeight;
      if (h > maxHeight) maxHeight = h;
    }
    // Nothing measurable in the string: fall back to Helvetica's box so a
    // blank span is never treated as zero-height when the pdf package would
    // still reserve a line.
    if (maxHeight == 0) maxHeight = _latin.stringMetrics('Hxg').maxHeight;
    return maxHeight * fontSize;
  }

  /// How many lines [text] occupies when wrapped to [width] points.
  ///
  /// Blank input is 0 lines, because the pdf package emits no line box for an
  /// empty span — a CQ with no stem must not be charged a line.
  int countLines(String text,
      {required double width, required double fontSize, bool bold = false}) {
    if (text.trim().isEmpty) return 0;
    if (width <= 0) return 1;

    final tokens = _tokenize(text, bold);
    if (tokens.isEmpty) return 1;

    var lines = 1;
    var cursor = 0.0;
    var hasInk = false;

    for (final token in tokens) {
      if (token.isSpace) {
        // A space at the start of a line is swallowed by the wrapper.
        if (hasInk) cursor += token.width * fontSize;
        continue;
      }

      final w = token.width * fontSize;
      if (hasInk && cursor + w > width) {
        lines++;
        cursor = w;
      } else if (!hasInk && w > width) {
        // A single unbreakable run longer than the line: the wrapper breaks it
        // mid-word rather than overflowing.
        lines += (w / width).ceil() - 1;
        cursor = w % width;
        if (cursor == 0) cursor = width;
      } else {
        cursor += w;
      }
      hasInk = true;
    }

    return lines;
  }

  /// Rendered height of [text] wrapped to [width], in points.
  double blockHeight(String text,
          {required double width,
          required double fontSize,
          bool bold = false}) =>
      countLines(text, width: width, fontSize: fontSize, bold: bold) *
      lineHeight(text, fontSize: fontSize, bold: bold);

  /// Split into space-separated tokens, keeping each token's own width in em so
  /// no font mixing is lost at the wrap points.
  List<_Token> _tokenize(String text, bool bold) {
    final tokens = <_Token>[];
    for (final segment in _segments(text, bold)) {
      final font = segment.font;
      final buffer = StringBuffer();
      for (final rune in segment.text.runes) {
        if (rune == 0x20) {
          if (buffer.isNotEmpty) {
            final chunk = buffer.toString();
            tokens.add(_Token(
                width: _metricsOf(font, chunk).advanceWidth, isSpace: false));
            buffer.clear();
          }
          // Collapse repeated spaces and drop a leading one.
          if (tokens.isEmpty || tokens.last.isSpace) continue;
          tokens.add(
              _Token(width: _metricsOf(font, ' ').advanceWidth, isSpace: true));
        } else {
          buffer.writeCharCode(rune);
        }
      }
      if (buffer.isNotEmpty) {
        final chunk = buffer.toString();
        tokens.add(_Token(
            width: _metricsOf(font, chunk).advanceWidth, isSpace: false));
      }
    }
    return tokens;
  }
}

class _Segment {
  const _Segment(this.text, this.font, this.needsUnicodeFont);

  final String text;
  final pdf.PdfFont font;

  /// Whether this piece needed a TrueType font because it is outside Latin-1.
  final bool needsUnicodeFont;
}

class _Token {
  const _Token({required this.width, required this.isSpace});

  /// Width in em units (multiply by font size for points).
  final double width;
  final bool isSpace;
}
