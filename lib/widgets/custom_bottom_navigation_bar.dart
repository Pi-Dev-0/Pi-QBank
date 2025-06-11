import 'package:flutter/material.dart';
import 'dart:ui';

class CustomBottomNavigationBar extends StatelessWidget {
  final int currentPageIndex;
  final ValueChanged<int> onPageSelected;
  final List<List<Color>> navGradients;

  const CustomBottomNavigationBar({
    super.key,
    required this.currentPageIndex,
    required this.onPageSelected,
    required this.navGradients,
  });

  Widget _buildNavItem(IconData icon, String label, bool isSelected,
      List<Color> gradientColors) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
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
                  color: gradientColors[0].withOpacity(0.3),
                  blurRadius: 15,
                  offset: const Offset(0, 5),
                ),
              ],
            )
          : null,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 26,
            color:
                isSelected ? Colors.white : gradientColors[0].withOpacity(0.8),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 9,
              color: isSelected
                  ? Colors.white
                  : gradientColors[0].withOpacity(0.9),
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ],
      ),
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
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => onPageSelected(0),
                  child: _buildNavItem(Icons.ondemand_video, 'Online Class',
                      currentPageIndex == 0, navGradients[0]),
                ),
              ),
              Expanded(
                child: GestureDetector(
                  onTap: () => onPageSelected(1),
                  child: _buildNavItem(Icons.article_outlined, 'Blog',
                      currentPageIndex == 1, navGradients[1]),
                ),
              ),
              Expanded(
                child: GestureDetector(
                  onTap: () => onPageSelected(2),
                  child: _buildNavItem(
                      Icons.home, 'Home', currentPageIndex == 2, navGradients[2]),
                ),
              ),
              Expanded(
                child: GestureDetector(
                  onTap: () => onPageSelected(3),
                  child: _buildNavItem(Icons.build_circle_outlined, 'Tools',
                      currentPageIndex == 3, navGradients[3]),
                ),
              ),
              Expanded(
                child: GestureDetector(
                  onTap: () => onPageSelected(4),
                  child: _buildNavItem(
                      Icons.psychology, 'AI', currentPageIndex == 4, navGradients[4]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
