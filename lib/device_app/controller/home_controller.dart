
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:installed_apps/installed_apps.dart';
import 'package:installed_apps/app_info.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:testproject/device_app/localSaver/localSaver.dart';
import 'package:testproject/device_app/localSaver/db_helper.dart';
import 'package:testproject/device_app/localSaver/active_apps_manager.dart';
import 'package:testproject/device_app/localSaver/custom_app_model.dart';
import 'package:testproject/device_app/controller/notifications_controller.dart';

import 'package:flutter/services.dart';

class HomeController extends GetxController with WidgetsBindingObserver {
  final allApps = <AppInfo>[].obs;
  final filteredApps = <AppInfo>[].obs;
  final desktopApps = <AppInfo>[].obs;
  final limitsMap = <String, int>{}.obs;
  final delayEnabledMap = <String, bool>{}.obs;
  final delaySecondsMap = <String, int>{}.obs;

  final drawerHeightFraction = 0.0.obs;
  final isDrawerOpen = false.obs;

  final currentTime = DateTime.now().obs;
  final isLoading = false.obs;

  Timer? _clockTimer;

  static const _channel = MethodChannel('com.example.testproject/package_change');

  @override
  void onInit() {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);
    SharedPreferences.getInstance().then((prefs) {
      prefs.setBool('is_launcher_foreground', true);
    });
    _startClock();
    
    _setupServiceSync();
    _setupActiveAppsListener();
    loadLauncherData();
    _syncOnceOnStartup();
    _setupPackageChannelListener();
  }

  void _setupServiceSync() {
    try {
      final service = FlutterBackgroundService();
      
      // Full active list sync listener from Service
      service.on('syncFullList').listen((event) {
        if (event != null && event['apps'] != null) {
          final List<dynamic> appsData = event['apps'];
          final List<CustomAppModel> loadedApps = appsData.map<CustomAppModel>((data) => CustomAppModel.fromMap(Map<String, dynamic>.from(data))).toList();
          
          ActiveAppsManager.activeAppsList.clear();
          ActiveAppsManager.activeAppsList.addAll(loadedApps);
        }
      });

      // Request full list sync in case service is already running
      service.invoke('requestActiveAppsSync');
    } catch (e) {
    }
  }

  void _setupActiveAppsListener() {
    // जब भी activeAppsList बदलेगी, फ़ेवरेट ऐप्स ऑटोमैटिक फ़िल्टर होकर UI में अपडेट हो जाएँगे
    ever(ActiveAppsManager.activeAppsList, (dynamic activeAppsVal) {
      final List<CustomAppModel> activeApps = List<CustomAppModel>.from(activeAppsVal as Iterable);
      final List<AppInfo> favApps = activeApps
          .where((app) => app.isFavorite == 1)
          .map<AppInfo>((app) => AppInfo.create({
                'name': app.displayName,
                'package_name': app.packageName,
                'icon': app.icon,
                'is_system_app': app.isSystemApp == 1,
              }))
          .toList();
      desktopApps.assignAll(favApps);
    });
  }

  void _setupPackageChannelListener() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'notificationSaved') {
        if (Get.isRegistered<NotificationsController>()) {
          Get.find<NotificationsController>().loadNotifications();
        }
        return;
      }

      final String? pkg = call.arguments as String?;
      if (pkg == null || pkg.isEmpty) return;

      if (call.method == 'packageAdded') {
        await AppDbHelper.instance.addSingleApp(pkg);
      } else if (call.method == 'packageRemoved') {
        await AppDbHelper.instance.removeSingleApp(pkg);
        await UsageDataSaver.clearLimitConfig(pkg);
      }

      // Reload the local lists from SQLite (extremely fast, no system list scan!)
      await loadLocalAppsFromCache();
    });
  }

  @override
  void onClose() {
    _clockTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.onClose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Print whatever event/state comes in directly:
    SharedPreferences.getInstance().then((prefs) {
      if (state == AppLifecycleState.resumed) {
        prefs.setBool('is_launcher_foreground', true);
      } else {
        prefs.setBool('is_launcher_foreground', false);
      }
    });

    if (state == AppLifecycleState.resumed) {
      // Screen refresh on resume disabled to prevent flickering
    }

    /*
    switch (state) {
      case AppLifecycleState.resumed:
        loadLauncherData();
        break;
      case AppLifecycleState.paused:
        break;
      case AppLifecycleState.inactive:
        break;
      case AppLifecycleState.detached:
        break;
      case AppLifecycleState.hidden:
        break;
    }
    */
  }

  void _startClock() {
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      currentTime.value = DateTime.now();
    });
  }

  Future<void> loadLauncherData() async {
    try {
      // Load directly from local SQL database cache
      await loadLocalAppsFromCache();
    } catch (e) {
      isLoading.value = false;
    }
  }

  Future<void> _syncOnceOnStartup() async {
    try {
      // Run system app sync with SQLite database once on launcher start
      final hasChanges = await AppDbHelper.instance.syncAppsWithSystem();
      if (hasChanges) {
        await loadLocalAppsFromCache();
      } else {
      }
    } catch (e) {
    }
  }

  Future<void> loadLocalAppsFromCache() async {
    try {
      // 1. Load all apps directly from SQLite (super fast!)
      List<AppInfo> apps = await AppDbHelper.instance.getApps(excludeSystemApps: false);

      // 2. Select Desktop Shortcut Apps (Favorites) from RAM activeAppsList instead of SQLite
      final tempDesktopApps = ActiveAppsManager.activeAppsList
          .where((app) => app.isFavorite == 1)
          .map((app) => AppInfo.create({
                'name': app.displayName,
                'package_name': app.packageName,
                'icon': app.icon,
                'is_system_app': app.isSystemApp == 1,
              }))
          .toList();

      // Show apps on UI instantly!
      allApps.assignAll(apps);
      filteredApps.assignAll(apps);
      desktopApps.assignAll(tempDesktopApps);
      isLoading.value = false;

      // 3. Fetch limits & delay configs from memory activeAppsList
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

      limitsMap.assignAll(tempLimitsMap);
      delayEnabledMap.assignAll(tempDelayEnabledMap);
      delaySecondsMap.assignAll(tempDelaySecondsMap);
    } catch (e) {
      isLoading.value = false;
    }
  }

  void filterApps(String query) {
    if (query.isEmpty) {
      filteredApps.assignAll(allApps);
    } else {
      filteredApps.assignAll(allApps
          .where((app) => app.name.toLowerCase().contains(query.toLowerCase()))
          .toList());
    }
  }

  Future<void> launchApp(String packageName) async {
    String appName = packageName;
    try {
      final app = allApps.firstWhere((app) => app.packageName == packageName);
      appName = app.name;
    } catch (_) {}

    final prefs = await SharedPreferences.getInstance();
    final isAccessibilityEnabled = prefs.getBool('is_accessibility_enabled') ?? false;

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
    final delaySeconds = ramApp != null && ramApp.countdown > 0 ? ramApp.countdown : 10;

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

  Future<void> updateDelayConfig(String packageName, bool enabled, int seconds) async {
    String displayName = packageName;
    bool isSystemApp = false;
    Uint8List? icon;
    try {
      final app = allApps.firstWhere((app) => app.packageName == packageName);
      displayName = app.name;
      isSystemApp = app.isSystemApp;
      icon = app.icon;
    } catch (_) {}

    ActiveAppsManager.updateApp(
      packageName: packageName,
      displayName: displayName,
      isSystemApp: isSystemApp ? 1 : 0,
      countdown: enabled ? seconds : 0,
      icon: icon,
    );

    await loadLocalAppsFromCache();
  }

  Future<void> updateAppLimit(String packageName, int limitMs, String appName) async {
    bool isSystemApp = false;
    Uint8List? icon;
    try {
      final app = allApps.firstWhere((app) => app.packageName == packageName);
      isSystemApp = app.isSystemApp;
      icon = app.icon;
    } catch (_) {}

    ActiveAppsManager.updateApp(
      packageName: packageName,
      displayName: appName,
      isSystemApp: isSystemApp ? 1 : 0,
      todayLimit: limitMs,
      icon: icon,
    );

    if (limitMs == 0) {
      final prefs = await SharedPreferences.getInstance();
      final blockedPkg = prefs.getString(UsageDataSaver.activeBlockedPackage) ?? '';
      if (blockedPkg == packageName) {
        await prefs.remove(UsageDataSaver.activeBlockedPackage);
      }
    }

    await loadLauncherData();
  }

  Future<void> toggleFavorite(String packageName) async {
    String displayName = packageName;
    bool isSystemApp = false;
    Uint8List? icon;
    try {
      final app = allApps.firstWhere((app) => app.packageName == packageName);
      displayName = app.name;
      isSystemApp = app.isSystemApp;
      icon = app.icon;
    } catch (_) {}

    final isFav = await AppDbHelper.instance.isAppFavorite(packageName);
    final newFav = !isFav;

    ActiveAppsManager.updateApp(
      packageName: packageName,
      displayName: displayName,
      isSystemApp: isSystemApp ? 1 : 0,
      isFavorite: newFav ? 1 : 0,
      icon: icon,
    );
    await loadLauncherData();
  }
}

