import 'package:flutter_test/flutter_test.dart';

import 'package:pi_qbank/config/app_config.dart';
import 'package:pi_qbank/services/highschool_qbank_service.dart';

void main() {
  group('Apps Script endpoint', () {
    test('has a usable default, so every target builds without a define', () {
      // This is the Linux regression: the value used to default to '', so a
      // plain `flutter build linux` shipped a generator that could not fetch.
      expect(AppConfig.highSchoolQBankApi, isNotEmpty);
      final uri = Uri.tryParse(AppConfig.highSchoolQBankApi);
      expect(uri, isNotNull);
      expect(uri!.scheme, 'https');
      expect(uri.host, isNotEmpty);
      expect(uri.path, endsWith('/exec'));
    });
  });

  group('URL guard', () {
    test('an empty endpoint fails with a clear, specific error', () {
      const service = HighSchoolQBankService(scriptUrl: '');
      expect(
        () => service.buildRequestUriForTest({'action': 'getQuestions'}),
        throwsA(isA<QBankNotConfiguredException>()),
      );
    });

    test('a scheme-less or non-http endpoint is rejected too', () {
      // Uri.parse('') plus query parameters yields a relative URI, which is
      // what used to reach dart:io and surface "Only HTTP and HTTPS URLs...".
      for (final bad in ['   ', 'not a url', '/relative/path', 'ftp://x/y']) {
        final service = HighSchoolQBankService(scriptUrl: bad);
        expect(
          () => service.buildRequestUriForTest({'a': 'b'}),
          throwsA(isA<QBankNotConfiguredException>()),
          reason: 'should reject ${bad.isEmpty ? '<blank>' : bad}',
        );
      }
    });

    test('a valid endpoint produces a URI carrying the query parameters', () {
      const service = HighSchoolQBankService(
        scriptUrl: 'https://example.com/macros/s/abc/exec',
      );
      final uri = service.buildRequestUriForTest({
        'action': 'getQuestions',
        'class': 'Class 6',
      });
      expect(uri.scheme, 'https');
      expect(uri.host, 'example.com');
      expect(uri.queryParameters['action'], 'getQuestions');
      expect(uri.queryParameters['class'], 'Class 6');
    });

    test('query parameters are encoded, not concatenated', () {
      const service =
          HighSchoolQBankService(scriptUrl: 'https://example.com/exec');
      final uri = service.buildRequestUriForTest({'chapters': '1,2,3'});
      expect(uri.queryParameters['chapters'], '1,2,3');
      expect(uri.query, contains('%2C'));
    });
  });
}
