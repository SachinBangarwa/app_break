
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
    loadLauncherData();
    _syncOnceOnStartup();
    _setupPackageChannelListener();
  }

  void _setupPackageChannelListener() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'notificationSaved') {
        print("--- [Flutter Dart] Received notification saved event ---");
        if (Get.isRegistered<NotificationsController>()) {
          Get.find<NotificationsController>().loadNotifications();
        }
        return;
      }

      final String? pkg = call.arguments as String?;
      print("--- [Flutter Dart] Received package change event: ${call.method} for package: $pkg ---");
      if (pkg == null || pkg.isEmpty) return;

      if (call.method == 'packageAdded') {
        print("--- [Flutter Dart] Syncing single new package to SQLite: $pkg ---");
        await AppDbHelper.instance.addSingleApp(pkg);
      } else if (call.method == 'packageRemoved') {
        print("--- [Flutter Dart] Removing single package from SQLite: $pkg ---");
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
    print("--- [LifeCycle Event] state: $state ---");
    SharedPreferences.getInstance().then((prefs) {
      if (state == AppLifecycleState.resumed) {
        prefs.setBool('is_launcher_foreground', true);
      } else {
        prefs.setBool('is_launcher_foreground', false);
      }
    });

    if (state == AppLifecycleState.resumed) {
      // Screen refresh on resume disabled to prevent flickering
      print("--- [LifeCycle] Resume detected, screen refresh skipped ---");
    }

    /*
    switch (state) {
      case AppLifecycleState.resumed:
        print("--- [LifeCycle] लॉन्चर खुला (FOREGROUND / RESUMED) ---");
        loadLauncherData();
        break;
      case AppLifecycleState.paused:
        print("--- [LifeCycle] लॉन्चर बंद हुआ/यूजर बाहर गया (BACKGROUND / PAUSED) ---");
        break;
      case AppLifecycleState.inactive:
        print("--- [LifeCycle] लॉन्चर अक्रिय/फोकस हटा (INACTIVE) ---");
        break;
      case AppLifecycleState.detached:
        print("--- [LifeCycle] लॉन्चर बंद हो रहा है (DETACHED) ---");
        break;
      case AppLifecycleState.hidden:
        print("--- [LifeCycle] लॉन्चर छिपा हुआ (HIDDEN) ---");
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
      debugPrint('Error loading launcher apps: $e');
      isLoading.value = false;
    }
  }

  Future<void> _syncOnceOnStartup() async {
    try {
      // Run system app sync with SQLite database once on launcher start
      final hasChanges = await AppDbHelper.instance.syncAppsWithSystem();
      if (hasChanges) {
        print("[HomeController] System app changes detected. Reloading cache.");
        await loadLocalAppsFromCache();
      } else {
        print("[HomeController] No system app changes detected on startup.");
      }
    } catch (e) {
      debugPrint('Error syncing apps on startup: $e');
    }
  }

  Future<void> loadLocalAppsFromCache() async {
    try {
      // 1. Load all apps directly from SQLite (super fast!)
      List<AppInfo> apps = await AppDbHelper.instance.getApps(excludeSystemApps: false);

      // 2. Select Desktop Shortcut Apps (Favorites) from SQLite
      List<AppInfo> tempDesktopApps = await AppDbHelper.instance.getFavoriteApps();

      // Show apps on UI instantly!
      allApps.assignAll(apps);
      filteredApps.assignAll(apps);
      desktopApps.assignAll(tempDesktopApps);
      isLoading.value = false;

      // 3. Fetch limits & delay configs from SharedPreferences in the background
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      Map<String, int> tempLimitsMap = {};
      Map<String, bool> tempDelayEnabledMap = {};
      Map<String, int> tempDelaySecondsMap = {};

      for (var app in apps) {
        final limit = prefs.getInt('limit_${app.packageName}') ?? 0;
        if (limit > 0) {
          tempLimitsMap[app.packageName] = limit;
        }

        final delayEnabled = prefs.getBool('delay_enabled_${app.packageName}') ?? false;
        final delaySecs = prefs.getInt('delay_seconds_${app.packageName}') ?? 10;
        tempDelayEnabledMap[app.packageName] = delayEnabled;
        tempDelaySecondsMap[app.packageName] = delaySecs;
      }

      limitsMap.assignAll(tempLimitsMap);
      delayEnabledMap.assignAll(tempDelayEnabledMap);
      delaySecondsMap.assignAll(tempDelaySecondsMap);
    } catch (e) {
      debugPrint('Error loading local apps from SQLite cache: $e');
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
    final delayEnabled = prefs.getBool('delay_enabled_$packageName') ?? false;
    final delaySeconds = prefs.getInt('delay_seconds_$packageName') ?? 10;

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
      if (delayEnabled) {
        try {
          await prefs.setString('active_overlay_type', 'restrict');
          await prefs.setString('active_restrict_package', packageName);
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
    await UsageDataSaver.saveDelayEnabled(packageName, enabled);
    await UsageDataSaver.saveDelaySeconds(packageName, seconds);

    // Send notification signal to the background service
    try {
      final service = FlutterBackgroundService();
      service.invoke('limitChanged', {'packageName': packageName});
    } catch (e) {
      debugPrint('Error invoking limitChanged: $e');
    }

    await loadLocalAppsFromCache();
  }

  Future<void> updateAppLimit(String packageName, int limitMs, String appName) async {
    print("[HomeController] --- [SETTING_LIMIT] Saving limit for $appName ($packageName): $limitMs ms ---");
    final usage = await UsageDataSaver.getCommittedUsage(packageName);
    final timeLeft = (limitMs - usage).clamp(0, limitMs);
    await UsageDataSaver.saveLimitConfig(packageName, appName, limitMs, timeLeft);

    if (limitMs == 0) {
      final prefs = await SharedPreferences.getInstance();
      final blockedPkg = prefs.getString(UsageDataSaver.activeBlockedPackage) ?? '';
      if (blockedPkg == packageName) {
        await prefs.remove(UsageDataSaver.activeBlockedPackage);
      }
    }

    try {
      final service = FlutterBackgroundService();
      print("[HomeController] Sending 'limitChanged' signal to background service for $packageName");
      service.invoke('limitChanged', {'packageName': packageName});
    } catch (e) {
      debugPrint('Error invoking limitChanged: $e');
    }

    await loadLauncherData();
  }

  Future<void> toggleFavorite(String packageName) async {
    final isFav = await AppDbHelper.instance.isAppFavorite(packageName);
    await AppDbHelper.instance.updateFavoriteStatus(packageName, !isFav);
    await loadLauncherData();
  }
}

