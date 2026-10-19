// The name an export lands under. A paper is called things like
// `পদার্থবিজ্ঞান_প্রথম_পত্র`, and the old sanitizer (`[^\w\.-]`, where Dart's
// `\w` is ASCII-only) turned every one of those letters into an underscore — a
// whole name of them collapsed to `________________.html`, and every paper
// overwrote the last. Only what a file system actually rejects is replaced now.
import 'package:flutter_test/flutter_test.dart';

import 'package:pi_qbank/services/highschool_export_service.dart';

String safe(String name) => HighSchoolExportService.safeFileName(name);

void main() {
  group('export file names', () {
    test('keep the script the paper is written in', () {
      expect(safe('পদার্থবিজ্ঞান.html'), 'পদার্থবিজ্ঞান.html');
      expect(safe('গণিত_প্রথম_পত্র.html'), 'গণিত_প্রথম_পত্র.html');
      // Bengali digits and the vowel signs are letters here, not separators.
      expect(safe('অধ্যায় ১ প্রশ্ন.html'), 'অধ্যায় ১ প্রশ্ন.html');
    });

    test('replace only what a file system rejects', () {
      expect(safe('a/b:c*d?e.html'), 'a_b_c_d_e.html');
      expect(safe('a|b"c<d>e.html'), 'a_b_c_d_e.html');
      expect(safe('a\u0000b.html'), 'a_b.html');
      expect(safe('a\\b.html'), 'a_b.html');
    });

    test('never hand back an empty or hidden name', () {
      expect(safe(''), 'document');
      expect(safe('   '), 'document');
      expect(safe('...'), 'document');
      expect(safe('.hidden.html'), 'hidden.html');
    });

    test('a plain Latin name is left alone', () {
      expect(safe('QuestionPaper.html'), 'QuestionPaper.html');
      expect(safe('Physics_First.html'), 'Physics_First.html');
    });
  });
}
