import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pi_qbank/pages/highschool_qpaper_generator_page.dart';

/// The service talks to Apps Script through the top-level `http.get`, so the
/// only seam for a widget test is `HttpOverrides`. See
/// `picker_filter_widget_test.dart` for the same fake in detail.
class _FakeOverrides extends HttpOverrides {
  _FakeOverrides(this._body);
  final String _body;

  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      _FakeHttpClient(_body);
}

class _FakeHttpClient implements HttpClient {
  _FakeHttpClient(this._body);
  final String _body;

  /// Number of requests opened. The back/forward test resets this to prove a
  /// reused picker does not hit the network again.
  static int opens = 0;

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    opens++;
    return _FakeRequest(_body);
  }

  @override
  Future<void> close({bool force = false}) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _FakeRequest implements HttpClientRequest {
  _FakeRequest(this._body);
  final String _body;

  @override
  Future<HttpClientResponse> close() async => _FakeResponse(_body);

  @override
  set followRedirects(bool value) {}

  @override
  set maxRedirects(int value) {}

  @override
  set contentLength(int value) {}

  @override
  set persistentConnection(bool value) {}

  @override
  Future<void> addStream(Stream<List<int>> stream) async {}

  @override
  void add(List<int> data) {}

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> flush() async {}

  @override
  void write(Object? obj) {}

  @override
  void writeAll(Iterable<dynamic> objects, [String separator = '']) {}

  @override
  HttpHeaders get headers => _FakeHeaders();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _FakeHeaders implements HttpHeaders {
  @override
  void forEach(void Function(String name, List<String> values) f,
      {void Function(Object? error)? onError}) {
    f('content-type', ['application/json; charset=utf-8']);
  }

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _FakeResponse implements HttpClientResponse, Stream<List<int>> {
  _FakeResponse(String body) : _bytes = utf8.encode(body);
  final List<int> _bytes;

  @override
  int get statusCode => 200;

  @override
  int get contentLength => _bytes.length;

  @override
  HttpHeaders get headers => _FakeHeaders();

  @override
  bool get isRedirect => false;

  @override
  String get reasonPhrase => 'OK';

  @override
  List<RedirectInfo> get redirects => const <RedirectInfo>[];

  @override
  bool get persistentConnection => true;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) =>
      Stream<List<int>>.value(_bytes).listen(
        onData,
        onError: onError,
        onDone: onDone,
        cancelOnError: cancelOnError,
      );

  @override
  bool get isBroadcast => false;

  Future<HttpClientResponse> finalize() async => this;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

/// Open the wizard's settings sheet the way a phone reader does: the floating
/// pill only rides the arrange step, so the helper walks through the picker
/// first and ticks one question.
Future<void> _openSheet(WidgetTester tester) async {
  HttpOverrides.global = _FakeOverrides(_questionPayload);
  addTearDown(() => HttpOverrides.global = _FakeOverrides(
        jsonEncode({'status': 'SUCCESS', 'data': <Object>[]}),
      ));

  await _openPickerOnPhone(tester);

  await tester.tap(find.byType(Checkbox).first);
  await tester.pumpAndSettle();
  await tester.tap(find.descendant(
    of: find.byType(AppBar),
    matching: find.text('সাজান'),
  ));
  await tester.pumpAndSettle();

  await tester.tap(find.text('সেটিংস'));
  await tester.pumpAndSettle();
}

Map<String, dynamic> _cq(String id, String chapter) => {
      'id': id,
      'class': 'Class (9-10) SSC',
      'subject': 'গণিত',
      'chapter_number': chapter,
      'chapter_name': 'অধ্যায় $chapter',
      'question_type': 'CQ',
      'stem_text': 'সৃজনশীল প্রশ্ন $id',
      'stem_image_url': '',
      'sub_questions_json': [
        {'label': 'ক', 'mark': 2, 'text': 'উপপ্রশ্ন ক'},
        {'label': 'খ', 'mark': 3, 'text': 'উপপ্রশ্ন খ'},
      ],
      'board_year_tag': '',
    };

Map<String, dynamic> _mcq(String id, String chapter) => {
      'id': id,
      'class': 'Class (9-10) SSC',
      'subject': 'গণিত',
      'chapter_number': chapter,
      'chapter_name': 'অধ্যায় $chapter',
      'question_type': 'MCQ',
      'stem_text': '',
      'stem_image_url': '',
      'stem_group': '',
      'sub_questions_json': {
        'text': 'বহুনির্বাচনি প্রশ্ন $id',
        'options': ['১', '২', '৩', '৪'],
      },
      'board_year_tag': '',
    };

Map<String, dynamic> _rq(String id, String chapter) => {
      'id': id,
      'class': 'Class (9-10) SSC',
      'subject': 'গণিত',
      'chapter_number': chapter,
      'chapter_name': 'অধ্যায় $chapter',
      'question_type': 'RQ',
      'stem_text': 'সংক্ষিপ্ত প্রশ্ন $id',
      'stem_image_url': '',
      'sub_questions_json': <Object>[],
      'board_year_tag': '',
      'short_mark': 2,
    };

final String _questionPayload = jsonEncode({
  'status': 'SUCCESS',
  'data': [
    _cq('c1', '1'),
    _mcq('m1', '1'),
    _rq('r1', '1'),
  ],
});

/// Pump the wizard at a phone width. A tall viewport lets the lazy lists build
/// every card.
Future<void> _pumpPhonePage(WidgetTester tester) async {
  tester.view.physicalSize = const Size(420, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    const MaterialApp(home: HighSchoolQPaperGeneratorPage()),
  );
  await tester.pumpAndSettle();
}

/// Pick class and subject, then fetch the bank and land on the picker.
Future<void> _goToPicker(WidgetTester tester) async {
  await tester.tap(find.text('ক্লাস নির্বাচন করুন'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Class (9-10) SSC').last);
  await tester.pumpAndSettle();

  await tester.tap(find.text('বিষয় নির্বাচন করুন'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('উচ্চতর গণিত').last);
  await tester.pumpAndSettle();

  // The app bar's own forward pill carries the step, not just the big button
  // at the bottom of the filters page.
  await tester.tap(find.text('পরবর্তী'));
  await tester.pumpAndSettle();
}

Future<void> _openPickerOnPhone(WidgetTester tester) async {
  await _pumpPhonePage(tester);
  await _goToPicker(tester);
}

void main() {
  setUpAll(() => HttpOverrides.global = _FakeOverrides(
        jsonEncode({'status': 'SUCCESS', 'data': <Object>[]}),
      ));
  tearDownAll(() => HttpOverrides.global = null);

  testWidgets('the settings pill only rides the arrange step', (tester) async {
    HttpOverrides.global = _FakeOverrides(_questionPayload);
    addTearDown(() => HttpOverrides.global = _FakeOverrides(
          jsonEncode({'status': 'SUCCESS', 'data': <Object>[]}),
        ));

    await _pumpPhonePage(tester);
    expect(find.text('সেটিংস'), findsNothing,
        reason: 'the filters step has no paper settings');

    await _goToPicker(tester);
    expect(find.text('সেটিংস'), findsNothing,
        reason: 'the picker step has no paper settings either');

    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
      of: find.byType(AppBar),
      matching: find.text('সাজান'),
    ));
    await tester.pumpAndSettle();

    expect(find.text('সেটিংস'), findsOneWidget,
        reason: 'the arrange step is where the paper is tuned');
  });

  testWidgets('the phone picker folds the random draw away', (tester) async {
    HttpOverrides.global = _FakeOverrides(_questionPayload);
    addTearDown(() => HttpOverrides.global = _FakeOverrides(
          jsonEncode({'status': 'SUCCESS', 'data': <Object>[]}),
        ));

    await _openPickerOnPhone(tester);

    final toggle = find.byKey(const ValueKey('random-selector-toggle'));
    expect(toggle, findsOneWidget);
    expect(find.descendant(of: toggle, matching: find.text('খুলুন')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('cq-count-field')), findsNothing,
        reason: 'the draw starts folded so the question list has room');
    expect(find.text('বাছাই'), findsNothing);

    await tester.tap(toggle);
    await tester.pumpAndSettle();

    expect(find.descendant(of: toggle, matching: find.text('গুটান')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('cq-count-field')), findsOneWidget);
    expect(find.byKey(const ValueKey('mcq-count-field')), findsOneWidget);
    expect(find.byKey(const ValueKey('rq-count-field')), findsOneWidget);
    expect(find.text('বাছাই'), findsOneWidget);

    await tester.tap(toggle);
    await tester.pumpAndSettle();

    expect(find.descendant(of: toggle, matching: find.text('খুলুন')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('cq-count-field')), findsNothing);
  });

  testWidgets('column choices live only in the settings sheet', (tester) async {
    HttpOverrides.global = _FakeOverrides(_questionPayload);
    addTearDown(() => HttpOverrides.global = _FakeOverrides(
          jsonEncode({'status': 'SUCCESS', 'data': <Object>[]}),
        ));

    await _pumpPhonePage(tester);
    await _goToPicker(tester);
    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
      of: find.byType(AppBar),
      matching: find.text('সাজান'),
    ));
    await tester.pumpAndSettle();

    // The arrange page no longer owns the section order or the column pills;
    // both live in the settings sheet so the page stays focused on text.
    expect(find.byTooltip('এক কলাম'), findsNothing);
    expect(find.byTooltip('দুই কলাম'), findsNothing);
    expect(find.byKey(const ValueKey('layout-CQ-single')), findsNothing);
    expect(find.byType(ReorderableListView), findsNothing,
        reason: 'the section order lives in the settings sheet, which moves '
            'rows with arrow buttons instead of a nested drag list');

    await tester.tap(find.text('সেটিংস'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('move-up-mcq')), findsOneWidget);
    expect(find.textContaining('সৃজনশীল (CQ)'), findsOneWidget);
    expect(find.textContaining('সংক্ষিপ্ত (SQ)'), findsOneWidget);
    expect(find.textContaining('বহুনির্বাচনী (MCQ)'), findsOneWidget);
    expect(find.byKey(const ValueKey('layout-CQ-single')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('layout-MCQ-doubleColumn')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('layout-সংক্ষিপ্ত-single')), findsOneWidget);
  });

  testWidgets('the sheet moves sections with the arrow buttons',
      (tester) async {
    await _openSheet(tester);

    // MCQ starts last; two taps on its up arrow put it first.
    await tester.tap(find.byKey(const ValueKey('move-up-mcq')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('move-up-mcq')));
    await tester.pumpAndSettle();

    // The rows carry their content, so compare where the three titles sit on
    // screen rather than which one happens to print a division letter: only a
    // non-empty section is numbered, and this sheet picked just one question.
    final mcqY =
        tester.getTopLeft(find.textContaining('বহুনির্বাচনী (MCQ)')).dy;
    final cqY = tester.getTopLeft(find.textContaining('সৃজনশীল (CQ)')).dy;
    final rqY = tester.getTopLeft(find.textContaining('সংক্ষিপ্ত (SQ)')).dy;
    expect(mcqY, lessThan(cqY));
    expect(cqY, lessThan(rqY));
  });

  testWidgets('the floating button opens the full settings sheet',
      (tester) async {
    await _openSheet(tester);

    expect(find.text('প্রশ্নপত্র সেটিংস'), findsOneWidget);
    final list = find
        .descendant(
          of: find.byKey(const ValueKey('mobile-settings-list')),
          matching: find.byType(Scrollable),
        )
        .first;
    for (final section in [
      'বিভাগ ও ক্রম',
      'পেজ সেটআপ',
      'টাইপোগ্রাফি ও ফাঁক',
      'MCQ অপশন স্টাইল',
      'হেডার তথ্য',
      'ব্র্যান্ডিং',
      'প্রশ্নের সংযুক্তি',
      'ছবি ও উত্তরপত্র',
      'সেট',
      'সহায়ক টুলস',
    ]) {
      // The ListView builds lazily, so a card further down is not in the tree
      // until it has been scrolled to.
      await tester.scrollUntilVisible(find.text(section), 250,
          scrollable: list);
      expect(find.text(section), findsOneWidget, reason: section);
    }
  });

  testWidgets('a layout chip updates the live summary at once', (tester) async {
    await _openSheet(tester);

    // MCQs start at the shipped default: two columns.
    expect(find.text('2 কলাম'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('layout-MCQ-tripleColumn')));
    await tester.pumpAndSettle();

    expect(find.text('3 কলাম'), findsOneWidget);
    expect(find.text('2 কলাম'), findsNothing,
        reason: 'the sheet rebuilt, not just the page behind it');
  });

  testWidgets('reset puts the summary back on the shipped defaults',
      (tester) async {
    await _openSheet(tester);

    await tester.tap(find.byKey(const ValueKey('layout-MCQ-tripleColumn')));
    await tester.pumpAndSettle();
    expect(find.text('3 কলাম'), findsOneWidget);

    await tester.tap(find.text('রিসেট'));
    await tester.pumpAndSettle();

    expect(find.text('2 কলাম'), findsOneWidget);
    // The summary and the page-size control both say A4 after the reset.
    expect(find.text('A4'), findsWidgets);
  });

  testWidgets('save closes the sheet', (tester) async {
    await _openSheet(tester);

    await tester.tap(find.text('সেভ করুন'));
    await tester.pumpAndSettle();

    expect(find.text('প্রশ্নপত্র সেটিংস'), findsNothing);
  });

  testWidgets('the picker counts ride in the app bar, not a second bar',
      (tester) async {
    HttpOverrides.global = _FakeOverrides(_questionPayload);
    addTearDown(() => HttpOverrides.global = _FakeOverrides(
          jsonEncode({'status': 'SUCCESS', 'data': <Object>[]}),
        ));

    await _openPickerOnPhone(tester);

    final appBar = find.byType(AppBar);
    expect(find.descendant(of: appBar, matching: find.text('CQ 0/1')),
        findsOneWidget);
    expect(find.descendant(of: appBar, matching: find.text('MCQ 0/1')),
        findsOneWidget);
    expect(find.descendant(of: appBar, matching: find.text('RQ 0/1')),
        findsOneWidget);
    expect(find.descendant(of: appBar, matching: find.text('মোট নম্বর: 0')),
        findsOneWidget);
    expect(find.descendant(of: appBar, matching: find.text('সাজান')),
        findsOneWidget);

    // The counts are live: ticking the first card raises its type at once.
    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    expect(find.descendant(of: appBar, matching: find.text('CQ 1/1')),
        findsOneWidget);

    // The old purple counter bar is gone from the body, which is the space the
    // move was meant to reclaim.
    expect(find.text('প্রশ্নপত্র সাজান ➜'), findsNothing);
  });

  testWidgets('back then forward reopens the picker untouched', (tester) async {
    HttpOverrides.global = _FakeOverrides(_questionPayload);
    addTearDown(() => HttpOverrides.global = _FakeOverrides(
          jsonEncode({'status': 'SUCCESS', 'data': <Object>[]}),
        ));

    await _openPickerOnPhone(tester);

    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('CQ 1/1')),
      findsOneWidget,
    );

    // Going forward again must not fetch: a fresh fetch would replace the
    // question objects and silently drop every tick.
    _FakeHttpClient.opens = 0;

    await tester.tap(find.byTooltip('আগের ধাপ'));
    await tester.pumpAndSettle();
    expect(find.text('ক্লাস নির্বাচন করুন'), findsOneWidget);

    await tester.tap(find.text('পরবর্তী'));
    await tester.pumpAndSettle();

    expect(_FakeHttpClient.opens, 0,
        reason: 'forward should reuse the loaded picker, not re-fetch');
    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('CQ 1/1')),
      findsOneWidget,
    );
    expect(tester.widget<Checkbox>(find.byType(Checkbox).first).value, isTrue,
        reason: 'the tick survived the back/forward trip');
  });

  testWidgets('branding switches live in the settings sheet', (tester) async {
    await _openSheet(tester);

    final list = find
        .descendant(
          of: find.byKey(const ValueKey('mobile-settings-list')),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(find.text('ব্র্যান্ডিং'), 400,
        scrollable: list);

    Future<void> tapSwitch(String key) async {
      final finder = find.byKey(ValueKey(key));
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
      await tester.tap(finder);
      await tester.pumpAndSettle();
    }

    expect(find.text('ব্র্যান্ডিং'), findsOneWidget);
    for (final key in [
      'branding-logo-switch',
      'branding-header-switch',
      'branding-footer-switch',
      'branding-watermark-switch',
      'branding-address-switch',
    ]) {
      expect(find.byKey(ValueKey(key)), findsOneWidget, reason: key);
    }

    // The watermark and address inputs stay folded until asked for.
    expect(find.text('জলছাপের লেখা'), findsNothing);
    await tapSwitch('branding-watermark-switch');
    expect(find.text('জলছাপের লেখা'), findsOneWidget);

    await tapSwitch('branding-address-switch');
    expect(find.text('প্রতিষ্ঠানের ঠিকানা'), findsOneWidget);

    // The header switch is independent and flips in place.
    await tapSwitch('branding-header-switch');
    expect(
      tester
          .widget<Switch>(find.byKey(const ValueKey('branding-header-switch')))
          .value,
      isTrue,
    );
  });

  testWidgets('the sheet makes two sets from the picked questions',
      (tester) async {
    HttpOverrides.global = _FakeOverrides(_questionPayload);
    addTearDown(() => HttpOverrides.global = _FakeOverrides(
          jsonEncode({'status': 'SUCCESS', 'data': <Object>[]}),
        ));

    await _openPickerOnPhone(tester);

    // One CQ, one MCQ and one RQ, so a split has something to deal.
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byType(Checkbox).at(i));
      await tester.pumpAndSettle();
    }

    await tester.tap(find.descendant(
      of: find.byType(AppBar),
      matching: find.text('সাজান'),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('সেটিংস'));
    await tester.pumpAndSettle();

    final list = find
        .descendant(
          of: find.byKey(const ValueKey('mobile-settings-list')),
          matching: find.byType(Scrollable),
        )
        .first;
    final toggle = find.byKey(const ValueKey('two-sets-switch'));
    await tester.scrollUntilVisible(toggle, 400, scrollable: list);
    await tester.ensureVisible(toggle);
    await tester.pumpAndSettle();
    await tester.tap(toggle);
    await tester.pumpAndSettle();

    expect(find.text('প্রথম সেটের নাম'), findsOneWidget);
    expect(find.text('দ্বিতীয় সেটের নাম'), findsOneWidget);
    expect(find.text('সব প্রশ্ন প্রথম সেটে'), findsOneWidget);

    final split = find.textContaining('অর্ধেক ভাগ করো');
    await tester.ensureVisible(split);
    await tester.pumpAndSettle();
    await tester.tap(split);
    await tester.pumpAndSettle();

    // Three picked questions alternate 2 / 1 between the two sets.
    expect(find.textContaining('2 টি প্রশ্ন'), findsOneWidget);
    expect(find.textContaining('1 টি প্রশ্ন'), findsOneWidget);
  });
}
