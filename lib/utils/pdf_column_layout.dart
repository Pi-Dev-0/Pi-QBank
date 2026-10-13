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

  /// A4 height in points (`PdfPageFormat.a4.height`).
  static const double a4Height = 841.89;

  /// Vertical page margin used by `pw.MultiPage`.
  static const double pageMarginV = 36;

  /// Printable width at the page margins.
  static double get contentWidth => a4Width - pageMarginH * 2;

  /// Printable height at the page margins.
  static double get contentHeight => a4Height - pageMarginV * 2;

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
    height += 2; // SizedBox(height: 2)
    height += metrics.blockHeight(examName, width: contentWidth, fontSize: 12);
    height += 8 + 1.2; // SizedBox(height: 8) + Divider
    height += 6; // SizedBox(height: 6)
    // A Row of four meta fields, spaceBetween: it never wraps, so the row is
    // one line tall no matter how the fields are distributed.
    height += metrics.lineHeight('বিষয়: $subject', fontSize: bodyFontSize);
    height += 6 + 1.2;
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
  static double cqHeight({
    required int index,
    required HighSchoolQuestion question,
    required double columnWidth,
    required PdfTextMetrics metrics,
    required bool hasImage,
    required StemImageSize imageSize,
  }) {
    final inner = columnWidth - cqBorder - cqPadding;
    var height = cqBorder + cqPadding;

    height += metrics.blockHeight('$index. ${question.stemText}',
        width: inner, fontSize: bodyFontSize);

    if (imageSize.isVisible && hasImage) {
      height += cqImageGap + imageSize.maxHeightPt;
    }

    height += cqStemGap;

    for (final sq in question.cqSubQuestions) {
      final mark = '[${sq.mark}]';
      final markWidth =
          metrics.textWidth(mark, fontSize: smallFontSize, bold: true);
      final textHeight = metrics.blockHeight(
        '(${sq.label}) ${sq.text}',
        width: inner - cqSubIndent - cqMarkGap - markWidth,
        fontSize: bodyFontSize,
      );
      final markHeight =
          metrics.lineHeight(mark, fontSize: smallFontSize, bold: true);
      height += cqSubTop + (textHeight > markHeight ? textHeight : markHeight);
    }

    return height;
  }

  /// Rendered height of an MCQ question, including the rule that follows it.
  ///
  /// The trailing separator is always counted. The builder omits it for the
  /// last question in a column, so this slightly over-estimates — which errs
  /// toward splitting earlier rather than overrunning a column.
  static double mcqHeight({
    required int index,
    required HighSchoolQuestion question,
    required double columnWidth,
    required PdfTextMetrics metrics,
    required bool stackOptions,
  }) {
    final mcq = question.mcqData;
    if (mcq == null) return 0;

    var height = metrics.blockHeight('$index. ${mcq.text}',
        width: columnWidth, fontSize: bodyFontSize);

    // A half-width cell cannot fit two options side by side, so double-column
    // mode stacks them one per row.
    final perRow = stackOptions ? 1 : 2;
    final available = columnWidth - mcqOptionIndent;

    for (int i = 0; i < mcq.options.length; i += perRow) {
      var rowHeight = 0.0;
      for (int c = 0; c < perRow; c++) {
        final idx = i + c;
        if (idx >= mcq.options.length) break;

        final cells = perRow;
        final gutters = perRow > 1 ? (perRow - 1) * mcqOptionGap : 0.0;
        final h = metrics.blockHeight(
          '${_mcqLetter(idx)} ${mcq.options[idx]}',
          width: (available - gutters) / cells,
          fontSize: bodyFontSize,
        );
        if (h > rowHeight) rowHeight = h;
      }
      height += mcqOptionTop + rowHeight;
    }

    return height + mcqSeparatorHeight;
  }

  static String _mcqLetter(int idx) {
    const letters = ['ক', 'খ', 'গ', 'ঘ'];
    return idx < letters.length ? letters[idx] : (idx + 1).toString();
  }
}

/// Split `heights` into `columns` groups of indices, balanced by height.
///
/// Returns `columns` groups (fewer if there are fewer items than columns), each
/// holding indices into `heights` in ascending order, and collectively covering
/// every index exactly once.
///
/// The split is optimal, not greedy.
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
/// is left after its predecessors. The result is that a page is filled and only
/// breaks when it genuinely must.
class PdfPageFlow {
  PdfPageFlow({required this.contentHeight, this.margin = 16});

  /// Printable height of a page.
  final double contentHeight;

  /// Slack subtracted from every budget.
  ///
  /// Heights are measured rather than exact, so this absorbs rounding and
  /// estimate error. Without it a block a few points too tall would silently
  /// jump pages and reintroduce the blank-page bug.
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

  /// Lay [heights] out into rows of balanced columns sized to the remaining
  /// space, returning rows of global indices.
  List<List<List<int>>> layout({
    required List<double> heights,
    required int columns,
    double trailingGap = 0,
  }) {
    final rows = <List<List<int>>>[];
    var start = 0;

    while (start < heights.length) {
      final remaining = heights.sublist(start);

      var budget = contentHeight - _used - margin;
      var count = _largestPrefix(remaining, columns, budget);

      if (count == 0) {
        // Nothing fits here — most likely because the page is nearly full.
        // Move to a fresh page and try again.
        _used = 0;
        budget = contentHeight - margin;
        count = _largestPrefix(remaining, columns, budget);
        // A single question taller than a whole page cannot be helped; emit it
        // rather than dropping it, and let the caller decide.
        if (count == 0) count = 1;
      }

      final slice = remaining.sublist(0, count);
      final row = balanceColumns(heights: slice, columns: columns);

      rows.add([
        for (final column in row) [for (final i in column) i + start]
      ]);

      _used += tallestColumnHeight(row, slice) + trailingGap;
      if (_used >= contentHeight - margin) _used = 0;

      start += count;
    }

    return rows;
  }

  /// Largest number of leading items whose optimal split still fits [budget].
  ///
  /// The optimal tallest column cannot shrink as items are added, so this is
  /// binary-searchable. Returns 0 when even the first item does not fit.
  int _largestPrefix(List<double> heights, int columns, double budget) {
    var lo = 1;
    var hi = heights.length;
    var best = 0;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      final groups =
          balanceColumns(heights: heights.sublist(0, mid), columns: columns);
      if (tallestColumnHeight(groups, heights) <= budget) {
        best = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return best;
  }
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

/// Tracks how much of the current page a flow layout has consumed, so each

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
