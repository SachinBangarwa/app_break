import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:testproject/device_app/controller/home_controller.dart';
import 'package:testproject/screens/blocking_screen.dart';
import 'package:testproject/screens/focus_screen.dart';
import 'package:testproject/screens/overview_screen.dart';
import 'package:testproject/screens/pause_screen.dart';

class MainTabScreen extends StatefulWidget {
  final int initialIndex;
  const MainTabScreen({super.key, this.initialIndex = 0});

  @override
  State<MainTabScreen> createState() => _MainTabScreenState();
}

class _MainTabScreenState extends State<MainTabScreen> {
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    if (!Get.isRegistered<HomeController>()) {
      Get.put(HomeController(), permanent: true);
    }
  }

  void _onTabSelected(int index) {
    if (_currentIndex == index) return;
    setState(() {
      _currentIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _currentIndex == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _currentIndex != 0) {
          setState(() {
            _currentIndex = 0;
          });
        }
      },
      child: Scaffold(
        body: IndexedStack(
          index: _currentIndex,
          children: const [
            OverviewScreen(), // Index 0: Overview
            PauseScreen(),    // Index 1: Pause
            BlockingScreen(), // Index 2: Blocking
            _PlaceholderTabScreen(title: 'Portal'), // Index 3: Portal
            FocusScreen(),    // Index 4: Focus
          ],
        ),

        // Bottom Navigation Bar
        bottomNavigationBar: SafeArea(
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(
                top: BorderSide(color: Color(0xFFE5E7EB), width: 1.0),
              ),
            ),
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildNavItem(
                  index: 0,
                  icon: Icons.access_time_rounded,
                  label: 'Overview',
                ),
                _buildNavItem(
                  index: 1,
                  icon: Icons.pause_circle_filled_rounded,
                  label: 'Pause',
                ),
                _buildNavItem(
                  index: 2,
                  icon: Icons.block_rounded,
                  label: 'Blocking',
                ),
                _buildNavItem(
                  index: 3,
                  icon: Icons.history_rounded,
                  label: 'Portal',
                ),
                _buildNavItem(
                  index: 4,
                  icon: Icons.track_changes_rounded,
                  label: 'Focus',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required int index,
    required IconData icon,
    required String label,
  }) {
    final bool isSelected = _currentIndex == index;
    final Color itemColor = isSelected ? Colors.black : const Color(0xFF6F6F6F);

    return InkWell(
      onTap: () => _onTabSelected(index),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: itemColor, size: 24),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              color: itemColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _PlaceholderTabScreen extends StatelessWidget {
  final String title;
  const _PlaceholderTabScreen({required this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      body: SafeArea(
        child: Center(
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
          ),
        ),
      ),
    );
  }
}
