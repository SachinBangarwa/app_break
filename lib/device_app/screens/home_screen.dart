import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:installed_apps/app_info.dart';
import 'package:installed_apps/installed_apps.dart';
import 'package:testproject/device_app/screens/device_apps_screen.dart';
import 'package:testproject/device_app/controller/home_controller.dart';
import 'package:testproject/device_app/screens/notifications_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  String _formatDate(DateTime currentTime) {
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    
    final day = weekdays[currentTime.weekday - 1];
    final month = months[currentTime.month - 1];
    return '$day, $month ${currentTime.day}';
  }

  String _formatTime(DateTime currentTime) {
    final hour = currentTime.hour.toString().padLeft(2, '0');
    final minute = currentTime.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  void _showAppOptions(BuildContext context, AppInfo app, HomeController controller) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1F1D2B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              // App details header
              ListTile(
                leading: app.icon != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.memory(app.icon!, width: 48, height: 48),
                      )
                    : const CircleAvatar(child: Icon(Icons.android)),
                title: Text(
                  app.name,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                ),
                subtitle: Text(
                  app.packageName,
                  style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
                ),
              ),
              const Divider(color: Colors.white12),
              // Favorite / Shortcut toggle option
              ListTile(
                leading: Icon(
                  controller.desktopApps.any((element) => element.packageName == app.packageName)
                      ? Icons.star_rounded
                      : Icons.star_outline_rounded,
                  color: Colors.amber,
                ),
                title: Text(
                  controller.desktopApps.any((element) => element.packageName == app.packageName)
                      ? 'Remove from Favorites'
                      : 'Add to Favorites',
                  style: const TextStyle(color: Colors.white),
                ),
                onTap: () {
                  Navigator.pop(context);
                  controller.toggleFavorite(app.packageName);
                },
              ),
              // Set limit option
              ListTile(
                leading: const Icon(Icons.hourglass_empty_rounded, color: Colors.deepPurpleAccent),
                title: const Text('Set Screen Time Limit', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  _showLimitSetupDialog(context, app, controller);
                },
              ),
              // Set delay option
              ListTile(
                leading: const Icon(Icons.av_timer_rounded, color: Colors.deepPurpleAccent),
                title: const Text('Set Mindful Delay', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  _showDelaySetupDialog(context, app, controller);
                },
              ),
              // App Info option
              ListTile(
                leading: const Icon(Icons.info_outline, color: Colors.blueAccent),
                title: const Text('System App Info', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  InstalledApps.openSettings(app.packageName);
                },
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  void _showLimitSetupDialog(BuildContext context, AppInfo app, HomeController controller) async {
    final currentLimitMs = controller.limitsMap[app.packageName] ?? 0;
    int currentLimitMinutes = currentLimitMs > 0 ? (currentLimitMs / 60000).round() : 0;

    final selectedMinutes = await showDialog<int>(
      context: context,
      builder: (context) {
        int tempLimit = currentLimitMinutes;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1F1D2B),
              title: Text(
                'Set Limit for ${app.name}',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Select daily screen time limit for this app:',
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                  const SizedBox(height: 24),
                  DropdownButton<int>(
                    value: tempLimit,
                    dropdownColor: const Color(0xFF1F1D2B),
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                    iconEnabledColor: Colors.deepPurpleAccent,
                    underline: Container(height: 2, color: Colors.deepPurpleAccent),
                    isExpanded: true,
                    items: const [
                      DropdownMenuItem(value: 0, child: Text('No Limit (Disabled)')),
                      DropdownMenuItem(value: 1, child: Text('1 Minute (For Testing)')),
                      DropdownMenuItem(value: 5, child: Text('5 Minutes')),
                      DropdownMenuItem(value: 15, child: Text('15 Minutes')),
                      DropdownMenuItem(value: 30, child: Text('30 Minutes')),
                      DropdownMenuItem(value: 60, child: Text('1 Hour')),
                      DropdownMenuItem(value: 120, child: Text('2 Hours')),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setDialogState(() {
                          tempLimit = val;
                        });
                      }
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, tempLimit),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurpleAccent),
                  child: const Text('Save Limit', style: TextStyle(color: Colors.white)),
                ),
              ],
            );
          },
        );
      },
    );

    if (selectedMinutes != null) {
      final newLimitMs = selectedMinutes * 60000;
      await controller.updateAppLimit(app.packageName, newLimitMs, app.name);

      Get.snackbar(
        'Limit Saved',
        newLimitMs > 0 
          ? 'Limit set to $selectedMinutes min for ${app.name}' 
          : 'Limit removed for ${app.name}',
        backgroundColor: Colors.green,
        colorText: Colors.white,
        snackPosition: SnackPosition.BOTTOM,
      );
    }
  }

  void _showDelaySetupDialog(BuildContext context, AppInfo app, HomeController controller) async {
    final currentEnabled = controller.delayEnabledMap[app.packageName] ?? false;
    final currentSeconds = controller.delaySecondsMap[app.packageName] ?? 10;

    await showDialog(
      context: context,
      builder: (context) {
        bool tempEnabled = currentEnabled;
        int tempSeconds = currentSeconds;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1F1D2B),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Text(
                'Mindful Delay: ${app.name}',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Enable a mindful countdown delay overlay before this app launches to help reduce impulsive openings.',
                    style: TextStyle(color: Colors.grey.shade300, fontSize: 14),
                  ),
                  const SizedBox(height: 20),
                  SwitchListTile(
                    title: const Text('Enable Delay', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white)),
                    subtitle: Text('Shows countdown overlay on launch', style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
                    value: tempEnabled,
                    activeColor: Colors.deepPurpleAccent,
                    contentPadding: EdgeInsets.zero,
                    onChanged: (value) {
                      setDialogState(() {
                        tempEnabled = value;
                      });
                    },
                  ),
                  const SizedBox(height: 10),
                  if (tempEnabled)
                    DropdownButtonFormField<int>(
                      value: tempSeconds,
                      dropdownColor: const Color(0xFF1F1D2B),
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.grey.shade600),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Colors.deepPurpleAccent),
                        ),
                        labelText: 'Countdown Duration',
                        labelStyle: TextStyle(color: Colors.grey.shade400),
                      ),
                      items: const [
                        DropdownMenuItem(value: 3, child: Text('3 Seconds', style: TextStyle(color: Colors.white))),
                        DropdownMenuItem(value: 5, child: Text('5 Seconds', style: TextStyle(color: Colors.white))),
                        DropdownMenuItem(value: 10, child: Text('10 Seconds', style: TextStyle(color: Colors.white))),
                        DropdownMenuItem(value: 15, child: Text('15 Seconds', style: TextStyle(color: Colors.white))),
                        DropdownMenuItem(value: 30, child: Text('30 Seconds', style: TextStyle(color: Colors.white))),
                      ],
                      onChanged: (value) {
                        setDialogState(() {
                          tempSeconds = value ?? 10;
                        });
                      },
                    ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
                ),
                ElevatedButton(
                  onPressed: () async {
                    Navigator.pop(context);
                    await controller.updateDelayConfig(app.packageName, tempEnabled, tempSeconds);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurpleAccent,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = Get.put(HomeController());
    final searchController = TextEditingController();

    final screenSize = MediaQuery.of(context).size;
    final screenHeight = screenSize.height;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (controller.drawerHeightFraction.value > 0) {
          controller.drawerHeightFraction.value = 0.0;
          controller.isDrawerOpen.value = false;
          searchController.clear();
          controller.filterApps('');
          FocusScope.of(context).unfocus();
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0D0C1D), // Dark space theme
        body: Stack(
          children: [
            // 1. Futuristic Gradient Background
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Color(0xFF0D0C1D),
                    Color(0xFF1A162B),
                    Color(0xFF0F0E17),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),

            // 2. Desktop Home Screen Page
            GestureDetector(
              onVerticalDragUpdate: (details) {
                double newFraction = controller.drawerHeightFraction.value - (details.primaryDelta! / screenHeight);
                controller.drawerHeightFraction.value = newFraction.clamp(0.0, 1.0);
              },
              onVerticalDragEnd: (details) {
                if (controller.drawerHeightFraction.value > 0.4 || details.primaryVelocity! < -300) {
                  controller.drawerHeightFraction.value = 1.0;
                  controller.isDrawerOpen.value = true;
                } else {
                  controller.drawerHeightFraction.value = 0.0;
                  controller.isDrawerOpen.value = false;
                  FocusScope.of(context).unfocus();
                }
              },
              child: SafeArea(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          IconButton(
                            icon: const Icon(
                              Icons.notifications_none_rounded, 
                              color: Colors.white70, 
                              size: 26
                            ),
                            onPressed: () => Get.to(() => const NotificationsScreen()),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    // Clock and Date Widget
                    Center(
                      child: Obx(() {
                        final time = controller.currentTime.value;
                        return Column(
                          children: [
                            Text(
                              _formatTime(time),
                              style: const TextStyle(
                                fontSize: 72,
                                fontWeight: FontWeight.w200,
                                color: Colors.white,
                                letterSpacing: 2,
                                shadows: [
                                  Shadow(
                                    color: Colors.black38,
                                    offset: Offset(0, 4),
                                    blurRadius: 10,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _formatDate(time),
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                color: Colors.grey.shade400,
                                letterSpacing: 1,
                              ),
                            ),
                          ],
                        );
                      }),
                    ),

                    const Spacer(),

                    // Desktop App Shortcuts Grid
                    Obx(() {
                      if (controller.isLoading.value) {
                        return const Center(child: CircularProgressIndicator(color: Colors.deepPurpleAccent));
                      }
                      if (controller.desktopApps.isEmpty) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32.0),
                        child: GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 4,
                            mainAxisSpacing: 20,
                            crossAxisSpacing: 20,
                            childAspectRatio: 0.72,
                          ),
                          itemCount: controller.desktopApps.length,
                          itemBuilder: (context, index) {
                            final app = controller.desktopApps[index];
                            final hasLimit = controller.limitsMap.containsKey(app.packageName);
                            
                            return GestureDetector(
                              onTap: () => controller.launchApp(app.packageName),
                              onLongPress: () => _showAppOptions(context, app, controller),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Stack(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withValues(alpha: 0.05),
                                          borderRadius: BorderRadius.circular(16),
                                        ),
                                        child: app.icon != null
                                            ? ClipRRect(
                                                borderRadius: BorderRadius.circular(10),
                                                child: Image.memory(app.icon!, width: 44, height: 44),
                                              )
                                            : const CircleAvatar(child: Icon(Icons.android)),
                                      ),
                                      if (hasLimit)
                                        Positioned(
                                          right: 0,
                                          top: 0,
                                          child: Container(
                                            padding: const EdgeInsets.all(4),
                                            decoration: const BoxDecoration(
                                              color: Colors.redAccent,
                                              shape: BoxShape.circle,
                                            ),
                                            child: const Icon(
                                              Icons.hourglass_full_rounded,
                                              size: 8,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    app.name,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Colors.white,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      );
                    }),

                    const Spacer(flex: 2),

                    // Bottom Dock (Glassmorphism containing Phone, Settings, Limits)
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.1),
                          width: 1.5,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          // Phone Dialer shortcut
                          _buildDockIcon(
                            icon: Icons.phone_android_rounded,
                            color: Colors.greenAccent.shade400,
                            onTap: () => controller.launchApp('com.android.dialer'),
                          ),
                          // Quick limits manager shortcut
                          _buildDockIcon(
                            icon: Icons.dashboard_rounded,
                            color: Colors.deepPurpleAccent,
                            onTap: () {
                              Get.to(() => const DeviceAppsScreen());
                            },
                          ),
                          // App Drawer Action Button
                          GestureDetector(
                            onTap: () {
                              controller.drawerHeightFraction.value = 1.0;
                              controller.isDrawerOpen.value = true;
                            },
                            child: Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: Colors.deepPurpleAccent.withValues(alpha: 0.15),
                                shape: BoxShape.circle,
                              ),
                              child: const Center(
                                child: Icon(Icons.keyboard_arrow_up_rounded, color: Colors.white, size: 28),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    // "Swipe Up" Hint Label
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: Text(
                        'Swipe up to open apps',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // 3. Sliding App Drawer Sheet (Frosted glass overlay)
            Obx(() {
              final drawerY = screenHeight - (controller.drawerHeightFraction.value * screenHeight);
              return Positioned(
                left: 0,
                right: 0,
                top: drawerY,
                height: screenHeight,
                child: Container(
                  decoration: const BoxDecoration(
                    color: Color(0xFA12111A), // Frosted/dark semi-opaque background
                    borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black54,
                        blurRadius: 15,
                        spreadRadius: 2,
                        offset: Offset(0, -4),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      const SizedBox(height: 12),
                      // Drag Handle Bar
                      GestureDetector(
                        onVerticalDragUpdate: (details) {
                          double newFraction = controller.drawerHeightFraction.value - (details.primaryDelta! / screenHeight);
                          controller.drawerHeightFraction.value = newFraction.clamp(0.0, 1.0);
                        },
                        onVerticalDragEnd: (details) {
                          if (controller.drawerHeightFraction.value < 0.8 && details.primaryVelocity! > 300) {
                            controller.drawerHeightFraction.value = 0.0;
                            controller.isDrawerOpen.value = false;
                            FocusScope.of(context).unfocus();
                          } else {
                            controller.drawerHeightFraction.value = 1.0;
                            controller.isDrawerOpen.value = true;
                          }
                        },
                        child: Container(
                          width: 50,
                          height: 6,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade700,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      
                      // App Drawer Search Bar
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20.0),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: TextField(
                            controller: searchController,
                            onChanged: controller.filterApps,
                            style: const TextStyle(color: Colors.white),
                            decoration: InputDecoration(
                              hintText: 'Search applications...',
                              hintStyle: TextStyle(color: Colors.grey.shade500),
                              prefixIcon: const Icon(Icons.search, color: Colors.grey),
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(vertical: 14),
                              suffixIcon: searchController.text.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(Icons.clear, color: Colors.grey),
                                      onPressed: () {
                                        searchController.clear();
                                        controller.filterApps('');
                                      },
                                    )
                                  : null,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      
                      // App List Grid (Drawer Content)
                      Expanded(
                        child: Obx(() {
                          if (controller.isLoading.value) {
                            return const Center(child: CircularProgressIndicator(color: Colors.deepPurpleAccent));
                          }
                          if (controller.filteredApps.isEmpty) {
                            return Center(
                              child: Text(
                                'No apps match your search',
                                style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
                              ),
                            );
                          }
                          return GridView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 4,
                              mainAxisSpacing: 24,
                              crossAxisSpacing: 16,
                              childAspectRatio: 0.72,
                            ),
                            itemCount: controller.filteredApps.length,
                            itemBuilder: (context, index) {
                              final app = controller.filteredApps[index];
                              final hasLimit = controller.limitsMap.containsKey(app.packageName);
                              
                              return GestureDetector(
                                onTap: () {
                                  controller.launchApp(app.packageName);
                                  // Close drawer after launching
                                  controller.drawerHeightFraction.value = 0.0;
                                  controller.isDrawerOpen.value = false;
                                  FocusScope.of(context).unfocus();
                                },
                                onLongPress: () => _showAppOptions(context, app, controller),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Stack(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(10),
                                          decoration: BoxDecoration(
                                            color: Colors.white.withValues(alpha: 0.04),
                                            borderRadius: BorderRadius.circular(16),
                                          ),
                                          child: app.icon != null
                                              ? ClipRRect(
                                                  borderRadius: BorderRadius.circular(12),
                                                  child: Image.memory(app.icon!, width: 44, height: 44),
                                                )
                                              : const CircleAvatar(child: Icon(Icons.android)),
                                        ),
                                        if (hasLimit)
                                          Positioned(
                                            right: 0,
                                            top: 0,
                                            child: Container(
                                              padding: const EdgeInsets.all(4),
                                              decoration: const BoxDecoration(
                                                color: Colors.redAccent,
                                                shape: BoxShape.circle,
                                              ),
                                              child: const Icon(
                                                Icons.hourglass_full_rounded,
                                                size: 8,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      app.name,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: Colors.white70,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ),
                              );
                            },
                          );
                        }),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildDockIcon({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Center(
          child: Icon(icon, color: color, size: 24),
        ),
      ),
    );
  }
}
