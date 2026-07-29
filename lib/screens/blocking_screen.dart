import 'package:flutter/material.dart';
import 'package:testproject/screens/shorts_blocking_screen.dart';
import 'package:testproject/screens/websites_blocking_screen.dart';

class BlockingScreen extends StatefulWidget {
  const BlockingScreen({super.key});

  @override
  State<BlockingScreen> createState() => _BlockingScreenState();
}

class _BlockingScreenState extends State<BlockingScreen> {
  void _showInfoDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text("Websites Blocking"),
        content: const Text(
          "Choose specific websites to block in your mobile browser when active protection is enabled.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Got it"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Section
              const Text(
                'Blocking',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Completely block specific locations inside configured apps to avoid distractions while using them.',
                style: TextStyle(
                  fontSize: 14,
                  color: Color(0xFF6B7280),
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 28),

              // Shorts Section
              const Text(
                'Shorts',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Limit short-form content by blocking Reels, Shorts and Stories in Instagram, YouTube, Facebook and Snapchat',
                style: TextStyle(
                  fontSize: 13,
                  color: Color(0xFF6B7280),
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 12),

              _buildOptionCard(
                icon: Icons.play_circle_fill_rounded,
                title: 'Set Shorts Blocking',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ShortsBlockingScreen(),
                    ),
                  );
                },
              ),
              const SizedBox(height: 28),

              // Websites Section
              Row(
                children: [
                  const Text(
                    'Websites',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: () => _showInfoDialog(context),
                    child: const Icon(
                      Icons.info_outline_rounded,
                      color: Colors.black,
                      size: 20,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                'Limit distracting websites by blocking specific links in your mobile browser.',
                style: TextStyle(
                  fontSize: 13,
                  color: Color(0xFF6B7280),
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 12),

              _buildOptionCard(
                icon: Icons.language_rounded,
                title: 'Set Websites Blocking',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const WebsitesBlockingScreen(),
                    ),
                  );
                },
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOptionCard({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16.0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16.0),
          border: Border.all(
            color: const Color(0xFFE5E7EB),
            width: 1.0,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(12.0),
              ),
              child: Icon(icon, color: Colors.black87, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.black,
                ),
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: Color(0xFF9CA3AF),
              size: 22,
            ),
          ],
        ),
      ),
    );
  }
}
