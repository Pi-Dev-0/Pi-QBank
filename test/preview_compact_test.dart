import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pi_qbank/pages/question_paper_preview_page.dart';

void main() {
  testWidgets('the phone preview keeps its floating controls in one row',
      (tester) async {
    tester.view.physicalSize = const Size(420, 820);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MaterialApp(
        home: QuestionPaperPreviewPage(
          schoolName: 'স্কুল',
          examName: 'পরীক্ষা',
          subject: 'গণিত',
          className: 'Class (9-10) SSC',
          time: '৩ ঘণ্টা',
          totalMarks: '১০০',
          questions: [],
        ),
      ),
    );
    await tester.pumpAndSettle();

    final settings = find.byType(FloatingActionButton);
    final edit = find.byTooltip('লাইভ এডিট');
    expect(settings, findsOneWidget);
    expect(edit, findsOneWidget);
    final settingsSize = tester.getSize(settings);
    final editSize = tester.getSize(edit);
    expect(editSize, const Size(48, 48),
        reason: 'the round edit control shrinks to a standard tap target');
    expect(settingsSize.height, lessThan(52),
        reason: 'the settings pill is lower than the stock 56px FAB');
    expect(settingsSize.width, lessThan(170));
    expect(
      (tester.getCenter(edit).dy - tester.getCenter(settings).dy).abs(),
      lessThan(2),
      reason: 'both controls share a row instead of stacking',
    );
    expect(tester.takeException(), isNull);
  });
}
