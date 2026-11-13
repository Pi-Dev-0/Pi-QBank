import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pi_qbank/pages/question_paper_preview_page.dart';

void main() {
  testWidgets('the phone preview keeps live edit in the app bar',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
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

    final appBar = find.byType(AppBar);
    final edit = find.byTooltip('লাইভ এডিট');
    expect(edit, findsOneWidget);
    expect(find.descendant(of: appBar, matching: edit), findsOneWidget,
        reason: 'the phone uses the AppBar action, not a floating button');

    // The only floating control is the compact settings pill.
    final settings = find.byType(FloatingActionButton);
    expect(settings, findsOneWidget);
    final settingsSize = tester.getSize(settings);
    expect(settingsSize.height, lessThan(52),
        reason: 'the settings pill is lower than the stock 56px FAB');
    expect(settingsSize.width, lessThan(170));
    expect(tester.takeException(), isNull);
  });
}
