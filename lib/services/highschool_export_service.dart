import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/highschool_question.dart';

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
/// Applied to the CQ and MCQ sections. Short questions (RQ) are one line each
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
        buffer.writeln('$index. ${q.stemText.trim()}');
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

        buffer.writeln('$index. ${mcq.text.trim()}');
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
      buffer.writeln('【 গ-বিভাগ: সংক্ষিপ্ত প্রশ্ন (RQ) 】');
      buffer.writeln();
      for (int i = 0; i < shorts.length; i++) {
        final data = shorts[i].shortData;
        if (data == null || data.text.trim().isEmpty) continue;
        final markStr = data.mark > 0 ? ' [${data.mark}]' : '';
        buffer.writeln('${i + 1}. ${data.text.trim()}$markStr');
      }
      buffer.writeln();
    }

    buffer.writeln(divider);
    buffer.writeln('জেনারেট করা হয়েছে Pi-QBank প্ল্যাটফর্ম থেকে');
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
    .footer-note {
      margin-top: 20pt;
      border-top: 1pt dashed #888888;
      font-size: 9pt;
      color: #666666;
      text-align: center;
      padding-top: 6pt;
    }
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
          <b>$index.</b> ${_escapeXml(q.stemText)}
          ${q.boardYearTag.isNotEmpty ? '<span style="font-size:9pt; color:#555555;"> [${_escapeXml(q.boardYearTag)}]</span>' : ''}
        </div>
        ${_stemImageMarkup(q, bytes: imageBytes, size: imageSize, usePoints: true)}
        <table class="cq-sub-table">''');
          for (final sq in q.cqSubQuestions) {
            cells.write('''
          <tr>
            <td class="cq-sub-label">(${_escapeXml(sq.label)})</td>
            <td class="cq-sub-text">${_escapeXml(sq.text)}</td>
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
      <div class="mcq-question"><b>$index.</b> ${_escapeXml(mcq.text)}</div>
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
  <div class="section-title">গ-বিভাগ: সংক্ষিপ্ত প্রশ্ন (RQ)</div>
  <div style="font-size:10pt; font-style:italic; margin-bottom:8pt; text-align:center;">[সংক্ষেপে উত্তর দাও]</div>
''');
      for (int i = 0; i < shorts.length; i++) {
        final data = shorts[i].shortData;
        if (data == null || data.text.trim().isEmpty) continue;
        buffer.write('''
  <div class="rq-item">
    <span>${i + 1}. ${_escapeXml(data.text)}</span>
    <span class="rq-mark">[${data.mark}]</span>
  </div>
''');
      }
    }

    buffer.write('''
  <div class="footer-note">জেনারেট করা হয়েছে Pi-QBank প্ল্যাটফর্ম থেকে</div>
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
    StemImageSize imageSize = StemImageSize.medium,
    QuestionLayout cqLayout = QuestionLayout.single,
    QuestionLayout mcqLayout = QuestionLayout.doubleColumn,
  }) {
    final cqs = questions.where((q) => q.isCq).toList();
    final mcqs = questions.where((q) => q.isMcq).toList();
    final shorts = questions.where((q) => q.isShort).toList();

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
      --text: #1e293b;
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
      max-width: 820px;
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

    .paper-sheet {
      max-width: 820px;
      margin: 0 auto;
      background: white;
      padding: 48px;
      border-radius: 8px;
      box-shadow: 0 4px 24px rgba(0,0,0,0.08);
    }
    .school-title { font-size: 24px; font-weight: 700; text-align: center; margin-bottom: 4px; }
    .exam-title { font-size: 18px; font-weight: 600; text-align: center; margin-bottom: 12px; }
    .meta-bar {
      display: flex;
      justify-content: space-between;
      flex-wrap: wrap;
      padding: 10px 0;
      border-top: 1.5px solid var(--text);
      border-bottom: 1.5px solid var(--text);
      margin-bottom: 24px;
      font-weight: 600;
      font-size: 15px;
    }
    .section-banner {
      text-align: center;
      font-size: 16px;
      font-weight: 700;
      background: #f1f5f9;
      padding: 6px 12px;
      border-radius: 6px;
      margin: 24px 0 16px 0;
      border: 1px solid #e2e8f0;
    }
    .cq-card {
      margin-bottom: 20px;
      padding: 16px;
      border: 1px solid var(--border);
      border-radius: 8px;
      page-break-inside: avoid;
    }
    .cq-stem { font-size: 15px; margin-bottom: 12px; }
    .cq-stem-img {
      display: block;
      max-width: 100%;
      max-height: 340px;
      margin: 0 auto 12px auto;
      object-fit: contain;
    }
    .cq-sub-item {
      display: flex;
      justify-content: space-between;
      margin-bottom: 6px;
      font-size: 14px;
      padding-left: 12px;
    }
    .cq-mark { font-weight: 700; min-width: 30px; text-align: right; }
    .cq-grid {
      display: grid;
      grid-template-columns: ${cqLayout.isDouble ? '1fr 1fr' : '1fr'};
      gap: ${cqLayout.isDouble ? '4px 22px' : '14px'};
    }
    .mcq-grid {
      display: grid;
      grid-template-columns: ${mcqLayout.isDouble ? '1fr 1fr' : '1fr'};
      gap: ${mcqLayout.isDouble ? '4px 22px' : '14px'};
    }
    .mcq-card {
      padding: 12px;
      border-bottom: 1px dashed var(--border);
      page-break-inside: avoid;
    }
    .mcq-options {
      display: grid;
      grid-template-columns: ${mcqLayout.isDouble ? '1fr' : '1fr 1fr'};
      gap: 6px 16px;
      margin-top: 6px;
      padding-left: 16px;
      font-size: 14px;
    }
    .rq-list { margin-top: 4px; }
    .rq-item {
      display: flex;
      justify-content: space-between;
      align-items: baseline;
      gap: 16px;
      font-size: 15px;
      padding: 10px 0;
      border-bottom: 1px dashed var(--border);
      page-break-inside: avoid;
    }
    .rq-mark { font-weight: 700; white-space: nowrap; }
    .footer-watermark {
      margin-top: 32px;
      text-align: center;
      font-size: 12px;
      color: #94a3b8;
      border-top: 1px solid #e2e8f0;
      padding-top: 12px;
    }

    @media print {
      body { background: white; padding: 0; }
      .no-print-toolbar { display: none !important; }
      .paper-sheet { box-shadow: none; border-radius: 0; padding: 20px 24px; max-width: 100%; }
      .cq-card { border: 1px solid #999; }
    }
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
    ${schoolName.trim().isNotEmpty ? '<div class="school-title">${_escapeXml(schoolName)}</div>' : ''}
    ${examName.trim().isNotEmpty ? '<div class="exam-title">${_escapeXml(examName)}</div>' : ''}
    
    <div class="meta-bar">
      <div>বিষয়: ${_escapeXml(subject)}</div>
      <div>শ্রেণি: ${_escapeXml(className)}</div>
      <div>সময়: ${_escapeXml(time)}</div>
      <div>পূর্ণমান: ${_escapeXml(totalMarks)}</div>
    </div>
''');

    if (cqs.isNotEmpty) {
      buffer.write('''
    <div class="section-banner">ক-বিভাগ: সৃজনশীল প্রশ্ন (CQ)</div>
    <div class="cq-grid">
''');
      for (int i = 0; i < cqs.length; i++) {
        final q = cqs[i];
        final index = i + 1;
        buffer.write('''
    <div class="cq-card">
      <div class="cq-stem">
        <b>$index.</b> ${_escapeXml(q.stemText)}
        ${q.boardYearTag.isNotEmpty ? '<small style="color:#64748b;"> [${_escapeXml(q.boardYearTag)}]</small>' : ''}
      </div>
      ${_stemImageMarkup(q, size: imageSize, usePoints: false)}
''');
        for (final sq in q.cqSubQuestions) {
          buffer.write('''
      <div class="cq-sub-item">
        <div><b>(${_escapeXml(sq.label)})</b> ${_escapeXml(sq.text)}</div>
        <div class="cq-mark">${sq.mark > 0 ? '[${sq.mark}]' : ''}</div>
      </div>
''');
        }
        buffer.write('''
    </div>
''');
      }
      buffer.write('''
    </div>
''');
    }

    if (mcqs.isNotEmpty) {
      buffer.write('''
    <div class="section-banner">খ-বিভাগ: বহুনির্বাচনী প্রশ্ন (MCQ)</div>
    <div class="mcq-grid">
''');
      const bengaliLetters = ['ক', 'খ', 'গ', 'ঘ'];
      for (int i = 0; i < mcqs.length; i++) {
        final q = mcqs[i];
        final mcq = q.mcqData;
        final index = i + 1;
        if (mcq == null) continue;

        buffer.write('''
      <div class="mcq-card">
        <div><b>$index.</b> ${_escapeXml(mcq.text)}</div>
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

    // Short question section (গ-বিভাগ)
    if (shorts.isNotEmpty) {
      buffer.write('''
    <div class="section-banner">গ-বিভাগ: সংক্ষিপ্ত প্রশ্ন (RQ)</div>
    <div class="rq-list">
''');
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
      buffer.write('''
    </div>
''');
    }

    buffer.write('''
    <div class="footer-watermark">জেনারেট করা হয়েছে Pi-QBank প্ল্যাটফর্ম থেকে</div>
  </div>
</body>
</html>
''');
    return buffer.toString();
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
        buffer.writeln('**$index.** ${q.stemText.trim()}');
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

        buffer.writeln('**$index.** ${mcq.text.trim()}');
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
      buffer.writeln('### গ-বিভাগ: সংক্ষিপ্ত প্রশ্ন (RQ)\n');
      for (int i = 0; i < shorts.length; i++) {
        final data = shorts[i].shortData;
        if (data == null || data.text.trim().isEmpty) continue;
        buffer.writeln('**${i + 1}.** ${data.text.trim()} `[${data.mark}]`');
      }
      buffer.writeln();
    }

    buffer.writeln('\n*জেনারেট করা হয়েছে Pi-QBank প্ল্যাটফর্ম থেকে*');
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
