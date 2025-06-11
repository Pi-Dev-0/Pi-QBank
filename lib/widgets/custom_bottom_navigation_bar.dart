import 'package:flutter/material.dart';
import 'dart:ui';

class CustomBottomNavigationBar extends StatefulWidget {
  final int currentPageIndex;
  final ValueChanged<int> onPageSelected;
  final List<List<Color>> navGradients;

  const CustomBottomNavigationBar({
    super.key,
    required this.currentPageIndex,
    required this.onPageSelected,
    required this.navGradients,
  });

  @override
  State<CustomBottomNavigationBar> createState() => _CustomBottomNavigationBarState();
}

class _CustomBottomNavigationBarState extends State<CustomBottomNavigationBar>
    with TickerProviderStateMixin {
  late AnimationController _animationController;
  late AnimationController _scaleController;
  late Animation<double> _curveAnimation;
  late Animation<double> _scaleAnimation;
  
  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    
    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );

    _curveAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.elasticOut,
    );
    
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 1.2,
    ).animate(CurvedAnimation(
      parent: _scaleController,
      curve: Curves.elasticOut,
    ));
  }

  @override
  void didUpdateWidget(CustomBottomNavigationBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentPageIndex != widget.currentPageIndex) {
      _animationController.forward(from: 0);
      _scaleController.forward().then((_) {
        _scaleController.reverse();
      });
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    _scaleController.dispose();
    super.dispose();
  }

  Widget _buildNavItem(IconData icon, String label, bool isSelected,
      List<Color> gradientColors, int index) {
    return AnimatedBuilder(
      animation: Listenable.merge([_curveAnimation, _scaleAnimation]),
      builder: (context, child) {
        double scale = isSelected ? _scaleAnimation.value : 1.0;
        double curveOffset = 0.0;
        
        if (isSelected && _animationController.isAnimating) {
          curveOffset = 15 * _curveAnimation.value * (1 - _curveAnimation.value) * 4;
        }

        return Transform.scale(
          scale: scale,
          child: Transform.translate(
            offset: Offset(0, -curveOffset),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16), // Adjusted padding
              decoration: isSelected
                  ? BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      gradient: LinearGradient(
                        colors: gradientColors,
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: gradientColors[0].withOpacity(0.4),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                          spreadRadius: 2,
                        ),
                      ],
                    )
                  : null,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                    child: Icon(
                      icon,
                      size: isSelected ? 28 : 22, // Adjusted icon size
                      color: isSelected 
                          ? Colors.white 
                          : gradientColors[0].withOpacity(0.7),
                    ),
                  ),
                  const SizedBox(height: 4),
                  AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                    style: TextStyle(
                      fontSize: isSelected ? 10 : 8, // Adjusted font size
                      color: isSelected
                          ? Colors.white
                          : gradientColors[0].withOpacity(0.8),
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    ),
                    child: Text(label),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          height: MediaQuery.of(context).size.height * 0.09,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.15),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
            border: Border.all(
              color: Colors.white.withOpacity(0.2),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            children: [
              // Online Class
              Expanded(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(30),
                    onTap: () => widget.onPageSelected(0),
                    child: Center(
                      child: _buildNavItem(
                        Icons.ondemand_video, 
                        'Classes',
                        widget.currentPageIndex == 0, 
                        widget.navGradients[0],
                        0,
                      ),
                    ),
                  ),
                ),
              ),
              // Blog
              Expanded(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(30),
                    onTap: () => widget.onPageSelected(1),
                    child: Center(
                      child: _buildNavItem(
                        Icons.article_outlined, 
                        'Blog',
                        widget.currentPageIndex == 1, 
                        widget.navGradients[1],
                        1,
                      ),
                    ),
                  ),
                ),
              ),
              // Home
              Expanded(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(30),
                    onTap: () => widget.onPageSelected(2),
                    child: Center(
                      child: _buildNavItem(
                        Icons.home, 
                        'Home',
                        widget.currentPageIndex == 2, 
                        widget.navGradients[2],
                        2,
                      ),
                    ),
                  ),
                ),
              ),
              // Tools
              Expanded(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(30),
                    onTap: () => widget.onPageSelected(3),
                    child: Center(
                      child: _buildNavItem(
                        Icons.build_circle_outlined, 
                        'Tools',
                        widget.currentPageIndex == 3, 
                        widget.navGradients[3],
                        3,
                      ),
                    ),
                  ),
                ),
              ),
              // AI
              Expanded(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(30),
                    onTap: () => widget.onPageSelected(4),
                    child: Center(
                      child: _buildNavItem(
                        Icons.psychology, 
                        'AI',
                        widget.currentPageIndex == 4, 
                        widget.navGradients[4],
                        4,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
