import 'package:flutter/material.dart';
import 'package:pi_qbank/widgets/typewriter_text.dart'; // Import the new TypewriterText

class LoadingWidget extends StatelessWidget {
  final double progress;
  final String loadingText;

  const LoadingWidget({
    super.key,
    this.progress = 0,
    this.loadingText = 'Loading...',
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white, // Full screen white background during loading
      child: Stack(
        children: [
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Image.asset(
                  'assets/images/launcher.png', // Your logo from assets
                  width: 100,
                  height: 100,
                ),
                const SizedBox(height: 20),
                TypewriterText(text: loadingText),
              ],
            ),
          ),
          Positioned( // Position linear progress indicator at the top
            top: 0,
            left: 0,
            right: 0,
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: Colors.grey[200], // Background for the progress bar
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.blue),
            ),
          ),
        ],
      ),
    );
  }
}