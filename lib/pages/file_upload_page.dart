import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import '../widgets/custom_app_bar.dart';
import '../config/app_config.dart';

class FileUploadPage extends StatefulWidget {
  const FileUploadPage({super.key});

  @override
  FileUploadPageState createState() => FileUploadPageState();
}

class FileUploadPageState extends State<FileUploadPage>
    with TickerProviderStateMixin {
  // Add constant for max file size (25MB in bytes)
  static const int _maxFileSize = 25 * 1024 * 1024; // 25MB in bytes

  bool _isUploading = false;
  PlatformFile? _selectedFile;
  String? _uploadStatus;
  late AnimationController _animationController;
  late AnimationController _pulseController;
  late AnimationController _scaleController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    
    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    
    _pulseAnimation = Tween<double>(
      begin: 1.0,
      end: 1.05,
    ).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ));
    
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.95,
    ).animate(CurvedAnimation(
      parent: _scaleController,
      curve: Curves.easeInOut,
    ));

    _pulseController.repeat(reverse: true);
  }

  @override
  void dispose() {
    _animationController.dispose();
    _pulseController.dispose();
    _scaleController.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    _scaleController.forward().then((_) => _scaleController.reverse());
    
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
      );

      if (result != null) {
        if (result.files.first.size > _maxFileSize) {
          setState(() {
            _uploadStatus = 'File size exceeds 25MB limit';
          });
          _clearStatus();
          return;
        }
        setState(() {
          _selectedFile = result.files.first;
        });
      }
    } catch (e) {
      debugPrint('Error picking file: $e');
    }
  }

  Future<void> _uploadFile() async {
    if (_selectedFile == null) {
      setState(() {
        _uploadStatus = 'Please select a file first';
      });
      _clearStatus();
      return;
    }

    // Double check file size before upload
    if (_selectedFile!.size > _maxFileSize) {
      setState(() {
        _uploadStatus = 'File size exceeds 10MB limit';
        _selectedFile = null;
      });
      _clearStatus();
      return;
    }

    setState(() {
      _isUploading = true;
      _uploadStatus = 'Uploading...';
    });

    try {
      final uri = Uri.parse(AppConfig.uploadBase);
      final request = http.MultipartRequest('POST', uri);

      // Add Uploadcare specific parameters
      request.fields['UPLOADCARE_PUB_KEY'] = AppConfig.fileUploadApi;
      request.fields['UPLOADCARE_STORE'] = '1';

      request.files.add(
        await http.MultipartFile.fromPath(
          'file',
          _selectedFile!.path!,
          filename: _selectedFile!.name,
        ),
      );

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        setState(() {
          _isUploading = false;
          _selectedFile = null; // Clear selected file
          _uploadStatus = 'File uploaded successfully!';
        });
        _clearStatus();
      } else {
        setState(() {
          _isUploading = false;
          _uploadStatus = 'Upload failed: ${response.statusCode}';
        });
      }
    } catch (e) {
      setState(() {
        _isUploading = false;
        _uploadStatus = 'Error uploading file: Something went wrong :-(';
      });
    }
  }

  void _clearStatus() {
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          _uploadStatus = null;
        });
      }
    });
  }

  String _getFileIcon(String? fileName) {
    if (fileName == null) return '📄';
    final extension = fileName.split('.').last.toLowerCase();
    switch (extension) {
      case 'pdf':
        return '📕';
      case 'doc':
      case 'docx':
        return '📘';
      case 'xls':
      case 'xlsx':
        return '📗';
      case 'ppt':
      case 'pptx':
        return '📙';
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
        return '🖼️';
      case 'mp3':
      case 'wav':
        return '🎵';
      case 'mp4':
      case 'avi':
        return '🎬';
      case 'zip':
      case 'rar':
        return '🗜️';
      default:
        return '📄';
    }
  }

  Widget _buildStatusMessage() {
    if (_uploadStatus == null) return const SizedBox();

    final isSuccess = _uploadStatus!.contains('successful');
    final isUploading = _uploadStatus!.contains('Uploading');
    
    // If currently uploading, the status is shown in the button area, so hide this message.
    if (isUploading) return const SizedBox();

    Color backgroundColor;
    Color iconColor;
    IconData icon;
    
    if (isSuccess) {
      backgroundColor = const Color(0xFF4CAF50).withOpacity(0.1);
      iconColor = const Color(0xFF4CAF50);
      icon = Icons.check_circle_rounded;
    } else { // This will now only be for error messages
      backgroundColor = const Color(0xFFFF5722).withOpacity(0.1);
      iconColor = const Color(0xFFFF5722);
      icon = Icons.error_rounded;
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutBack,
      margin: const EdgeInsets.symmetric(vertical: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: iconColor.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: iconColor.withOpacity(0.15),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconColor, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              _uploadStatus!,
              style: TextStyle(
                color: iconColor,
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
          ),
          // Removed the CircularProgressIndicator here as it's now handled in the button area
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const CustomAppBar(
        title: 'Upload File',
        centerTitle: true,
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFF8FAFF),
              Color(0xFFFFFFFF),
              Color(0xFFF0F8FF),
            ],
            stops: [0.0, 0.5, 1.0],
          ),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Guidelines Card
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      const Color(0xFF667EEA).withOpacity(0.1),
                      const Color(0xFF764BA2).withOpacity(0.05),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: const Color(0xFF667EEA).withOpacity(0.2),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF667EEA).withOpacity(0.1),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF667EEA).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.info_outline_rounded,
                        color: Color(0xFF667EEA),
                        size: 28,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Upload Guidelines',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        color: Color(0xFF2D3748),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      '📏 Maximum file size: 10MB\n📁 Supported files: All formats\n🔒 Files will be stored securely',
                      style: TextStyle(
                        color: Color(0xFF4A5568),
                        height: 1.6,
                        fontSize: 16,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 32),
              
              // File Selection Card
              AnimatedBuilder(
                animation: _scaleAnimation,
                builder: (context, child) {
                  return Transform.scale(
                    scale: _scaleAnimation.value,
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.08),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Card(
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: InkWell(
                          onTap: _pickFile,
                          borderRadius: BorderRadius.circular(24),
                          child: Container(
                            padding: const EdgeInsets.all(32),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(24),
                              gradient: _selectedFile != null
                                  ? LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [
                                        const Color(0xFF4CAF50).withOpacity(0.05),
                                        const Color(0xFF8BC34A).withOpacity(0.1),
                                      ],
                                    )
                                  : null,
                              border: Border.all(
                                color: _selectedFile != null
                                    ? const Color(0xFF4CAF50).withOpacity(0.3)
                                    : Colors.grey.withOpacity(0.2),
                                width: 2,
                              ),
                            ),
                            child: Column(
                              children: [
                                AnimatedBuilder(
                                  animation: _pulseAnimation,
                                  builder: (context, child) {
                                    return Transform.scale(
                                      scale: _selectedFile != null ? 1.0 : _pulseAnimation.value,
                                      child: Container(
                                        width: 80,
                                        height: 80,
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            begin: Alignment.topLeft,
                                            end: Alignment.bottomRight,
                                            colors: _selectedFile != null
                                                ? [
                                                    const Color(0xFF4CAF50),
                                                    const Color(0xFF8BC34A),
                                                  ]
                                                : [
                                                    const Color(0xFF667EEA),
                                                    const Color(0xFF764BA2),
                                                  ],
                                          ),
                                          borderRadius: BorderRadius.circular(20),
                                          boxShadow: [
                                            BoxShadow(
                                              color: (_selectedFile != null
                                                      ? const Color(0xFF4CAF50)
                                                      : const Color(0xFF667EEA))
                                                  .withOpacity(0.3),
                                              blurRadius: 15,
                                              offset: const Offset(0, 5),
                                            ),
                                          ],
                                        ),
                                        child: _selectedFile != null
                                            ? Center(
                                                child: Text(
                                                  _getFileIcon(_selectedFile!.name),
                                                  style: const TextStyle(fontSize: 32),
                                                ),
                                              )
                                            : const Icon(
                                                Icons.cloud_upload_rounded,
                                                size: 40,
                                                color: Colors.white,
                                              ),
                                      ),
                                    );
                                  },
                                ),
                                const SizedBox(height: 24),
                                Text(
                                  _selectedFile != null
                                      ? _selectedFile!.name
                                      : 'Tap to select a file',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                    color: _selectedFile != null
                                        ? const Color(0xFF4CAF50)
                                        : const Color(0xFF2D3748),
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                if (_selectedFile != null) ...[
                                  const SizedBox(height: 12),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF4CAF50).withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      'Size: ${(_selectedFile!.size / 1024).toStringAsFixed(2)} KB',
                                      style: const TextStyle(
                                        color: Color(0xFF4CAF50),
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
              
              const SizedBox(height: 32),
              
              // Upload Button / Uploading Indicator
              if (_selectedFile != null)
                _isUploading
                    ? Container(
                        margin: const EdgeInsets.only(top: 16),
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        decoration: BoxDecoration(
                          color: Colors.blueAccent, /* Primary color for uploading state */
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.blueAccent.withOpacity(0.3),
                              blurRadius: 20,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              height: 24,
                              width: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                              ),
                            ),
                            SizedBox(width: 16),
                            Text(
                              'Uploading...',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      )
                    : Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF667EEA).withOpacity(0.3),
                              blurRadius: 20,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: ElevatedButton(
                          onPressed: _uploadFile,
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 20),
                            elevation: 0,
                            backgroundColor: Colors.deepPurple,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.cloud_upload_rounded,
                                size: 24,
                              ),
                              SizedBox(width: 12),
                              Text(
                                'Upload File',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
              
              // Status Message
              _buildStatusMessage(),
            ],
          ),
        ),
      ),
    );
  }
}
