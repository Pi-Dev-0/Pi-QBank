import 'dart:convert';
import 'dart:io';

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
