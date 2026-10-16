import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pi_qbank/models/highschool_question.dart';
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

Map<String, dynamic> _mcq(String id, String chapter, String text) => {
      'id': id,
      'class': 'Class (9-10) SSC',
      'subject': 'গণিত',
      'chapter_number': chapter,
      'chapter_name': 'অধ্যায় $chapter',
      'question_type': 'MCQ',
      'stem_text': '',
      'stem_image_url': '',
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

/// Two chapters, one question of each type in each.
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

/// A subject the sheet has never heard of.
final String _emptyPayload = jsonEncode({'status': 'SUCCESS', 'data': []});

/// A field of the hand-entry sheet, found by the label the sheet gives it.
Finder _field(String label) => find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.labelText == label,
    );

/// The CQ sub-question mark boxes, in the order they are drawn.
final Finder _markFields = find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.labelText == 'নম্বর',
);

/// Pick the class and subject, but do not load anything yet.
Future<void> _openStep1(
  WidgetTester tester, {
  Size size = const Size(1000, 2400),
}) async {
  // Tall enough that the lazy list builds every card, so assertions are about
  // the data rather than about what happens to be on screen.
  tester.view.physicalSize = size;
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
}

Future<void> _openPicker(WidgetTester tester) async {
  await _openStep1(tester);
  await tester.ensureVisible(find.text('প্রশ্ন লোড করুন'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('প্রশ্ন লোড করুন'));
  await tester.pumpAndSettle();
}

Future<void> _openManualSheet(WidgetTester tester) async {
  await tester.tap(find.text('নিজে প্রশ্ন লিখুন'));
  await tester.pumpAndSettle();
}

/// Tap the sheet's save button, scrolling it into view first.
Future<void> _saveSheet(WidgetTester tester) async {
  await tester.ensureVisible(find.text('প্রশ্নপত্রে যোগ করুন'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('প্রশ্নপত্রে যোগ করুন'));
  await tester.pumpAndSettle();
}

HighSchoolQuestion _typed({
  String type = 'CQ',
  String text = 'নিজে লেখা প্রশ্ন',
  String stem = '',
  String image = '',
  List<CqSubQuestion> subs = const [],
  List<String> options = const [],
  String correct = '',
  int mark = 1,
}) =>
    HighSchoolQuestion.manual(
      className: 'Class 6',
      subject: 'গণিত',
      chapterNumber: '3',
      chapterName: 'বৃত্ত',
      questionType: type,
      text: text,
      stem: stem,
      stemImageUrl: image,
      subQuestions: subs,
      options: options,
      correctAnswer: correct,
      shortMark: mark,
    );

/// Save the edit sheet, scrolling the button into view first.
Future<void> _saveEdit(WidgetTester tester) async {
  await tester.ensureVisible(find.text('পরিবর্তন সংরক্ষণ করুন'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('পরিবর্তন সংরক্ষণ করুন'));
  await tester.pumpAndSettle();
}

/// The text a labelled box currently holds.
String _boxText(WidgetTester tester, String label) =>
    tester.widget<TextField>(_field(label)).controller!.text;

/// Open a card and start editing the question on it.
Future<void> _openEdit(WidgetTester tester, String title) async {
  await tester.tap(find.text(title));
  await tester.pumpAndSettle();
  await tester.tap(find.text('সম্পাদনা করুন'));
  await tester.pumpAndSettle();
}

/// A CQ exactly as the sheet returns one, source tag and all.
HighSchoolQuestion _fetchedCq() => HighSchoolQuestion.fromJson({
      ..._cq('c1', '1', 'মূল উদ্দীপক [ঢাকা বোর্ড ২০১৯]'),
      'board_year_tag': 'ঢাকা বোর্ড ২০১৯',
    });

/// The bar over a chapter's questions in the picker.
///
/// The header's own text is the same string as the chapter tag every card
/// carries, so a test would find five of them; the key is what identifies the
/// bar itself.
Finder _chapterHeader(String number) =>
    find.byKey(ValueKey('chapter-header-$number'));

/// What a chapter header reports, e.g. `3 টি` or `1 নির্বাচিত`.
Finder _inHeader(String number, String text) =>
    find.descendant(of: _chapterHeader(number), matching: find.text(text));

void main() {
  setUpAll(() => HttpOverrides.global = _FakeOverrides(_payload));
  tearDownAll(() => HttpOverrides.global = null);

  group('a hand-typed question', () {
    test('an MCQ keeps its question in the payload, not the stem', () {
      final q = _typed(
        type: 'MCQ',
        text: 'নিচের কোনটি বৃত্তের কেন্দ্র?',
        options: const ['O', '', 'AB', 'PQ'],
        correct: 'AB',
      );

      expect(q.isMcq, isTrue);
      expect(q.isManual, isTrue);
      // Typed to be printed, so it arrives selected.
      expect(q.isSelected, isTrue);
      expect(q.questionType, 'MCQ');
      expect(q.stemText, isEmpty);
      expect(q.paperQuestionText, 'নিচের কোনটি বৃত্তের কেন্দ্র?');
      // The blank option is dropped rather than printed as an empty cell.
      expect(q.mcqData!.options, ['O', 'AB', 'PQ']);
      expect(q.mcqData!.correctAns, 'AB');
      expect(q.totalMarks, 1);
    });

    test('an MCQ typed with an উদ্দীপক keeps it apart from the question', () {
      final q = _typed(
        type: 'MCQ',
        stem: 'নিচের চিত্রটি দেখে উত্তর দাও।',
        image: 'https://example.com/figure.png',
        text: 'চিত্রে কয়টি ত্রিভুজ আছে?',
        options: const ['২', '৩', '৪', '৫'],
        correct: '৩',
      );

      // The intro is the stem, where the group logic and the figure look for it.
      expect(q.mcqStemText, 'নিচের চিত্রটি দেখে উত্তর দাও।');
      expect(q.stemImageUrl, 'https://example.com/figure.png');
      // The question itself stays in the payload.
      expect(q.mcqData!.text, 'চিত্রে কয়টি ত্রিভুজ আছে?');
      expect(q.opensMcqStemGroup(null), isTrue);

      // Two rows typed under the same intro print it once: the second one is in
      // the group the first opened.
      final partner = _typed(
        type: 'MCQ',
        stem: 'নিচের চিত্রটি দেখে উত্তর দাও।',
        text: 'চিত্রের ক্ষেত্রফল কত?',
        options: const ['২', '৩', '৪', '৫'],
      );
      expect(partner.opensMcqStemGroup(q), isFalse);
      expect(partner.opensMcqStemGroup(null), isTrue);
    });

    test('a CQ keeps its intro in the stem, where it has always been', () {
      final q = _typed(
        text: 'উদ্দীপকটি পড়ে উত্তর দাও।',
        image: 'https://example.com/figure.png',
      );
      expect(q.paperStemText, 'উদ্দীপকটি পড়ে উত্তর দাও।');
      expect(q.stemImageUrl, 'https://example.com/figure.png');
      expect(q.mcqStemText, isEmpty);
    });

    test('a CQ sums the marks of the sub-questions typed for it', () {
      final q = _typed(
        text: 'উদ্দীপকটি পড়ে উত্তর দাও।',
        subs: const [
          CqSubQuestion(label: 'ক', mark: 2, text: 'প্রশ্ন ক'),
          // A blank mark box arrives as 0: worth nothing, so it becomes 1.
          CqSubQuestion(label: 'খ', mark: 0, text: 'প্রশ্ন খ'),
        ],
      );

      expect(q.isCq, isTrue);
      expect(q.paperStemText, 'উদ্দীপকটি পড়ে উত্তর দাও।');
      expect(q.cqSubQuestions.map((s) => s.text), ['প্রশ্ন ক', 'প্রশ্ন খ']);
      expect(q.cqSubQuestions.map((s) => s.label), ['ক', 'খ']);
      expect(q.cqSubQuestions.last.mark, 1);
      expect(q.totalMarks, 3);
    });

    test('a short question keeps its own mark, never below one', () {
      final marked = _typed(type: 'RQ', text: 'বৃত্ত কাকে বলে?', mark: 3);
      expect(marked.isShort, isTrue);
      expect(marked.shortData!.text, 'বৃত্ত কাকে বলে?');
      expect(marked.totalMarks, 3);

      // `SHORT` is the other spelling of the same type, and a blank mark box
      // still prints as one mark rather than none.
      final blank = _typed(type: 'SHORT', text: 'বৃত্ত কাকে বলে?', mark: 0);
      expect(blank.questionType, 'RQ');
      expect(blank.isShort, isTrue);
      expect(blank.totalMarks, 1);
    });

    test('gets the same fraction glyphs as a fetched row', () {
      final q = _typed(
        text: 'একটি 1/2 অংশ',
        subs: const [CqSubQuestion(label: 'ক', mark: 2, text: '2/3 অংশ')],
      );

      expect(q.paperStemText, contains('½'));
      expect(q.cqSubQuestions.first.text, contains('⅔'));
    });

    test('is trimmed and gets an id of its own', () {
      final a = HighSchoolQuestion.manual(
        className: 'Class 6',
        subject: 'গণিত',
        chapterNumber: ' 3 ',
        chapterName: ' বৃত্ত ',
        questionType: 'RQ',
        text: '  বৃত্ত কাকে বলে?  ',
      );
      final b = _typed();

      expect(a.chapterNumber, '3');
      expect(a.chapterName, 'বৃত্ত');
      expect(a.shortData!.text, 'বৃত্ত কাকে বলে?');
      expect(a.id, startsWith('manual-'));
      expect(a.id, isNot(b.id));
    });
  });

  group('hand entry in the picker', () {
    testWidgets('an MCQ typed in the picker joins the list, selected',
        (tester) async {
      await _openPicker(tester);
      expect(find.textContaining('মোট নম্বর: 0'), findsOneWidget);

      await _openManualSheet(tester);
      await tester.tap(find.text('বহুনির্বাচনি'));
      await tester.pumpAndSettle();
      await tester.enterText(_field('প্রশ্ন'), 'নিজে লেখা বহুনির্বাচনি');
      for (final letter in ['ক', 'খ', 'গ', 'ঘ']) {
        await tester.enterText(_field('অপশন $letter'), 'অপশন $letter');
      }
      await _saveSheet(tester);

      // The sheet closed, and the question is a card in the list with its mark
      // counted and a badge saying where it came from.
      expect(find.text('প্রশ্নপত্রে যোগ করুন'), findsNothing);
      expect(find.text('নিজে লেখা বহুনির্বাচনি'), findsOneWidget);
      expect(find.text('নিজে লেখা'), findsOneWidget);
      expect(find.textContaining('মোট নম্বর: 1'), findsOneWidget);
    });

    testWidgets('the MCQ sheet takes an উদ্দীপক and a picture link',
        (tester) async {
      await _openPicker(tester);
      await _openManualSheet(tester);
      await tester.tap(find.text('বহুনির্বাচনি'));
      await tester.pumpAndSettle();

      // An MCQ's intro and its figure are fields of their own; the question
      // itself is the 'প্রশ্ন' box.
      expect(_field('উদ্দীপক (ঐচ্ছিক)'), findsOneWidget);
      expect(_field('প্রশ্ন'), findsOneWidget);
      expect(_field('ছবির লিংক (ঐচ্ছিক)'), findsOneWidget);

      // A short question has neither: its text is the question and nothing else.
      await tester.tap(find.text('সংক্ষিপ্ত'));
      await tester.pumpAndSettle();
      expect(_field('উদ্দীপক (ঐচ্ছিক)'), findsNothing);
      expect(_field('ছবির লিংক (ঐচ্ছিক)'), findsNothing);
    });

    testWidgets('an উদ্দীপক typed with an MCQ shows up with the question',
        (tester) async {
      await _openPicker(tester);
      await _openManualSheet(tester);
      await tester.tap(find.text('বহুনির্বাচনি'));
      await tester.pumpAndSettle();
      await tester.enterText(_field('উদ্দীপক (ঐচ্ছিক)'), 'নিজে লেখা উদ্দীপক');
      await tester.enterText(_field('প্রশ্ন'), 'নিজে লেখা বহুনির্বাচনি');
      for (final letter in ['ক', 'খ', 'গ', 'ঘ']) {
        await tester.enterText(_field('অপশন $letter'), 'অপশন $letter');
      }
      await _saveSheet(tester);

      // The card's one-line summary is the question; the intro is kept apart
      // from it, and shown with the options when the card is opened.
      expect(find.text('নিজে লেখা উদ্দীপক'), findsNothing);
      await tester.tap(find.text('নিজে লেখা বহুনির্বাচনি'));
      await tester.pumpAndSettle();
      expect(find.text('নিজে লেখা উদ্দীপক'), findsOneWidget);
    });

    testWidgets('a CQ totals only the sub-questions that were filled in',
        (tester) async {
      await _openPicker(tester);
      await _openManualSheet(tester);

      await tester.enterText(_field('উদ্দীপক'), 'নিজে লেখা উদ্দীপক');
      await tester.enterText(_field('উপপ্রশ্ন ক'), 'উপপ্রশ্ন এক');
      await tester.enterText(_field('উপপ্রশ্ন খ'), 'উপপ্রশ্ন দুই');
      await tester.enterText(_field('উপপ্রশ্ন গ'), 'উপপ্রশ্ন তিন');
      await tester.enterText(_markFields.at(0), '2');
      await tester.enterText(_markFields.at(1), '3');
      await tester.enterText(_markFields.at(2), '5');
      // The fourth sub-question is left blank, so it is not part of the CQ —
      // otherwise its default mark would push the total past 10.
      await _saveSheet(tester);

      expect(find.text('নিজে লেখা উদ্দীপক'), findsOneWidget);
      expect(find.textContaining('মোট নম্বর: 10'), findsOneWidget);
    });

    testWidgets('a blank or short question is refused with a reason',
        (tester) async {
      await _openPicker(tester);
      await _openManualSheet(tester);
      await tester.tap(find.text('সংক্ষিপ্ত'));
      await tester.pumpAndSettle();

      // Nothing typed yet.
      await _saveSheet(tester);
      expect(find.text('প্রশ্ন লিখুন।'), findsOneWidget);
      // The sheet stays open with the complaint rather than closing empty.
      expect(find.text('প্রশ্নপত্রে যোগ করুন'), findsOneWidget);

      await tester.enterText(_field('প্রশ্ন'), ' ');
      await _saveSheet(tester);
      expect(find.text('প্রশ্ন লিখুন।'), findsOneWidget);
    });

    testWidgets('with nothing in the bank the sheet is still reachable',
        (tester) async {
      HttpOverrides.global = _FakeOverrides(_emptyPayload);
      addTearDown(() => HttpOverrides.global = _FakeOverrides(_payload));

      await _openStep1(tester);
      await tester.tap(find.text('প্রশ্ন লোড করুন'));
      await tester.pumpAndSettle();
      expect(find.textContaining('কোনো প্রশ্ন পাওয়া যায়নি'), findsWidgets);

      // An empty subject still opens the picker, so hand entry stays reachable
      // from its empty list.
      await tester.tap(find.text('নিজে প্রশ্ন লিখুন').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('সংক্ষিপ্ত'));
      await tester.pumpAndSettle();

      // No chapter list came back with the empty reply, so the question is
      // filed under a chapter typed by hand.
      expect(_field('অধ্যায় নম্বর'), findsOneWidget);
      await tester.enterText(_field('অধ্যায় নম্বর'), '3');
      await tester.enterText(_field('অধ্যায়ের নাম'), 'বৃত্ত');
      await tester.enterText(_field('প্রশ্ন'), 'নিজে লেখা সংক্ষিপ্ত');
      await tester.enterText(_markFields.first, '3');
      await _saveSheet(tester);

      // The paper moved on to the picker with the typed question standing in
      // for the chapter the bank does not have: the bar over it and the card's
      // own tag both name the chapter that was typed.
      expect(find.text('নিজে লেখা সংক্ষিপ্ত'), findsOneWidget);
      expect(_chapterHeader('3'), findsOneWidget);
      expect(find.textContaining('অধ্যায় 3: বৃত্ত'), findsNWidgets(2));
      expect(find.textContaining('মোট নম্বর: 3'), findsOneWidget);
    });

    testWidgets('the sheet files the question under a chapter the picker knows',
        (tester) async {
      await _openPicker(tester);
      await _openManualSheet(tester);
      await tester.tap(find.text('সংক্ষিপ্ত'));
      await tester.pumpAndSettle();

      // The picker knows chapters 1 and 2 from the loaded questions, so the
      // sheet offers them rather than asking for a number and a name.
      expect(_field('অধ্যায় নম্বর'), findsNothing);
      expect(_field('অধ্যায়ের নাম'), findsNothing);

      await tester.enterText(_field('প্রশ্ন'), 'এক নম্বর অধ্যায়ের প্রশ্ন');
      await _saveSheet(tester);

      // It landed in the chapter the sheet was showing — the first one — and
      // the chapter below it is untouched.
      expect(find.text('এক নম্বর অধ্যায়ের প্রশ্ন'), findsOneWidget);
      expect(find.text('4 টি'), findsOneWidget);
      expect(find.text('3 টি'), findsOneWidget);
    });

    testWidgets('a typed question survives going back and loading again',
        (tester) async {
      await _openPicker(tester);
      await _openManualSheet(tester);
      await tester.tap(find.text('বহুনির্বাচনি'));
      await tester.pumpAndSettle();
      await tester.enterText(_field('প্রশ্ন'), 'নিজে লেখা বহুনির্বাচনি');
      await tester.enterText(_field('অপশন ক'), 'ক');
      await tester.enterText(_field('অপশন খ'), 'খ');
      await _saveSheet(tester);
      expect(find.textContaining('মোট নম্বর: 1'), findsOneWidget);

      // Back to step 1 and load again: the sheet cannot return the typed
      // question, so it has to be carried across the re-fetch.
      await tester.tap(find.byTooltip('আগের ধাপ'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('প্রশ্ন লোড করুন'));
      await tester.pumpAndSettle();

      expect(find.text('নিজে লেখা বহুনির্বাচনি'), findsOneWidget);
      expect(find.textContaining('মোট নম্বর: 1'), findsOneWidget);
    });
  });

  group('correcting a fetched question', () {
    test('an edit keeps the row it came from and everything about it', () {
      final original = _fetchedCq()
        ..isSelected = true
        ..setLabel = 'খ';

      final edited = HighSchoolQuestion.edited(
        original: original,
        chapterNumber: '2',
        chapterName: 'চলক',
        text: 'সম্পাদিত উদ্দীপক',
        subQuestions: const [
          CqSubQuestion(label: 'ক', mark: 2, text: 'সম্পাদিত উপপ্রশ্ন'),
        ],
      );

      // The paper keeps printing the row it fixed: same id, same class and
      // subject, and the source tag the HTML still shows.
      expect(edited.id, original.id);
      expect(edited.className, original.className);
      expect(edited.subject, original.subject);
      expect(edited.boardYearTag, 'ঢাকা বোর্ড ২০১৯');
      expect(edited.isManual, isFalse);
      expect(edited.isEdited, isTrue);

      // Where it is filed and where it sits in the paper stay the reader's.
      expect(edited.chapterNumber, '2');
      expect(edited.chapterName, 'চলক');
      expect(edited.isSelected, isTrue);
      expect(edited.setLabel, 'খ');

      expect(edited.paperStemText, 'সম্পাদিত উদ্দীপক');
      expect(edited.totalMarks, 2);
    });

    test('an edit is normalised exactly like a first typing', () {
      final edited = HighSchoolQuestion.edited(
        original: _fetchedCq(),
        chapterNumber: '1',
        chapterName: 'অধ্যায় 1',
        text: '  1/2 অংশ  ',
        subQuestions: const [
          CqSubQuestion(label: 'ক', mark: 0, text: '2/3 অংশ')
        ],
      );

      expect(edited.paperStemText, '½ অংশ');
      expect(edited.cqSubQuestions.first.text, '⅔ অংশ');
      // A blank mark box is worth one mark, not none.
      expect(edited.cqSubQuestions.first.mark, 1);
    });

    test('an edit of an MCQ keeps the intro apart from the question', () {
      final original =
          HighSchoolQuestion.fromJson(_mcq('m1', '1', 'মূল প্রশ্ন'));

      final edited = HighSchoolQuestion.edited(
        original: original,
        chapterNumber: '1',
        chapterName: 'অধ্যায় 1',
        stem: 'নিচের চিত্র দেখে উত্তর দাও।',
        stemImageUrl: 'https://example.com/figure.png',
        text: 'চিত্রে কয়টি ত্রিভুজ আছে?',
        options: const ['২', '', '৪', '৫'],
        correctAnswer: '৪',
      );

      expect(edited.isMcq, isTrue);
      expect(edited.mcqStemText, 'নিচের চিত্র দেখে উত্তর দাও।');
      expect(edited.stemImageUrl, 'https://example.com/figure.png');
      expect(edited.mcqData!.text, 'চিত্রে কয়টি ত্রিভুজ আছে?');
      // The blank option is dropped and the answer is the text of the option it
      // points at, so it survives its neighbours being rewritten.
      expect(edited.mcqData!.options, ['২', '৪', '৫']);
      expect(edited.mcqData!.correctAns, '৪');
    });

    test('editing a hand-typed question leaves it hand-typed', () {
      final typed = _typed(type: 'RQ', text: 'বৃত্ত কাকে বলে?', mark: 2);

      final edited = HighSchoolQuestion.edited(
        original: typed,
        chapterNumber: '3',
        chapterName: 'বৃত্ত',
        text: 'বৃত্ত কাকে বলে?',
        shortMark: 4,
      );

      // Still not in the bank, and still carries the id the picker keys on.
      expect(edited.isManual, isTrue);
      expect(edited.isEdited, isTrue);
      expect(edited.id, typed.id);
      expect(edited.isShort, isTrue);
      expect(edited.shortData!.text, 'বৃত্ত কাকে বলে?');
      expect(edited.totalMarks, 4);
    });
  });

  group('editing in the picker', () {
    testWidgets('a fetched CQ opens filled in and replaces itself on save',
        (tester) async {
      await _openPicker(tester);
      await _openEdit(tester, 'সৃজনশীল প্রশ্ন এক');

      // Edit mode: the question's own kind, its text already in the boxes, and a
      // button that saves rather than adds.
      expect(find.text('প্রশ্ন সম্পাদনা করুন'), findsOneWidget);
      expect(find.text('প্রশ্নপত্রে যোগ করুন'), findsNothing);
      expect(find.text('সৃজনশীল'), findsOneWidget);
      expect(_boxText(tester, 'উদ্দীপক'), 'সৃজনশীল প্রশ্ন এক');
      expect(_boxText(tester, 'উপপ্রশ্ন ক'), 'উপপ্রশ্ন ক c1');
      expect(_boxText(tester, 'উপপ্রশ্ন খ'), 'উপপ্রশ্ন খ c1');

      await tester.enterText(_field('উদ্দীপক'), 'সম্পাদিত উদ্দীপক');
      await tester.enterText(_field('উপপ্রশ্ন খ'), 'সম্পাদিত উপপ্রশ্ন');
      await _saveEdit(tester);

      // The card was replaced, not joined by a second one, and it says where the
      // text came from.
      expect(find.text('প্রশ্ন সম্পাদনা করুন'), findsNothing);
      expect(find.textContaining('সৃজনশীল প্রশ্ন এক'), findsNothing);
      expect(find.text('সম্পাদিত উদ্দীপক'), findsWidgets);
      expect(find.text('সম্পাদিত উপপ্রশ্ন'), findsWidgets);
      expect(find.text('সম্পাদিত'), findsOneWidget);
      // Chapter 1 still holds three questions: one was replaced, not added.
      expect(_inHeader('1', '3 টি'), findsOneWidget);
    });

    testWidgets('an edit moves the marks the paper would carry',
        (tester) async {
      await _openPicker(tester);
      // Select the chapter 1 CQ: two sub-questions worth 2 and 3.
      await tester.tap(find.byType(Checkbox).first);
      await tester.pumpAndSettle();
      expect(find.textContaining('মোট নম্বর: 5'), findsOneWidget);

      await _openEdit(tester, 'সৃজনশীল প্রশ্ন এক');
      // The mark boxes open with the marks the bank has.
      expect(tester.widget<TextField>(_markFields.at(0)).controller!.text, '2');
      expect(tester.widget<TextField>(_markFields.at(1)).controller!.text, '3');

      await tester.enterText(_markFields.at(1), '4');
      await _saveEdit(tester);

      expect(find.textContaining('মোট নম্বর: 6'), findsOneWidget);
      expect(find.textContaining('মোট নম্বর: 5'), findsNothing);
    });

    testWidgets('a fetched MCQ opens with its options and keeps them',
        (tester) async {
      await _openPicker(tester);
      await _openEdit(tester, 'বহুনির্বাচনি প্রশ্ন এক');

      expect(find.text('বহুনির্বাচনি'), findsOneWidget);
      expect(_boxText(tester, 'প্রশ্ন'), 'বহুনির্বাচনি প্রশ্ন এক');
      expect(_boxText(tester, 'অপশন ক'), '১');
      expect(_boxText(tester, 'অপশন ঘ'), '৪');

      await tester.enterText(_field('অপশন ক'), 'সম্পাদিত অপশন');
      await _saveEdit(tester);

      // The card stays open on the question it was showing, so the corrected
      // option is there to be read.
      expect(find.text('সম্পাদিত অপশন'), findsWidgets);
      expect(find.text('১'), findsNothing);
    });

    testWidgets('a corrected question survives going back and loading again',
        (tester) async {
      await _openPicker(tester);
      await _openEdit(tester, 'সংক্ষিপ্ত প্রশ্ন এক');
      await tester.enterText(_field('প্রশ্ন'), 'সম্পাদিত সংক্ষিপ্ত');
      await _saveEdit(tester);
      expect(find.text('সম্পাদিত সংক্ষিপ্ত'), findsWidgets);

      // The sheet returns the row as the bank has it, so the correction has to
      // be carried over the re-fetch by id.
      await tester.tap(find.byTooltip('আগের ধাপ'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('প্রশ্ন লোড করুন'));
      await tester.pumpAndSettle();

      expect(find.text('সম্পাদিত সংক্ষিপ্ত'), findsWidgets);
      expect(find.textContaining('সংক্ষিপ্ত প্রশ্ন এক'), findsNothing);
    });

    testWidgets('backing out of the edit sheet leaves the question alone',
        (tester) async {
      await _openPicker(tester);
      await _openEdit(tester, 'সৃজনশীল প্রশ্ন এক');
      await tester.enterText(_field('উদ্দীপক'), 'বাতিল করা সম্পাদনা');

      await tester.tap(find.byTooltip('বন্ধ করুন'));
      await tester.pumpAndSettle();

      expect(find.textContaining('সৃজনশীল প্রশ্ন এক'), findsOneWidget);
      expect(find.text('বাতিল করা সম্পাদনা'), findsNothing);
      expect(find.text('সম্পাদিত'), findsNothing);
    });
  });

  group('chapter folding', () {
    testWidgets('a chapter header folds its questions away and back',
        (tester) async {
      await _openPicker(tester);
      expect(find.textContaining('প্রশ্ন এক'), findsNWidgets(3));
      expect(_inHeader('1', '3 টি'), findsOneWidget);

      await tester.tap(_chapterHeader('1'));
      await tester.pumpAndSettle();

      // Chapter 1's three cards are gone and chapter 2's are untouched; the
      // header stays and now offers to open the group again.
      expect(find.textContaining('প্রশ্ন এক'), findsNothing);
      expect(find.textContaining('প্রশ্ন দুই'), findsNWidgets(3));
      expect(_chapterHeader('1'), findsOneWidget);
      expect(_inHeader('1', '3 টি'), findsOneWidget);
      expect(find.byTooltip('প্রশ্নগুলো দেখান'), findsOneWidget);
      expect(find.byTooltip('প্রশ্নগুলো লুকান'), findsOneWidget);

      await tester.tap(_chapterHeader('1'));
      await tester.pumpAndSettle();
      expect(find.textContaining('প্রশ্ন এক'), findsNWidgets(3));
      expect(find.byTooltip('প্রশ্নগুলো দেখান'), findsNothing);
    });

    testWidgets('a folded chapter still says what is selected in it',
        (tester) async {
      await _openPicker(tester);

      // The first card is chapter 1's CQ.
      await tester.tap(find.byType(Checkbox).first);
      await tester.pumpAndSettle();
      expect(_inHeader('1', '1 নির্বাচিত'), findsOneWidget);

      await tester.tap(_chapterHeader('1'));
      await tester.pumpAndSettle();

      expect(find.textContaining('প্রশ্ন এক'), findsNothing);
      expect(_inHeader('1', '1 নির্বাচিত'), findsOneWidget);
      expect(_inHeader('2', '1 নির্বাচিত'), findsNothing);
    });

    testWidgets('folding one chapter leaves the others alone', (tester) async {
      await _openPicker(tester);

      await tester.tap(_chapterHeader('2'));
      await tester.pumpAndSettle();
      expect(find.textContaining('প্রশ্ন দুই'), findsNothing);
      expect(find.textContaining('প্রশ্ন এক'), findsNWidgets(3));

      // A type filter does not open what the reader folded away.
      await tester.tap(find.byTooltip('সৃজনশীল'));
      await tester.pumpAndSettle();
      expect(find.textContaining('সৃজনশীল প্রশ্ন এক'), findsOneWidget);
      expect(find.textContaining('সৃজনশীল প্রশ্ন দুই'), findsNothing);
    });
  });
}
