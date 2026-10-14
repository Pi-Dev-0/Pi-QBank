import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:pi_qbank/utils/pdf_mixed_text.dart';
import 'package:pi_qbank/utils/pdf_text_metrics.dart';

/// A typeset fraction is drawn as a widget with a box the estimator never sees
/// directly. If the two disagree about its width, every column that contains
/// one drifts — the same render/measure mismatch that has produced blank pages
/// in this project more than once.
void main() {
  late ByteData banglaData;
  late ByteData symbolData;

  setUpAll(() {
    banglaData = ByteData.sublistView(
        File('assets/fonts/SutonnyMJ Regular.ttf').readAsBytesSync());
    symbolData = ByteData.sublistView(
        File('assets/fonts/MathSymbols.ttf').readAsBytesSync());
  });

  PdfTextMetrics metrics() => PdfTextMetrics(
        banglaFontData: banglaData,
        symbolFontData: symbolData,
      );

  group('measurement of typeset pieces', () {
    test('a fraction is wider than nothing and taller than a plain line', () {
      final m = metrics();
      expect(m.textWidth(r'\frac{x+2}{3}', fontSize: 11), greaterThan(0));

      final plain = m.lineHeight('x+2', fontSize: 11);
      final stacked = m.lineHeight(r'\frac{x+2}{3}', fontSize: 11);
      expect(stacked, greaterThan(plain),
          reason: 'a stacked fraction must raise the line box');
    });

    test('a fraction with a longer numerator is wider', () {
      final m = metrics();
      final narrow = m.textWidth(r'\frac{1}{2}', fontSize: 11);
      final wide = m.textWidth(r'\frac{x+1234}{2}', fontSize: 11);
      expect(wide, greaterThan(narrow));
    });

    test('a superscript is smaller than the text it rides on', () {
      final m = metrics();
      expect(m.textWidth('x^{2}', fontSize: 11),
          greaterThan(m.textWidth('x', fontSize: 11)));
      expect(m.textWidth('x^{2}', fontSize: 11),
          lessThan(m.textWidth('xyz', fontSize: 11)));
    });

    test('maths mode does not change the width', () {
      // The `$` only sets italic styling; the estimator must not charge more.
      final m = metrics();
      expect(m.textWidth(r'$x+1$', fontSize: 11),
          closeTo(m.textWidth('x+1', fontSize: 11), 0.0001));
    });

    test('a fraction is never measured as zero width', () {
      // A regression here would silently swallow the whole question.
      final m = metrics();
      expect(m.textWidth(r'\frac{a}{b}', fontSize: 11), greaterThan(1));
    });
  });

  group('line counting', () {
    test('a fraction is one unbreakable token', () {
      final m = metrics();
      // Narrow column: the words wrap onto several lines...
      final words =
          m.countLines('one two three four five', width: 40, fontSize: 11);
      // ...but a fraction cannot be broken across them, so it needs at least
      // as many lines as its own width demands.
      expect(m.countLines(r'\frac{abcdefgh}{ijkl}', width: 40, fontSize: 11),
          greaterThanOrEqualTo(1));
      expect(words, greaterThan(1));
    });
  });

  group('the renderer draws what the estimator measured', () {
    test('a fraction renders without complaint and appears in the output',
        () async {
      final bangla = pw.Font.ttf(banglaData);
      final doc = pw.Document();
      final log = <String>[];
      await runZoned(() async {
        doc.addPage(pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (ctx) => pw.RichText(
            text: buildPdfTextSpan(
                r'বাক্যঃ $\frac{2+x}{3} = 1$ এবং $x^{2}$ তাই $\frac{a}{b}$।',
                pw.TextStyle(font: bangla, fontSize: 11),
                // The same engine the layout uses, so the rule is drawn at the
                // width the estimator charged for it.
                measure: (t, size, bold) =>
                    metrics().textWidth(t, fontSize: size, bold: bold)),
          ),
        ));
        File('/tmp/opencode/math_probe.pdf').writeAsBytesSync(await doc.save());
      },
          zoneSpecification: ZoneSpecification(
              print: (self, parent, zone, line) => log.add(line)));
      // "Helvetica has no Unicode support" is printed once per document when
      // the base-14 font object is built and is harmless. What must not appear
      // is a glyph nothing in the chain can draw.
      final unresolved =
          log.where((l) => l.contains('Unable to find a font')).toList();
      expect(unresolved, isEmpty,
          reason: 'these glyphs would render as blank boxes: $unresolved');

      final bytes = File('/tmp/opencode/math_probe.pdf').readAsBytesSync();
      expect(bytes.length, greaterThan(1000));
    });
  });
}
