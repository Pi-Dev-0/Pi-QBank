import 'dart:typed_data';

import 'package:pdf/pdf.dart' as pdf;

import 'math_text.dart';
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

  /// Advance width of the box the pdf package draws in place of a rune that
  /// no font in the chain covers, in em.
  ///
  /// `text.dart`'s `_addPlaceholder` builds a
  /// `SizedBox(height: fontSize, width: fontSize / 2)`, so an unrenderable
  /// character is *not* free space — it occupies half an em. Measuring it as
  /// zero is what makes a two-column layout drift on a question containing one,
  /// because the estimate and the page then disagree about how wide it is.
  static const double _placeholderWidthEm = 0.5;

  /// Height of that box, in em (`SizedBox(height: fontSize)`).
  ///
  /// Taller than any text line, so its presence raises the line box.
  static const double _placeholderHeightEm = 1.0;

  /// The fonts the renderer would try, in order, for a run.
  ///
  /// Same chain as the `pw.TextSpan`: the run's own font, then its
  /// `fontFallback` list. The renderer walks it per rune, so the measurer has
  /// to as well — a Bangla run can still carry a math symbol, and a Latin run
  /// can carry one too.
  List<pdf.PdfFont> _fontChain(bool isBangla, bool bold) {
    final chain = <pdf.PdfFont>[
      isBangla ? (_bangla ?? _latin) : (bold ? _latinBold : _latin),
    ];
    for (final font in [_symbol, _bangla]) {
      if (font != null && !chain.contains(font)) chain.add(font);
    }
    return chain;
  }

  /// Split [text] into pieces that each belong to a single measuring font.
  ///
  /// A single run can mix scripts — `"x ≤ 5"` is ASCII with a math symbol in
  /// the middle — and the symbol has to move to a different font. Runes are
  /// therefore grouped by *which font in the chain actually covers them*,
  /// which is how the renderer groups them.
  ///
  /// Splitting by script instead used to mis-measure in two ways: a symbol
  /// inside a Bangla run was measured with the Bangla font, which has no such
  /// glyph, and a rune no font covers came out zero-width while the page still
  /// drew a box for it.
  /// Split [text] into the pieces the layout measures.
  ///
  /// LaTeX is parsed first and the Bangla conversion second, matching
  /// [buildPdfTextSpan] exactly. Doing it the other way round parses Bijoy's
  /// legacy encoding, where `থ` is `_` and `স্ব` is `^` — so every `থ` became a
  /// subscript and every `স্ব` a superscript, in the drawing *and* here.
  List<_Segment> _segments(String text, bool bold) {
    final out = <_Segment>[];

    for (final piece in parseMath(text)) {
      switch (piece) {
        case MathFraction():
          // One item for the whole stack: it cannot be broken across a line,
          // and its box is the sum of its two halves plus the rule.
          out.add(_Segment('', _fontChain(true, bold).first, math: piece));
        case MathScript():
          out.add(_Segment('', _fontChain(true, bold).first, math: piece));
        case MathText(:final text):
          for (final run in splitPdfTextRuns(text)) {
            if (run.isEmpty) continue;
            _splitByCoverage(
                run.text, run.isBangla, _fontChain(run.isBangla, bold), out);
          }
      }
    }
    return out;
  }

  /// Split plain text into runs of runes the font chain can actually draw.
  void _splitByCoverage(
      String text, bool isBangla, List<pdf.PdfFont> chain, List<_Segment> out) {
    final buffer = StringBuffer();
    pdf.PdfFont? bufferFont;

    void flush() {
      final font = bufferFont;
      if (buffer.isEmpty || font == null) {
        buffer.clear();
        return;
      }
      out.add(_Segment(buffer.toString(), font));
      buffer.clear();
    }

    for (final rune in text.runes) {
      pdf.PdfFont? match;
      for (final font in chain) {
        if (font.isRuneSupported(rune)) {
          match = font;
          break;
        }
      }
      match ??= _undrawable;

      if (bufferFont != null && !identical(bufferFont, match)) flush();
      bufferFont = match;
      buffer.writeCharCode(rune);
    }
    flush();
  }

  /// Width of a typeset piece, in em.
  double _mathWidthEm(MathSegment piece, bool bold) {
    switch (piece) {
      case MathFraction(:final numerator, :final denominator):
        final n = textWidth(numerator, fontSize: fracFontScale, bold: bold);
        final d = textWidth(denominator, fontSize: fracFontScale, bold: bold);
        return (n > d ? n : d) + fracPaddingX * 2;
      case MathScript(:final text):
        return textWidth(text, fontSize: scriptFontScale, bold: bold);
      case MathText(:final text):
        return textWidth(text, fontSize: 1, bold: bold);
    }
  }

  /// Height of a typeset piece, in em.
  double _mathHeightEm(MathSegment piece, bool bold) {
    switch (piece) {
      case MathFraction(:final numerator, :final denominator):
        return lineHeight(numerator, fontSize: fracFontScale, bold: bold) +
            fracRuleHeight +
            lineHeight(denominator, fontSize: fracFontScale, bold: bold);
      case MathScript(:final text):
        return lineHeight(text, fontSize: scriptFontScale, bold: bold);
      case MathText(:final text):
        return lineHeight(text, fontSize: 1, bold: bold);
    }
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
      final piece = segment.math;
      if (piece != null) {
        em += _mathWidthEm(piece, bold);
      } else {
        em += segment.isUndrawable
            ? _placeholderWidthEm * segment.text.runes.length
            : _metricsOf(segment.font, segment.text).advanceWidth;
      }
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
      final piece = segment.math;
      if (piece != null) {
        final h = _mathHeightEm(piece, bold);
        if (h > maxHeight) maxHeight = h;
        continue;
      }
      if (segment.isUndrawable) {
        // SizedBox(height: fontSize) — taller than any glyph line.
        maxHeight = _placeholderHeightEm;
        continue;
      }
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
      final piece = segment.math;
      if (piece != null) {
        // A typeset stack or script is drawn as one box and must not be broken
        // across a line, so it becomes a single unbreakable token.
        tokens.add(_Token(width: _mathWidthEm(piece, bold), isSpace: false));
        continue;
      }
      final font = segment.font;
      final buffer = StringBuffer();
      if (segment.isUndrawable) {
        // Each rune became its own SizedBox on the page, and a box does not
        // break at spaces, so they stay separate unbreakable tokens.
        for (var i = 0; i < segment.text.runes.length; i++) {
          tokens.add(_Token(width: _placeholderWidthEm, isSpace: false));
        }
        continue;
      }
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

/// Sentinel font standing for "no font in the chain covers these runes".
///
/// Identity only — it is never asked for metrics, because
/// [_placeholderWidthEm] already describes what the page draws instead.
final pdf.PdfFont _undrawable = const _UndrawableFont();

class _UndrawableFont implements pdf.PdfFont {
  const _UndrawableFont();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('An undrawable rune must not be measured with a font');
}

class _Segment {
  _Segment(this.text, this.font, {this.math});

  final String text;

  /// The font that covers every rune in [text], or the undrawable sentinel if
  /// no font does.
  final pdf.PdfFont font;

  /// Set when this piece is a typeset fraction or script rather than text.
  /// Measured from the piece itself, because its box is drawn as a widget and
  /// has no single font.
  final MathSegment? math;

  /// True when no font can draw this piece and the page draws a placeholder.
  bool get isUndrawable => identical(font, _undrawable);
}

class _Token {
  const _Token({required this.width, required this.isSpace});

  /// Width in em units (multiply by font size for points).
  final double width;
  final bool isSpace;
}
