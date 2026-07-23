import 'dart:io';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:installed_apps/app_info.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:usage_stats/usage_stats.dart';
import '../controller/device_apps_controller.dart';

class DeviceAppsScreen extends StatelessWidget {
  const DeviceAppsScreen({super.key});

  Future<void> _showDelayDialog(
    BuildContext context,
    AppInfo app,
    DeviceAppsController controller,
  ) async {
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
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: Text('Mindful Delay: ${app.name}'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Enable a mindful countdown delay overlay before this app launches to help reduce impulsive openings.',
                  ),
                  const SizedBox(height: 20),
                  SwitchListTile(
                    title: const Text(
                      'Enable Delay',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    subtitle: const Text('Shows countdown overlay on launch'),
                    value: tempEnabled,
                    activeColor: Colors.deepPurple,
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
                      decoration: InputDecoration(
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        labelText: 'Countdown Duration',
                      ),
                      items: const [
                        DropdownMenuItem(value: 3, child: Text('3 Seconds')),
                        DropdownMenuItem(value: 5, child: Text('5 Seconds')),
                        DropdownMenuItem(value: 10, child: Text('10 Seconds')),
                        DropdownMenuItem(value: 15, child: Text('15 Seconds')),
                        DropdownMenuItem(value: 30, child: Text('30 Seconds')),
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
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    Navigator.pop(context);
                    await controller.updateDelayConfig(
                      app.packageName,
                      tempEnabled,
                      tempSeconds,
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurple,
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

  Future<void> _showLimitDialog(
    BuildContext context,
    AppInfo app,
    DeviceAppsController controller,
  ) async {
    final currentLimitMs = controller.limitsMap[app.packageName] ?? 0;
    int currentLimitMinutes =
        currentLimitMs > 0 ? (currentLimitMs / 60000).round() : 0;

    final selectedMinutes = await showDialog<int>(
      context: context,
      builder: (context) {
        int tempLimit = currentLimitMinutes;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: Text('Daily Limit: ${app.name}'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Set a maximum daily usage limit. Once reached, an overlay will block the app.',
                  ),
                  const SizedBox(height: 20),
                  DropdownButtonFormField<int>(
                    value: tempLimit,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      labelText: 'Select Limit',
                    ),
                    items: const [
                      DropdownMenuItem(value: 0, child: Text('No Limit')),
                      DropdownMenuItem(
                        value: 1,
                        child: Text('1 Minute (Test)'),
                      ),
                      DropdownMenuItem(value: 5, child: Text('5 Minutes')),
                      DropdownMenuItem(value: 10, child: Text('10 Minutes')),
                      DropdownMenuItem(value: 15, child: Text('15 Minutes')),
                      DropdownMenuItem(value: 30, child: Text('30 Minutes')),
                      DropdownMenuItem(value: 60, child: Text('1 Hour')),
                    ],
                    onChanged: (value) {
                      setDialogState(() {
                        tempLimit = value ?? 0;
                      });
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, tempLimit),
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    if (selectedMinutes != null) {
      await controller.updateLimit(app.packageName, selectedMinutes, app.name);
    }
  }

  String _formatDuration(int ms) {
    if (ms <= 0) return 'Not used';
    final duration = Duration(milliseconds: ms);
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '${hours}h ${minutes}m';
    } else if (minutes > 0) {
      return '${minutes}m';
    } else {
      return '${seconds}s';
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = Get.put(DeviceAppsController());
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FD),
      appBar: AppBar(
        title: const Text(
          'Device Applications',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
        ),
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.black87,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh list',
            onPressed: controller.loadApps,
          ),
        ],
      ),
      body: SafeArea(
        child: Obx(() {
          return Column(
            children: [
              // Background Monitor & Overlay Permission Settings Cards
              if (!controller.isLoading.value &&
                  controller.errorMessage.isEmpty)
                _buildSettingsHeader(controller),

              // Top Selector for Duration (Only show if we have permission)
              if (controller.hasUsagePermission.value &&
                  !controller.isLoading.value &&
                  controller.errorMessage.value.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20.0,
                    vertical: 8.0,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.timer_outlined,
                        size: 20,
                        color: Colors.grey.shade600,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children:
                                controller.intervals.map((interval) {
                                  final isSelected =
                                      controller.selectedDays.value ==
                                      interval['days'];
                                  return Padding(
                                    padding: const EdgeInsets.only(right: 8.0),
                                    child: ChoiceChip(
                                      label: Text(
                                        interval['label'],
                                        style: TextStyle(
                                          fontSize: 12,
                                          color:
                                              isSelected
                                                  ? primaryColor
                                                  : Colors.grey.shade700,
                                          fontWeight:
                                              isSelected
                                                  ? FontWeight.bold
                                                  : FontWeight.normal,
                                        ),
                                      ),
                                      selected: isSelected,
                                      selectedColor: primaryColor.withValues(
                                        alpha: 0.15,
                                      ),
                                      checkmarkColor: primaryColor,
                                      onSelected: (selected) {
                                        if (selected) {
                                          controller.changeInterval(
                                            interval['days'],
                                          );
                                        }
                                      },
                                    ),
                                  );
                                }).toList(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              // Permission Banner for UsageStats (Show if not granted)
              if (!controller.hasUsagePermission.value &&
                  !controller.isLoading.value &&
                  controller.errorMessage.value.isEmpty)
                _buildPermissionBanner(primaryColor, controller),

              // Main Content Area
              Expanded(
                child: _buildMainContent(context, primaryColor, controller),
              ),
            ],
          );
        }),
      ),
    );
  }

  Widget _buildSettingsHeader(DeviceAppsController controller) {
    final statusColor =
        controller.isServiceRunning.value
            ? Colors.green.shade600
            : Colors.amber.shade800;
    final statusBg =
        controller.isServiceRunning.value
            ? Colors.green.shade50
            : Colors.amber.shade50;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Background Limit Monitor',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    controller.isServiceRunning.value
                        ? 'Enforcing limits in real time'
                        : 'Permissions required to start',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: statusBg,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: statusColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      controller.isServiceRunning.value ? 'Active' : 'Inactive',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: statusColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // Overlay Permission Warning Alert
          if (!controller.hasOverlayPermission.value) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.red.shade100),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.red.shade700,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Overlay (Draw over apps) permission required to block apps.',
                      style: TextStyle(fontSize: 12, color: Colors.black87),
                    ),
                  ),
                  TextButton(
                    onPressed: () async {
                      await FlutterOverlayWindow.requestPermission();
                      Future.delayed(
                        const Duration(seconds: 1),
                        controller.checkServiceAndPermissions,
                      );
                    },
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      'Grant',
                      style: TextStyle(
                        color: Colors.red.shade800,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPermissionBanner(
    Color primaryColor,
    DeviceAppsController controller,
  ) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.amber.shade200, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                color: Colors.amber.shade800,
                size: 28,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Usage Statistics Access Required',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Colors.amber.shade900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'To see how much time you spend on each app, please grant Usage Access in System Settings.',
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.shade800,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: () async {
              await UsageStats.grantUsagePermission();
              Future.delayed(const Duration(seconds: 1), controller.loadApps);
            },
            icon: const Icon(Icons.settings, size: 18),
            label: const Text('Grant Permission'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.amber.shade800,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMainContent(
    BuildContext context,
    Color primaryColor,
    DeviceAppsController controller,
  ) {
    if (controller.isLoading.value) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
            ),
            const SizedBox(height: 16),
            Text(
              'Scanning installed applications...',
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }

    if (controller.errorMessage.value.isNotEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.error_outline,
                  color: Colors.red.shade400,
                  size: 48,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Unsupported Platform / Error',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                controller.errorMessage.value,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600, height: 1.4),
              ),
              const SizedBox(height: 24),
              if (Platform.isAndroid)
                ElevatedButton.icon(
                  onPressed: controller.loadApps,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Try Again'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    }

    if (controller.allApps.isEmpty) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.apps_outage_rounded,
                size: 72,
                color: Colors.grey.shade400,
              ),
              const SizedBox(height: 16),
              Text(
                'No Apps Found',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'No user applications were retrieved from this device.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: controller.loadApps,
      color: primaryColor,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: controller.allApps.length,
        itemBuilder: (context, index) {
          final app = controller.allApps[index];
          final appName = app.name;
          final packageName = app.packageName;
          final appIcon = app.icon;

          final usageTimeMs = controller.usageMap[packageName] ?? 0;
          final formattedUsage = _formatDuration(usageTimeMs);

          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
              leading:
                  appIcon != null
                      ? ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.memory(
                          appIcon,
                          width: 40,
                          height: 40,
                          fit: BoxFit.cover,
                        ),
                      )
                      : CircleAvatar(
                        backgroundColor: primaryColor.withValues(alpha: 0.1),
                        child: Text(
                          appName.isNotEmpty ? appName[0].toUpperCase() : 'A',
                          style: TextStyle(
                            color: primaryColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
              title: Row(
                children: [
                  Expanded(
                    child: Text(
                      appName,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: Colors.black87,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Limit Action Chip
                  Obx(() {
                    final currentLimitMs =
                        controller.limitsMap[packageName] ?? 0;
                    final currentLimitMins =
                        (currentLimitMs / 60000).round();

                    return GestureDetector(
                      onTap: () => _showLimitDialog(context, app, controller),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color:
                              currentLimitMs > 0
                                  ? Colors.red.shade50
                                  : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color:
                                currentLimitMs > 0
                                    ? Colors.red.shade200
                                    : Colors.grey.shade300,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              currentLimitMs > 0
                                  ? Icons.hourglass_full_rounded
                                  : Icons.hourglass_empty_rounded,
                              size: 12,
                              color:
                                  currentLimitMs > 0
                                      ? Colors.red.shade700
                                      : Colors.grey.shade600,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              currentLimitMs > 0
                                  ? '${currentLimitMins}m'
                                  : 'Set Limit',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color:
                                    currentLimitMs > 0
                                        ? Colors.red.shade800
                                        : Colors.grey.shade700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                  const SizedBox(width: 8),

                  // Delay Action Chip
                  Obx(() {
                    final delayEnabled =
                        controller.delayEnabledMap[packageName] ?? false;
                    final delaySecs =
                        controller.delaySecondsMap[packageName] ?? 10;

                    return GestureDetector(
                      onTap: () => _showDelayDialog(context, app, controller),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color:
                              delayEnabled
                                  ? Colors.deepPurple.shade50
                                  : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color:
                                delayEnabled
                                    ? Colors.deepPurple.shade200
                                    : Colors.grey.shade300,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              delayEnabled
                                  ? Icons.av_timer_rounded
                                  : Icons.timer_outlined,
                              size: 12,
                              color:
                                  delayEnabled
                                      ? Colors.deepPurple.shade700
                                      : Colors.grey.shade600,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              delayEnabled
                                  ? '${delaySecs}s Delay'
                                  : 'Set Delay',
                              style: TextStyle(
                                fontSize: 11,
                                overflow: TextOverflow.ellipsis,
                                fontWeight: FontWeight.bold,
                                color:
                                    delayEnabled
                                        ? Colors.deepPurple.shade800
                                        : Colors.grey.shade700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ],
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 4.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      packageName,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade500,
                        fontFamily: 'monospace',
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (controller.hasUsagePermission.value) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.query_stats_rounded,
                            size: 14,
                            color:
                                usageTimeMs > 0
                                    ? Colors.deepOrange
                                    : Colors.grey.shade400,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Used: $formattedUsage',
                            style: TextStyle(
                              fontSize: 12,
                              color:
                                  usageTimeMs > 0
                                      ? Colors.deepOrange.shade800
                                      : Colors.grey.shade600,
                              fontWeight:
                                  usageTimeMs > 0
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              trailing: IconButton(
                icon: Icon(Icons.launch, color: primaryColor),
                tooltip: 'Launch App',
                onPressed: () => controller.launchApp(packageName),
              ),
            ),
          );
        },
      ),
    );
  }
}
