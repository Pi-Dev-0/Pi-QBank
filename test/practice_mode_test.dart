// Practice sheets keep the questions and the chapter but drop the exam clock
// and total marks. These tests pin both ends: the written masthead and the
// desktop rail that switches between the two kinds of sheet. The phone picker
// tests at the end cover the floating search/filter and random actions that
// give the question list its full height.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pi_qbank/models/highschool_question.dart';
import 'package:pi_qbank/pages/highschool_qpaper_generator_page.dart';
import 'package:pi_qbank/services/highschool_export_service.dart';

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

Map<String, dynamic> _cqJson({
  String id = 'cq',
  String chapterNumber = '1',
  String chapterName = 'অনুশীলনী ১',
  String stemText = 'একটি উদ্দীপক',
}) =>
    {
      'id': id,
      'class': 'Class (9-10) SSC',
      'subject': 'গণিত',
      'chapter_number': chapterNumber,
      'chapter_name': chapterName,
      'question_type': 'CQ',
      'stem_text': stemText,
      'stem_image_url': '',
      'sub_questions_json': [
        {'label': 'ক', 'mark': 2, 'text': 'সমাধান করো।'},
      ],
      'board_year_tag': '',
    };

HighSchoolQuestion _cq() => HighSchoolQuestion.fromJson(_cqJson());

void main() {
  setUpAll(() => HttpOverrides.global = _FakeOverrides(
        jsonEncode({'status': 'SUCCESS', 'data': <Object>[]}),
      ));
  tearDownAll(() => HttpOverrides.global = null);

  test('practice sheets leave the clock and total off the masthead', () {
    final html = HighSchoolExportService.generateHtml(
      schoolName: 'স্কুল',
      examName: 'অনুশীলন শিট',
      subject: 'গণিত',
      className: 'দশম',
      time: '',
      totalMarks: '',
      questions: [_cq()],
      cqInstruction: 'প্রতিটি প্রশ্নের উত্তর নিজের খাতায় লিখুন।',
    );
    final body = html.split('</style>').last.split('<script>').first;

    expect(body, contains('অনুশীলন শিট'));
    expect(body, contains('প্রতিটি প্রশ্নের উত্তর নিজের খাতায় লিখুন।'));
    expect(body, isNot(contains('>সময়:')));
    expect(body, isNot(contains('>পূর্ণমান:')));
  });

  testWidgets('the desktop rail switches to a practice sheet and back',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MaterialApp(home: HighSchoolQPaperGeneratorPage()),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('studio-class-field')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Class (9-10) SSC').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('studio-subject-field')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('উচ্চতর গণিত').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('প্রশ্ন লোড করুন'));
    await tester.pumpAndSettle();

    final rail = find.byKey(const PageStorageKey('studio-settings-rail'));
    expect(rail, findsOneWidget);
    final scrollable =
        find.descendant(of: rail, matching: find.byType(Scrollable)).first;
    await tester.scrollUntilVisible(
      find.text('প্রশ্নপত্রের ধরন'),
      250,
      scrollable: scrollable,
    );

    await tester.tap(find.text('অনুশীলন'));
    await tester.pumpAndSettle();

    expect(find.text('অনুশীলনের শিরোনাম'), findsWidgets);
    expect(find.text('পূর্ণমান'), findsNothing);
    expect(find.text('সময়'), findsNothing);
    expect(find.text('নির্দেশনা (ঐচ্ছিক)'), findsOneWidget);

    await tester.tap(find.text('পরীক্ষা'));
    await tester.pumpAndSettle();

    expect(find.text('পরীক্ষার নাম'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('পূর্ণমান'),
      250,
      scrollable: scrollable,
    );
    expect(find.text('পূর্ণমান'), findsOneWidget);
    expect(find.text('সময়'), findsOneWidget);
  });

  testWidgets('the desktop rail sizes CQ, SQ and MCQ separately',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MaterialApp(home: HighSchoolQPaperGeneratorPage()),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('studio-class-field')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Class (9-10) SSC').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('studio-subject-field')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('উচ্চতর গণিত').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('প্রশ্ন লোড করুন'));
    await tester.pumpAndSettle();

    final rail = find.byKey(const PageStorageKey('studio-settings-rail'));
    final scrollable =
        find.descendant(of: rail, matching: find.byType(Scrollable)).first;
    await tester.scrollUntilVisible(find.text('CQ ফন্ট সাইজ'), 250,
        scrollable: scrollable);
    await tester.ensureVisible(find.text('CQ ফন্ট সাইজ'));
    await tester.pumpAndSettle();

    expect(find.text('সাধারণ ফন্ট সাইজ'), findsOneWidget);
    expect(find.text('CQ ফন্ট সাইজ'), findsOneWidget);
    expect(find.text('SQ ফন্ট সাইজ'), findsOneWidget);
    expect(find.text('MCQ ফন্ট সাইজ'), findsOneWidget);

    final cqRow = find
        .ancestor(of: find.text('CQ ফন্ট সাইজ'), matching: find.byType(Row))
        .first;
    final sqRow = find
        .ancestor(of: find.text('SQ ফন্ট সাইজ'), matching: find.byType(Row))
        .first;
    String rowValue(Finder row) => tester
        .widgetList<Text>(find.descendant(of: row, matching: find.byType(Text)))
        .last
        .data!;

    expect(rowValue(cqRow), '15');
    expect(rowValue(sqRow), '15');

    await tester.tap(find.descendant(
        of: cqRow, matching: find.byIcon(Icons.add_circle_outline)));
    await tester.pumpAndSettle();

    expect(rowValue(cqRow), '16');
    expect(rowValue(sqRow), '15',
        reason: 'the CQ control must not move the short questions');
    expect(tester.takeException(), isNull);
  });

  testWidgets('the phone card fills its width and fits the practice switch',
      (tester) async {
    HttpOverrides.global = _FakeOverrides(jsonEncode({
      'status': 'SUCCESS',
      'data': [_cqJson()],
    }));
    addTearDown(() => HttpOverrides.global = _FakeOverrides(
          jsonEncode({'status': 'SUCCESS', 'data': <Object>[]}),
        ));

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

    await tester.tap(find.text('পরবর্তী'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('একটি উদ্দীপক').first);
    await tester.pumpAndSettle();

    await tester.tap(find.descendant(
      of: find.byType(AppBar),
      matching: find.text('সাজান'),
    ));
    await tester.pumpAndSettle();

    expect(find.text('প্রশ্নপত্রের মাথার তথ্য'), findsOneWidget);
    expect(find.text('প্রশ্নপত্রের ধরন'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('অনুশীলন'));
    await tester.pumpAndSettle();

    expect(find.text('অনুশীলনের শিরোনাম'), findsOneWidget);
    expect(find.text('পূর্ণমান'), findsNothing);
    expect(find.text('সময়'), findsNothing);
    expect(find.text('নির্দেশনা (ঐচ্ছিক)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the phone typography card keeps its font controls compact',
      (tester) async {
    HttpOverrides.global = _FakeOverrides(jsonEncode({
      'status': 'SUCCESS',
      'data': [_cqJson()],
    }));
    addTearDown(() => HttpOverrides.global = _FakeOverrides(
          jsonEncode({'status': 'SUCCESS', 'data': <Object>[]}),
        ));

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

    await tester.tap(find.text('পরবর্তী'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('একটি উদ্দীপক').first);
    await tester.pumpAndSettle();

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
    await tester.scrollUntilVisible(find.text('টাইপোগ্রাফি ও ফাঁক'), 300,
        scrollable: list);
    await tester.pumpAndSettle();

    final general = find.byKey(const ValueKey('general-font-size'));
    expect(general, findsOneWidget);
    expect(tester.getSize(general).height, lessThan(52),
        reason: 'the general control should be one low line, not two');

    final cq = find.byKey(const ValueKey('font-size-CQ'));
    final sq = find.byKey(const ValueKey('font-size-SQ'));
    final mcq = find.byKey(const ValueKey('font-size-MCQ'));
    expect(cq, findsOneWidget);
    expect(sq, findsOneWidget);
    expect(mcq, findsOneWidget);
    expect(tester.getSize(cq).height, lessThan(70),
        reason: 'the three family controls share one compact row');
    expect(
        (tester.getCenter(cq).dy - tester.getCenter(sq).dy).abs(), lessThan(1));
    expect((tester.getCenter(sq).dy - tester.getCenter(mcq).dy).abs(),
        lessThan(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the phone picker typesets equations instead of showing markup',
      (tester) async {
    HttpOverrides.global = _FakeOverrides(jsonEncode({
      'status': 'SUCCESS',
      'data': [
        {
          'id': 'latex-cq',
          'class': 'Class (9-10) SSC',
          'subject': 'গণিত',
          'chapter_number': '1',
          'chapter_name': 'অনুশীলনী ১',
          'question_type': 'CQ',
          'stem_text':
              r'$\frac{x}{2}+\frac{y}{3}=1 \quad \text{এবং} \quad \frac{4x}{7}-\frac{2y}{9}=-1$',
          'stem_image_url': '',
          'sub_questions_json': [
            {
              'label': 'ক',
              'mark': 2,
              'text':
                  r'$(4,3)$ বিন্দুটি $\left(\frac{1}{2}\right)$ সমীকরণকে সিদ্ধ করে কি না যাচাই করো।',
            },
          ],
          'board_year_tag': '',
        },
      ],
    }));
    addTearDown(() => HttpOverrides.global = _FakeOverrides(
          jsonEncode({'status': 'SUCCESS', 'data': <Object>[]}),
        ));

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

    await tester.tap(find.text('পরবর্তী'));
    await tester.pumpAndSettle();

    // The card typesets the stem and the sub-question: no raw command or
    // delimiter should survive in the visible text.
    expect(find.textContaining(r'\frac'), findsNothing);
    expect(find.textContaining(r'\left'), findsNothing);
    expect(find.textContaining(r'\quad'), findsNothing);
    expect(find.textContaining('সমীকরণকে সিদ্ধ'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the phone picker hides its controls behind floating actions',
      (tester) async {
    HttpOverrides.global = _FakeOverrides(jsonEncode({
      'status': 'SUCCESS',
      'data': [_cqJson()],
    }));
    addTearDown(() => HttpOverrides.global = _FakeOverrides(
          jsonEncode({'status': 'SUCCESS', 'data': <Object>[]}),
        ));

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

    await tester.tap(find.text('পরবর্তী'));
    await tester.pumpAndSettle();

    final searchBox = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.hintText == 'অনুসন্ধান…',
    );
    expect(searchBox, findsNothing,
        reason: 'the search bar moved off the top of the picker');
    expect(find.byKey(const ValueKey('random-selector-toggle')), findsNothing);
    expect(find.byKey(const ValueKey('picker-filter-fab')), findsOneWidget);
    expect(find.byKey(const ValueKey('picker-random-fab')), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const ValueKey('picker-filter-fab')));
    await tester.pumpAndSettle();

    expect(searchBox, findsOneWidget);
    expect(find.text('প্রশ্নের ধরন'), findsOneWidget);
    expect(find.byTooltip('বহুনির্বাচনি'), findsOneWidget);
    expect(find.byTooltip('ছবি: সব'), findsOneWidget);

    await tester.enterText(searchBox, 'উদ্দীপক');
    await tester.pumpAndSettle();
    expect(find.text('1 টি প্রশ্ন'), findsOneWidget);

    await tester.tap(find.text('দেখুন'));
    await tester.pumpAndSettle();

    expect(find.text('1 টি প্রশ্ন দেখানো হচ্ছে'), findsOneWidget);
    await tester.tap(find.text('মুছুন'));
    await tester.pumpAndSettle();
    expect(find.text('1 টি প্রশ্ন দেখানো হচ্ছে'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('picker-random-fab')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('cq-count-field')), findsOneWidget);
    expect(find.byKey(const ValueKey('mcq-count-field')), findsOneWidget);
    expect(find.byKey(const ValueKey('rq-count-field')), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('cq-count-field')), '1');
    await tester.tap(find.text('বাছাই'));
    await tester.pumpAndSettle();

    expect(find.text('CQ 1/1'), findsOneWidget);
    expect(find.byKey(const ValueKey('cq-count-field')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the filter sheet narrows the picker by chapter', (tester) async {
    HttpOverrides.global = _FakeOverrides(jsonEncode({
      'status': 'SUCCESS',
      'data': [
        _cqJson(id: 'cq1', stemText: 'প্রথম অধ্যায়ের উদ্দীপক'),
        _cqJson(
          id: 'cq2',
          chapterNumber: '2',
          chapterName: 'অনুশীলনী ২',
          stemText: 'দ্বিতীয় অধ্যায়ের উদ্দীপক',
        ),
      ],
    }));
    addTearDown(() => HttpOverrides.global = _FakeOverrides(
          jsonEncode({'status': 'SUCCESS', 'data': <Object>[]}),
        ));

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

    await tester.tap(find.text('পরবর্তী'));
    await tester.pumpAndSettle();

    expect(find.textContaining('প্রথম অধ্যায়ের উদ্দীপক'), findsOneWidget);
    expect(find.textContaining('দ্বিতীয় অধ্যায়ের উদ্দীপক'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('picker-filter-fab')));
    await tester.pumpAndSettle();

    expect(find.text('অধ্যায়'), findsOneWidget);
    expect(find.text('অধ্যায় 1'), findsOneWidget);
    expect(find.text('অধ্যায় 2'), findsOneWidget);

    await tester.tap(find.text('অধ্যায় 2'));
    await tester.pumpAndSettle();
    expect(find.text('1 টি প্রশ্ন'), findsOneWidget);

    await tester.tap(find.text('দেখুন'));
    await tester.pumpAndSettle();

    expect(find.text('1 টি প্রশ্ন দেখানো হচ্ছে'), findsOneWidget);
    expect(find.textContaining('প্রথম অধ্যায়ের উদ্দীপক'), findsNothing);
    expect(find.textContaining('দ্বিতীয় অধ্যায়ের উদ্দীপক'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the picker sheets fit a short phone', (tester) async {
    HttpOverrides.global = _FakeOverrides(jsonEncode({
      'status': 'SUCCESS',
      'data': [_cqJson()],
    }));
    addTearDown(() => HttpOverrides.global = _FakeOverrides(
          jsonEncode({'status': 'SUCCESS', 'data': <Object>[]}),
        ));

    tester.view.physicalSize = const Size(420, 820);
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

    await tester.tap(find.text('পরবর্তী'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('picker-filter-fab')));
    await tester.pumpAndSettle();
    expect(find.text('দেখুন'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('বন্ধ করুন'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('picker-random-fab')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('cq-count-field')), findsOneWidget);
    expect(find.text('বাছাই'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
