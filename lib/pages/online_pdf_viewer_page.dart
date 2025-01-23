import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:logger/logger.dart';

class OnlinePDFViewerPage extends StatefulWidget {
  final String pdfUrl;
  final String title;

  const OnlinePDFViewerPage({
    super.key,
    required this.pdfUrl,
    required this.title,
  });

  @override
  OnlinePDFViewerPageState createState() => OnlinePDFViewerPageState();
}

class OnlinePDFViewerPageState extends State<OnlinePDFViewerPage> {
  String? _localFilePath;
  bool _isLoading = true;
  double _downloadProgress = 0.0;
  final Logger _logger = Logger();

  @override
  void initState() {
    super.initState();
    _downloadAndSavePDF();
  }

  Future<void> _downloadAndSavePDF() async {
    try {
      // Get the file size first
      final headResponse = await http.head(Uri.parse(widget.pdfUrl));
      final totalBytes = int.tryParse(headResponse.headers['content-length'] ?? '0') ?? 0;

      // Download the PDF
      final client = http.Client();
      final request = http.Request('GET', Uri.parse(widget.pdfUrl));
      final streamedResponse = await client.send(request);
      
      // Prepare file for writing
      final directory = await getTemporaryDirectory();
      final filePath = '${directory.path}/${widget.title}.pdf';
      final file = File(filePath);
      final fileWriter = file.openWrite();

      // Track download progress
      int receivedBytes = 0;
      await for (var chunk in streamedResponse.stream) {
        fileWriter.add(chunk);
        receivedBytes += chunk.length;
        
        setState(() {
          _downloadProgress = totalBytes > 0 
              ? receivedBytes / totalBytes 
              : 0.0;
        });
      }

      await fileWriter.close();
      client.close();

      setState(() {
        _localFilePath = filePath;
        _isLoading = false;
        _downloadProgress = 1.0;
      });
    } catch (e) {
      _logger.e('PDF Download Error: $e');
      _showErrorSnackBar('Error downloading PDF');
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
    setState(() {
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Text(
          widget.title,
          textAlign: TextAlign.center,
        ),
      ),
      body: _isLoading
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(
                    value: _downloadProgress,
                    backgroundColor: Colors.grey[300],
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Theme.of(context).primaryColor,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '${(_downloadProgress * 100).toStringAsFixed(0)}%',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
              ),
            )
          : _localFilePath != null
              ? PDFView(
                  filePath: _localFilePath!,
                  enableSwipe: true,
                  swipeHorizontal: false,
                  autoSpacing: false,
                  pageFling: true,
                  onError: (error) {
                    _logger.e('PDF View Error: $error');
                    _showErrorSnackBar('Error viewing PDF');
                  },
                  onPageError: (page, error) {
                    _logger.e('PDF Page Error on page $page: $error');
                  },
                )
              : Center(
                  child: Text('Unable to load PDF: ${widget.title}'),
                ),
    );
  }
}
