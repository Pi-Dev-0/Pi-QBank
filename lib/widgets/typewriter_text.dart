import 'dart:async';
import 'package:flutter/material.dart';

class TypewriterText extends StatefulWidget {
  final String text;
  final Duration speed;

  const TypewriterText({
    super.key,
    required this.text,
    this.speed = const Duration(milliseconds: 200),
  });

  @override
  State<TypewriterText> createState() => _TypewriterTextState();
}

class _TypewriterTextState extends State<TypewriterText> {
  String _displayedText = '';
  int _currentIndex = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startTypewriterEffect();
  }

  void _startTypewriterEffect() {
    _timer = Timer.periodic(widget.speed, (timer) {
      if (!mounted) {
        _timer?.cancel();
        return;
      }
      setState(() {
        if (_currentIndex < widget.text.length) {
          _displayedText += widget.text[_currentIndex];
          _currentIndex++;
        } else {
          _displayedText = '';
          _currentIndex = 0;
        }
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      _displayedText,
      style: const TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.bold,
        color: Colors.blueAccent,
      ),
    );
  }
}