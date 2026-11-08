import '../models/highschool_question.dart';

/// Group MCQs into the units that must stay together in a paper.
///
/// Two or more consecutive MCQs sharing the same উদ্দীপক are one unit: the
/// introduction is printed once above them, so selecting half a run would show
/// a question without the stimulus it refers to. A unit of one is an ordinary
/// question with no shared introduction.
///
/// Chapters are handled separately, exactly as the paper generator does: a
/// question at the start of a new chapter starts a new run even if its intro
/// happens to read like the last one in the previous chapter.
List<List<HighSchoolQuestion>> mcqStemUnits(
  Iterable<HighSchoolQuestion> questions,
) {
  final byChapter = <String, List<HighSchoolQuestion>>{};
  for (final question in questions) {
    if (!question.isMcq) continue;
    byChapter
        .putIfAbsent(question.chapterNumber, () => <HighSchoolQuestion>[])
        .add(question);
  }

  final units = <List<HighSchoolQuestion>>[];
  final chapters = byChapter.keys.toList()..sort(compareChapterNumbers);
  for (final chapter in chapters) {
    final mcqs = byChapter[chapter]!;
    var run = <HighSchoolQuestion>[];
    for (final question in mcqs) {
      if (run.isNotEmpty && question.sharesMcqStemWith(run.last)) {
        run.add(question);
      } else {
        if (run.isNotEmpty) units.add(List.unmodifiable(run));
        run = <HighSchoolQuestion>[question];
      }
    }
    if (run.isNotEmpty) units.add(List.unmodifiable(run));
  }
  return units;
}

/// Expand a set of picked question ids to every question in the same unit.
///
/// A saved selection can predate run-aware picking, and a caller can hand in
/// just one id from a shared-stimulus pair. Expanding here keeps every path
/// from asking half a group.
Set<String> expandMcqStemPicks(
  Iterable<String> ids,
  Iterable<HighSchoolQuestion> questions,
) {
  final byId = <String, List<HighSchoolQuestion>>{};
  for (final unit in mcqStemUnits(questions)) {
    for (final question in unit) {
      byId[question.id] = unit;
    }
  }

  final out = <String>{};
  for (final id in ids) {
    final unit = byId[id];
    if (unit == null) {
      out.add(id);
    } else {
      out.addAll(unit.map((question) => question.id));
    }
  }
  return out;
}
