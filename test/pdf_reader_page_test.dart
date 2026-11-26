import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_qbank/pages/pdf_reader_page.dart';

void main() {
  group('LocalPdfItem', () {
    test('extracts clean display name and parent folder', () {
      final item = LocalPdfItem(
        file: File('/storage/emulated/0/Download/Biology_Chapter_1.pdf'),
        path: '/storage/emulated/0/Download/Biology_Chapter_1.pdf',
        fileName: 'Biology_Chapter_1.pdf',
        sizeInBytes: 1024 * 1024 * 3, // 3MB
        lastModified: DateTime(2024, 11, 20, 14, 30),
      );

      expect(item.displayName, 'Biology_Chapter_1');
      expect(item.parentFolder, 'Download');
      expect(item.sizeInBytes, 3 * 1024 * 1024);
    });

    test('handles files without .pdf extension gracefully', () {
      final item = LocalPdfItem(
        file: File('/storage/documents/my_document'),
        path: '/storage/documents/my_document',
        fileName: 'my_document',
        sizeInBytes: 500,
        lastModified: DateTime.now(),
      );

      expect(item.displayName, 'my_document');
      expect(item.parentFolder, 'documents');
    });

    test('ignores emulated or 0 as folder names', () {
      final item = LocalPdfItem(
        file: File('/storage/emulated/0/my_notes.pdf'),
        path: '/storage/emulated/0/my_notes.pdf',
        fileName: 'my_notes.pdf',
        sizeInBytes: 1000,
        lastModified: DateTime.now(),
      );

      expect(item.parentFolder, '');
    });
  });

  group('PdfSortOption', () {
    test('all enum values have valid non-empty labels', () {
      for (final sort in PdfSortOption.values) {
        expect(sort.label.isNotEmpty, true);
        expect(sort.icon, isNotNull);
      }
    });
  });
}
