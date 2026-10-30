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

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async =>
      _FakeRequest(_body);

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

/// A phone width keeps the wizard, whose Scaffold carries the floating
/// settings pill. A tall viewport lets the lazy list build every card.
Future<void> _openSheet(WidgetTester tester) async {
  tester.view.physicalSize = const Size(420, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    const MaterialApp(home: HighSchoolQPaperGeneratorPage()),
  );
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

/// Pick class and subject, fetch the bank, and land on the question picker.
Future<void> _openPickerOnPhone(WidgetTester tester) async {
  tester.view.physicalSize = const Size(420, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    const MaterialApp(home: HighSchoolQPaperGeneratorPage()),
  );
  await tester.pumpAndSettle();

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

void main() {
  setUpAll(() => HttpOverrides.global = _FakeOverrides(
        jsonEncode({'status': 'SUCCESS', 'data': <Object>[]}),
      ));
  tearDownAll(() => HttpOverrides.global = null);

  testWidgets('the floating button opens the full settings sheet',
      (tester) async {
    await _openSheet(tester);

    expect(find.text('প্রশ্নপত্র সেটিংস'), findsOneWidget);
    for (final section in [
      'কলাম লেআউট',
      'পেজ সেটআপ',
      'টাইপোগ্রাফি ও ফাঁক',
      'MCQ অপশন স্টাইল',
      'হেডার তথ্য',
      'প্রশ্নের সংযুক্তি',
      'ছবি ও উত্তরপত্র',
    ]) {
      expect(find.text(section), findsOneWidget, reason: section);
    }

    // The last card sits below the first viewport; scrolling to it proves the
    // list is complete rather than truncated.
    await tester.scrollUntilVisible(
      find.text('সহায়ক টুলস'),
      400,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('সহায়ক টুলস'), findsOneWidget);
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
}
