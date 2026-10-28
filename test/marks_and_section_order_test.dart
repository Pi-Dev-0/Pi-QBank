import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pi_qbank/pages/highschool_qpaper_generator_page.dart';

/// Minimal `HttpClient` answering every request with a canned Apps Script reply.
///
/// `HttpClient` has no public constructor, so the fake is built with
/// `implements` + `noSuchMethod` over only the members `package:http` uses.
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

  /// `package:http`'s top-level `get` closes its client in a `finally`.
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
      Stream<List<int>>.value(_bytes).listen(onData,
          onError: onError, onDone: onDone, cancelOnError: cancelOnError);

  @override
  bool get isBroadcast => false;

  Future<HttpClientResponse> finalize() async => this;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

Map<String, dynamic> _cq(String id, List<int> subMarks) => {
      'id': id,
      'class': 'Class (9-10) SSC',
      'subject': 'গণিত',
      'chapter_number': '1',
      'chapter_name': 'অধ্যায় ১',
      'question_type': 'CQ',
      'stem_text': 'সৃজনশীল প্রশ্ন $id',
      'stem_image_url': '',
      'sub_questions_json': [
        for (var i = 0; i < subMarks.length; i++)
          {
            'label': String.fromCharCode(0x0995 + i),
            'mark': subMarks[i],
            'text': 'উপপ্রশ্ন ${i + 1}',
          }
      ],
      'board_year_tag': '',
    };

Map<String, dynamic> _mcq(String id) => {
      'id': id,
      'class': 'Class (9-10) SSC',
      'subject': 'গণিত',
      'chapter_number': '1',
      'chapter_name': 'অধ্যায় ১',
      'question_type': 'MCQ',
      'stem_text': '',
      'stem_image_url': '',
      'sub_questions_json': {
        'text': 'বহুনির্বাচনি $id',
        'options': ['১', '২', '৩', '৪'],
      },
      'board_year_tag': '',
    };

Map<String, dynamic> _rq(String id, int mark) => {
      'id': id,
      'class': 'Class (9-10) SSC',
      'subject': 'গণিত',
      'chapter_number': '1',
      'chapter_name': 'অধ্যায় ১',
      'question_type': 'RQ',
      'stem_text': 'সংক্ষিপ্ত $id',
      'stem_image_url': '',
      'sub_questions_json': <Object>[],
      'board_year_tag': '',
      'short_mark': mark,
    };

/// Six CQs worth 10 marks each, plus 2 MCQ and 4 RQ worth 2 each.
final String _payload = jsonEncode({
  'status': 'SUCCESS',
  'data': [
    for (var i = 1; i <= 6; i++) _cq('c$i', [2, 3, 5]),
    _mcq('m1'),
    _mcq('m2'),
    for (var i = 1; i <= 4; i++) _rq('r$i', 2),
  ],
});

Future<void> _openPicker(WidgetTester tester) async {
  // Under the desktop breakpoint, so this exercises the three-step wizard and
  // its compact step-3 layout rather than the desktop studio.
  tester.view.physicalSize = const Size(900, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    const MaterialApp(home: HighSchoolQPaperGeneratorPage()),
  );
  await tester.tap(find.text('ক্লাস নির্বাচন করুন'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Class (9-10) SSC').last);
  await tester.pumpAndSettle();
  await tester.tap(find.text('বিষয় নির্বাচন করুন'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('উচ্চতর গণিত').last);
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text('প্রশ্ন লোড করুন'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('প্রশ্ন লোড করুন'));
  await tester.pumpAndSettle();
}

/// Select everything and move on to the last step.
Future<void> _toLastStep(WidgetTester tester) async {
  await tester.tap(find.text('সব নির্বাচন'));
  await tester.pumpAndSettle();
  await tester.tap(find.textContaining('প্রশ্নপত্র সাজান ➜'));
  await tester.pumpAndSettle();
}

/// Vertical distance from the tile at [from] to where the tile at [to] sits,
/// so a drag lands where the test means rather than at a guessed offset.
double _dragDelta(WidgetTester tester, int from, int to) {
  final centres = <double>[];
  for (var i = 0; i < 3; i++) {
    centres.add(
        tester.getCenter(find.byIcon(Icons.drag_indicator_rounded).at(i)).dy);
  }
  final tileHeight = centres[1] - centres[0];
  return centres[to] + (from > to ? 0 : tileHeight) - centres[from];
}

String _shownTotal(WidgetTester tester) =>
    tester.widget<Text>(find.textContaining('মোট নম্বর:').first).data!;

/// The section banners in the drag list, top to bottom.
List<String> _sectionOrder(WidgetTester tester) => tester
    .widgetList<Text>(find.descendant(
        of: find.byType(ReorderableListView), matching: find.byType(Text)))
    .map((t) => t.data ?? '')
    .where((t) => t.contains('বিভাগ'))
    .toList();

void main() {
  setUpAll(() => HttpOverrides.global = _FakeOverrides(_payload));
  tearDownAll(() => HttpOverrides.global = null);

  group('marks total', () {
    testWidgets('unfiltered, the total is the sum of the selected cards',
        (tester) async {
      await _openPicker(tester);

      // The six CQs only: 6 x (2+3+5) = 60. Cards are ordered CQ, MCQ, RQ,
      // so the first six checkboxes are the CQs.
      for (var i = 0; i < 6; i++) {
        await tester.tap(find.byType(Checkbox).at(i));
        await tester.pumpAndSettle();
      }
      expect(_shownTotal(tester), contains('60'));
    });

    testWidgets('selecting other types raises it by their marks',
        (tester) async {
      await _openPicker(tester);
      await tester.tap(find.text('সব নির্বাচন'));
      await tester.pumpAndSettle();

      // 6 CQ x 10 + 2 MCQ x 1 + 4 RQ x 2 = 70.
      expect(_shownTotal(tester), contains('70'));
    });

    testWidgets('a filter that hides selections says so', (tester) async {
      await _openPicker(tester);
      await tester.tap(find.text('সব নির্বাচন'));
      await tester.pumpAndSettle();
      final all = _shownTotal(tester);

      await tester.tap(find.byTooltip('সৃজনশীল'));
      await tester.pumpAndSettle();

      // The reported bug: the visible CQ cards add up to 60 while the total
      // still counts the MCQ and RQ the filter has hidden. The total is not
      // wrong — the paper carries every selection — but nothing said so.
      expect(_shownTotal(tester), all);
      expect(find.textContaining('ফিল্টারের বাইরে'), findsOneWidget);
      // 2 MCQ x 1 + 4 RQ x 2 = 10 marks hidden behind the CQ filter.
      expect(find.textContaining('10 নম্বরের নির্বাচিত'), findsOneWidget);
    });

    testWidgets('the last step breaks the total down by type', (tester) async {
      await _openPicker(tester);
      await _toLastStep(tester);

      expect(find.text('CQ: 6টি  ·  60 নম্বর'), findsOneWidget);
      expect(find.text('MCQ: 2টি  ·  2 নম্বর'), findsOneWidget);
      expect(find.text('RQ: 4টি  ·  8 নম্বর'), findsOneWidget);
      expect(find.text('মোট নম্বর: 70'), findsOneWidget);
    });

    testWidgets('step 3 writes the class the way a paper does', (tester) async {
      await _openPicker(tester);
      await _toLastStep(tester);

      // The শ্রেণি field carries the paper's own name for the class; the
      // canonical label stays behind for the fetch calls and the sheet.
      expect(find.text('নবম-দশম'), findsOneWidget);
      expect(find.text('Class (9-10) SSC'), findsNothing);
    });

    testWidgets('the CQ remark sits under the field, not in the label',
        (tester) async {
      await _openPicker(tester);
      await _toLastStep(tester);

      // The label stays short enough to float above the box.
      final label = find.text('যেকোনো কয়টি CQ-র উত্তর দিতে হবে');
      expect(label, findsOneWidget);

      // The remark is the helper, which the field draws under its own border.
      final remark = find.textContaining('খালি রাখলে লেখা হবে না');
      expect(remark, findsOneWidget);
      final cqField = find.byWidgetPredicate(
        (w) =>
            w is TextField &&
            w.decoration?.labelText == 'যেকোনো কয়টি CQ-র উত্তর দিতে হবে',
      );
      // The input row itself — the helper is drawn under it, inside the field.
      final inputRow = find.descendant(
        of: cqField,
        matching: find.byType(EditableText),
      );
      expect(
        tester.getTopLeft(remark).dy,
        greaterThan(tester.getBottomLeft(inputRow).dy),
        reason: 'the remark belongs below the input line',
      );
    });
  });

  group('section order', () {
    testWidgets('defaults to CQ, then the short questions, then MCQ',
        (tester) async {
      await _openPicker(tester);
      await _toLastStep(tester);

      expect(_sectionOrder(tester), [
        'ক-বিভাগ: সৃজনশীল (CQ)',
        'খ-বিভাগ: সংক্ষিপ্ত (SQ)',
        'গ-বিভাগ: বহুনির্বাচনী (MCQ)',
      ]);
    });

    testWidgets('each tile shows its own count and marks', (tester) async {
      await _openPicker(tester);
      await _toLastStep(tester);

      expect(find.text('6 টি · 60 নম্বর'), findsOneWidget);
      expect(find.text('2 টি · 2 নম্বর'), findsOneWidget);
      expect(find.text('4 টি · 8 নম্বর'), findsOneWidget);
    });

    testWidgets('dragging MCQ to the top reorders the sections',
        (tester) async {
      await _openPicker(tester);
      await _toLastStep(tester);

      // The grab handle on the last tile, dragged past the first two.
      final delta = _dragDelta(tester, 2, 0);
      await tester.drag(
          find.byIcon(Icons.drag_indicator_rounded).last, Offset(0, delta));
      await tester.pumpAndSettle();

      expect(_sectionOrder(tester), [
        'ক-বিভাগ: বহুনির্বাচনী (MCQ)',
        'খ-বিভাগ: সৃজনশীল (CQ)',
        'গ-বিভাগ: সংক্ষিপ্ত (SQ)',
      ]);
    });

    testWidgets('moving MCQ between CQ and the short questions splits them',
        (tester) async {
      await _openPicker(tester);
      await _toLastStep(tester);

      // MCQ (last) up one slot: between CQ and RQ.
      final delta = _dragDelta(tester, 2, 1);
      await tester.drag(
          find.byIcon(Icons.drag_indicator_rounded).last, Offset(0, delta));
      await tester.pumpAndSettle();

      expect(_sectionOrder(tester), [
        'ক-বিভাগ: সৃজনশীল (CQ)',
        'খ-বিভাগ: বহুনির্বাচনী (MCQ)',
        'গ-বিভাগ: সংক্ষিপ্ত (SQ)',
      ]);
    });

    testWidgets('an empty section is still listed, with nothing in it',
        (tester) async {
      await _openPicker(tester);

      // Select only the CQs, then go to the last step.
      for (var i = 0; i < 6; i++) {
        await tester.tap(find.byType(Checkbox).at(i));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.textContaining('প্রশ্নপত্র সাজান ➜'));
      await tester.pumpAndSettle();

      // The rows still map one-for-one onto the order the blocks print in: a
      // block with nothing in it keeps its place and says so, because the order
      // still decides the letter the other blocks print under.
      expect(find.byType(ReorderableListView), findsOneWidget);
      expect(find.text('কোনো সংক্ষিপ্ত প্রশ্ন নেই'), findsOneWidget);
      expect(find.text('কোনো বহুনির্বাচনী প্রশ্ন নেই'), findsOneWidget);
    });
  });
}
