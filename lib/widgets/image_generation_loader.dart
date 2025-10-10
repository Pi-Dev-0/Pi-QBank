import 'package:flutter/material.dart';

class ImageGenerationLoader extends StatefulWidget {
  final double size;
  final Color color;

  const ImageGenerationLoader({
    super.key,
    this.size = 200.0,
    this.color = Colors.blue,
  });

  @override
  State<ImageGenerationLoader> createState() => _ImageGenerationLoaderState();
}

class _ImageGenerationLoaderState extends State<ImageGenerationLoader>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _rotationAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat();

    _rotationAnimation = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOutCubic,
      ),
    );

    _scaleAnimation = TweenSequence([
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 1.2),
        weight: 50,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.2, end: 1.0),
        weight: 50,
      ),
    ]).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOutCubic,
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return Transform.scale(
              scale: _scaleAnimation.value,
              child: Transform.rotate(
                angle: _rotationAnimation.value * 2 * 3.14159,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Icon(
                      Icons.auto_awesome,
                      size: widget.size * 0.3,
                      color: widget.color.withOpacity(0.5),
                    )
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
