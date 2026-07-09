import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controller/onboarding_controller.dart';

class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.put(OnboardingController());

    return Scaffold(
      backgroundColor: const Color(0xFF0F0E17), // Premium dark theme
      body: SafeArea(
        child: Obx(() {
          if (controller.isLoading.value) {
            return const Center(child: CircularProgressIndicator(color: Colors.deepPurpleAccent));
          }
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 32),
                // App Logo or Header
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.deepPurpleAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(
                    Icons.settings_suggest_rounded,
                    color: Colors.deepPurpleAccent,
                    size: 32,
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Welcome to Device Hub',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'To monitor app limits and keep your focus on track, we need a few permissions. Grant these steps to get started.',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade400,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 32),
                // Steps List
                Expanded(
                  child: ListView(
                    children: [
                      _buildStepItem(
                        stepNumber: 1,
                        title: 'Notification Alert',
                        description: 'Allows background service alerts when limits are set.',
                        isGranted: controller.hasNotificationPermission.value,
                        onTap: controller.requestNotification,
                      ),
                      const SizedBox(height: 16),
                      _buildStepItem(
                        stepNumber: 2,
                        title: 'Usage Statistics',
                        description: 'Tracks app screen time to calculate daily limit metrics.',
                        isGranted: controller.hasUsagePermission.value,
                        onTap: controller.requestUsage,
                      ),
                      const SizedBox(height: 16),
                      _buildStepItem(
                        stepNumber: 3,
                        title: 'Draw Over Apps',
                        description: 'Creates overlay window to block apps once limits expire.',
                        isGranted: controller.hasOverlayPermission.value,
                        onTap: controller.requestOverlay,
                      ),
                      const SizedBox(height: 16),
                      _buildStepItem(
                        stepNumber: 4,
                        title: 'Accessibility Service (Optional)',
                        description: 'Monitors app window state changes to detect app launches instantly.',
                        isGranted: controller.hasAccessibilityPermission.value,
                        onTap: controller.requestAccessibility,
                      ),
                    ],
                  ),
                ),
                // Action button
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: controller.allPermissionsGranted ? controller.finishSetup : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepPurpleAccent,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.grey.shade800,
                      disabledForegroundColor: Colors.grey.shade500,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Text(
                      controller.allPermissionsGranted ? 'Let\'s Go!' : 'Complete All Steps',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _buildStepItem({
    required int stepNumber,
    required String title,
    required String description,
    required bool isGranted,
    required VoidCallback onTap,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF1F1D2B),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isGranted ? Colors.green.withValues(alpha: 0.3) : Colors.grey.shade800,
          width: 1.5,
        ),
      ),
      child: Row(
        children: [
          // Step circle badge
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: isGranted ? Colors.green.withValues(alpha: 0.15) : Colors.deepPurpleAccent.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: isGranted
                  ? const Icon(Icons.check_rounded, color: Colors.green, size: 20)
                  : Text(
                      '$stepNumber',
                      style: const TextStyle(
                        color: Colors.deepPurpleAccent,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 16),
          // Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    color: Colors.grey.shade400,
                    fontSize: 12,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Action button or Text
          isGranted
              ? Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'Granted',
                    style: TextStyle(
                      color: Colors.green,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                )
              : ElevatedButton(
                  onPressed: onTap,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurpleAccent.withValues(alpha: 0.15),
                    foregroundColor: Colors.deepPurpleAccent,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text(
                    'Grant',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
        ],
      ),
    );
  }
}
