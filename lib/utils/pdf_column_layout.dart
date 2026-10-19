/// Decides how a flat list of questions is spread across newspaper-style
/// columns.
///
/// ## The problem this solves
///
/// The obvious layout — put questions into rows of two and render each row as a
/// `pw.Row` of two cells — makes **every cell as tall as the tallest cell in its
/// row**. A three-line MCQ sitting beside a CQ carrying a diagram therefore
/// inherits nine lines of blank space, and the gap repeats down the whole
/// section. Multiply that by every row and a two-column paper wastes a
/// substantial part of the page.
///
/// Real newspaper columns don't do that: each column is an independent vertical
/// stack, so the next question simply continues wherever the previous one ended.
/// Reproducing that needs one decision up front — *how many questions go in the
/// first column* — which is what [balanceColumns] makes.
///
/// ## Approach
///
/// [balanceColumns] splits one block of questions into balanced columns, keeping
/// reading order (left column top-to-bottom, then right) and minimising the
/// tallest column. [PdfPageFlow] then decides how many blocks to emit and how
/// tall each may be, so that a long section flows across pages without ever
/// leaving a page half empty.
///
/// Because the result depends on accurate heights, the caller should measure
/// them with `PdfTextMetrics` rather than estimating.
library;

import '../models/highschool_question.dart';
import '../services/highschool_export_service.dart';
import 'pdf_text_metrics.dart';

/// Geometry of the PDF question paper's columns and question cards.
///
/// These constants describe the widgets built by the generator page. They live
/// here, next to the height estimators, because a split that is measured
/// against the wrong padding is silently wrong — so the numbers that describe a
/// card and the numbers that estimate its height have to be the same numbers.
class PdfLayout {
  /// Space between columns.
  static const double gutter = 16;

  /// Horizontal page margin used by `pw.MultiPage`.
  static const double pageMarginH = 40;

  /// A4 width in points (`PdfPageFormat.a4.width`).
  static const double a4Width = 595.276;

  /// Font sizes that affect wrapping, matching the page's text styles.
  ///
  /// These are the paper's *base* sizes. The caller's `fontStep` moves every
  /// size in the paper — these two, the masthead's two, and the styles the page
  /// builds — together, which is what the font-size control on the generator
  /// page does. The step has to reach the height estimators below as well as the
  /// `pw.TextStyle`s they mirror: estimating 11pt text and drawing 13pt text is
  /// what makes a column overflow its allowance.
  static const double bodyFontSize = 11;
  static const double smallFontSize = 9;

  // CQ card chrome.
  /// Width of the card's border, both sides — **not** part of the inset.
  ///
  /// The pdf package paints a `Container`'s border *inside* the box without
  /// deflating the child (its `DecoratedBox` ignores `dimensions`), so only
  /// [cqPadding] insets the text. Charging the border as well measured every
  /// line 2pt narrower than the drawn one, which is enough to wrap a borderline
  /// line a word early, add a line to the estimate, and leave the foot of the
  /// page empty.
  static const double cqBorder = 2; // 1pt border, both sides
  static const double cqPadding = 16; // EdgeInsets.all(8)
  static const double cqStemGap = 4;
  static const double cqImageGap = 6;
  static const double cqSubIndent = 6;
  static const double cqSubTop = 3;
  static const double cqMarkGap = 10;

  // MCQ option chrome.
  static const double mcqOptionIndent = 10;
  static const double mcqOptionTop = 2;
  static const double mcqOptionGap = 12;

  /// Gap between an MCQ's উদ্দীপক — its intro and figure — and the numbered
  /// question line under it. Measured here because the card is: the estimator
  /// and the item have to agree or the column the packer filled is not the
  /// column that gets drawn.
  static const double mcqStemGap = 4;

  /// The dashed rule drawn between consecutive MCQs.
  static const double mcqSeparatorHeight = 6 + 1 + 6;

  /// Vertical gap the page leaves after each CQ card.
  static const double cqCardGap = 12;

  /// Vertical gap the page leaves after each short question (SQ).
  static const double rqGap = 6;

  /// Rendered height of a short question row.
  ///
  /// Mirrors the RQ widget: text in an [Expanded], then the mark, with the row
  /// padded by [rqGap] underneath. The row is as tall as the taller of the two,
  /// exactly as the builder lays it out.
  static double rqHeight({
    required int index,
    required HighSchoolQuestion question,
    required double columnWidth,
    required PdfTextMetrics metrics,
    double fontStep = 0,
  }) {
    final data = question.shortData;
    if (data == null || data.text.trim().isEmpty) return 0;

    final size = bodyFontSize + fontStep;
    final mark = '[${data.mark}]';
    final markWidth = metrics.textWidth(mark, fontSize: size);
    final textHeight = metrics.blockHeight(
      '$index. ${data.text}',
      width: columnWidth - 12 - markWidth,
      fontSize: size,
    );
    final markHeight = metrics.lineHeight(mark, fontSize: size);

    return rqGap + (textHeight > markHeight ? textHeight : markHeight);
  }

  /// A4 height in points (`PdfPageFormat.a4.height`).
  static const double a4Height = 841.89;

  /// Vertical page margin used by `pw.MultiPage`.
  ///
  /// Tightened from the usual 36pt: on A4 every point here is a point of usable
  /// page across the whole paper, and 28pt (~10mm) is still clear of the dead
  /// band most printers cannot reach.
  /// Vertical page margin. Asymmetric: the head needs somewhere to start, the
  /// foot does not — the sheet is trimmed at print, so anything below the last
  /// question is blank paper.
  static const double pageMarginTop = 18;
  static const double pageMarginBottom = 6;
  static const double pageMarginV = 28; // kept for call sites that want both

  /// Printable width at the page margins.
  static double get contentWidth => a4Width - pageMarginH * 2;

  /// Printable height at the page margins.
  static double get contentHeight =>
      a4Height - pageMarginTop - pageMarginBottom;

  /// Vertical spacing of the masthead.
  ///
  /// Shared by the header widget and [headerHeight] on purpose. The two must
  /// agree exactly: the flow reserves [headerHeight] to decide where the first
  /// row of questions starts, so if the widget drew a different amount the
  /// block would either overflow or leave a hole at the foot of page 1.
  static const double headerTitleGap = 2; // below the school name
  static const double headerExamGap = 5; // exam name -> first rule
  static const double headerMetaGap = 2; // rules <-> the meta row
  static const double headerDivider = 1.2; // rule thickness

  /// Space above a section banner.
  ///
  /// The same value before every banner — the CQ one straight after the
  /// masthead, and the MCQ and RQ ones after the previous section — so the
  /// three sections are visually consistent instead of one being tighter than
  /// the others.
  static const double sectionGap = 5;

  /// Space between a section's heading and its first question.
  ///
  /// Was a bare 10pt sitting next to the heading in three places. Named because
  /// the heading is a full-width bar: without any break under it the first
  /// question reads as part of the bar rather than as the first item of the
  /// section.
  ///
  /// Raised to 16 for that reason, then dialled back twice (13, then 10) as too
  /// open once it was visible in the two-set layout.
  ///
  /// The renderer draws a SizedBox of exactly this and the flow charges exactly
  /// this, so the two cannot drift apart.
  static const double sectionBannerGap = 10;

  /// The masthead's own name for [sectionGap], for readability at the call site.
  static const double headerAfterGap = sectionGap;

  /// Space above and below the rule that separates one printed set from the
  /// next. Generous on purpose: both sets share one sheet, so without a clear
  /// break the second masthead reads as a stray header rather than a new paper.
  /// Space around the dashed rule separating two sets that share a sheet.
  ///
  /// Fixed, not computed from the leftover height. A computed gap has to be
  /// sized from measured heights before the page is laid out, and when that
  /// estimate runs out, the gap itself is what pushes content onto the next
  /// page — which is how a two-set paper ended up with a blank half-sheet and a
  /// masthead stranded at the foot of it.
  static const double setDividerGapAbove = 16;
  static const double setDividerGapBelow = 12;

  /// Breathing room under a section heading in the merged two-set, two-column
  /// flow.
  ///
  /// Only that layout uses it. Elsewhere the heading is a full-width box with a
  /// `SizedBox` of its own beneath it; in the merged flow the heading rides in
  /// the column as a fragment, so without this it would sit flush against the
  /// first card.
  ///
  /// The same value as [sectionBannerGap] so a heading looks identical whether
  /// CQ and the short questions were merged or not.
  static const double mergedHeadingGap = sectionBannerGap;

  /// Height of the school/exam header, mirroring the header widget.
  ///
  /// This matters more than it looks: the header is the first thing on page 1,
  /// so the space left for the first row of CQ questions is
  /// `contentHeight - headerHeight`. Ignoring it is what pushes the whole CQ
  /// section onto page 2 and leaves page 1 nearly blank.
  static double headerHeight({
    required PdfTextMetrics metrics,
    required String schoolName,
    required String examName,
    required String subject,
    required String className,
    required String time,
    required String totalMarks,
    double fontStep = 0,
  }) {
    final school = 15 + fontStep;
    final exam = 12 + fontStep;
    final body = bodyFontSize + fontStep;
    var height = 0.0;
    if (schoolName.trim().isNotEmpty) {
      height += metrics.blockHeight(schoolName,
          width: contentWidth, fontSize: school);
    }
    height += headerTitleGap;
    height +=
        metrics.blockHeight(examName, width: contentWidth, fontSize: exam);
    height += headerExamGap + headerDivider;
    height += headerMetaGap;
    // A Row of four meta fields, spaceBetween: it never wraps, so the row is
    // one line tall no matter how the fields are distributed.
    height += metrics.lineHeight('বিষয়: $subject', fontSize: body);
    height += headerMetaGap + headerDivider;
    return height;
  }

  /// Height of a grey section banner, mirroring the banner widget.
  static double sectionBannerHeight(PdfTextMetrics metrics,
          {double fontStep = 0}) =>
      8 /* padding */ +
      2 /* border */ +
      metrics.lineHeight('ক', fontSize: bodyFontSize + fontStep);

  /// Width of one column when the section is split into [columns].
  static double columnWidth(int columns) => columns <= 1
      ? contentWidth
      : (contentWidth - gutter * (columns - 1)) / columns;

  /// Rendered height of a CQ card.
  ///
  /// Mirrors the card widget: border, padding, stem, optional image, then one
  /// row per sub-question holding its text and its right-aligned mark.
  /// Rendered height of a CQ card.
  ///
  /// Mirrors the card widget: border, padding, stem, optional image, then one
  /// row per sub-question holding its text and its right-aligned mark.
  static double cqHeight({
    required int index,
    required HighSchoolQuestion question,
    required double columnWidth,
    required PdfTextMetrics metrics,
    required bool hasImage,
    required StemImageSize imageSize,
    double fontStep = 0,
  }) =>
      cqFragments(
        index: index,
        question: question,
        columnWidth: columnWidth,
        metrics: metrics,
        hasImage: hasImage,
        imageSize: imageSize,
        fontStep: fontStep,
      ).fold<double>(0, (sum, h) => sum + h);

  /// The CQ card broken into the chunks it can be split at.
  ///
  /// Chunk 0 is the stem together with its figure — a figure is never split, so
  /// it stays welded to the text above it. Each sub-question is its own chunk,
  /// because that is where a reader expects a break.
  ///
  /// The gap after the card is folded into the final chunk, so any chunk can be
  /// measured and placed on its own.
  static List<double> cqFragments({
    required int index,
    required HighSchoolQuestion question,
    required double columnWidth,
    required PdfTextMetrics metrics,
    required bool hasImage,
    required StemImageSize imageSize,
    double fontStep = 0,
  }) {
    final body = bodyFontSize + fontStep;
    final small = smallFontSize + fontStep;
    final inner = columnWidth - cqPadding;

    var head = cqPadding;
    // Measured from the same text the card draws, source tag and all trimmed —
    // see [HighSchoolQuestion.paperStemText].
    head += metrics.blockHeight('$index. ${question.paperStemText}',
        width: inner, fontSize: body);
    if (imageSize.isVisible && hasImage) {
      head += cqImageGap + imageSize.maxHeightPt;
    }

    final parts = <double>[head];
    for (final sq in question.cqSubQuestions) {
      final mark = '[${sq.mark}]';
      final markWidth = metrics.textWidth(mark, fontSize: small);
      final textHeight = metrics.blockHeight(
        '(${sq.label}) ${sq.text}',
        width: inner - cqSubIndent - cqMarkGap - markWidth,
        fontSize: body,
      );
      final markHeight = metrics.lineHeight(mark, fontSize: small);
      // The SizedBox(height: 4) before the sub-questions rides on the first
      // sub-question, matching where the builder draws it.
      parts.add(cqSubTop +
          (textHeight > markHeight ? textHeight : markHeight) +
          (parts.length == 1 ? cqStemGap : 0));
    }

    // A CQ with no sub-questions still needs its trailing gap.
    if (parts.length == 1) parts.add(cqStemGap);
    parts[parts.length - 1] += cqCardGap;
    return parts;
  }

  /// How many MCQ options share a row.
  ///
  /// Four to a row is how the papers teachers already hand out set them, and it
  /// is what the sheet does too when all four fit. Too wide together, the four
  /// fall to two rows of two; too wide even for that, every option takes a line
  /// of its own. Nothing in between — three and a half-width one below reads as
  /// a mistake, not as a layout.
  ///
  /// The width alone decides, so a narrow column is treated the same way as a
  /// full-width block: short answers still pair up inside it, and only options
  /// that will not sit side by side go one to a line.
  ///
  /// Measured rather than guessed, because the answer depends on the text. The
  /// estimator and the item both ask this question, so the room budgeted for a
  /// question and the room it takes are decided by the same arithmetic.
  static int mcqOptionsPerRow({
    required List<String> options,
    required double columnWidth,
    required PdfTextMetrics metrics,
    double fontStep = 0,
  }) {
    if (options.length < 2) return 1;

    final body = bodyFontSize + fontStep;
    final available = columnWidth - mcqOptionIndent;
    final widths = [
      for (var i = 0; i < options.length; i++)
        metrics.textWidth(mcqOptionText(i, options[i]), fontSize: body),
    ];

    // A smaller count always gives every option more room, so one per row always
    // fits and the search ends there.
    for (final perRow in const [4, 2, 1]) {
      if (perRow > options.length) continue;
      final cell = (available - (perRow - 1) * mcqOptionGap) / perRow;
      if (widths.every((wanted) => wanted <= cell)) return perRow;
    }
    return 1;
  }

  /// One MCQ option exactly as the estimator measures it and the item prints it:
  /// the letter in brackets, then the text.
  static String mcqOptionText(int index, String option) =>
      '(${_mcqLetter(index)}) $option';

  /// Rendered height of an MCQ question, including the rule that follows it.
  static double mcqHeight({
    required int index,
    required HighSchoolQuestion question,
    required double columnWidth,
    required PdfTextMetrics metrics,
    double fontStep = 0,
    bool withStem = false,
    bool hasImage = false,
    StemImageSize imageSize = StemImageSize.medium,
  }) =>
      mcqFragments(
        index: index,
        question: question,
        columnWidth: columnWidth,
        metrics: metrics,
        fontStep: fontStep,
        withStem: withStem,
        hasImage: hasImage,
        imageSize: imageSize,
      ).fold<double>(0, (sum, h) => sum + h);

  /// The MCQ question broken into the chunks it can be split at: the head (the
  /// The `… উদ্দীপক, when this question opens one, then the numbered question line),
  /// then one chunk per row of options.
  ///
  /// Chunking by *row* rather than by option matters — how many options share a
  /// row is measured from the room they have (see [mcqOptionsPerRow]), so a
  /// chunk is only ever cut the way the card is actually drawn.
  ///
  /// [withStem] is true for the question that *opens* a group of MCQs under one
  /// উদ্দীপক (see [HighSchoolQuestion.opensMcqStemGroup]). The intro is welded to
  /// the head rather than being a chunk of its own: an intro stranded at the
  /// foot of a column, with the questions it introduces overleaf, reads as
  /// belonging to whatever happens to be beneath it.
  ///
  /// [stemText] overrides the intro the estimate reads. The paper rewrites a
  /// shared intro's question numbers before drawing it
  /// ([HighSchoolExportService.stemWithNumbers]), and rewriting can make it a
  /// line longer or shorter — passing the very text the card draws is what
  /// keeps the booked room and the drawn card the same room.
  static List<double> mcqFragments({
    required int index,
    required HighSchoolQuestion question,
    required double columnWidth,
    required PdfTextMetrics metrics,
    double fontStep = 0,
    bool withStem = false,
    String? stemText,
    bool hasImage = false,
    StemImageSize imageSize = StemImageSize.medium,
  }) {
    final mcq = question.mcqData;
    if (mcq == null) return const [];

    final body = bodyFontSize + fontStep;

    var head = 0.0;
    final stem = withStem ? (stemText ?? question.mcqStemText) : '';
    if (stem.isNotEmpty) {
      head += metrics.blockHeight(stem, width: columnWidth, fontSize: body);
      if (imageSize.isVisible && hasImage) {
        head += cqImageGap + imageSize.maxHeightPt;
      }
      head += mcqStemGap;
    }

    // Measured from the same line the item draws — see
    // [HighSchoolQuestion.paperQuestionText].
    head += metrics.blockHeight('$index. ${question.paperQuestionText}',
        width: columnWidth, fontSize: body);

    final parts = <double>[head];

    // Four options to a row where they fit, two where they do not, one where
    // even two will not sit side by side.
    final perRow = mcqOptionsPerRow(
      options: mcq.options,
      columnWidth: columnWidth,
      metrics: metrics,
      fontStep: fontStep,
    );
    final available = columnWidth - mcqOptionIndent;

    for (int i = 0; i < mcq.options.length; i += perRow) {
      var rowHeight = 0.0;
      for (int c = 0; c < perRow; c++) {
        final idx = i + c;
        if (idx >= mcq.options.length) break;

        final gutters = perRow > 1 ? (perRow - 1) * mcqOptionGap : 0.0;
        final h = metrics.blockHeight(
          mcqOptionText(idx, mcq.options[idx]),
          width: (available - gutters) / perRow,
          fontSize: body,
        );
        if (h > rowHeight) rowHeight = h;
      }
      parts.add(mcqOptionTop + rowHeight);
    }

    // The dashed rule that closes the question.
    parts[parts.length - 1] += mcqSeparatorHeight;
    return parts;
  }

  /// Short questions are a single line, so there is nothing sensible to split.
  static List<double> rqFragments({
    required int index,
    required HighSchoolQuestion question,
    required double columnWidth,
    required PdfTextMetrics metrics,
    double fontStep = 0,
  }) {
    final height = rqHeight(
        index: index,
        question: question,
        columnWidth: columnWidth,
        metrics: metrics,
        fontStep: fontStep);
    return height <= 0 ? const [] : [height];
  }

  static String _mcqLetter(int idx) {
    const letters = ['ক', 'খ', 'গ', 'ঘ'];
    return idx < letters.length ? letters[idx] : (idx + 1).toString();
  }
}

/// One measured chunk of the flow, placeable on its own.
///
/// A question is broken into fragments at the points where a break looks
/// natural. The flow packs fragments, then the renderer regroups consecutive
/// fragments of the same question, so a question that fits is drawn exactly as
/// before and only a question that genuinely straddles a boundary is split.
class PdfFlowFragment {
  const PdfFlowFragment({
    required this.height,
    required this.question,
    required this.indexInQuestion,
    required this.isFirst,
    required this.isLast,
  });

  final double height;

  /// Which question this belongs to, used to regroup fragments.
  final int question;

  /// Position of this fragment within its question, used to pick the content.
  final int indexInQuestion;

  final bool isFirst;
  final bool isLast;
}

/// Split `heights` into `columns` groups of indices, balanced by height.
///
/// Returns `columns` groups (fewer if there are fewer items than columns), each
/// holding indices into `heights` in ascending order, and collectively covering
/// every index exactly once.
///
/// ## The split is optimal, not greedy
///
/// A tempting shortcut is to fill each column to `total / columns` and move on
/// once the next item would overshoot. That is wrong: after the flow reaches the
/// last column there is nowhere left to move to, so a long tail piles up there.
/// With heights `[66, 60, 66, 60, 60, 66]` and two columns it produces
/// `[126, 252]` — a column more than twice the ideal 189 — when `[192, 186]`
/// was available all along.
///
/// So this solves the partitioning exactly, minimising the tallest column with
/// the classic linear-partition dynamic program. Minimising the tallest column
/// is the right objective: the whole block is as tall as its highest column, so
/// that single number decides how much page the section costs. Cost is
/// `O(columns * n^2)`, which is negligible for a question paper.
List<List<int>> balanceColumns({
  required List<double> heights,
  required int columns,
}) {
  if (heights.isEmpty) return const [];

  final n = heights.length;
  final cols = columns < 1 ? 1 : (columns > n ? n : columns);
  if (cols == 1) return [List.generate(n, (i) => i)];

  // prefix[i] = total height of items [0, i).
  final prefix = List<double>.filled(n + 1, 0);
  for (var i = 0; i < n; i++) {
    prefix[i + 1] = prefix[i] + heights[i];
  }
  double sumOf(int from, int to) => prefix[to] - prefix[from];

  // best[c][i] = smallest achievable tallest column when items [0, i) are
  // split into exactly c non-empty columns, in order.
  // split[c][i] = the boundary index achieving it.
  final best = List.generate(
      cols + 1, (_) => List<double>.filled(n + 1, double.infinity));
  final split = List.generate(cols + 1, (_) => List<int>.filled(n + 1, 0));

  for (var i = 1; i <= n; i++) {
    best[1][i] = sumOf(0, i);
  }

  for (var c = 2; c <= cols; c++) {
    for (var i = c; i <= n; i++) {
      for (var k = c - 1; k < i; k++) {
        if (best[c - 1][k].isInfinite) continue;
        final tail = sumOf(k, i);
        final candidate = best[c - 1][k] > tail ? best[c - 1][k] : tail;
        if (candidate < best[c][i]) {
          best[c][i] = candidate;
          split[c][i] = k;
        }
      }
    }
  }

  // Walk the split points backwards to recover the groups.
  final groups = List.generate(cols, (_) => <int>[]);
  var end = n;
  for (var c = cols; c >= 1; c--) {
    final start = split[c][end];
    groups[c - 1] = [for (var i = start; i < end; i++) i];
    end = start;
  }
  return groups;
}

/// Lay a block's fragments into balanced columns without ever splitting a
/// question across a column boundary.
///
/// [balanceColumns] balances individual fragments, which is optimal for height
/// but will happily put the last sub-part of a question at the top of the next
/// column. The reader then sees `1. (ক) ... (খ) ...` at the foot of one column
/// and a bare `(গ)` heading the next, which reads as a question of its own.
///
/// A question is therefore one indivisible unit here: it runs to the foot of
/// whichever column holds it, and the next question starts below it. Balancing
/// then chooses *which questions share a column*, still minimising the tallest
/// column.
///
/// Splitting across a **page** is a different matter and is unaffected — that
/// is what lets a long question continue overleaf.
List<List<int>> balanceQuestions({
  required List<PdfFlowFragment> fragments,
  required int columns,
}) {
  if (fragments.isEmpty) return const [];

  // One unit per question: where it starts, where it ends, how tall it is.
  final starts = <int>[];
  final ends = <int>[];
  final totals = <double>[];
  for (var i = 0; i < fragments.length; i++) {
    if (i == 0 || fragments[i].question != fragments[i - 1].question) {
      starts.add(i);
      ends.add(i + 1);
      totals.add(fragments[i].height);
    } else {
      ends[ends.length - 1] = i + 1;
      totals[totals.length - 1] += fragments[i].height;
    }
  }

  // The same optimal splitter, run over questions rather than fragments.
  final questionGroups = balanceColumns(heights: totals, columns: columns);

  return [
    for (final group in questionGroups)
      [
        for (final q in group)
          for (var i = starts[q]; i < ends[q]; i++) i
      ],
  ];
}

/// Largest column height [balanceColumns] produces, for tests and diagnostics.
double tallestColumnHeight(List<List<int>> groups, List<double> heights) {
  var tallest = 0.0;
  for (final group in groups) {
    var sum = 0.0;
    for (final i in group) {
      sum += heights[i];
    }
    if (sum > tallest) tallest = sum;
  }
  return tallest;
}

/// Height the old row-based layout would have produced: every row is as tall as
/// its tallest cell. Kept so the improvement can be asserted rather than
/// assumed.
double rowBasedHeight(List<List<int>> groups, List<double> heights) {
  var total = 0.0;
  for (final group in groups) {
    var tallest = 0.0;
    for (final i in group) {
      if (heights[i] > tallest) tallest = heights[i];
    }
    total += tallest;
  }
  return total;
}

/// Tracks how much of the current page a flow layout has consumed, so each
/// column block can be sized to the space that is genuinely left.
///
/// ## Why this exists
///
/// `pw.MultiPage` breaks *between* widgets and cannot split one. A block of
/// columns is a single unbreakable `pw.Row`, so the rule is brutal: if the
/// block is taller than the space remaining, it jumps to the next page and
/// whatever was below it on the current page is left blank.
///
/// That is exactly the bug this fixes. The masthead plus the CQ banner can use
/// 200pt+ of page 1, leaving far less than a full page for the questions. A
/// block budgeted for a whole page therefore never fits and the entire CQ
/// section jumps to page 2, leaving page 1 almost empty.
///
/// This replays the page fill using the same measured heights, so the first
/// block is sized to what is left after the header and each later block to what
/// is left after its predecessors. Pages fill up, and only break when they
/// genuinely must.
class PdfPageFlow {
  PdfPageFlow({required this.contentHeight, this.margin = defaultMargin});

  /// Printable height of a page.
  final double contentHeight;

  /// Slack subtracted from every budget.
  ///
  /// This is not cosmetic. A block is laid out from *measured* heights and then
  /// drawn from real widgets, and the two never agree exactly. dart_pdf does not
  /// clip a block that overruns — it moves the **whole thing** to the next sheet.
  /// So a block measured to fit by a couple of points can cost an entire page
  /// of blank space when it lands on the wrong side of that difference.
  ///
  /// It therefore has to exceed the drift, not merely exist. The drift grows
  /// with the number of cards in a block, and a full page holds a dozen or so,
  /// so this is sized for that rather than for a single measurement.
  ///
  /// Cost when nothing drifts: this much blank at the foot of each page. That
  /// is a far better trade than losing a whole block to a wholesale move.
  final double margin;

  /// Slack subtracted from every budget.
  ///
  /// Sized so a block still has room to be drawn a little taller than it was
  /// measured — dart_pdf moves an overrunning block to the next sheet whole,
  /// which costs far more blank space than this ever does. Kept small because
  /// every point here is a point of blank at the foot of every page.
  static const double defaultMargin = 14;

  double _used = 0;
  int _pageBreaks = 0;

  /// Height of the current page already accounted for.
  double get used => _used;

  /// How many times content has overflowed onto a fresh page.
  ///
  /// `used` then describes only the *last* page, so anything reasoning about
  /// leftover space has to check this first rather than trusting `used`.
  int get pageBreaks => _pageBreaks;

  /// Start a fresh page.
  ///
  /// Every reset goes through here. `used` alone cannot be trusted to reveal a
  /// break — it reads the same either way — so [pageBreaks] is what a caller
  /// checks before reasoning about the page as a whole. A reset that skipped
  /// the counter would leave it reporting a single page for a document that had
  /// already spilled onto a second one.
  void _breakPage() {
    _used = 0;
    _pageBreaks++;
  }

  /// Start a new page deliberately.
  ///
  /// Must be paired with a `pw.NewPage` in the widget list, so the flow's
  /// arithmetic and the pdf package's own pagination agree. Telling only one of
  /// them leaves the flow packing against a page that no longer exists.
  void breakPage() => _breakPage();

  /// Reserve [height] of vertical space, starting a new page first if it will
  /// not fit on the current one.
  void consume(double height) {
    if (height <= 0) return;
    if (_used + height > contentHeight - margin) _breakPage();
    _used += height;
  }

  /// Lay plain heights out into rows of balanced columns, sized to the
  /// remaining space.
  List<List<List<PdfFlowFragment>>> layout({
    required List<double> heights,
    required int columns,
    double trailingGap = 0,
  }) =>
      layoutFragments(
        fragments: [
          for (var i = 0; i < heights.length; i++)
            PdfFlowFragment(
              height: heights[i],
              question: i,
              indexInQuestion: 0,
              isFirst: true,
              isLast: true,
            ),
        ],
        columns: columns,
        trailingGap: trailingGap,
      );

  /// Lay fragments out into rows of balanced columns, sized to the remaining
  /// space.
  ///
  /// Because fragments are packed rather than whole questions, a block can end
  /// part-way through a question. That is what fills the foot of a page: the
  /// stem of the next question goes here and its options continue overleaf.
  /// The renderer regroups consecutive fragments of the same question, so
  /// nothing looks split unless it really is.
  ///
  /// Returns a list of rows, each a list of columns of fragments.
  List<List<List<PdfFlowFragment>>> layoutFragments({
    required List<PdfFlowFragment> fragments,
    required int columns,
    double trailingGap = 0,
    void Function(String line)? trace,
  }) {
    final rows = <List<List<PdfFlowFragment>>>[];
    if (fragments.isEmpty) return rows;

    final heights = [for (final f in fragments) f.height];

    // Contiguous runs of fragments, one per question.
    final runStart = <int>[];
    final runEnd = <int>[];
    final questionHeight = <double>[];

    // Which run each question id belongs to, so a run index can always be
    // recovered from a fragment. A fragment's id is *not* its run index: the
    // merged CQ + SQ run numbers its two headings after every question (see
    // `_appendPdfCqAndShortSection`), so the ids read
    // `[heading, 0, 1, …, heading, cqCount, …]` and subtracting one from the
    // other is what sent the packer's cursor behind the block it had just
    // measured — a `sublist(46, 8)`, which is a range error, not a bad page.
    final runOfQuestion = <int, int>{};
    for (var i = 0; i < fragments.length; i++) {
      if (i == 0 || fragments[i].question != fragments[i - 1].question) {
        runOfQuestion[fragments[i].question] = runStart.length;
        runStart.add(i);
        runEnd.add(i + 1);
        questionHeight.add(heights[i]);
      } else {
        runEnd[runEnd.length - 1] = i + 1;
        questionHeight[questionHeight.length - 1] += heights[i];
      }
    }

    var question = 0;
    var start = 0;

    while (question < runStart.length) {
      var budget = contentHeight - _used - margin;

      // Prefer whole questions, so a page normally breaks at a natural edge.
      var count = _largestPrefix(questionHeight, question, columns, budget);

      if (count == 0) {
        // Not even one question fits in what is left. Start a fresh page and
        // ask again there, where the budget is a whole sheet.
        _breakPage();
        budget = contentHeight - margin;
        count = _largestPrefix(questionHeight, question, columns, budget);
      }

      var end = count > 0 ? runEnd[question + count - 1] : start;

      // How tall the block [start, at) is estimated to be drawn: the taller of
      // the columns `balanceColumns` puts the whole questions in, plus the gap
      // that follows the block.
      double estimate(int at) {
        final h = heights.sublist(start, at);
        final block = fragments.sublist(start, at);
        return _tallestOf(
                balanceQuestions(fragments: block, columns: columns), h) +
            trailingGap;
      }

      // The whole questions `_largestPrefix` chose are measured one way and
      // drawn another, and the two disagree by a point or two. Drawing the
      // block at exactly its estimate is how a page overflows by a hair and
      // the export dies with "Widget won't fit into the page" — so the choice
      // is checked against the same measure the block will be drawn with, and
      // walked back until it genuinely fits.
      while (end > start && estimate(end) > budget) {
        end--;
      }

      if (end == start) {
        // One piece is taller than a whole sheet. Emit it rather than stall:
        // the pdf package is the only thing here that can carry the overflow
        // onto the next page, and dropping the question is not an option.
        end = start + 1;
      }

      final slice = heights.sublist(start, end);
      final groups = balanceQuestions(
          fragments: fragments.sublist(start, end), columns: columns);
      final columnHeights = <double>[
        for (final column in groups) _sumOf(column, slice),
      ];

      // Fill the foot of the block.
      //
      // Whole-question packing stops one question short whenever the next one
      // would not fit, and an order-preserving split cannot even out an uneven
      // run of questions — both leave white space at the foot of the page. Only
      // the last column can be continued (anything appended to an earlier
      // column would read out of order), so the pieces of the question that
      // follows are appended there for as long as they fit, and that question
      // continues overleaf if they run out.
      //
      // Re-balancing the block for each extra piece would be the wrong move:
      // the pieces are not whole questions, so the optimum shifts under the
      // extra weight, the tallest column can jump by more than the piece is
      // tall, and the search gives up with most of a card still to spare.
      while (end < fragments.length) {
        final last = columnHeights.length - 1;
        final h = heights[end];
        if (columnHeights[last] + h + trailingGap > budget) break;
        groups[last].add(end - start);
        columnHeights[last] += h;
        end++;
      }

      // The block is sized from measured heights and then drawn from the same
      // widgets. When the two disagree, dart_pdf moves the whole row to the
      // next sheet rather than clipping it, which shows up as a band of blank
      // space at the foot of a page. `_used` is the predictor, `drawn` is what
      // will be drawn: trace both and compare.
      trace?.call('page=${_pageBreaks + 1} '
          'used=${_used.toStringAsFixed(1)} '
          'budget=${budget.toStringAsFixed(1)} '
          'drawn=${(_tallestOf(groups, heights.sublist(start, end)) + trailingGap).toStringAsFixed(1)} '
          'fragments=$start..$end/${fragments.length} '
          'cols=${columnHeights.map((h) => h.toStringAsFixed(0)).join("/")}');

      rows.add([
        for (final column in groups)
          [for (final i in column) fragments[start + i]]
      ]);

      _used += _tallestOf(groups, heights.sublist(start, end)) + trailingGap;
      // The page is full, so whatever comes next starts another one.
      if (_used >= contentHeight - margin) _breakPage();

      start = end;
      if (start >= fragments.length) break;
      // Back to a run index. `end` can sit part-way through a question — that
      // is the point of filling the foot — so the run to resume at is the one
      // that question belongs to, not its id.
      question = runOfQuestion[fragments[start].question]!;
    }

    return rows;
  }

  static double _sumOf(List<int> column, List<double> heights) {
    var sum = 0.0;
    for (final i in column) {
      sum += heights[i];
    }
    return sum;
  }

  static double _tallestOf(List<List<int>> groups, List<double> heights) {
    var tallest = 0.0;
    for (final column in groups) {
      final sum = _sumOf(column, heights);
      if (sum > tallest) tallest = sum;
    }
    return tallest;
  }

  /// Largest number of whole questions from [start] whose optimal split still
  /// fits [budget].
  ///
  /// The optimal tallest column cannot shrink as items are added, so this is
  /// binary-searchable. Returns 0 when even the first question does not fit.
  int _largestPrefix(
      List<double> heights, int start, int columns, double budget) {
    final available = heights.length - start;
    var lo = 1;
    var hi = available;
    var best = 0;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      final slice = heights.sublist(start, start + mid);
      final groups = balanceColumns(heights: slice, columns: columns);
      if (_tallestOf(groups, slice) <= budget) {
        best = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return best;
  }
}
