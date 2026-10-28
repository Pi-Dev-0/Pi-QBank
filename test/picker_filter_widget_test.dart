import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pi_qbank/pages/highschool_qpaper_generator_page.dart';

/// Fakes the Apps Script response.
///
/// The service uses the top-level `http.get`, which cannot be swapped for a
/// `MockClient`, so the only seam is `HttpOverrides`. Going through it means
/// the test still exercises the real page, the real service and the real
/// response parsing.
class _FakeOverrides extends HttpOverrides {
  _FakeOverrides(this._body);
  final String _body;

  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      _FakeHttpClient(_body);
}

/// `HttpClient` has no public constructor, so the fake is built with
/// `implements` + `noSuchMethod` and only the members `package:http` actually
/// touches: `openUrl`, `HttpClientRequest.close`, and on the response the
/// status, headers and byte stream.
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

  // `package:http` configures the request before closing it; none of it
  // matters for a canned reply.
  @override
  set followRedirects(bool value) {}

  @override
  set maxRedirects(int value) {}

  @override
  set contentLength(int value) {}

  @override
  set persistentConnection(bool value) {}

  // The request body is empty for these endpoints, but `package:http` still
  // pipes it in.
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

  /// Every other `Stream` member the response is never asked for.
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

Map<String, dynamic> _cq(String id, String chapter, String text) => {
      'id': id,
      'class': 'Class (9-10) SSC',
      'subject': 'গণিত',
      'chapter_number': chapter,
      'chapter_name': 'অধ্যায় $chapter',
      'question_type': 'CQ',
      'stem_text': text,
      'stem_image_url': '',
      'sub_questions_json': [
        {'label': 'ক', 'mark': 2, 'text': 'উপপ্রশ্ন ক $id'},
        {'label': 'খ', 'mark': 3, 'text': 'উপপ্রশ্ন খ $id'},
      ],
      'board_year_tag': '',
    };

Map<String, dynamic> _mcq(
  String id,
  String chapter,
  String text, {
  String stem = '',
  String group = '',
}) =>
    {
      'id': id,
      'class': 'Class (9-10) SSC',
      'subject': 'গণিত',
      'chapter_number': chapter,
      'chapter_name': 'অধ্যায় $chapter',
      'question_type': 'MCQ',
      'stem_text': stem,
      'stem_image_url': '',
      'stem_group': group,
      'sub_questions_json': {
        'text': text,
        'options': ['১', '২', '৩', '৪'],
      },
      'board_year_tag': '',
    };

Map<String, dynamic> _rq(String id, String chapter, String text) => {
      'id': id,
      'class': 'Class (9-10) SSC',
      'subject': 'গণিত',
      'chapter_number': chapter,
      'chapter_name': 'অধ্যায় $chapter',
      'question_type': 'RQ',
      'stem_text': text,
      'stem_image_url': '',
      'sub_questions_json': <Object>[],
      'board_year_tag': '',
      'short_mark': 2,
    };

/// Interleaved on purpose — that is exactly the pile-up the picker must tame.
final String _payload = jsonEncode({
  'status': 'SUCCESS',
  'data': [
    _cq('c1', '1', 'সৃজনশীল প্রশ্ন এক'),
    _rq('r1', '1', 'সংক্ষিপ্ত প্রশ্ন এক'),
    _mcq('m1', '1', 'বহুনির্বাচনি প্রশ্ন এক'),
    _cq('c2', '2', 'সৃজনশীল প্রশ্ন দুই'),
    _rq('r2', '2', 'সংক্ষিপ্ত প্রশ্ন দুই'),
    _mcq('m2', '2', 'বহুনির্বাচনি প্রশ্ন দুই'),
  ],
});

/// The picker's own search box, found by its hint rather than by position.
final Finder _searchBox = find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.hintText == 'অনুসন্ধান…',
);

/// The checkbox on the card whose preview text contains [text].
Finder _checkboxFor(String text) => find.descendant(
      of: find
          .ancestor(of: find.textContaining(text), matching: find.byType(Row))
          .first,
      matching: find.byType(Checkbox),
    );

Future<void> _openPicker(WidgetTester tester) async {
  // Tall enough that the lazy ListView builds every card, so assertions are
  // about the data rather than about what happens to be on screen.
  tester.view.physicalSize = const Size(1600, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    const MaterialApp(home: HighSchoolQPaperGeneratorPage()),
  );

  // At this width the page draws the desktop studio, whose pickers are the
  // compact `শ্রেণি` / `বিষয়` fields. The wizard's own labels stay as a
  // fallback, so this helper still works if the window is narrowed.
  final classField = find.byKey(const ValueKey('studio-class-field'));
  final subjectField = find.byKey(const ValueKey('studio-subject-field'));

  await tester.tap(
      classField.evaluate().isNotEmpty
          ? classField
          : find.text('ক্লাস নির্বাচন করুন'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Class (9-10) SSC').last);
  await tester.pumpAndSettle();
  await tester.tap(
      subjectField.evaluate().isNotEmpty
          ? subjectField
          : find.text('বিষয় নির্বাচন করুন'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('উচ্চতর গণিত').last);
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text('প্রশ্ন লোড করুন'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('প্রশ্ন লোড করুন'));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => HttpOverrides.global = _FakeOverrides(_payload));
  tearDownAll(() => HttpOverrides.global = null);

  testWidgets('all three types are listed and counted when unfiltered',
      (tester) async {
    await _openPicker(tester);

    // Every type is reachable from the filter bar, named by its tooltip.
    for (final name in ['সব প্রশ্ন', 'সৃজনশীল', 'বহুনির্বাচনি', 'সংক্ষিপ্ত']) {
      expect(find.byTooltip(name), findsOneWidget, reason: name);
    }

    // All six questions are on screen: three per chapter, one of each type.
    // Scoped to the picker list: the settings rail also names the section
    // types, and a bare finder would count those too.
    final pickerList = find.byKey(const ValueKey('studio-picker-list'));
    expect(
        find.descendant(
            of: pickerList, matching: find.textContaining('প্রশ্ন এক')),
        findsNWidgets(3));
    expect(
        find.descendant(
            of: pickerList, matching: find.textContaining('প্রশ্ন দুই')),
        findsNWidgets(3));
  });

  testWidgets('a type chip shows only that type', (tester) async {
    await _openPicker(tester);

    await tester.tap(find.byTooltip('সংক্ষিপ্ত'));
    await tester.pumpAndSettle();

    final pickerList = find.byKey(const ValueKey('studio-picker-list'));
    expect(find.textContaining('সংক্ষিপ্ত প্রশ্ন এক'), findsOneWidget);
    expect(find.textContaining('সংক্ষিপ্ত প্রশ্ন দুই'), findsOneWidget);
    expect(
        find.descendant(
            of: pickerList, matching: find.textContaining('সৃজনশীল প্রশ্ন')),
        findsNothing);
    expect(
        find.descendant(
            of: pickerList, matching: find.textContaining('বহুনির্বাচনি প্রশ্ন')),
        findsNothing);

    // MCQ too, so the filter is not hard-wired to one type.
    await tester.tap(find.byTooltip('বহুনির্বাচনি'));
    await tester.pumpAndSettle();
    expect(find.textContaining('বহুনির্বাচনি প্রশ্ন এক'), findsOneWidget);
    expect(find.textContaining('সংক্ষিপ্ত প্রশ্ন এক'), findsNothing);
  });

  testWidgets('the search box narrows within the current type', (tester) async {
    await _openPicker(tester);

    await tester.enterText(_searchBox, 'এক');
    await tester.pumpAndSettle();

    expect(find.textContaining('প্রশ্ন এক'), findsNWidgets(3));
    expect(find.textContaining('প্রশ্ন দুই'), findsNothing);
    expect(find.text('3 টি দেখানো হচ্ছে'), findsOneWidget);
  });

  testWidgets('a search with no matches explains itself', (tester) async {
    await _openPicker(tester);

    await tester.enterText(_searchBox, 'zzzz');
    await tester.pumpAndSettle();

    expect(find.textContaining('কোনো প্রশ্ন মেলেনি'), findsOneWidget);
  });

  testWidgets('a ticked question rises to the top of its chapter',
      (tester) async {
    await _openPicker(tester);

    double top(String text) => tester.getTopLeft(find.textContaining(text)).dy;

    // A chapter reads CQ, MCQ, RQ — the short question sits last.
    expect(top('সৃজনশীল প্রশ্ন এক'), lessThan(top('বহুনির্বাচনি প্রশ্ন এক')));
    expect(top('বহুনির্বাচনি প্রশ্ন এক'), lessThan(top('সংক্ষিপ্ত প্রশ্ন এক')));

    await tester.tap(_checkboxFor('সংক্ষিপ্ত প্রশ্ন এক'));
    await tester.pumpAndSettle();

    // Ticked, it leads its chapter; the other two keep their order.
    expect(top('সংক্ষিপ্ত প্রশ্ন এক'), lessThan(top('সৃজনশীল প্রশ্ন এক')));
    expect(top('সৃজনশীল প্রশ্ন এক'), lessThan(top('বহুনির্বাচনি প্রশ্ন এক')));

    // The reordering is per chapter: the other one is untouched.
    expect(top('সৃজনশীল প্রশ্ন দুই'), lessThan(top('বহুনির্বাচনি প্রশ্ন দুই')));
    expect(top('বহুনির্বাচনি প্রশ্ন দুই'), lessThan(top('সংক্ষিপ্ত প্রশ্ন দুই')));

    // Unticking puts it back where the type order wants it.
    await tester.tap(_checkboxFor('সংক্ষিপ্ত প্রশ্ন এক'));
    await tester.pumpAndSettle();
    expect(top('সৃজনশীল প্রশ্ন এক'), lessThan(top('বহুনির্বাচনি প্রশ্ন এক')));
    expect(top('বহুনির্বাচনি প্রশ্ন এক'), lessThan(top('সংক্ষিপ্ত প্রশ্ন এক')));
  });

  // A shared উদ্দীপক: the intro prints once, over the first of the questions
  // that follow it, so half a run is not something the paper can print. The
  // picker therefore selects a run whole — one tick takes its partner with it,
  // and one untick lets it go.
  group('a shared উদ্দীপক', () {
    const intro = 'নিচের উদ্দীপকটি পড়।';

    final shared = jsonEncode({
      'status': 'SUCCESS',
      'data': [
        _mcq('s1', '1', 'যৌথ প্রশ্ন এক', stem: intro, group: 'উদ্দীপক-১'),
        _mcq('s2', '1', 'যৌথ প্রশ্ন দুই', stem: intro, group: 'উদ্দীপক-১'),
        _mcq('s3', '1', 'একা প্রশ্ন'),
      ],
    });

    setUp(() => HttpOverrides.global = _FakeOverrides(shared));
    tearDown(() => HttpOverrides.global = _FakeOverrides(_payload));

    int tickedCount(WidgetTester tester) => tester
        .widgetList<Checkbox>(find.byType(Checkbox))
        .where((c) => c.value == true)
        .length;

    testWidgets('a run is selected whole, and says so on the card',
        (tester) async {
      await _openPicker(tester);

      // Both rows of the run are marked as one.
      expect(find.text('একই উদ্দীপক · 2টি'), findsNWidgets(2));
      // The third question shares nothing, so it carries no such mark.
      expect(find.textContaining('একই উদ্দীপক'), findsNWidgets(2));

      await tester.tap(_checkboxFor('যৌথ প্রশ্ন এক'));
      await tester.pumpAndSettle();

      expect(tickedCount(tester), 2,
          reason: 'ticking one of a shared run takes its partner along');

      await tester.tap(_checkboxFor('যৌথ প্রশ্ন এক'));
      await tester.pumpAndSettle();

      expect(tickedCount(tester), 0,
          reason: 'a shared run is let go whole');
    });

    testWidgets('a question sharing nothing is ticked on its own',
        (tester) async {
      await _openPicker(tester);

      await tester.tap(_checkboxFor('একা প্রশ্ন'));
      await tester.pumpAndSettle();

      expect(tickedCount(tester), 1,
          reason: 'no run, no company: only this one is ticked');
    });
  });

  group('a random draw', () {
    /// The three count boxes, found by their keys.
    final cqBox = find.byKey(const ValueKey('cq-count-field'));
    final mcqBox = find.byKey(const ValueKey('mcq-count-field'));
    final rqBox = find.byKey(const ValueKey('rq-count-field'));

    Future<void> draw(
        WidgetTester tester, {
        String cq = '0',
        String mcq = '0',
        String rq = '0',
      }) async {
      await tester.enterText(cqBox, cq);
      await tester.enterText(mcqBox, mcq);
      await tester.enterText(rqBox, rq);
      await tester.tap(find.text('বাছাই'));
      await tester.pumpAndSettle();
    }

    testWidgets('spreads the count over the types, one each to begin with',
        (tester) async {
      await _openPicker(tester);

      await draw(tester, cq: '1', mcq: '1', rq: '1');

      // Two of each type in the bank, so one each is picked.
      expect(find.text('CQ: 1/2'), findsOneWidget);
      expect(find.text('MCQ: 1/2'), findsOneWidget);
      expect(find.text('RQ: 1/2'), findsOneWidget);
    });

    testWidgets('replaces the selection rather than adding to it',
        (tester) async {
      await _openPicker(tester);

      // Fill the paper first, then ask for a smaller draw.
      await tester.tap(find.text('সব নির্বাচন'));
      await tester.pumpAndSettle();
      expect(find.text('CQ: 2/2'), findsOneWidget);

      await draw(tester, cq: '1', mcq: '1', rq: '1');

      // The count asked for is the count in the paper — not seven.
      expect(find.text('CQ: 1/2'), findsOneWidget);
      expect(find.text('MCQ: 1/2'), findsOneWidget);
      expect(find.text('RQ: 1/2'), findsOneWidget);
    });

    testWidgets('a draw larger than the bank takes everything',
        (tester) async {
      await _openPicker(tester);

      await draw(tester, cq: '99', mcq: '99', rq: '99');

      expect(find.text('CQ: 2/2'), findsOneWidget);
      expect(find.text('MCQ: 2/2'), findsOneWidget);
      expect(find.text('RQ: 2/2'), findsOneWidget);
    });

    testWidgets('an empty count is refused with a reason', (tester) async {
      await _openPicker(tester);

      await draw(tester, cq: '', mcq: '', rq: '');
      expect(find.textContaining('সংখ্যা লিখুন'), findsOneWidget);
    });

    testWidgets('a zero count is refused with a reason', (tester) async {
      await _openPicker(tester);

      await draw(tester, cq: '0', mcq: '0', rq: '0');
      expect(find.textContaining('সংখ্যা লিখুন'), findsOneWidget);
      // Nothing was ticked by the refused draw.
      expect(find.text('CQ: 0/2'), findsOneWidget);
    });
  });
}
