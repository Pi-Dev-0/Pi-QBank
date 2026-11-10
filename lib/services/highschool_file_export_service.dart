import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'highschool_export_service.dart';

/// Native file operations for the high-school exporter.
///
/// Kept outside [HighSchoolExportService] so the HTML generator can be reused
/// by the browser build without importing `dart:io` or native file plugins.
class HighSchoolFileExportService {
  static Future<File> saveFile({
    required String content,
    required String fileName,
    List<int>? bytes,
  }) async {
    final tempDir = await getTemporaryDirectory();
    final sanitizedName = HighSchoolExportService.safeFileName(fileName);
    final file = File('${tempDir.path}/$sanitizedName');
    if (bytes != null) {
      await file.writeAsBytes(bytes);
    } else {
      await file.writeAsString(content, encoding: utf8);
    }
    return file;
  }

  /// Let the reader choose a real location for an edited sheet.
  ///
  /// The ordinary [saveFile] writes into the app's temporary directory, which
  /// is right for "open this in a browser" but not for keeping a corrected
  /// paper. This opens the platform save dialog instead. A cancelled dialog
  /// returns null; the caller should leave the page untouched in that case.
  static Future<File?> saveFileAs({
    required String content,
    required String fileName,
  }) async {
    final safeName = HighSchoolExportService.safeFileName(fileName);
    final bytes = Uint8List.fromList(utf8.encode(content));
    final mobile = Platform.isAndroid || Platform.isIOS;
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'HTML সংরক্ষণ করুন',
      fileName: safeName,
      type: FileType.custom,
      allowedExtensions: const ['html'],
      bytes: mobile ? bytes : null,
    );
    if (path == null) return null;
    final file = File(path);
    // Android and iOS receive the bytes through the picker. The desktop
    // pickers only choose a path, so write the document here.
    if (!mobile) {
      await file.writeAsString(content, encoding: utf8);
    }
    return file;
  }

  static Future<void> openExportedFile(BuildContext context, File file) async {
    try {
      final result = await OpenFile.open(file.path);
      if (result.type != ResultType.done && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('ফাইলটি সরাসরি ওপেন করা যায়নি: ${result.message}'),
            backgroundColor: Colors.amber.shade800,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('ত্রুটি: $error'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  static Future<void> shareExportedFile(File file, {String? text}) async {
    await Share.shareXFiles(
      [XFile(file.path)],
      text: text ?? 'Pi-QBank Question Paper',
    );
  }
}
