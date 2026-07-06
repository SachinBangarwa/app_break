import 'dart:io';
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

class DeviceAppsController extends GetxController with WidgetsBindingObserver {
  final allApps = <AppInfo>[].obs;
  final usageMap = <String, int>{}.obs;
  final limitsMap = <String, int>{}.obs;
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
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      Map<String, int> tempLimitsMap = {};
      for (var app in allApps) {
        final limit = prefs.getInt('limit_${app.packageName}') ?? 0;
        if (limit > 0) {
          tempLimitsMap[app.packageName] = limit;
        }
      }
      
      hasOverlayPermission.value = hasOverlay;
      isServiceRunning.value = isRunning;
      limitsMap.assignAll(tempLimitsMap);

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
          debugPrint("[DeviceAppsController] All permissions granted. Auto-starting background service...");
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
      errorMessage.value = 'Listing installed apps is only supported on Android devices.';
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
        
        final startDate = DateTime(now.year, now.month, now.day)
            .subtract(Duration(days: selectedDays.value - 1));
            
        final queryStartDate = startDate.subtract(const Duration(days: 1));
        
        List<EventUsageInfo> events = await UsageStats.queryEvents(queryStartDate, endDate);
        
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
              final startTime = activeStartTime < startBoundary ? startBoundary : activeStartTime;
              final endTime = eventTime > endBoundary ? endBoundary : eventTime;
              final duration = endTime - startTime;
              if (duration > 0) {
                tempUsageMap[activeApp] = (tempUsageMap[activeApp] ?? 0) + duration;
              }
            }
            activeApp = pName;
            activeStartTime = eventTime;
          } else if (eType == '2') {
            if (activeApp == pName) {
              final startTime = activeStartTime < startBoundary ? startBoundary : activeStartTime;
              final endTime = eventTime > endBoundary ? endBoundary : eventTime;
              final duration = endTime - startTime;
              if (duration > 0) {
                tempUsageMap[pName] = (tempUsageMap[pName] ?? 0) + duration;
              }
              activeApp = null;
            }
          } else if (eType == '16' || eType == '17') {
            if (activeApp != null) {
              final startTime = activeStartTime < startBoundary ? startBoundary : activeStartTime;
              final endTime = eventTime > endBoundary ? endBoundary : eventTime;
              final duration = endTime - startTime;
              if (duration > 0) {
                tempUsageMap[activeApp] = (tempUsageMap[activeApp] ?? 0) + duration;
              }
              activeApp = null;
            }
          }
        }
        
        if (activeApp != null) {
          final startTime = activeStartTime < startBoundary ? startBoundary : activeStartTime;
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

  Future<void> updateLimit(String packageName, int selectedMinutes, String appName) async {
    final prefs = await SharedPreferences.getInstance();
    if (selectedMinutes == 0) {
      await prefs.remove('limit_$packageName');
      await prefs.remove('name_$packageName');
    } else {
      await prefs.setInt('limit_$packageName', selectedMinutes * 60000);
      await prefs.setString('name_$packageName', appName);
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
