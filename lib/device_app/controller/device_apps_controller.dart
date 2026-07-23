import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:installed_apps/installed_apps.dart';
import 'package:installed_apps/app_info.dart';
import 'package:usage_stats/usage_stats.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:testproject/device_app/localSaver/db_helper.dart';
import 'package:testproject/device_app/localSaver/localSaver.dart';
import 'package:testproject/device_app/localSaver/active_apps_manager.dart';
import '../localSaver/custom_app_model.dart';

class DeviceAppsController extends GetxController with WidgetsBindingObserver {
  final allApps = <AppInfo>[].obs;
  final usageMap = <String, int>{}.obs;
  final limitsMap = <String, int>{}.obs;
  final delayEnabledMap = <String, bool>{}.obs;
  final delaySecondsMap = <String, int>{}.obs;
  final isLoading = false.obs;
  final errorMessage = ''.obs;

  final hasUsagePermission = false.obs;
  final hasOverlayPermission = false.obs;
  final isServiceRunning = false.obs;
  final selectedDays = 1.obs;

  final List<Map<String, dynamic>> intervals = const [
    {'label': '1 Day', 'days': 1},
    {'label': '2 Days', 'days': 2},
    {'label': '3 Days', 'days': 3},
    {'label': 'Week', 'days': 7},
    {'label': 'Month', 'days': 30},
  ];

  @override
  void onInit() {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);
    loadApps();
  }

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    super.onClose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      loadApps();
    }
  }

  Future<void> checkServiceAndPermissions() async {
    try {
      final hasOverlay = await FlutterOverlayWindow.isPermissionGranted();
      final isRunning = await FlutterBackgroundService().isRunning();

      Map<String, int> tempLimitsMap = {};
      Map<String, bool> tempDelayEnabledMap = {};
      Map<String, int> tempDelaySecondsMap = {};

      for (var app in ActiveAppsManager.activeAppsList) {
        if (app.todayLimit > 0) {
          tempLimitsMap[app.packageName] = app.todayLimit;
        }
        if (app.countdown > 0) {
          tempDelayEnabledMap[app.packageName] = true;
          tempDelaySecondsMap[app.packageName] = app.countdown;
        }
      }

      hasOverlayPermission.value = hasOverlay;
      isServiceRunning.value = isRunning;
      limitsMap.assignAll(tempLimitsMap);
      delayEnabledMap.assignAll(tempDelayEnabledMap);
      delaySecondsMap.assignAll(tempDelaySecondsMap);

      await autoStartServiceIfPermissionsGranted();
    } catch (e) {
      debugPrint('Error checking services: $e');
    }
  }

  Future<void> autoStartServiceIfPermissionsGranted() async {
    try {
      final hasOverlay = await FlutterOverlayWindow.isPermissionGranted();
      final hasUsage = await UsageStats.checkUsagePermission() ?? false;
      final hasNotif = await Permission.notification.isGranted;

      if (hasOverlay && hasUsage && hasNotif) {
        final service = FlutterBackgroundService();
        final isRunning = await service.isRunning();
        if (!isRunning) {
          debugPrint(
            "[DeviceAppsController] All permissions granted. Auto-starting background service...",
          );
          final started = await service.startService();
          if (started) {
            isServiceRunning.value = true;
          }
        }
      }
    } catch (e) {
      debugPrint('Error auto-starting service: $e');
    }
  }

  Future<void> loadApps() async {
    isLoading.value = true;
    errorMessage.value = '';

    if (!Platform.isAndroid) {
      isLoading.value = false;
      errorMessage.value =
          'Listing installed apps is only supported on Android devices.';
      return;
    }

    try {
      // 1. Check Usage Permission
      bool? hasPermission = await UsageStats.checkUsagePermission();
      hasUsagePermission.value = hasPermission ?? false;

      // 2. Fetch Usage Stats if permitted
      if (hasUsagePermission.value) {
        final now = DateTime.now();
        final endDate = now;

        final startDate = DateTime(
          now.year,
          now.month,
          now.day,
        ).subtract(Duration(days: selectedDays.value - 1));

        final queryStartDate = startDate.subtract(const Duration(days: 1));

        List<EventUsageInfo> events = await UsageStats.queryEvents(
          queryStartDate,
          endDate,
        );

        events.sort((a, b) {
          final aTime = int.tryParse(a.timeStamp ?? '0') ?? 0;
          final bTime = int.tryParse(b.timeStamp ?? '0') ?? 0;
          return aTime.compareTo(bTime);
        });

        Map<String, int> tempUsageMap = {};
        String? activeApp;
        int activeStartTime = 0;

        final startBoundary = startDate.millisecondsSinceEpoch;
        final endBoundary = endDate.millisecondsSinceEpoch;

        for (var event in events) {
          final pName = event.packageName ?? '';
          if (pName.isEmpty) continue;

          final eventTime = int.tryParse(event.timeStamp ?? '0') ?? 0;
          if (eventTime == 0) continue;

          final eType = event.eventType;

          if (eType == '1') {
            if (activeApp != null) {
              final startTime =
                  activeStartTime < startBoundary
                      ? startBoundary
                      : activeStartTime;
              final endTime = eventTime > endBoundary ? endBoundary : eventTime;
              final duration = endTime - startTime;
              if (duration > 0) {
                tempUsageMap[activeApp] =
                    (tempUsageMap[activeApp] ?? 0) + duration;
              }
            }
            activeApp = pName;
            activeStartTime = eventTime;
          } else if (eType == '2') {
            if (activeApp == pName) {
              final startTime =
                  activeStartTime < startBoundary
                      ? startBoundary
                      : activeStartTime;
              final endTime = eventTime > endBoundary ? endBoundary : eventTime;
              final duration = endTime - startTime;
              if (duration > 0) {
                tempUsageMap[pName] = (tempUsageMap[pName] ?? 0) + duration;
              }
              activeApp = null;
            }
          } else if (eType == '16' || eType == '17') {
            if (activeApp != null) {
              final startTime =
                  activeStartTime < startBoundary
                      ? startBoundary
                      : activeStartTime;
              final endTime = eventTime > endBoundary ? endBoundary : eventTime;
              final duration = endTime - startTime;
              if (duration > 0) {
                tempUsageMap[activeApp] =
                    (tempUsageMap[activeApp] ?? 0) + duration;
              }
              activeApp = null;
            }
          }
        }

        if (activeApp != null) {
          final startTime =
              activeStartTime < startBoundary ? startBoundary : activeStartTime;
          final endTime = endBoundary;
          final duration = endTime - startTime;
          if (duration > 0) {
            tempUsageMap[activeApp] = (tempUsageMap[activeApp] ?? 0) + duration;
          }
        }

        usageMap.assignAll(tempUsageMap);
      } else {
        usageMap.clear();
      }

      // 3. Fetch Installed Apps from SQLite database
      final apps = await AppDbHelper.instance.getApps(excludeSystemApps: true);

      if (hasUsagePermission.value) {
        apps.sort((a, b) {
          final aTime = usageMap[a.packageName] ?? 0;
          final bTime = usageMap[b.packageName] ?? 0;
          if (aTime == bTime) {
            return a.name.compareTo(b.name);
          }
          return bTime.compareTo(aTime);
        });
      } else {
        apps.sort((a, b) => a.name.compareTo(b.name));
      }

      allApps.assignAll(apps);
      isLoading.value = false;

      // 4. Update service & limits status
      await checkServiceAndPermissions();
    } catch (e) {
      isLoading.value = false;
      errorMessage.value = 'Failed to load apps: $e';
    }
  }

  Future<void> launchApp(String packageName) async {
    String appName = packageName;
    try {
      final app = allApps.firstWhere((app) => app.packageName == packageName);
      appName = app.name;
    } catch (_) {}

    final prefs = await SharedPreferences.getInstance();
    final isAccessibilityEnabled =
        prefs.getBool('is_accessibility_enabled') ?? false;

    CustomAppModel? ramApp;
    for (final a in ActiveAppsManager.activeAppsList) {
      if (a.packageName == packageName) {
        ramApp = a;
        break;
      }
    }
    final limitMs = ramApp?.todayLimit ?? 0;
    final todayUsageMs = ramApp?.todayUsage ?? 0;
    final isBlocked = limitMs > 0 && todayUsageMs >= limitMs;

    final delayEnabled = ramApp != null && ramApp.countdown > 0;
    final delaySeconds =
        ramApp != null && ramApp.countdown > 0 ? ramApp.countdown : 10;

    if (isAccessibilityEnabled) {
      try {
        await InstalledApps.startApp(packageName);
      } catch (e) {
        Get.snackbar(
          'Launch Error',
          'Could not launch app: $e',
          backgroundColor: Colors.redAccent,
          colorText: Colors.white,
        );
      }
    } else {
      if (delayEnabled && !isBlocked) {
        try {
          await prefs.setString('launch_on_dismiss_package', packageName);

          await FlutterOverlayWindow.showOverlay(
            alignment: OverlayAlignment.center,
            height: WindowSize.matchParent,
            width: WindowSize.matchParent,
            overlayTitle: "Focus Pause",
            overlayContent: "Taking a mindful break.",
            enableDrag: false,
          );

          Future.delayed(const Duration(milliseconds: 400), () {
            FlutterOverlayWindow.shareData({
              'overlayType': 'restrict',
              'packageName': packageName,
              'appName': appName,
              'delaySeconds': delaySeconds,
            });
          });
        } catch (e) {
          Get.snackbar(
            'Launch Error',
            'Could not show overlay: $e',
            backgroundColor: Colors.redAccent,
            colorText: Colors.white,
          );
        }
      } else {
        try {
          await InstalledApps.startApp(packageName);
        } catch (e) {
          Get.snackbar(
            'Launch Error',
            'Could not launch app: $e',
            backgroundColor: Colors.redAccent,
            colorText: Colors.white,
          );
        }
      }
    }
  }

  Future<void> updateDelayConfig(
    String packageName,
    bool enabled,
    int seconds,
  ) async {
    String displayName = packageName;
    bool isSystemApp = false;
    Uint8List? icon;
    try {
      final app = allApps.firstWhere((app) => app.packageName == packageName);
      displayName = app.name;
      isSystemApp = app.isSystemApp;
      icon = app.icon;
    } catch (_) {}

    if (enabled && seconds > 0) {
      delayEnabledMap[packageName] = true;
      delaySecondsMap[packageName] = seconds;
    } else {
      delayEnabledMap.remove(packageName);
      delaySecondsMap.remove(packageName);
    }

    ActiveAppsManager.updateApp(
      packageName: packageName,
      displayName: displayName,
      isSystemApp: isSystemApp ? 1 : 0,
      countdown: enabled ? seconds : 0,
      icon: icon,
    );

    await checkServiceAndPermissions();
  }

  Future<void> updateLimit(
    String packageName,
    int selectedMinutes,
    String appName,
  ) async {
    final limitMs = selectedMinutes * 60000;
    bool isSystemApp = false;
    Uint8List? icon;
    try {
      final app = allApps.firstWhere((app) => app.packageName == packageName);
      isSystemApp = app.isSystemApp;
      icon = app.icon;
    } catch (_) {}

    if (limitMs > 0) {
      limitsMap[packageName] = limitMs;
    } else {
      limitsMap.remove(packageName);
    }

    ActiveAppsManager.updateApp(
      packageName: packageName,
      displayName: appName,
      isSystemApp: isSystemApp ? 1 : 0,
      todayLimit: limitMs,
      icon: icon,
    );

    if (limitMs == 0) {
      final prefs = await SharedPreferences.getInstance();
      final blockedPkg =
          prefs.getString(UsageDataSaver.activeBlockedPackage) ?? '';
      if (blockedPkg == packageName) {
        await prefs.remove(UsageDataSaver.activeBlockedPackage);
      }
    }

    await checkServiceAndPermissions();

    if (selectedMinutes > 0 && !isServiceRunning.value) {
      Get.snackbar(
        'Notice',
        'Please enable "Background Limit Monitor" at the top to enforce this limit!',
        backgroundColor: Colors.amber,
        colorText: Colors.black,
        duration: const Duration(seconds: 4),
      );
    }
  }

  void changeInterval(int days) {
    selectedDays.value = days;
    loadApps();
  }
}
