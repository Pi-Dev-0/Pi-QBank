import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards which sections take part in the merged CQ + short-question run.
///
/// The run is laid out as one continuous flow, so only the two types that share
/// it may be emitted from it; MCQ is the dispatcher's job.
///
/// The bug these pin: the loop's second branch was a bare `else`, so an MCQ
/// entry in the reader's order fell into it and printed the whole
/// short-question section again — once for the MCQ entry and once for the SQ
/// entry. Nothing threw, no count was wrong, and the marks still added up: the
/// paper simply carried two copies of every short question.
///
/// The emitter assembles real widgets from private state and writes to disk, so
/// there is no seam a test can call. Like `section_banner_gap_test.dart` this is
/// therefore pinned against the source, and is about *which kinds* the run
/// emits, not how they look.
void main() {
  late String source;

  setUpAll(() {
    source = File('lib/pages/highschool_qpaper_generator_page.dart')
        .readAsStringSync();
  });

  /// The body of the merged CQ + short-question emitter.
  String mergedEmitter() {
    final start = source.indexOf('void _appendPdfCqAndShortSection(');
    final end = source.indexOf('\n  void _showError(', start);
    expect(start, greaterThan(-1));
    expect(end, greaterThan(start));
    return source.substring(start, end);
  }

  /// The merged branch of the dispatcher, up to where the run is emitted.
  String mergedDispatch() {
    final start = source.indexOf('if (mergeCqAndShorts) {');
    final end = source.indexOf('_appendPdfCqAndShortSection(', start);
    expect(start, greaterThan(-1));
    expect(end, greaterThan(start));
    return source.substring(start, end);
  }

  test('the short questions are emitted only for the SQ section', () {
    final emitter = mergedEmitter();

    expect(emitter.contains('} else if (kind.isRq) {'), isTrue,
        reason: 'a bare `else` lets an MCQ entry print the SQ section twice');
  });

  test('the run emits nothing for MCQ', () {
    final emitter = mergedEmitter();

    expect(emitter.contains('kind.isMcq'), isFalse,
        reason: 'MCQ belongs to the dispatcher, not to the shared run');
  });

  test('MCQ placed first opens the paper, not closes it', () {
    final dispatch = mergedDispatch();

    expect(dispatch.contains('_activeSections.first.isMcq'), isTrue);
    expect(dispatch.contains('emitMcq()'), isTrue,
        reason: 'the reader put MCQ first and the paper must start with it');
  });
}
