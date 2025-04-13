import 'package:flutter/material.dart';
import 'dart:async';
import '../widgets/custom_app_bar.dart';
import 'package:provider/provider.dart';
import '../services/connectivity_service.dart';
import '../widgets/connectivity_wrapper.dart';

class FileUploadPage extends StatefulWidget {
  const FileUploadPage({super.key});

  @override
  FileUploadPageState createState() => FileUploadPageState();
}

class FileUploadPageState extends State<FileUploadPage> {
  final FileIOUploadService _uploadService = FileIOUploadService();
  bool _isUploading = false;
  bool _isLoading = false;
  bool _showSuccess = false;
  FileUploadResult? _selectedFile;
  Timer? _successTimer;

  @override
  void dispose() {
    _successTimer?.cancel();
    super.dispose();
  }

  Future<void> _selectFile() async {
    setState(() {
      _isLoading = true;
    });
    try {
      final file = await _uploadService.selectFile();
      setState(() {
        _selectedFile = file;
        _isLoading = false;
      });
    } on FileSizeExceededException catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        _showErrorBox(e.toString());
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        _showErrorBox('An error occurred: $e');
      }
    }
  }

  Future<void> _uploadFile() async {
    if (_selectedFile == null) return;

    // Capture context-dependent services before async operations
    final connectivityService =
        Provider.of<ConnectivityService>(context, listen: false);

    try {
      await connectivityService.initConnectivity();

      if (!connectivityService.isOnline) {
        // Use a null-aware context check
        if (mounted) {
          ConnectivityWrapper.showOnRetry(context);
        }
        return;
      }

      setState(() {
        _isUploading = true;
        _showSuccess = false;
      });

      final result = await _uploadService.uploadFile(_selectedFile!);

      if (result != null && result.containsKey('file')) {
        setState(() {
          _selectedFile = null;
          _showSuccess = true;
        });

        // Cancel any existing timer
        _successTimer?.cancel();

        // Set new timer for 3 seconds
        _successTimer = Timer(const Duration(seconds: 3), () {
          if (mounted) {
            setState(() {
              _showSuccess = false;
            });
          }
        });
      }
    } catch (e) {
      // Ensure context is still valid before showing error
      if (mounted) {
        _showErrorBox('An error occurred: $e');
      }
    } finally {
      // Reset uploading state if widget is still mounted
      if (mounted) {
        setState(() {
          _isUploading = false;
        });
      }
    }
  }

  void _showErrorBox(String message) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.red.withOpacity(0.1),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.error_outline,
                    color: Colors.red.shade700,
                    size: 32,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'File Size Error',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.red.shade700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 20),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: TextButton.styleFrom(
                    backgroundColor: Colors.red.shade50,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(
                    'OK',
                    style: TextStyle(
                      color: Colors.red.shade700,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void showPrivacyPolicy() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.privacy_tip, color: Colors.blue.shade700),
              const SizedBox(width: 8),
              const Text('Privacy Policy'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildPolicySection(
                  'File Upload Services',
                  [
                    'We use file.io to temporarily store files you upload',
                    'When you upload files, they are transmitted to file.io\'s servers',
                    'We only accept PDF and image files (jpg, jpeg, png, gif)',
                    'Files are automatically deleted from file.io\'s servers after a short period',
                  ],
                ),
                const SizedBox(height: 16),
                _buildPolicySection(
                  'Third-Party Services',
                  [
                    'Our app integrates with file.io (File Hosting Service):',
                    '• Purpose: Temporary file storage and transfer',
                    '• Data shared: User-uploaded files',
                    '• Data retention: Files are temporarily stored',
                  ],
                ),
                const SizedBox(height: 16),
                _buildPolicySection(
                  'User Rights',
                  [
                    'You have the right to:',
                    '• Know how your uploaded files are processed',
                    '• Request information about file storage duration',
                    '• Understand that files are subject to file.io\'s terms',
                  ],
                ),
                const SizedBox(height: 16),
                _buildPolicySection(
                  'Security Measures',
                  [
                    'To protect your uploaded files:',
                    '• We use secure HTTPS connections',
                    '• Files are only temporarily stored',
                    '• We limit file types to PDFs and images',
                    '• We implement file size restrictions',
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildPolicySection(String title, List<String> points) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.blue.shade700,
          ),
        ),
        const SizedBox(height: 8),
        ...points.map((point) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(point),
            )),
      ],
    );
  }

  Widget _buildFilePreview() {
    if (_selectedFile == null) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.file_upload_outlined, size: 48, color: Colors.grey),
            SizedBox(height: 8),
            Text('No file selected', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.insert_drive_file, color: Colors.blue.shade700),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _selectedFile!.fileName,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.blue.shade700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Size: ${(_selectedFile!.fileSize / 1024).toStringAsFixed(2)} KB',
            style: TextStyle(color: Colors.blue.shade700),
          ),
        ],
      ),
    );
  }

  Widget _buildInstructionItem({
    required IconData icon,
    required String text,
  }) {
    return Row(
      children: [
        Icon(
          icon,
          size: 20,
          color: Colors.blue.shade600,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: Colors.blue.shade700,
              fontSize: 14,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CustomAppBar(
        title: 'Upload File',
        centerTitle: true,
        actions: [
          IconButton(
            onPressed: showPrivacyPolicy,
            icon: Icon(Icons.privacy_tip),
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                margin: const EdgeInsets.only(bottom: 24),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.shade200),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.blue.withOpacity(0.1),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          color: Colors.blue.shade700,
                          size: 24,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Instructions:',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue.shade700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _buildInstructionItem(
                      icon: Icons.description_outlined,
                      text: 'Upload PDF or Image files only',
                    ),
                    const SizedBox(height: 8),
                    _buildInstructionItem(
                      icon: Icons.file_copy_outlined,
                      text: 'Maximum file size: 25MB',
                    ),
                    const SizedBox(height: 8),
                    _buildInstructionItem(
                      icon: Icons.warning_amber_outlined,
                      text:
                          'Please don\'t close this page until upload is complete',
                    ),
                  ],
                ),
              ),
              _buildFilePreview(),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _isLoading ? null : _selectFile,
                      icon: const Icon(Icons.file_upload),
                      label: const Text('Select File'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _selectedFile == null || _isUploading
                          ? null
                          : _uploadFile,
                      icon: const Icon(Icons.cloud_upload),
                      label: Text(_isUploading ? 'Uploading...' : 'Upload'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        backgroundColor: Theme.of(context).primaryColor,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              if (_isUploading)
                Column(
                  children: const [
                    SizedBox(height: 24),
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text(
                      'Uploading your file...',
                      style: TextStyle(
                        color: Colors.blue,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              if (_isLoading)
                Column(
                  children: const [
                    SizedBox(height: 24),
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text(
                      'Loading file...',
                      style: TextStyle(
                        color: Colors.blue,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              if (_showSuccess)
                Container(
                  margin: const EdgeInsets.only(top: 24),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.green.shade200),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.green.withOpacity(0.1),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Icon(
                        Icons.check_circle_outline,
                        color: Colors.green.shade700,
                        size: 48,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Upload Successful!',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.green.shade700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Your file has been successfully uploaded to our servers.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.green.shade600,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
