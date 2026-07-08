import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:testproject/device_app/controller/notifications_controller.dart';
import 'package:testproject/device_app/controller/home_controller.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  String _formatTimestamp(int timestamp) {
    final now = DateTime.now();
    final time = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final difference = now.difference(time);

    if (difference.inSeconds < 60) {
      return "Just now";
    } else if (difference.inMinutes < 60) {
      return "${difference.inMinutes}m ago";
    } else if (difference.inHours < 24) {
      return "${difference.inHours}h ago";
    } else {
      return "${time.day}/${time.month} ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}";
    }
  }

  Widget _getAppIcon(String packageName, HomeController homeController) {
    final app = homeController.allApps.firstWhereOrNull((a) => a.packageName == packageName);
    if (app != null && app.icon != null) {
      return Image.memory(
        app.icon!,
        width: 32,
        height: 32,
        errorBuilder: (context, error, stackTrace) => const Icon(Icons.android, size: 32, color: Colors.grey),
      );
    }
    return const Icon(Icons.android, size: 32, color: Colors.grey);
  }

  String _getAppName(String packageName, HomeController homeController) {
    final app = homeController.allApps.firstWhereOrNull((a) => a.packageName == packageName);
    return app?.name ?? packageName;
  }

  @override
  Widget build(BuildContext context) {
    final controller = Get.put(NotificationsController());
    final homeController = Get.find<HomeController>();

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
          onPressed: () => Get.back(),
        ),
        title: const Text(
          "Notification Center",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20),
        ),
        actions: [
          Obx(() {
            if (controller.hasPermission.value && controller.notifications.isNotEmpty) {
              return IconButton(
                icon: const Icon(Icons.delete_sweep_outlined, color: Colors.redAccent, size: 26),
                onPressed: () {
                  Get.defaultDialog(
                    title: "Clear History?",
                    middleText: "This will delete all saved notification logs. This action cannot be undone.",
                    titleStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    middleTextStyle: const TextStyle(color: Colors.grey),
                    backgroundColor: Colors.grey[900],
                    textConfirm: "Clear",
                    textCancel: "Cancel",
                    confirmTextColor: Colors.white,
                    cancelTextColor: Colors.grey,
                    buttonColor: Colors.redAccent,
                    onConfirm: () {
                      controller.clearNotifications();
                      Get.back();
                    },
                  );
                },
              );
            }
            return const SizedBox.shrink();
          }),
        ],
      ),
      body: Obx(() {
        return Column(
          children: [
            // Status Toggle Switch
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF161427),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withOpacity(0.08)),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: SwitchListTile(
                  title: const Text(
                    "Notification Saver",
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                  subtitle: const Text(
                    "Intercept, dismiss from status bar, and save notifications locally.",
                    style: TextStyle(color: Colors.white60, fontSize: 11),
                  ),
                  activeColor: Colors.blueAccent,
                  value: controller.isSaverEnabled.value,
                  onChanged: (val) => controller.toggleSaver(val),
                ),
              ),
            ),

            const SizedBox(height: 8),

            // Main Content Area
            Expanded(
              child: _buildMainContent(context, controller, homeController),
            ),
          ],
        );
      }),
    );
  }

  Widget _buildMainContent(BuildContext context, NotificationsController controller, HomeController homeController) {
    if (!controller.hasPermission.value) {
      return Center(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.security_outlined,
                    color: Colors.redAccent,
                    size: 64,
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  "Notification Access Required",
                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                const Text(
                  "Android OS requires you to explicitly grant notification listener access so the launcher can save and clean notifications.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey, fontSize: 13, height: 1.5),
                ),
                const SizedBox(height: 28),
                ElevatedButton(
                  onPressed: () => controller.requestPermission(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                  child: const Text("Open System Settings", style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (controller.isLoading.value) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.blueAccent),
      );
    }

    if (controller.notifications.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.notifications_off_outlined, color: Colors.grey[700], size: 64),
            const SizedBox(height: 16),
            Text(
              "No saved notifications",
              style: TextStyle(color: Colors.grey[500], fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              "Intercepted notifications will appear here.",
              style: TextStyle(color: Colors.grey[700], fontSize: 12),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: controller.notifications.length,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemBuilder: (context, index) {
        final notif = controller.notifications[index];
        final String pkg = notif['packageName'] ?? '';
        final String title = notif['title'] ?? '';
        final String body = notif['body'] ?? '';
        final int timestamp = notif['timestamp'] ?? 0;

        final int notifId = notif['id'] ?? 0;

        return GestureDetector(
          onTap: () => controller.launchNotification(notifId, pkg),
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF161427),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withOpacity(0.08)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header (App Icon + App Name + Time)
                  Row(
                    children: [
                      _getAppIcon(pkg, homeController),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _getAppName(pkg, homeController),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.7),
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      Text(
                        _formatTimestamp(timestamp),
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.5),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  
                  // Content (Title + Body)
                  if (title.isNotEmpty) ...[
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 4),
                  ],
                  if (body.isNotEmpty) ...[
                    Text(
                      body,
                      style: const TextStyle(
                        color: Color(0xFFE2E2E2), // Crisp off-white for high contrast and readability
                        fontSize: 13,
                        height: 1.3,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
