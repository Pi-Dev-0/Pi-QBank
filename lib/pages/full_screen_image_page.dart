import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';

class FullScreenImagePage extends StatelessWidget {
  final String? base64Image;
  final String? imagePath;

  const FullScreenImagePage({
    super.key,
    this.base64Image,
    this.imagePath,
  });

  @override
  Widget build(BuildContext context) {
    Widget imageWidget;
    if (base64Image != null) {
      imageWidget = Image.memory(base64Decode(base64Image!));
    } else if (imagePath != null) {
      imageWidget = Image.file(File(imagePath!));
    } else {
      imageWidget = const Center(child: Text('No image to display.'));
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Center(
        child: InteractiveViewer(
          panEnabled: true, // Set to false to disable pan
          minScale: 0.5,
          maxScale: 4.0,
          child: imageWidget,
        ),
      ),
    );
  }
}
