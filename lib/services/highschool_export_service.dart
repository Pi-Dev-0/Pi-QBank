import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/highschool_question.dart';
import '../utils/math_text.dart';

/// Service responsible for exporting High School question papers in multiple formats:
/// - Microsoft Word (.doc with Word XML/HTML formatting)
/// - Web / HTML (.html with print CSS)
/// - Plain Text (.txt)
/// - Markdown (.md)
/// - JSON Data (.json)
/// How stem images are sized in an export.
///
/// The same setting drives PDF (points), Word (points) and HTML (pixels) so the
/// question paper looks consistent no matter which format the student receives.
enum StemImageSize {
  /// Leave stem images out entirely.
  hidden,

  /// Thumbnail — good when there are many figures and space is tight.
  small,

  /// Default — readable on a phone screen and on paper.
  medium,

  /// Large figure, for diagrams that need detail.
  large,
}

extension StemImageSizeMetrics on StemImageSize {
  /// Max height in points, used by PDF and Word. 0 means "don't render".
  double get maxHeightPt {
    switch (this) {
      case StemImageSize.hidden:
        return 0;
      case StemImageSize.small:
        return 70;
      case StemImageSize.medium:
        return 130;
      case StemImageSize.large:
        return 220;
    }
  }

  /// Max width in points. Diagrams are rarely wider than they are tall, and
  /// letting them run to the full column makes small figures look lost.
  double get maxWidthPt {
    switch (this) {
      case StemImageSize.hidden:
        return 0;
      case StemImageSize.small:
        return 140;
      case StemImageSize.medium:
        return 250;
      case StemImageSize.large:
        return 400;
    }
  }

  /// Max height in CSS pixels for HTML (browsers render at ~1.33x points).
  double get maxHeightPx => maxHeightPt * 1.333;

  bool get isVisible => this != StemImageSize.hidden;

  /// Bengali label for the UI selector.
  String get label {
    switch (this) {
      case StemImageSize.hidden:
        return 'ছবি রাখবেন না';
      case StemImageSize.small:
        return 'ছোট';
      case StemImageSize.medium:
        return 'মাঝারি';
      case StemImageSize.large:
        return 'বড়';
    }
  }

  String get description {
    switch (this) {
      case StemImageSize.hidden:
        return 'শুধু লেখা, কোনো ছবি যাবে না';
      case StemImageSize.small:
        return 'ছোট থাম্বনেইল';
      case StemImageSize.medium:
        return 'সাধারণ আকার (প্রস্তাবিত)';
      case StemImageSize.large:
        return 'বড় ডায়াগ্রামের জন্য';
    }
  }
}

/// How MCQ questions are arranged on the page.
///
/// Applied to the CQ and MCQ sections. Short questions (SQ) are one line each
/// and are never split across columns.
enum QuestionLayout {
  /// One question per row, running the full width of the page.
  single,

  /// Two questions per row — the usual exam-paper layout, and much more compact.
  doubleColumn,
}

extension QuestionLayoutMetrics on QuestionLayout {
  /// How many MCQs sit side by side.
  int get mcqColumns => this == QuestionLayout.doubleColumn ? 2 : 1;

  bool get isDouble => this == QuestionLayout.doubleColumn;

  String get label => isDouble ? 'দুই কলাম' : 'এক কলাম';

  String get description => isDouble
      ? 'প্রতি সারিতে দুটি MCQ — কম পেজ, ছোট প্রশ্নপত্র'
      : 'প্রতি সারিতে একটি MCQ — প্রশ্ন ও অপশন সরল দেখা যায়';
}

/// One of the blocks a question paper is divided into.
///
/// The reader can drag the blocks into any order, and that order reaches the
/// exports as a list of these — so the printed paper, the HTML preview and the
/// reorder list in the app all agree. The বাংলা letter a block is headed with
/// comes from its *position* in that list, not from its type: whichever block
/// the reader put first is ক-বিভাগ.
enum PaperSection {
  /// সৃজনশীল প্রশ্ন.
  cq,

  /// সংক্ষিপ্ত প্রশ্ন (the sheet calls these RQ).
  rq,

  /// বহুনির্বাচনী প্রশ্ন.
  mcq;

  /// CQ, then the short questions, then MCQ — the order a paper is printed in
  /// until the reader drags the blocks around.
  static const List<PaperSection> defaultOrder = [cq, rq, mcq];
}

class HighSchoolExportService {
  HighSchoolExportService._();

  // ─────────────────────────────────────────────────────────────────────────
  // Stem image helpers
  //
  // PDF and Word need the actual image bytes; HTML/Markdown only need a URL
  // that a browser can load. Both depend on the URL being *directly fetchable*,
  // which a Google Drive sharing link is not.
  // ─────────────────────────────────────────────────────────────────────────

  /// Largest image we will embed, to stop a few huge originals from blowing up
  /// the exported file (and the base64 payload Word embeds inline).
  static const int maxImageBytes = 5 * 1024 * 1024;
  static const Duration _imageTimeout = Duration(seconds: 20);

  /// Turn a Google Drive sharing link into a direct-download link.
  /// Any other URL is returned unchanged.
  static String resolveImageUrl(String rawUrl) {
    final url = rawUrl.trim();
    if (url.isEmpty) return url;
    if (!url.contains('drive.google.com')) return url;

    // .../file/d/<ID>/view  |  .../file/d/<ID>/preview  |  .../open?id=<ID>
    final fileMatch = RegExp(r'/file/d/([a-zA-Z0-9_-]+)').firstMatch(url);
    if (fileMatch != null) {
      return 'https://drive.google.com/uc?export=download&id=${fileMatch.group(1)}';
    }
    final idMatch = RegExp(r'[?&]id=([a-zA-Z0-9_-]+)').firstMatch(url);
    if (idMatch != null) {
      return 'https://drive.google.com/uc?export=download&id=${idMatch.group(1)}';
    }
    return url;
  }

  /// Download every distinct stem image once, keyed by *resolved* URL.
  ///
  /// Failures are skipped rather than thrown: an unreachable image must not
  /// block the whole export. Returns an empty map when nothing could be
  /// downloaded, and callers fall back to a plain URL reference.
  static Future<Map<String, Uint8List>> prefetchStemImages(
    List<HighSchoolQuestion> questions,
  ) async {
    final wanted = <String>{};
    for (final q in questions) {
      final resolved = resolveImageUrl(q.stemImageUrl);
      if (resolved.isNotEmpty) wanted.add(resolved);
    }
    if (wanted.isEmpty) return <String, Uint8List>{};

    final out = <String, Uint8List>{};
    for (final url in wanted) {
      try {
        final res = await http.get(Uri.parse(url)).timeout(_imageTimeout);
        if (res.statusCode != 200 || res.bodyBytes.isEmpty) continue;
        if (res.bodyBytes.length > maxImageBytes) continue;
        // Sanity check: Drive answers a blocked/large file with HTML.
        final isHtml =
            res.headers['content-type']?.contains('text/html') ?? false;
        if (isHtml) continue;
        out[url] = res.bodyBytes;
      } catch (_) {
        // Ignore — this image will be referenced by URL instead.
      }
    }
    return out;
  }

  /// Identify the image format from its magic bytes.
  ///
  /// Stem diagrams are very often JPEG or WEBP, so guessing "png" would emit a
  /// wrong MIME type in the data URI. Falls back to image/png.
  static String sniffImageMime(Uint8List bytes) {
    bool starts(List<int> sig, [int offset = 0]) {
      if (bytes.length < offset + sig.length) return false;
      for (var i = 0; i < sig.length; i++) {
        if (bytes[offset + i] != sig[i]) return false;
      }
      return true;
    }

    if (starts([0x89, 0x50, 0x4E, 0x47])) return 'image/png';
    if (starts([0xFF, 0xD8, 0xFF])) return 'image/jpeg';
    if (starts([0x47, 0x49, 0x46, 0x38])) return 'image/gif';
    if (starts([0x42, 0x4D])) return 'image/bmp';
    // RIFF....WEBP
    if (starts([0x52, 0x49, 0x46, 0x46]) &&
        starts([0x57, 0x45, 0x42, 0x50], 8)) {
      return 'image/webp';
    }
    return 'image/png';
  }

  /// An `<img>`/data-URI fragment for the stem image, or '' when there is none.
  ///
  /// [bytes] lets Word embed the image inline (Word will not reliably render a
  /// remote <img src>); HTML/Markdown pass null and just link to the URL.
  static String _stemImageMarkup(
    HighSchoolQuestion q, {
    Map<String, Uint8List>? bytes,
    required StemImageSize size,
    required bool usePoints,
  }) {
    if (!size.isVisible) return '';
    final resolved = resolveImageUrl(q.stemImageUrl);
    if (resolved.isEmpty) return '';

    final imageBytes = bytes?[resolved];
    final src = imageBytes != null
        ? 'data:${sniffImageMime(imageBytes)};base64,${base64Encode(imageBytes)}'
        : _escapeXml(resolved);

    final unit = usePoints ? 'pt' : 'px';
    final maxH = usePoints ? size.maxHeightPt : size.maxHeightPx;
    final maxW = usePoints ? size.maxWidthPt : size.maxWidthPt * 1.333;

    return '<img src="$src" alt="উদ্দীপক চিত্র" '
        'style="display:block; margin:4pt 0 6pt 0; '
        'max-width:${_trimNum(maxW)}$unit; max-height:${_trimNum(maxH)}$unit; '
        'object-fit:contain; '
        '${usePoints ? '' : 'margin-left:auto; margin-right:auto;'}" />';
  }

  /// Trim a double for CSS output (no trailing ".0").
  static String _trimNum(double v) {
    if (v == v.roundToDouble()) return v.round().toString();
    return v.toStringAsFixed(1);
  }

  /// True when the stem image should appear at all.
  static bool _hasStemImage(HighSchoolQuestion q, StemImageSize size) =>
      size.isVisible && resolveImageUrl(q.stemImageUrl).isNotEmpty;

  static String _stemImageUrlOf(HighSchoolQuestion q) =>
      resolveImageUrl(q.stemImageUrl);

  // ─────────────────────────────────────────────────────────────────────────
  // 1. Plain Text Format
  // ─────────────────────────────────────────────────────────────────────────

  static String generatePlainText({
    required String schoolName,
    required String examName,
    required String subject,
    required String className,
    required String time,
    required String totalMarks,
    required List<HighSchoolQuestion> questions,
    StemImageSize imageSize = StemImageSize.medium,
  }) {
    final buffer = StringBuffer();
    final divider = '=' * 50;
    final thinDivider = '-' * 50;

    buffer.writeln(divider);
    if (schoolName.trim().isNotEmpty) {
      buffer.writeln(schoolName.trim());
    }
    if (examName.trim().isNotEmpty) {
      buffer.writeln(examName.trim());
    }
    buffer.writeln(divider);

    final metaLine1 = <String>[];
    if (subject.trim().isNotEmpty) metaLine1.add('বিষয়: $subject');
    if (className.trim().isNotEmpty) metaLine1.add('শ্রেণি: $className');
    if (metaLine1.isNotEmpty) buffer.writeln(metaLine1.join('  |  '));

    final metaLine2 = <String>[];
    if (time.trim().isNotEmpty) metaLine2.add('সময়: $time');
    if (totalMarks.trim().isNotEmpty) metaLine2.add('পূর্ণমান: $totalMarks');
    if (metaLine2.isNotEmpty) buffer.writeln(metaLine2.join('  |  '));
    buffer.writeln(thinDivider);
    buffer.writeln();

    final cqs = questions.where((q) => q.isCq).toList();
    final mcqs = questions.where((q) => q.isMcq).toList();
    final shorts = questions.where((q) => q.isShort).toList();

    // CQ Section
    if (cqs.isNotEmpty) {
      buffer.writeln('【 ক-বিভাগ: সৃজনশীল প্রশ্ন (CQ) 】');
      buffer.writeln('[নিচের উদ্দীপকগুলো পড়ে সংশ্লিষ্ট প্রশ্নের উত্তর দাও]');
      buffer.writeln();

      for (int i = 0; i < cqs.length; i++) {
        final q = cqs[i];
        final index = i + 1;
        buffer.writeln('$index. ${latexToPlainText(q.paperStemText.trim())}');
        if (q.boardYearTag.isNotEmpty) {
          buffer.writeln('   [উৎস: ${q.boardYearTag}]');
        }
        if (_hasStemImage(q, imageSize)) {
          // Plain text cannot embed an image, so surface the link.
          buffer.writeln('   [চিত্র: ${_stemImageUrlOf(q)}]');
        }

        for (final sq in q.cqSubQuestions) {
          final markStr = sq.mark > 0 ? ' [${sq.mark}]' : '';
          buffer.writeln('   (${sq.label}) ${sq.text}$markStr');
        }
        buffer.writeln();
      }
    }

    // MCQ Section
    if (mcqs.isNotEmpty) {
      buffer.writeln(thinDivider);
      buffer.writeln('【 খ-বিভাগ: বহুনির্বাচনী প্রশ্ন (MCQ) 】');
      buffer.writeln('[সঠিক উত্তরের পাশে টিক (✓) চিহ্ন দাও]');
      buffer.writeln();

      const bengaliLetters = ['ক', 'খ', 'গ', 'ঘ'];
      for (int i = 0; i < mcqs.length; i++) {
        final q = mcqs[i];
        final mcq = q.mcqData;
        final index = i + 1;
        if (mcq == null) continue;

        buffer.writeln('$index. ${q.paperQuestionText}');
        final options = mcq.options;
        for (int optIdx = 0; optIdx < options.length; optIdx++) {
          final letter = optIdx < bengaliLetters.length
              ? bengaliLetters[optIdx]
              : '${optIdx + 1}';
          buffer.writeln('   ($letter) ${options[optIdx]}');
        }
        buffer.writeln();
      }
    }

    // Short question section (গ-বিভাগ)
    if (shorts.isNotEmpty) {
      buffer.writeln(thinDivider);
      buffer.writeln('【 গ-বিভাগ: সংক্ষিপ্ত প্রশ্ন (SQ) 】');
      buffer.writeln();
      for (int i = 0; i < shorts.length; i++) {
        final data = shorts[i].shortData;
        if (data == null || data.text.trim().isEmpty) continue;
        final markStr = data.mark > 0 ? ' [${data.mark}]' : '';
        buffer.writeln('${i + 1}. ${data.text.trim()}$markStr');
      }
      buffer.writeln();
    }

    return buffer.toString();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 2. Microsoft Word Document (.doc via Word-HTML format)
  // ─────────────────────────────────────────────────────────────────────────

  static String generateWordDoc({
    required String schoolName,
    required String examName,
    required String subject,
    required String className,
    required String time,
    required String totalMarks,
    required List<HighSchoolQuestion> questions,
    Map<String, Uint8List>? imageBytes,
    StemImageSize imageSize = StemImageSize.medium,
    QuestionLayout cqLayout = QuestionLayout.single,
    QuestionLayout mcqLayout = QuestionLayout.doubleColumn,
    QuestionLayout rqLayout = QuestionLayout.single,
  }) {
    final cqs = questions.where((q) => q.isCq).toList();
    final mcqs = questions.where((q) => q.isMcq).toList();
    final shorts = questions.where((q) => q.isShort).toList();

    final buffer = StringBuffer();
    buffer.write('''
<html xmlns:o='urn:schemas-microsoft-com:office:office'
      xmlns:w='urn:schemas-microsoft-com:office:word'
      xmlns='http://www.w3.org/TR/REC-html40'>
<head>
  <meta charset='utf-8'>
  <title>${_escapeXml(examName.isEmpty ? 'Question Paper' : examName)}</title>
  <!--[if gte mso 9]>
  <xml>
    <w:WordDocument>
      <w:View>Print</w:View>
      <w:Zoom>100</w:Zoom>
      <w:DoNotOptimizeForBrowser/>
    </w:WordDocument>
  </xml>
  <![endif]-->
  <style>
    @page Section1 {
      size: 595.45pt 841.9pt; /* A4 */
      margin: 1.0in 0.8in 1.0in 0.8in;
      mso-header-margin: 36.0pt;
      mso-footer-margin: 36.0pt;
      mso-paper-source: 0;
    }
    div.Section1 { page: Section1; }
    body {
      font-family: 'Kalpurush', 'SolaimanLipi', 'Nirmala UI', 'Vrinda', 'Times New Roman', serif;
      font-size: 11pt;
      line-height: 1.45;
      color: #000000;
    }
    .header-table {
      width: 100%;
      border-collapse: collapse;
      margin-bottom: 8pt;
      border-bottom: 2pt solid #000000;
      padding-bottom: 6pt;
    }
    .school-title {
      font-size: 18pt;
      font-weight: bold;
      text-align: center;
      margin: 0 0 4pt 0;
    }
    .exam-title {
      font-size: 14pt;
      font-weight: bold;
      text-align: center;
      margin: 0 0 6pt 0;
    }
    .meta-row {
      font-size: 11pt;
      font-weight: bold;
    }
    .section-title {
      font-size: 13pt;
      font-weight: bold;
      text-align: center;
      background-color: #f0f0f0;
      padding: 4pt;
      margin: 12pt 0 8pt 0;
      border: 1pt solid #cccccc;
    }
    .cq-box {
      margin-bottom: 12pt;
      page-break-inside: avoid;
    }
    .cq-stem {
      font-size: 11pt;
      margin-bottom: 4pt;
    }
    .cq-stem-img {
      max-width: 420pt;
      max-height: 320pt;
      margin: 4pt 0 6pt 0;
      display: block;
    }
    .cq-sub-table {
      width: 100%;
      border-collapse: collapse;
      margin-left: 12pt;
    }
    .cq-sub-label {
      width: 25pt;
      font-weight: bold;
      vertical-align: top;
    }
    .cq-sub-text {
      vertical-align: top;
    }
    .cq-sub-mark {
      width: 40pt;
      text-align: right;
      font-weight: bold;
      vertical-align: top;
    }
    .mcq-container {
      margin-bottom: 8pt;
      page-break-inside: avoid;
    }
    .mcq-layout-table {
      width: 100%;
      border-collapse: collapse;
      table-layout: fixed;
    }
    .cq-col-cell {
      width: ${cqLayout.isDouble ? '50%' : '100%'};
      vertical-align: top;
      padding: 0pt 4pt 8pt 0pt;
    }
    .mcq-col-cell {
      width: ${mcqLayout.isDouble ? '50%' : '100%'};
      vertical-align: top;
      padding: 0pt 4pt 8pt 0pt;
    }
    .mcq-question {
      font-weight: 500;
      margin-bottom: 3pt;
    }
    .mcq-options-table {
      width: 100%;
      border-collapse: collapse;
      margin-left: 10pt;
    }
    .mcq-opt-cell {
      width: 50%;
      padding: 2pt 4pt;
      vertical-align: top;
    }
    .rq-col-cell {
      width: ${rqLayout.isDouble ? '50%' : '100%'};
      vertical-align: top;
      padding: 0pt 4pt 0pt 0pt;
    }
    .rq-item {
      display: flex;
      justify-content: space-between;
      gap: 12pt;
      margin-bottom: 6pt;
      font-size: 11pt;
      page-break-inside: avoid;
    }
    .rq-mark {
      font-weight: bold;
      white-space: nowrap;
    }
    .frac { display:inline-block; vertical-align:middle; text-align:center; margin:0 .15em; line-height:1.05; }
    .frac-num { display:block; padding:0 .25em; border-bottom:1px solid #000; }
    .frac-den { display:block; padding:0 .25em; }
    .mathv { font-style:italic; }
  </style>
</head>
<body>
<div class="Section1">
  <div class="header-table">
    ${schoolName.trim().isNotEmpty ? '<div class="school-title">${_escapeXml(schoolName)}</div>' : ''}
    ${examName.trim().isNotEmpty ? '<div class="exam-title">${_escapeXml(examName)}</div>' : ''}
    <table style="width:100%; border:none; margin-top:4pt;">
      <tr class="meta-row">
        <td style="text-align:left;">বিষয়: ${_escapeXml(subject)}</td>
        <td style="text-align:center;">শ্রেণি: ${_escapeXml(className)}</td>
        <td style="text-align:right;">সময়: ${_escapeXml(time)} | পূর্ণমান: ${_escapeXml(totalMarks)}</td>
      </tr>
    </table>
  </div>
''');

    // CQ Section
    if (cqs.isNotEmpty) {
      buffer.write('''
  <div class="section-title">ক-বিভাগ: সৃজনশীল প্রশ্ন (CQ)</div>
  <div style="font-size:10pt; font-style:italic; margin-bottom:8pt; text-align:center;">[যেকোনো নির্ধারিত সংখ্যক প্রশ্নের উত্তর দাও]</div>
''');

      // A real table keeps columns stable in Word/WPS, which CSS does not.
      buffer.write('''
  <table class="mcq-layout-table" width="100%" cellspacing="0" cellpadding="0">
''');
      final cqCols = cqLayout.mcqColumns;
      for (int i = 0; i < cqs.length; i += cqCols) {
        final cells = StringBuffer();
        for (int c = 0; c < cqCols; c++) {
          if (c > 0) cells.write('<td class="mcq-col-gap" width="16"></td>');
          final idx = i + c;
          if (idx >= cqs.length) {
            cells.write('<td class="mcq-col-cell"></td>');
            continue;
          }
          final q = cqs[idx];
          final index = idx + 1;
          cells.write('''
    <td class="cq-col-cell">
      <div class="cq-box">
        <div class="cq-stem">
          <b>$index.</b> ${latexToHtml(_escapeXml(q.paperStemText))}
          ${q.boardYearTag.isNotEmpty ? '<span style="font-size:9pt; color:#555555;"> [${_escapeXml(q.boardYearTag)}]</span>' : ''}
        </div>
        ${_stemImageMarkup(q, bytes: imageBytes, size: imageSize, usePoints: true)}
        <table class="cq-sub-table">''');
          for (final sq in q.cqSubQuestions) {
            cells.write('''
          <tr>
            <td class="cq-sub-label">(${_escapeXml(sq.label)})</td>
            <td class="cq-sub-text">${latexToHtml(_escapeXml(sq.text))}</td>
            <td class="cq-sub-mark">${sq.mark > 0 ? '[${sq.mark}]' : ''}</td>
          </tr>''');
          }
          cells.write('''
        </table>
      </div>
    </td>''');
        }
        buffer.write('''
    <tr>$cells
    </tr>
''');
      }
      buffer.write('''
  </table>
''');
    }

    // MCQ Section
    if (mcqs.isNotEmpty) {
      buffer.write('''
  <div class="section-title">খ-বিভাগ: বহুনির্বাচনী প্রশ্ন (MCQ)</div>
  <div style="font-size:10pt; font-style:italic; margin-bottom:8pt; text-align:center;">[সঠিক উত্তরের পাশে টিক (✓) চিহ্ন দাও]</div>
''');

      const bengaliLetters = ['ক', 'খ', 'গ', 'ঘ'];

      // Options for one question, as an HTML fragment.
      String optionsHtml(List<String> options) {
        final b = StringBuffer();
        for (int opt = 0; opt < options.length; opt += 2) {
          final l1 =
              opt < bengaliLetters.length ? bengaliLetters[opt] : '${opt + 1}';
          final has2 = opt + 1 < options.length;
          final l2 = has2 && (opt + 1) < bengaliLetters.length
              ? bengaliLetters[opt + 1]
              : '${opt + 2}';
          final o2 = has2 ? options[opt + 1] : '';
          b.write('''
      <tr>
        <td class="mcq-opt-cell">($l1) ${_escapeXml(options[opt])}</td>
        <td class="mcq-opt-cell">${has2 ? '($l2) ${_escapeXml(o2)}' : ''}</td>
      </tr>''');
        }
        return b.toString();
      }

      // One question as a full cell.
      String questionCell(int index, HighSchoolQuestion q) {
        final mcq = q.mcqData;
        if (mcq == null) return '<td class="mcq-col-cell"></td>';
        return '''
    <td class="mcq-col-cell">
      <div class="mcq-question"><b>$index.</b> ${_escapeXml(q.paperQuestionText)}</div>
      <table class="mcq-options-table">${optionsHtml(mcq.options)}</table>
    </td>''';
      }

      // A real table keeps the columns stable in Word/WPS, which a CSS grid
      // does not reliably survive.
      buffer.write('''
  <table class="mcq-layout-table" width="100%" cellspacing="0" cellpadding="0">
''');
      final cols = mcqLayout.mcqColumns;
      for (int i = 0; i < mcqs.length; i += cols) {
        final cells = StringBuffer();
        for (int c = 0; c < cols; c++) {
          final idx = i + c;
          if (c > 0) cells.write('<td class="mcq-col-gap" width="16"></td>');
          cells.write(idx < mcqs.length
              ? questionCell(idx + 1, mcqs[idx])
              : '<td class="mcq-col-cell"></td>');
        }
        buffer.write('''
    <tr>$cells
    </tr>
''');
      }
      buffer.write('''
  </table>
''');
    }

    // Short question section (গ-বিভাগ)
    if (shorts.isNotEmpty) {
      buffer.write('''
  <div class="section-title">গ-বিভাগ: সংক্ষিপ্ত প্রশ্ন (SQ)</div>
  <div style="font-size:10pt; font-style:italic; margin-bottom:8pt; text-align:center;">[সংক্ষেপে উত্তর দাও]</div>
''');

      // Short questions in two columns, laid out as a table so Word keeps the
      // fixed 50/50 split that its CQ and MCQ sections use.
      String rqCell(int index) {
        final data = shorts[index].shortData;
        if (data == null || data.text.trim().isEmpty) return '';
        return '''
    <div class="rq-item">
      <span>${index + 1}. ${_escapeXml(data.text)}</span>
      <span class="rq-mark">[${data.mark}]</span>
    </div>''';
      }

      final rqCols = rqLayout.mcqColumns;
      if (rqCols > 1) {
        buffer.write('''
  <table class="mcq-layout-table" width="100%" cellspacing="0" cellpadding="0">
''');
        for (int i = 0; i < shorts.length; i += rqCols) {
          buffer.write('  <tr>');
          for (int c = 0; c < rqCols; c++) {
            if (c > 0) buffer.write('<td class="mcq-col-gap" width="16"></td>');
            final idx = i + c;
            buffer.write(idx < shorts.length
                ? '    <td class="rq-col-cell">${rqCell(idx)}</td>'
                : '    <td class="rq-col-cell"></td>');
          }
          buffer.write('  </tr>\n');
        }
        buffer.write('  </table>\n');
      } else {
        for (int i = 0; i < shorts.length; i++) {
          final cell = rqCell(i);
          if (cell.isNotEmpty) buffer.write('$cell\n');
        }
      }
    }

    buffer.write('''
</div>
</body>
</html>
''');
    return buffer.toString();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 3. Web / HTML Format (Print-optimized, responsive)
  // ─────────────────────────────────────────────────────────────────────────

  static String generateHtml({
    required String schoolName,
    required String examName,
    required String subject,
    required String className,
    required String time,
    required String totalMarks,
    required List<HighSchoolQuestion> questions,
    List<String> setLabels = const [],
    List<PaperSection> sectionOrder = PaperSection.defaultOrder,
    StemImageSize imageSize = StemImageSize.medium,
    QuestionLayout cqLayout = QuestionLayout.single,
    QuestionLayout mcqLayout = QuestionLayout.doubleColumn,
    QuestionLayout rqLayout = QuestionLayout.single,
  }) {
    // A two-set paper prints as two papers in one file. A question belongs to a
    // set through [HighSchoolQuestion.setLabel], and a question the reader never
    // filed into a set belongs to both — dropping it would silently lose a
    // question from the paper.
    final labels = [
      for (final label in setLabels)
        if (label.trim().isNotEmpty) label.trim(),
    ];
    final sets = <List<HighSchoolQuestion>>[
      for (var i = 0; i < (labels.isEmpty ? 1 : labels.length); i++)
        _questionsForSet(questions, labels, i),
    ];

    // The blocks the paper actually has, in the order the reader arranged them.
    // Read off every question rather than one set, so a block that happens to be
    // empty in one set keeps its letter in the other — the PDF does the same.
    final ordered = <PaperSection>[
      ...sectionOrder,
      ...PaperSection.defaultOrder.where((s) => !sectionOrder.contains(s)),
    ];
    final sections = [
      for (final s in ordered)
        if (questions.any((q) => _sectionOf(q) == s)) s,
    ];

    // Which blocks are laid out in two columns, and whether CQ and the short
    // questions share one continuous flow. The PDF merges the two the same way:
    // they are packed together only while they sit next to each other and both
    // are two-column. MCQ never joins the flow — its options lay out
    // differently, and it wants a fresh pair of columns.
    final twoColumnBlocks = <PaperSection>{
      if (cqLayout.isDouble) PaperSection.cq,
      if (rqLayout.isDouble) PaperSection.rq,
      if (mcqLayout.isDouble) PaperSection.mcq,
    };
    final mergeCqAndShort = cqLayout.isDouble && rqLayout.isDouble;

    final buffer = StringBuffer();
    buffer.write('''
<!DOCTYPE html>
<html lang="bn">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>${_escapeXml(examName.isEmpty ? 'Question Paper' : examName)} - Pi-QBank</title>
  <link href="https://fonts.googleapis.com/css2?family=Hind+Siliguri:wght@400;500;600;700&display=swap" rel="stylesheet">
  <style>
    :root {
      --primary: #4f46e5;
      /* The PDF writes its text in pure black; the page should look the same. */
      --text: #000000;
      /* Marks and source tags: secondary text, a touch grey. */
      --muted: #64748b;
      --border: #cbd5e1;
      --bg: #f8fafc;
    }
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      font-family: 'Hind Siliguri', 'SolaimanLipi', sans-serif;
      background: var(--bg);
      color: var(--text);
      line-height: 1.6;
      padding: 24px;
    }
    .no-print-toolbar {
      max-width: 210mm;
      margin: 0 auto 20px auto;
      display: flex;
      justify-content: space-between;
      align-items: center;
      background: white;
      padding: 14px 20px;
      border-radius: 12px;
      box-shadow: 0 4px 12px rgba(0,0,0,0.06);
    }
    .btn {
      display: inline-flex;
      align-items: center;
      gap: 8px;
      padding: 10px 18px;
      font-size: 14px;
      font-weight: 600;
      border-radius: 8px;
      border: none;
      cursor: pointer;
      text-decoration: none;
      transition: all 0.2s;
    }
    .btn-primary { background: var(--primary); color: white; }
    .btn-primary:hover { background: #4338ca; }
    .btn-outline { background: white; border: 1px solid #cbd5e1; color: var(--text); }
    .btn-outline:hover { background: #f1f5f9; }

    /* The sheet *is* an A4 page: the same 210×297mm canvas the PDF export uses,
       the same 18pt at the head and 40pt down each side, and a foot of 18px.
       Same paper, same text width, so a line that wraps here wraps the same way
       in the PDF: the canvas on screen is what the printer produces. */
    .paper-sheet {
      width: 210mm;
      max-width: 100%;
      min-height: 297mm;
      margin: 0 auto;
      background: white;
      padding: 18pt 40pt 18px;
      border-radius: 8px;
      box-shadow: 0 4px 24px rgba(0,0,0,0.08);
    }
    /* A second sheet exists only when the two sets do not fit on one page: the
       script at the foot of the file splits them when that is the case, and on
       paper the split becomes a page break. */
    .paper-sheet + .paper-sheet { margin-top: 24px; }
    /* One set. Sets share the sheet while the pair fits on a page. */
    .set-head {
      break-inside: avoid;
      break-after: avoid;
    }
    /* The dashed rule the PDF draws between two sets that share a sheet, with
       the same gaps above and below it. */
    .set-divider {
      border-top: 1px dashed var(--border);
      margin: 16pt 0 12pt 0;
      break-after: avoid;
    }
    .school-title { font-size: 24px; font-weight: 700; text-align: center; margin-bottom: 4px; }
    .exam-title { font-size: 18px; font-weight: 600; text-align: center; }
    .meta-bar {
      display: flex;
      justify-content: space-between;
      flex-wrap: wrap;
      padding: 2px 0;
      border-top: 1.5px solid var(--text);
      border-bottom: 1.5px solid var(--text);
      font-weight: 600;
      font-size: 15px;
    }
    /* The PDF's own spacing, in the PDF's own units: `PdfLayout.sectionGap`
       above every banner and `PdfLayout.sectionBannerGap` below it. The same
       two numbers the page charges its widget tree, so the band under the
       masthead is no wider here than the gap before any other section, and the
       three sections sit the same distance apart in both exports. */
    .section-banner {
      text-align: center;
      font-size: 14px;
      font-weight: 700;
      background: #f1f5f9;
      padding: 3px 6px;
      border-radius: 6px;
      margin: 5pt 0 10pt 0;
      border: 1px solid #e2e8f0;
    }
    /* The same bar inside a two-column block: it opens the first column instead
       of spanning the page, so the declaration is one column wide like the
       questions under it. Its top margin goes: a margin on the first child of
       the flow would push the declaration's column down and leave the right
       column's first question sitting higher than the heading beside it. The
       gap above the block moves out to the column container instead, which both
       columns share and which therefore starts them level. `break-after` keeps
       the bar from being stranded at the foot of a column with its questions
       overleaf. */
    .section-banner.in-flow {
      margin: 0 0 6px 0;
      break-after: avoid;
    }
    /* No frame around a question. The two sides are divided by one vertical
       line down the gutter — set on the flow containers with `column-rule` —
       instead of every question carrying a box of its own, which is what made
       the two columns read as two stacks of cards.
       And no `break-inside: avoid` either: keeping every question whole is what
       left the columns lopsided, since a card too tall for the space it had
       left jumped to the next column and stranded the rest of the one before
       it. Letting a question break — as the PDF does, where it repeats the
       number on the continuation — is what lets the two sides finish level.
       `widows`/`orphans` keep a split from leaving one line behind. */
    .cq-card {
      margin-bottom: 10px;
      orphans: 2;
      widows: 2;
    }
    .cq-stem { font-size: 15px; margin-bottom: 5px; }
    .cq-stem-img {
      display: block;
      max-width: 100%;
      max-height: 340px;
      margin: 0 auto 12px auto;
      object-fit: contain;
    }
    /* A sub-question row under its stem: just a small indent and the mark on
       the right. No margin of its own — the line boxes are the whole of the
       spacing, so the run sits tight. */
    .cq-sub-item {
      display: flex;
      justify-content: space-between;
      font-size: 14px;
      padding-left: 6px;
    }
    .cq-mark {
      font-weight: 700;
      min-width: 30px;
      text-align: right;
      color: var(--muted);
    }
    /* Two-column sections flow like a newspaper: a question keeps the height it
       needs and the next one continues below it in the same column. A grid
       would instead stretch every pair in a row to the taller of the two, so a
       one-line question beside a diagram sat in a card half full of white. */
    .cq-grid {${cqLayout.isDouble ? '\n      margin-top: 5pt;\n      column-count: 2;\n      column-gap: 22px;\n      column-rule: 1px solid var(--border);' : ''}
    }
    /* A merged CQ + short-question run: one continuous pair of columns, so the
       short questions begin exactly where the creative questions run out —
       mid-column or at the head of the next one. The gap above the run sits on
       the container, not on the heading inside it, so both columns start level. */
    .flow-grid {${mergeCqAndShort ? '\n      margin-top: 5pt;\n      column-count: 2;\n      column-gap: 22px;\n      column-rule: 1px solid var(--border);' : ''}
    }
    .mcq-grid {${mcqLayout.isDouble ? '\n      margin-top: 5pt;\n      column-count: 2;\n      column-gap: 22px;\n      column-rule: 1px solid var(--border);' : ''}
    }
    .mcq-card {
      padding: 12px;
      margin-bottom: 12px;
      border-bottom: 1px dashed var(--border);
      orphans: 2;
      widows: 2;
    }
    .mcq-options {
      display: grid;
      grid-template-columns: ${mcqLayout.isDouble ? '1fr' : '1fr 1fr'};
      gap: 6px 16px;
      margin-top: 6px;
      padding-left: 16px;
      font-size: 14px;
    }
    .rq-grid {${rqLayout.isDouble ? '\n      margin-top: 5pt;\n      column-count: 2;\n      column-gap: 22px;\n      column-rule: 1px solid var(--border);' : ''}
    }
    /* Short questions are a single line each, as in the PDF: no padding and no
       gap of their own — the line box is the whole of the row, and the mark is
       held at the right edge by the flex row. A one-line row stays whole:
       breaking inside it would gain nothing for the column balance and could cut
       a question in half. */
    .rq-item {
      display: flex;
      justify-content: space-between;
      align-items: baseline;
      font-size: 15px;
      page-break-inside: avoid;
      break-inside: avoid;
    }
    .rq-mark { font-weight: 700; white-space: nowrap; color: var(--muted); }

    @page { size: A4; margin: 0; }

    @media print {
      body { background: white; padding: 0; }
      .no-print-toolbar { display: none !important; }
      /* No margin on the page box: the sheet carries the page's own margins, so
         a printed page breaks where the exported PDF page breaks. */
      .paper-sheet {
        width: auto;
        max-width: none;
        min-height: 0;
        box-shadow: none;
        border-radius: 0;
        padding: 18pt 40pt 18px;
      }
      .paper-sheet + .paper-sheet { break-before: page; margin-top: 0; }
    }
    .frac { display:inline-block; vertical-align:middle; text-align:center; margin:0 .15em; line-height:1.05; }
    .frac-num { display:block; padding:0 .25em; border-bottom:1px solid #000; }
    .frac-den { display:block; padding:0 .25em; }
    .mathv { font-style:italic; }
  </style>
</head>
<body>
  <div class="no-print-toolbar">
    <div><b>Pi-QBank</b> প্রশ্নপত্র প্রিভিউ</div>
    <div style="display:flex; gap:10px;">
      <button class="btn btn-primary" onclick="window.print()">🖨️ প্রিন্ট / PDF সংরক্ষণ</button>
    </div>
  </div>

  <div class="paper-sheet">
''');

    // Every set goes on one sheet. Whether the sets stay together or get a sheet
    // each is decided by what actually fits, in the script at the foot of the
    // file — the page is A4 either way, so what fits on screen is what fits on
    // paper.
    for (var i = 0; i < sets.length; i++) {
      if (i > 0) {
        buffer.write('''
    <div class="set-divider"></div>
''');
      }
      _writeHtmlSet(
        buffer,
        schoolName: schoolName,
        examName: examName,
        subject: subject,
        className: className,
        time: time,
        totalMarks: totalMarks,
        setLabel: labels.isEmpty ? '' : labels[i],
        questions: sets[i],
        sections: sections,
        twoColumnBlocks: twoColumnBlocks,
        mergeCqAndShort: mergeCqAndShort,
        imageSize: imageSize,
      );
    }

    buffer.write('''
  </div>

  <script>
    /* Two sets share the sheet while the pair fits on a single A4 page; when it
       does not, the second set moves into a sheet of its own and the printer —
       which breaks between sheets — puts it on a page of its own. Measured
       rather than guessed: the sheet is A4 wide either way, so what fits here is
       what fits on paper. A pair that fits gets the page's leftover space put
       between the sets, so the second one reaches the foot of the page instead
       of leaving a band of white under it. */
    (function () {
      function decide() {
        var sheet = document.querySelector('.paper-sheet');
        if (!sheet) return;
        var sets = Array.prototype.slice.call(
            sheet.querySelectorAll(':scope > .paper-set'));
        if (sets.length < 2) return;

        var style = getComputedStyle(sheet);
        var padTop = parseFloat(style.paddingTop);
        var padBottom = parseFloat(style.paddingBottom);

        // A page's worth of room, from the page box itself rather than a
        // hard-coded number of pixels.
        var probe = document.createElement('div');
        probe.style.cssText =
            'position:absolute;visibility:hidden;width:0;height:297mm;';
        document.body.appendChild(probe);
        var room = probe.getBoundingClientRect().height - padTop - padBottom;
        probe.remove();

        // What the sets take right now — the rule between them and every margin
        // included. Measured with the page's own minimum height out of the way,
        // so a short pair reports its real height and not a full page.
        var minHeight = sheet.style.minHeight;
        sheet.style.minHeight = '0';
        var used = sheet.getBoundingClientRect().height - padTop - padBottom;
        sheet.style.minHeight = minHeight;

        var divider = sheet.querySelector(':scope > .set-divider');
        if (used <= room) {
          if (divider) {
            // The leftover belongs between the sets: half above the rule and
            // half below, so it marks the middle of the separation and the
            // second set finishes level with the foot of the page.
            var slack = (room - used) / 2;
            var rule = getComputedStyle(divider);
            divider.style.marginTop =
                (parseFloat(rule.marginTop) + slack) + 'px';
            divider.style.marginBottom =
                (parseFloat(rule.marginBottom) + slack) + 'px';
          }
          return;
        }

        var anchor = sheet;
        for (var i = 1; i < sets.length; i++) {
          var next = document.createElement('div');
          next.className = 'paper-sheet';
          anchor.parentNode.insertBefore(next, anchor.nextSibling);
          next.appendChild(sets[i]);
          anchor = next;
        }
        if (divider) divider.remove();
      }

      function run() {
        // Fonts and images decide how tall a set is, so wait for both.
        if (document.fonts && document.fonts.ready) {
          document.fonts.ready.then(decide);
        } else {
          decide();
        }
      }

      if (document.readyState === 'complete') run();
      else window.addEventListener('load', run);
    })();
  </script>
</body>
</html>
''');
    return buffer.toString();
  }

  /// The block a question is printed in, or null when its type is none of the
  /// three the paper is divided into — a row every export leaves out.
  static PaperSection? _sectionOf(HighSchoolQuestion q) {
    if (q.isCq) return PaperSection.cq;
    if (q.isMcq) return PaperSection.mcq;
    if (q.isShort) return PaperSection.rq;
    return null;
  }

  /// The questions of set [index], out of a paper printed with [labels].
  ///
  /// Without labels there is one set and every question belongs to it.
  ///
  /// An unlabelled question belongs to *every* set: it is a question the reader
  /// selected but never filed away, and both papers should still carry it —
  /// dropping it would lose it from the paper altogether.
  static List<HighSchoolQuestion> _questionsForSet(
    List<HighSchoolQuestion> questions,
    List<String> labels,
    int index,
  ) {
    if (labels.isEmpty) return questions;
    return questions
        .where((q) => q.setLabel.trim().isEmpty || q.setLabel == labels[index])
        .toList();
  }

  /// The heading a block is printed under.
  ///
  /// The বাংলা letter comes from the block's *position*, not its type: the
  /// blocks can be dragged into any order, so whichever one the reader put
  /// first is ক-বিভাগ. Tying the letter to the type would print two "ক-বিভাগ"s
  /// the moment a block moved.
  static String _sectionHeading(PaperSection kind, int position) {
    const letters = ['ক', 'খ', 'গ'];
    final letter =
        position < letters.length ? letters[position] : '${position + 1}';
    switch (kind) {
      case PaperSection.cq:
        return '$letter-বিভাগ: সৃজনশীল প্রশ্ন (CQ)';
      case PaperSection.rq:
        return '$letter-বিভাগ: সংক্ষিপ্ত প্রশ্ন (SQ)';
      case PaperSection.mcq:
        return '$letter-বিভাগ: বহুনির্বাচনী প্রশ্ন (MCQ)';
    }
  }

  /// One set of the paper: its masthead, then every block in the reader's order.
  ///
  /// The sheet holds each set in a `.paper-set` of its own so the script at the
  /// foot of the file can move one into a separate sheet when the pair does not
  /// fit on a single page. The set's name rides in the masthead's meta bar
  /// rather than in a banner of its own — the PDF does the same, and it costs no
  /// vertical space.
  static void _writeHtmlSet(
    StringBuffer buffer, {
    required String schoolName,
    required String examName,
    required String subject,
    required String className,
    required String time,
    required String totalMarks,
    required String setLabel,
    required List<HighSchoolQuestion> questions,
    required List<PaperSection> sections,
    required Set<PaperSection> twoColumnBlocks,
    required bool mergeCqAndShort,
    required StemImageSize imageSize,
  }) {
    buffer.write('''
    <div class="paper-set">
      <div class="set-head">
        ${schoolName.trim().isNotEmpty ? '<div class="school-title">${_escapeXml(schoolName)}</div>' : ''}
        ${examName.trim().isNotEmpty ? '<div class="exam-title">${_escapeXml(examName)}</div>' : ''}

        <div class="meta-bar">
          ${setLabel.isNotEmpty ? '<div>সেট: ${_escapeXml(setLabel)}</div>' : ''}
          <div>বিষয়: ${_escapeXml(subject)}</div>
          <div>শ্রেণি: ${_escapeXml(className)}</div>
          <div>সময়: ${_escapeXml(time)}</div>
          <div>পূর্ণমান: ${_escapeXml(totalMarks)}</div>
        </div>
      </div>
''');

    for (var i = 0; i < sections.length; i++) {
      final kind = sections[i];
      final inSection = questions.where((q) => _sectionOf(q) == kind).toList();
      // A block that came up empty in this set is skipped. Its letter comes from
      // [i], its position in the paper, so the blocks that do print keep the
      // letters they have in the other set.
      if (inSection.isEmpty) continue;

      final heading = _sectionHeading(kind, i);

      // CQ and the short questions are neighbours on a two-column sheet: one
      // flow for both, so the second type begins exactly where the first one
      // runs out. The partner's own turn in this loop is consumed here.
      final partner = _mergePartnerOf(sections, i, mergeCqAndShort);
      if (partner != null) {
        _writeHtmlMergedFlow(
          buffer,
          questions: questions,
          first: kind,
          second: partner,
          firstHeading: heading,
          secondHeading: _sectionHeading(partner, i + 1),
          imageSize: imageSize,
        );
        i++;
        continue;
      }

      // A block laid out in two columns declares itself *inside* the first
      // column. See [_writeHtmlDeclaration].
      final declarationInFlow = twoColumnBlocks.contains(kind);
      switch (kind) {
        case PaperSection.cq:
          _writeHtmlCqSection(buffer, inSection, heading, imageSize,
              declarationInFlow: declarationInFlow);
          break;
        case PaperSection.mcq:
          _writeHtmlMcqSection(buffer, inSection, heading,
              declarationInFlow: declarationInFlow);
          break;
        case PaperSection.rq:
          _writeHtmlRqSection(buffer, inSection, heading,
              declarationInFlow: declarationInFlow);
          break;
      }
    }

    buffer.write('''
    </div>
''');
  }

  /// A block's declaration — the bar naming the question type.
  ///
  /// [inFlow] writes it to be placed *inside* the block's columns instead of
  /// across the page. A full-width bar over a two-column block reads as a page
  /// header and costs a line of the sheet; inside the flow it opens the first
  /// column, one column wide like the questions under it.
  static void _writeHtmlDeclaration(
    StringBuffer buffer,
    String heading, {
    required bool inFlow,
  }) {
    buffer.write(inFlow
        ? '      <div class="section-banner in-flow">${_escapeXml(heading)}</div>\n'
        : '    <div class="section-banner">${_escapeXml(heading)}</div>\n');
  }

  /// The block that shares a flow with the one at [index], or null.
  ///
  /// CQ and the short questions merge while they are neighbours on a two-column
  /// sheet, so the second type begins where the first one runs out. MCQ never
  /// merges — its options lay out differently, and it wants a fresh pair of
  /// columns. The PDF merges on exactly the same terms.
  static PaperSection? _mergePartnerOf(
    List<PaperSection> sections,
    int index,
    bool mergeCqAndShort,
  ) {
    if (!mergeCqAndShort || index + 1 >= sections.length) return null;
    final a = sections[index], b = sections[index + 1];
    final pair = (a == PaperSection.cq && b == PaperSection.rq) ||
        (a == PaperSection.rq && b == PaperSection.cq);
    return pair ? b : null;
  }

  /// CQ and the short questions as one continuous two-column flow.
  ///
  /// Both types share one pair of columns, so the second declaration and its
  /// questions land exactly where the first type's questions run out — mid
  /// column, or at the head of the next one — instead of the second block
  /// starting a fresh full-width row below whatever the first one left over.
  static void _writeHtmlMergedFlow(
    StringBuffer buffer, {
    required List<HighSchoolQuestion> questions,
    required PaperSection first,
    required PaperSection second,
    required String firstHeading,
    required String secondHeading,
    required StemImageSize imageSize,
  }) {
    buffer.write('''
    <div class="flow-grid">
''');
    _writeHtmlFlowPart(buffer, questions, first, firstHeading, imageSize);
    _writeHtmlFlowPart(buffer, questions, second, secondHeading, imageSize);
    buffer.write('''
    </div>
''');
  }

  /// One type's share of a merged flow: its declaration, then its questions.
  ///
  /// With no container of its own — the flow the two types share *is* the
  /// column container, and that is what makes the second type continue where
  /// the first one ended.
  static void _writeHtmlFlowPart(
    StringBuffer buffer,
    List<HighSchoolQuestion> questions,
    PaperSection kind,
    String heading,
    StemImageSize imageSize,
  ) {
    final inSection = questions.where((q) => _sectionOf(q) == kind).toList();
    if (inSection.isEmpty) return;

    _writeHtmlDeclaration(buffer, heading, inFlow: true);
    if (kind == PaperSection.cq) {
      _writeHtmlCqCards(buffer, inSection, imageSize);
    } else {
      _writeHtmlRqItems(buffer, inSection);
    }
  }

  /// The সৃজনশীল প্রশ্ন block: its declaration, then one bordered card per
  /// question.
  static void _writeHtmlCqSection(
    StringBuffer buffer,
    List<HighSchoolQuestion> cqs,
    String heading,
    StemImageSize imageSize, {
    required bool declarationInFlow,
  }) {
    if (!declarationInFlow) {
      _writeHtmlDeclaration(buffer, heading, inFlow: false);
    }
    buffer.write('''
    <div class="cq-grid">
''');
    if (declarationInFlow) {
      _writeHtmlDeclaration(buffer, heading, inFlow: true);
    }
    _writeHtmlCqCards(buffer, cqs, imageSize);
    buffer.write('''
    </div>
''');
  }

  /// The CQ cards, with no container: the block or the merged flow supplies the
  /// columns.
  static void _writeHtmlCqCards(
    StringBuffer buffer,
    List<HighSchoolQuestion> cqs,
    StemImageSize imageSize,
  ) {
    for (int i = 0; i < cqs.length; i++) {
      final q = cqs[i];
      final index = i + 1;
      buffer.write('''
    <div class="cq-card">
      <div class="cq-stem">
        <b>$index.</b> ${latexToHtml(_escapeXml(q.paperStemText))}
        ${q.boardYearTag.isNotEmpty ? '<small style="color:var(--muted);"> [${_escapeXml(q.boardYearTag)}]</small>' : ''}
      </div>
      ${_stemImageMarkup(q, size: imageSize, usePoints: false)}
''');
      for (final sq in q.cqSubQuestions) {
        buffer.write('''
      <div class="cq-sub-item">
        <div><b>(${_escapeXml(sq.label)})</b> ${latexToHtml(_escapeXml(sq.text))}</div>
        <div class="cq-mark">${sq.mark > 0 ? '[${sq.mark}]' : ''}</div>
      </div>
''');
      }
      buffer.write('''
    </div>
''');
    }
  }

  /// The বহুনির্বাচনী প্রশ্ন block.
  static void _writeHtmlMcqSection(
    StringBuffer buffer,
    List<HighSchoolQuestion> mcqs,
    String heading, {
    required bool declarationInFlow,
  }) {
    if (!declarationInFlow) {
      _writeHtmlDeclaration(buffer, heading, inFlow: false);
    }
    buffer.write('''
    <div class="mcq-grid">
''');
    if (declarationInFlow) {
      _writeHtmlDeclaration(buffer, heading, inFlow: true);
    }
    const bengaliLetters = ['ক', 'খ', 'গ', 'ঘ'];
    for (int i = 0; i < mcqs.length; i++) {
      final q = mcqs[i];
      final mcq = q.mcqData;
      final index = i + 1;
      if (mcq == null) continue;

      buffer.write('''
      <div class="mcq-card">
        <div><b>$index.</b> ${_escapeXml(q.paperQuestionText)}</div>
        <div class="mcq-options">
''');
      final options = mcq.options;
      for (int opt = 0; opt < options.length; opt++) {
        final l =
            opt < bengaliLetters.length ? bengaliLetters[opt] : '${opt + 1}';
        buffer.write('''
          <div>($l) ${_escapeXml(options[opt])}</div>
''');
      }
      buffer.write('''
        </div>
      </div>
''');
    }
    buffer.write('''
    </div>
''');
  }

  /// The সংক্ষিপ্ত প্রশ্ন block.
  static void _writeHtmlRqSection(
    StringBuffer buffer,
    List<HighSchoolQuestion> shorts,
    String heading, {
    required bool declarationInFlow,
  }) {
    if (!declarationInFlow) {
      _writeHtmlDeclaration(buffer, heading, inFlow: false);
    }
    buffer.write('''
    <div class="rq-list">
      <div class="rq-grid">
''');
    if (declarationInFlow) {
      _writeHtmlDeclaration(buffer, heading, inFlow: true);
    }
    _writeHtmlRqItems(buffer, shorts);
    buffer.write('''
      </div>
    </div>
''');
  }

  /// The short-question lines, with no container: the block or the merged flow
  /// supplies the columns.
  static void _writeHtmlRqItems(
    StringBuffer buffer,
    List<HighSchoolQuestion> shorts,
  ) {
    for (int i = 0; i < shorts.length; i++) {
      final data = shorts[i].shortData;
      if (data == null || data.text.trim().isEmpty) continue;
      buffer.write('''
        <div class="rq-item">
          <div><b>${i + 1}.</b> ${_escapeXml(data.text)}</div>
          <div class="rq-mark">[${data.mark}]</div>
        </div>
''');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 4. Markdown Format (.md)
  // ─────────────────────────────────────────────────────────────────────────

  static String generateMarkdown({
    required String schoolName,
    required String examName,
    required String subject,
    required String className,
    required String time,
    required String totalMarks,
    required List<HighSchoolQuestion> questions,
    StemImageSize imageSize = StemImageSize.medium,
  }) {
    final buffer = StringBuffer();
    if (schoolName.trim().isNotEmpty) {
      buffer.writeln('# ${schoolName.trim()}\n');
    }
    if (examName.trim().isNotEmpty) {
      buffer.writeln('## ${examName.trim()}\n');
    }

    buffer.writeln(
        '**বিষয়:** $subject | **শ্রেণি:** $className | **সময়:** $time | **পূর্ণমান:** $totalMarks\n');
    buffer.writeln('---\n');

    final cqs = questions.where((q) => q.isCq).toList();
    final mcqs = questions.where((q) => q.isMcq).toList();
    final shorts = questions.where((q) => q.isShort).toList();

    if (cqs.isNotEmpty) {
      buffer.writeln('### ক-বিভাগ: সৃজনশীল প্রশ্ন (CQ)\n');
      for (int i = 0; i < cqs.length; i++) {
        final q = cqs[i];
        final index = i + 1;
        buffer
            .writeln('**$index.** ${latexToPlainText(q.paperStemText.trim())}');
        if (q.boardYearTag.isNotEmpty) {
          buffer.writeln('> *উৎস: ${q.boardYearTag}*');
        }
        if (_hasStemImage(q, imageSize)) {
          buffer.writeln('![উদ্দীপক চিত্র](${_stemImageUrlOf(q)})');
        }
        buffer.writeln();
        for (final sq in q.cqSubQuestions) {
          buffer.writeln('- **(${sq.label})** ${sq.text} `[${sq.mark}]`');
        }
        buffer.writeln();
      }
    }

    if (mcqs.isNotEmpty) {
      buffer.writeln('---\n');
      buffer.writeln('### খ-বিভাগ: বহুনির্বাচনী প্রশ্ন (MCQ)\n');
      const bengaliLetters = ['ক', 'খ', 'গ', 'ঘ'];
      for (int i = 0; i < mcqs.length; i++) {
        final q = mcqs[i];
        final mcq = q.mcqData;
        final index = i + 1;
        if (mcq == null) continue;

        buffer.writeln('**$index.** ${q.paperQuestionText}');
        for (int opt = 0; opt < mcq.options.length; opt++) {
          final l =
              opt < bengaliLetters.length ? bengaliLetters[opt] : '${opt + 1}';
          buffer.writeln('- ($l) ${mcq.options[opt]}');
        }
        buffer.writeln();
      }
    }

    if (shorts.isNotEmpty) {
      buffer.writeln('---\n');
      buffer.writeln('### গ-বিভাগ: সংক্ষিপ্ত প্রশ্ন (SQ)\n');
      for (int i = 0; i < shorts.length; i++) {
        final data = shorts[i].shortData;
        if (data == null || data.text.trim().isEmpty) continue;
        buffer.writeln('**${i + 1}.** ${data.text.trim()} `[${data.mark}]`');
      }
      buffer.writeln();
    }
    return buffer.toString();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 5. JSON Format (.json)
  // ─────────────────────────────────────────────────────────────────────────

  static String generateJson({
    required String schoolName,
    required String examName,
    required String subject,
    required String className,
    required String time,
    required String totalMarks,
    required List<HighSchoolQuestion> questions,
  }) {
    final data = {
      'exam_info': {
        'school_name': schoolName,
        'exam_name': examName,
        'subject': subject,
        'class': className,
        'time': time,
        'total_marks': totalMarks,
        'generated_at': DateTime.now().toIso8601String(),
        'platform': 'Pi-QBank',
      },
      'questions': questions.map((q) => q.toJson()).toList(),
    };
    return const JsonEncoder.withIndent('  ').convert(data);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // File I/O & Sharing Helpers
  // ─────────────────────────────────────────────────────────────────────────

  static Future<File> saveFile({
    required String content,
    required String fileName,
    List<int>? bytes,
  }) async {
    final tempDir = await getTemporaryDirectory();
    final sanitizedName = fileName.replaceAll(RegExp(r'[^\w\.-]'), '_');
    final file = File('${tempDir.path}/$sanitizedName');
    if (bytes != null) {
      await file.writeAsBytes(bytes);
    } else {
      await file.writeAsString(content, encoding: utf8);
    }
    return file;
  }

  static Future<void> openExportedFile(BuildContext context, File file) async {
    try {
      final result = await OpenFile.open(file.path);
      if (result.type != ResultType.done && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('ফাইলটি সরাসরি ওপেন করা যায়নি: ${result.message}'),
            backgroundColor: Colors.amber.shade800,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('ত্রুটি: $e'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  static Future<void> shareExportedFile(File file, {String? text}) async {
    await Share.shareXFiles(
      [XFile(file.path)],
      text: text ?? 'Pi-QBank Question Paper',
    );
  }

  static void copyToClipboard(
    BuildContext context,
    String text, {
    String message = 'প্রশ্নপত্রের টেক্সট সফলভাবে কপি করা হয়েছে!',
  }) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded,
                color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: const Color(0xFF10B981),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  static String _escapeXml(String input) {
    return input
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }
}
