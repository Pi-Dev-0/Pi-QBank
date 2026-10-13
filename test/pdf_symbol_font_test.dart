import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:pi_qbank/utils/pdf_mixed_text.dart';
import 'package:pi_qbank/utils/pdf_text_metrics.dart';

/// Characters the geometry and algebra questions in the bank actually use.
///
/// The symbol font used to be a hand-picked codepoint list, so U+2220 and
/// U+22A5 were never picked and every occurrence logged "Unable to find a
/// font to draw" and rendered a placeholder box.
const _symbols = {
  'U+2220': '∠', // angle
  'U+22A5': '⊥', // perpendicular
  'U+2229': '∩',
  'U+222A': '∪',
  'U+2208': '∈',
  'U+2205': '∅',
  'U+2260': '≠',
  'U+2264': '≤',
  'U+2265': '≥',
  'U+00D7': '×',
  'U+221A': '√',
  'U+2211': '∑',
  'U+2212': '−',
  'U+2248': '≈',
  'U+2192': '→',
  'U+00B1': '±',
  'U+2026': '…',
  'U+03B1': 'α',
  'U+03B2': 'β',
  'U+03C0': 'π',
  'U+00B2': '²',
  'U+00B3': '³',
};

List<_Font> _loadFonts() {
  final banglaBytes =
      File('assets/fonts/SutonnyMJ Regular.ttf').readAsBytesSync();
  final symbolBytes = File('assets/fonts/MathSymbols.ttf').readAsBytesSync();
  return [
    _Font(
      name: 'bangla',
      bytes: ByteData.sublistView(banglaBytes),
      pdf: pw.Font.ttf(ByteData.sublistView(banglaBytes)),
    ),
    _Font(
      name: 'symbols',
      bytes: ByteData.sublistView(symbolBytes),
      pdf: pw.Font.ttf(ByteData.sublistView(symbolBytes)),
    ),
  ];
}

class _Font {
  _Font({required this.name, required this.bytes, required this.pdf});
  final String name;
  final ByteData bytes;
  final pw.Font pdf;
}

/// Run [body] with `print` captured, so the pdf package's debug-only warnings
/// can be asserted on rather than eyeballed in a console log.
Future<List<String>> capturePrint(Future<void> Function() body) async {
  final log = <String>[];
  await runZoned(
    body,
    zoneSpecification: ZoneSpecification(
      print: (_, __, ___, line) => log.add(line),
    ),
  );
  return log;
}

void main() {
  test('the symbol font covers the math the question bank uses', () {
    final fonts = _loadFonts();
    final symbols = fonts.firstWhere((f) => f.name == 'symbols');

    // Proves the font parses and carries a cmap at all.
    final doc = PdfDocument();
    expect(PdfTtfFont(doc, symbols.bytes), isNotNull);

    final missing = <String>[];
    for (final entry in _symbols.entries) {
      if (!_hasGlyph(symbols.bytes, entry.value)) missing.add(entry.key);
    }
    expect(missing, isEmpty,
        reason: 'MathSymbols.ttf is missing $missing — rebuild it with '
            'tools/build_math_symbols_font.py');
  });

  test('measuring a symbol does not silently collapse to zero width', () {
    final fonts = _loadFonts();
    final metrics = PdfTextMetrics(
      banglaFontData: fonts[0].bytes,
      symbolFontData: fonts[1].bytes,
    );

    // "x ⊥ y" is a Latin run, so a regression here would show up as the symbol
    // measuring as nothing while it still occupies space on the page.
    final withSymbol = metrics.textWidth('AB ⊥ AB', fontSize: 11, bold: false);
    final without = metrics.textWidth('AB AB', fontSize: 11, bold: false);
    expect(withSymbol, greaterThan(without));
  });

  test('a rune no font covers is charged the box the page draws for it', () {
    final fonts = _loadFonts();
    final metrics = PdfTextMetrics(
      banglaFontData: fonts[0].bytes,
      symbolFontData: fonts[1].bytes,
    );

    // U+27C2 DOUBLE UP TACK is absent from both fonts, so the pdf package
    // draws `SizedBox(height: fontSize, width: fontSize / 2)` in its place.
    // Measuring it as zero is how a two-column layout quietly drifts.
    const boxWidthEm = 0.5;
    expect(
      metrics.textWidth('⟂', fontSize: 11),
      closeTo(boxWidthEm * 11, 0.0001),
    );

    // And it is additive, not a replacement for the surrounding text.
    final base = metrics.textWidth('AB', fontSize: 11);
    expect(metrics.textWidth('AB⟂', fontSize: 11), closeTo(base + 5.5, 0.0001));

    // Its box is taller than a text line, so it raises the line box.
    expect(
      metrics.lineHeight('AB⟂', fontSize: 11),
      greaterThanOrEqualTo(11.0),
    );
  });

  test('drawing a symbol uses a real font, not a placeholder', () async {
    final fonts = _loadFonts();
    final log = await capturePrint(() async {
      final doc = pw.Document();
      final base = pw.TextStyle(
        font: fonts[0].pdf,
        fontFallback: [fonts[1].pdf],
        fontSize: 12,
      );

      doc.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (ctx) => pw.Column(children: [
          for (final entry in _symbols.entries)
            pw.RichText(
              text: buildPdfTextSpan(
                'AB${entry.value}CD ∠AB⊥CD',
                base,
                bold: false,
              ),
            ),
        ]),
      ));

      final bytes = await doc.save();
      // Force the real rendering path, not just object construction.
      expect(bytes.length, greaterThan(1000));
    });

    final unresolved =
        log.where((l) => l.contains('Unable to find a font to draw')).toList();
    expect(unresolved, isEmpty,
        reason: 'no font in the chain covers: $unresolved');
  });
}

/// Whether [font] maps [char] to a real glyph.
bool _hasGlyph(ByteData data, String char) {
  final doc = PdfDocument();
  final font = PdfTtfFont(doc, data);
  return font.isRuneSupported(char.runes.first);
}
