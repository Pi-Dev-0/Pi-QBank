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
/// * Line height is the span from the line's *highest ascent* to its *lowest
///   descent*, matching how the pdf package keeps the two ends separately while
///   laying a line out. Mixing in Helvetica raises the line box, and a
///   Bangla-only line is only as tall as the Bangla font's ascent, because its
///   glyphs sit above the baseline — the estimator has to reproduce both or
///   every column drifts.
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

  /// Slack the wrapper allows before it breaks, matching the pdf package's own
  /// `constraintWidth + 0.00001` comparison.
  static const double _epsilon = 0.00001;

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
      // The page never puts whitespace through its font-coverage split (see the
      // `spaces` set in its `_preProcessSpans`), so a space or a line break
      // stays in the run around it instead of turning into an undrawable box.
      if (_isPdfWhitespace(rune)) {
        bufferFont ??= chain.isEmpty ? _undrawable : chain.first;
        buffer.writeCharCode(rune);
        continue;
      }

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
  ///
  /// [baseFontSize] is the size the caller will multiply the result by, and is
  /// needed because the padding around a fraction is a fixed number of points
  /// rather than a fraction of an em: adding it raw would charge the padding
  /// `baseFontSize` times over, which widens every fraction by ~30pt and wraps
  /// its line one word early. The estimate then runs ahead of the page it is
  /// predicting, and the page breaks with its foot empty.
  double _mathWidthEm(MathSegment piece, bool bold, double baseFontSize) {
    switch (piece) {
      case MathFraction(:final numerator, :final denominator):
        final n = textWidth(numerator, fontSize: fracFontScale, bold: bold);
        final d = textWidth(denominator, fontSize: fracFontScale, bold: bold);
        return (n > d ? n : d) + fracPaddingX * 2 / baseFontSize;
      case MathScript(:final text):
        return textWidth(text, fontSize: scriptFontScale, bold: bold);
      case MathText(:final text):
        return textWidth(text, fontSize: 1, bold: bold);
    }
  }

  /// Height of a typeset piece, in em.
  ///
  /// Same point-versus-em trap as [_mathWidthEm]: the fraction rule is 0.5pt
  /// however large the text is, so it is converted rather than added raw —
  /// otherwise every line holding a fraction measures 5pt taller than it draws.
  double _mathHeightEm(MathSegment piece, bool bold, double baseFontSize) {
    switch (piece) {
      case MathFraction(:final numerator, :final denominator):
        return lineHeight(numerator, fontSize: fracFontScale, bold: bold) +
            fracRuleHeight / baseFontSize +
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
        em += _mathWidthEm(piece, bold, fontSize);
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
    final em = _lineHeightEm(_tokenize(text, bold, fontSize));
    // Nothing measurable in the string: fall back to Helvetica's box so a
    // blank span is never treated as zero-height when the pdf package would
    // still reserve a line.
    return (em == 0 ? _latin.stringMetrics('Hxg').maxHeight : em) * fontSize;
  }

  /// Height in em of a single line built from [line].
  ///
  /// The page keeps the two ends of the line separately — `top` is the lowest
  /// descent, `bottom` the highest ascent, both starting at the baseline — so
  /// the line is as tall as the whole span those words cover, not as tall as
  /// its tallest single word. A line with no word on it is charged the font's
  /// empty-line height instead.
  static double _lineHeightEm(List<_Token> line) {
    var top = 0.0;
    var bottom = 0.0;
    var empty = 0.0;
    for (final token in line) {
      if (token.isBreak) {
        if (token.emptyLineHeight > empty) empty = token.emptyLineHeight;
        continue;
      }
      if (token.ascent > bottom) bottom = token.ascent;
      if (token.descent < top) top = token.descent;
    }
    final box = bottom - top;
    return box > empty ? box : empty;
  }

  /// How many lines [text] occupies when wrapped to [width] points.
  ///
  /// Blank input is 0 lines, because the pdf package emits no line box for an
  /// empty span — a CQ with no stem must not be charged a line.
  int countLines(String text,
          {required double width,
          required double fontSize,
          bool bold = false}) =>
      _wrap(text, width: width, fontSize: fontSize, bold: bold).length;

  /// Rendered height of [text] wrapped to [width], in points.
  ///
  /// Each line is charged its own height — the highest ascent minus the lowest
  /// descent over the words on it — because that is what the pdf package does.
  /// Charging every line the tallest piece in the whole block measures it a few
  /// points per line too tall, and a page that is told it is full when it is
  /// not breaks with its foot empty — a whole question's worth of white space
  /// in the worst case.
  double blockHeight(String text,
      {required double width,
      required double fontSize,
      bool bold = false}) {
    var total = 0.0;
    for (final line
        in _wrap(text, width: width, fontSize: fontSize, bold: bold)) {
      total += _lineHeightEm(line) * fontSize;
    }
    return total;
  }

  /// Greedy wrap, mirroring the pdf package's own line breaking.
  ///
  /// Returns one list of tokens per line; each token carries the width and the
  /// line height it contributes, both in em.
  List<List<_Token>> _wrap(String text,
      {required double width,
      required double fontSize,
      bool bold = false}) {
    if (text.isEmpty) return const [];

    final tokens = _tokenize(text, bold, fontSize);
    if (tokens.isEmpty) return [<_Token>[]];

    final lines = <List<_Token>>[<_Token>[]];
    var cursor = 0.0;
    var hasInk = false;

    for (final token in tokens) {
      if (token.isBreak) {
        // Close the line here. A line the page finds no word on gets no line
        // box of its own, but a break that ends it still charges the font's own
        // height — so the break token replaces whatever spaces were on it.
        if (!hasInk) lines.last = <_Token>[token];
        lines.add(<_Token>[]);
        cursor = 0;
        hasInk = false;
        continue;
      }
      if (token.isSpace) {
        // Every whitespace rune moves the pen, even at the start of a line —
        // the page turns the gap into a space word and the text after it is
        // shifted. A space never gives a line its height, though.
        cursor += token.width * fontSize;
        lines.last.add(token);
        continue;
      }

      final w = token.inkWidth * fontSize;
      final advance = token.width * fontSize;
      if (hasInk && cursor + w > width + _epsilon) {
        lines.add(<_Token>[token]);
        cursor = advance;
      } else if (!hasInk && w > width + _epsilon) {
        // A single unbreakable run longer than the line: the wrapper breaks it
        // mid-word rather than overflowing, so it covers several line boxes.
        final spanned = (w / width).ceil();
        for (var i = 1; i < spanned; i++) {
          lines.add(<_Token>[token]);
        }
        lines.last.add(token);
        cursor = w % width;
        if (cursor == 0) cursor = width;
      } else {
        lines.last.add(token);
        cursor += advance;
      }
      hasInk = true;
    }

    // The last line is only a line box if a word or a break ended up on it: a
    // stemless or spaces-only run occupies no height at all.
    if (!hasInk) lines.removeLast();

    return lines;
  }

  /// Split into space-separated tokens, keeping each token's own width in em so
  /// no font mixing is lost at the wrap points.
  List<_Token> _tokenize(String text, bool bold, double baseFontSize) {
    final tokens = <_Token>[];
    for (final segment in _segments(text, bold)) {
      final piece = segment.math;
      if (piece != null) {
        // A typeset stack or script is drawn as one box and must not be broken
        // across a line, so it becomes a single unbreakable token.
        final w = _mathWidthEm(piece, bold, baseFontSize);
        tokens.add(_Token(
            width: w,
            inkWidth: w,
            // A typeset stack is drawn as a widget that hangs from the line's
            // top, so it adds height below the baseline and nothing above it.
            ascent: _mathHeightEm(piece, bold, baseFontSize),
            isSpace: false));
        continue;
      }
      final font = segment.font;
      final buffer = StringBuffer();
      if (segment.isUndrawable) {
        // Each rune became its own SizedBox on the page, and a box does not
        // break at spaces, so they stay separate unbreakable tokens.
        for (var i = 0; i < segment.text.runes.length; i++) {
          tokens.add(_Token(
              width: _placeholderWidthEm,
              inkWidth: _placeholderWidthEm,
              ascent: _placeholderHeightEm,
              isSpace: false));
        }
        continue;
      }
      final space = _metricsOf(font, ' ');
      // A line the page finds no word on is charged the font's own empty-line
      // height — ascent plus the descent, with the descent's sign dropped.
      final emptyLineHeight = font.ascent + -font.descent;

      void flush() {
        if (buffer.isEmpty) return;
        final m = _metricsOf(font, buffer.toString());
        tokens.add(_Token(
            width: m.advanceWidth,
            inkWidth: m.width,
            ascent: m.ascent,
            descent: m.descent,
            isSpace: false));
        buffer.clear();
      }

      for (final rune in segment.text.runes) {
        if (rune == _lineFeed) {
          // A hard line break. The page splits every span on '\n' and closes
          // the line there, so the wrapper has to as well: read as an ordinary
          // character it glued both halves of the stem together and measured
          // every stem carrying a break a line or two short — enough to push a
          // whole block onto the next page and leave the one it belonged on
          // blank.
          flush();
          tokens.add(_Token(
              width: 0,
              inkWidth: 0,
              emptyLineHeight: emptyLineHeight,
              isSpace: false,
              isBreak: true));
        } else if (_isPdfWhitespace(rune)) {
          // The page splits each line on `\s` and turns every gap into a
          // space, so repeated spaces are not collapsed and a leading one
          // still shifts the text after it.
          flush();
          tokens.add(_Token(
              width: space.advanceWidth,
              inkWidth: space.width,
              isSpace: true));
        } else {
          buffer.writeCharCode(rune);
        }
      }
      flush();
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
  const _Token(
      {required this.width,
      required this.inkWidth,
      this.ascent = 0,
      this.descent = 0,
      this.emptyLineHeight = 0,
      this.isSpace = false,
      this.isBreak = false});

  /// Advance in em units (multiply by font size for points): how far the pen
  /// moves after this token.
  final double width;

  /// Ink extent in em units. pdf tests *this* against the remaining space when
  /// deciding whether a word still fits ([PdfFontMetrics.width] is
  /// `right - left`, while the pen advances by `advanceWidth`), so a line may
  /// end a point or two past the box without wrapping. Charging the advance
  /// here wraps a borderline line one word early, which adds a whole line.
  final double inkWidth;

  /// How far this token's ink rises above the baseline, in em.
  ///
  /// A line is as tall as the *highest ascent minus the lowest descent* over the
  /// words on it — the pdf package keeps the two ends separately, so a word
  /// with tall ascenders and one with deep descenders together make a line
  /// taller than either alone. Folded into one "height" per word the model read
  /// every such line short, and Bangla-only lines (whose glyphs all sit above
  /// the baseline) a whole 2.2pt short each.
  final double ascent;

  /// How far this token's ink drops below the baseline, in em. Usually negative
  /// for Latin, but the Bijoy font's glyphs sit above the baseline and report a
  /// *positive* descent — which the page clamps at zero, making a Bangla-only
  /// line only as tall as its ascent.
  final double descent;

  /// Height charged for a line that has no word on it, in em. Only a line break
  /// uses this; the page charges `font.emptyLineHeight` there.
  final double emptyLineHeight;

  final bool isSpace;

  /// True for a hard line break (`\n`). It draws nothing and has no width, but
  /// it ends the line it appears on — and it carries the font's own box height
  /// so that an otherwise empty line still occupies a line box.
  final bool isBreak;
}

/// Line feed: the one character the page treats as a hard line break.
const int _lineFeed = 0x0a;

/// True for the characters the text layout treats as whitespace.
///
/// Copied from the pdf package's own `_preProcessSpans` (which skips these in
/// its font-coverage split), plus the plain space and carriage return. Every
/// one of them advances the pen by a single space; only [_lineFeed] also breaks
/// the line.
bool _isPdfWhitespace(int rune) => const {
      0x09, 0x0a, 0x0d, 0x20, 0x00a0, 0x1680, 0x2000, 0x2001, 0x2002, //
      0x2003, 0x2004, 0x2005, 0x2006, 0x2007, 0x2008, 0x2009, 0x200a,
      0x202f, 0x205f, 0x3000,
    }.contains(rune);
