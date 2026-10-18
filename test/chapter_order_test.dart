import 'package:flutter_test/flutter_test.dart';

import 'package:pi_qbank/models/highschool_question.dart';

/// Chapter labels are labels, not integers: "2.2 চক্রবৃদ্ধি মুনাফা" is a
/// section inside chapter 2, and it used to print ahead of chapter 1 because
/// `int.tryParse` gave up and the failure stood in as 0.
void main() {
  test('a section sorts inside its chapter', () {
    final labels = ['10', '2.2', '1', '11', '2', '3'];

    labels.sort(compareChapterNumbers);

    expect(labels, ['1', '2', '2.2', '3', '10', '11']);
  });

  test('a deeper section sorts after its own', () {
    final labels = ['2.2', '2.1', '2'];

    labels.sort(compareChapterNumbers);

    expect(labels, ['2', '2.1', '2.2']);
  });

  test('a label that is not a number sorts last, not first', () {
    final labels = ['অনুশীলনী', '2', '1', 'পরিশীলনী'];

    labels.sort(compareChapterNumbers);

    expect(labels, ['1', '2', 'অনুশীলনী', 'পরিশীলনী']);
  });

  test('the same number written differently counts as the same chapter', () {
    expect(compareChapterNumbers('2', '2.0'), 0);
    expect(compareChapterNumbers(' 3 ', '3'), 0);
  });

  test('surrounding space does not turn a number into a word', () {
    final labels = [' 4 ', '3'];

    labels.sort(compareChapterNumbers);

    expect(labels, ['3', ' 4 ']);
  });
}
