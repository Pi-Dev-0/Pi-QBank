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
  static const double bodyFontSize = 11;
  static const double smallFontSize = 9;

  // CQ card chrome.
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

  /// The dashed rule drawn between consecutive MCQs.
  static const double mcqSeparatorHeight = 6 + 1 + 6;

  /// Vertical gap the page leaves after each CQ card.
  static const double cqCardGap = 12;

  /// Vertical gap the page leaves after each short question (RQ).
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
  }) {
    final data = question.shortData;
    if (data == null || data.text.trim().isEmpty) return 0;

    final mark = '[${data.mark}]';
    final markWidth = metrics.textWidth(mark, fontSize: bodyFontSize);
    final textHeight = metrics.blockHeight(
      '$index. ${data.text}',
      width: columnWidth - 12 - markWidth,
      fontSize: bodyFontSize,
    );
    final markHeight = metrics.lineHeight(mark, fontSize: bodyFontSize);

    return rqGap + (textHeight > markHeight ? textHeight : markHeight);
  }

  /// A4 height in points (`PdfPageFormat.a4.height`).
  static const double a4Height = 841.89;

  /// Vertical page margin used by `pw.MultiPage`.
  ///
  /// Tightened from the usual 36pt: on A4 every point here is a point of usable
  /// page across the whole paper, and 28pt (~10mm) is still clear of the dead
  /// band most printers cannot reach.
  static const double pageMarginV = 28;

  /// Printable width at the page margins.
  static double get contentWidth => a4Width - pageMarginH * 2;

  /// Printable height at the page margins.
  static double get contentHeight => a4Height - pageMarginV * 2;

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


  /// The masthead's own name for [sectionGap], for readability at the call site.
  static const double headerAfterGap = sectionGap;

  /// Space above and below the rule that separates one printed set from the
  /// next. Generous on purpose: both sets share one sheet, so without a clear
  /// break the second masthead reads as a stray header rather than a new paper.
  static const double setDividerGapAbove = 16;
  static const double setDividerGapBelow = 12;

  /// Breathing room under a section heading in the merged two-set, two-column
  /// flow.
  ///
  /// Only that layout uses it. Elsewhere the heading is a full-width box with a
  /// `SizedBox` of its own beneath it; in the merged flow the heading rides in
  /// the column as a fragment, so without this it would sit flush against the
  /// first card.
  static const double mergedHeadingGap = 8;

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
  }) {
    var height = 0.0;
    if (schoolName.trim().isNotEmpty) {
      height +=
          metrics.blockHeight(schoolName, width: contentWidth, fontSize: 15);
    }
    height += headerTitleGap;
    height += metrics.blockHeight(examName, width: contentWidth, fontSize: 12);
    height += headerExamGap + headerDivider;
    height += headerMetaGap;
    // A Row of four meta fields, spaceBetween: it never wraps, so the row is
    // one line tall no matter how the fields are distributed.
    height += metrics.lineHeight('বিষয়: $subject', fontSize: bodyFontSize);
    height += headerMetaGap + headerDivider;
    return height;
  }

  /// Height of a grey section banner, mirroring the banner widget.
  static double sectionBannerHeight(PdfTextMetrics metrics) =>
      8 /* padding */ +
      2 /* border */ +
      metrics.lineHeight('ক', fontSize: bodyFontSize);

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
  }) =>
      cqFragments(
        index: index,
        question: question,
        columnWidth: columnWidth,
        metrics: metrics,
        hasImage: hasImage,
        imageSize: imageSize,
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
  }) {
    final inner = columnWidth - cqBorder - cqPadding;

    var head = cqBorder + cqPadding;
    head += metrics.blockHeight('$index. ${question.stemText}',
        width: inner, fontSize: bodyFontSize);
    if (imageSize.isVisible && hasImage) {
      head += cqImageGap + imageSize.maxHeightPt;
    }

    final parts = <double>[head];
    for (final sq in question.cqSubQuestions) {
      final mark = '[${sq.mark}]';
      final markWidth = metrics.textWidth(mark, fontSize: smallFontSize);
      final textHeight = metrics.blockHeight(
        '(${sq.label}) ${sq.text}',
        width: inner - cqSubIndent - cqMarkGap - markWidth,
        fontSize: bodyFontSize,
      );
      final markHeight = metrics.lineHeight(mark, fontSize: smallFontSize);
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

  /// Rendered height of an MCQ question, including the rule that follows it.
  static double mcqHeight({
    required int index,
    required HighSchoolQuestion question,
    required double columnWidth,
    required PdfTextMetrics metrics,
    required bool stackOptions,
  }) =>
      mcqFragments(
        index: index,
        question: question,
        columnWidth: columnWidth,
        metrics: metrics,
        stackOptions: stackOptions,
      ).fold<double>(0, (sum, h) => sum + h);

  /// The MCQ question broken into the chunks it can be split at: the stem, then
  /// one chunk per row of options.
  ///
  /// Chunking by *row* rather than by option matters — the builder lays options
  /// out two-per-row in single-column mode and one-per-row in double, so a
  /// chunk is only ever cut the way the card is actually drawn.
  static List<double> mcqFragments({
    required int index,
    required HighSchoolQuestion question,
    required double columnWidth,
    required PdfTextMetrics metrics,
    required bool stackOptions,
  }) {
    final mcq = question.mcqData;
    if (mcq == null) return const [];

    final parts = <double>[
      metrics.blockHeight('$index. ${mcq.text}',
          width: columnWidth, fontSize: bodyFontSize)
    ];

    // A half-width cell cannot fit two options side by side, so double-column
    // mode stacks them one per row.
    final perRow = stackOptions ? 1 : 2;
    final available = columnWidth - mcqOptionIndent;

    for (int i = 0; i < mcq.options.length; i += perRow) {
      var rowHeight = 0.0;
      for (int c = 0; c < perRow; c++) {
        final idx = i + c;
        if (idx >= mcq.options.length) break;

        final gutters = perRow > 1 ? (perRow - 1) * mcqOptionGap : 0.0;
        final h = metrics.blockHeight(
          '${_mcqLetter(idx)} ${mcq.options[idx]}',
          width: (available - gutters) / perRow,
          fontSize: bodyFontSize,
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
  }) {
    final height = rqHeight(
        index: index,
        question: question,
        columnWidth: columnWidth,
        metrics: metrics);
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
  PdfPageFlow({required this.contentHeight, this.margin = 8});

  /// Printable height of a page.
  final double contentHeight;

  /// Slack subtracted from every budget.
  ///
  /// Heights are measured rather than exact, so this absorbs rounding and
  /// estimate error. Without it a block a few points too tall would silently
  /// jump pages and reintroduce the blank-page bug. Kept small — the measured
  /// estimates land within a point or two — so it costs almost no page.
  final double margin;

  double _used = 0;

  /// Height of the current page already accounted for.
  double get used => _used;

  /// Reserve [height] of vertical space, starting a new page first if it will
  /// not fit on the current one.
  void consume(double height) {
    if (height <= 0) return;
    if (_used + height > contentHeight - margin) _used = 0;
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
  }) {
    final rows = <List<List<PdfFlowFragment>>>[];
    if (fragments.isEmpty) return rows;

    final heights = [for (final f in fragments) f.height];

    // Contiguous runs of fragments, one per question.
    final runStart = <int>[];
    final runEnd = <int>[];
    final questionHeight = <double>[];
    for (var i = 0; i < fragments.length; i++) {
      if (i == 0 || fragments[i].question != fragments[i - 1].question) {
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
      final budget = contentHeight - _used - margin;
      var count = _largestPrefix(questionHeight, question, columns, budget);

      if (count == 0) {
        // Nothing fits on the rest of this page — most likely because it is
        // nearly full. Move to a fresh page and try again.
        _used = 0;
        count = _largestPrefix(
            questionHeight, question, columns, contentHeight - margin);
        if (count == 0) count = 1; // taller than a page; emit rather than drop
      }

      var end = runEnd[question + count - 1];
      var slice = heights.sublist(start, end);
      var groups = balanceColumns(heights: slice, columns: columns);

      // Fill the foot of the block.
      //
      // Whole-question packing stops one question short whenever the next one
      // would overflow, leaving up to its full height empty at the foot of the
      // page. Each following question is therefore offered to the block as
      // fragments: `balanceColumns` redistributes *everything* it already
      // holds, so the spare room in both columns is shared out and the page
      // fills properly. A question may end up with its stem at the foot of one
      // column and its options at the head of the next — still on this page,
      // still in order.
      //
      // Only *complete* questions are admitted. Admitting a part would push the
      // remainder onto the next block, and measurement showed that reliably
      // costs an extra page: the stranded fragment forces a break while the
      // space it vacated sits unused. Splitting within a page is free;
      // splitting across one is not.
      while (question + count < runStart.length) {
        final extendedEnd = runEnd[question + count];
        final extended = heights.sublist(start, extendedEnd);
        final groups2 = balanceColumns(heights: extended, columns: columns);
        if (_tallestOf(groups2, extended) > budget) break;
        count++;
        end = extendedEnd;
        slice = extended;
        groups = groups2;
      }

      rows.add([
        for (final column in groups)
          [for (final i in column) fragments[start + i]]
      ]);

      _used += _tallestOf(groups, slice) + trailingGap;
      if (_used >= contentHeight - margin) _used = 0;

      start = end;
      if (start >= fragments.length) break;
      question = fragments[start].question;
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
