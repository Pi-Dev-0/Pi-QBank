import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import '../config/app_config.dart';

class FileSizeExceededException implements Exception {
  final String message;
  FileSizeExceededException(this.message);

  @override
  String toString() => message;
}

class FileIOUploadService {
  final String baseUrl = 'https://file.io';
  late final String _apiKey;
  static const int _maxFileSize = 25 * 1024 * 1024; // 25 MB in bytes

  FileIOUploadService() {
    _apiKey = AppConfig.fileIoApiKey;
  }

  Future<FileUploadResult?> selectFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        withData: true,
        type: FileType.custom,
        allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png', 'gif'],
      );

      if (result == null || result.files.isEmpty) {
        return null;
      }

      // Check file size
      if (result.files.first.size > _maxFileSize) {
        throw FileSizeExceededException('File size exceeds 25 MB limit');
      }

      return FileUploadResult.fromPlatformFile(result.files.first);
    } on FileSizeExceededException {
      rethrow; // Re-throw this specific exception
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> uploadFile(FileUploadResult file) async {
    try {
      var request = http.MultipartRequest('POST', Uri.parse('$baseUrl/'));

      if (_apiKey.isNotEmpty) {
        request.headers['Authorization'] = 'Bearer $_apiKey';
      }

      request.files.add(
        await http.MultipartFile.fromPath(
          'file',
          file.path!,
          filename: file.fileName,
        ),
      );

      final response = await request.send();
      final responseString = await response.stream.bytesToString();
      final responseData = json.decode(responseString);

      if (response.statusCode == 200) {
        return responseData;
      }
      return null;
    } catch (e) {
      return null;
    }
  }
}

class FileUploadResult {
  final String fileName;
  final int fileSize;
  final String? path;
  final Uint8List? bytes;

  FileUploadResult({
    required this.fileName,
    required this.fileSize,
    this.path,
    this.bytes,
  });

  factory FileUploadResult.fromPlatformFile(PlatformFile? file) {
    return FileUploadResult(
      fileName: file?.name ?? '',
      fileSize: file?.size ?? 0,
      path: file?.path,
      bytes: file?.bytes,
    );
  }
}
