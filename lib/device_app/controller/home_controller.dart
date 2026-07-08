
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:installed_apps/installed_apps.dart';
import 'package:installed_apps/app_info.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:testproject/device_app/localSaver/localSaver.dart';
import 'package:testproject/device_app/localSaver/db_helper.dart';
import 'package:testproject/device_app/controller/notifications_controller.dart';

import 'package:flutter/services.dart';

class HomeController extends GetxController with WidgetsBindingObserver {
  final allApps = <AppInfo>[].obs;
  final filteredApps = <AppInfo>[].obs;
  final desktopApps = <AppInfo>[].obs;
  final limitsMap = <String, int>{}.obs;

  final drawerHeightFraction = 0.0.obs;
  final isDrawerOpen = false.obs;

  final currentTime = DateTime.now().obs;
  final isLoading = true.obs;

  Timer? _clockTimer;

  static const _channel = MethodChannel('com.example.testproject/package_change');

  @override
  void onInit() {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);
    _startClock();
    loadLauncherData();
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
      // 1. Sync system apps to SQLite database using fast diff check
      await AppDbHelper.instance.syncAppsWithSystem();
      await loadLocalAppsFromCache();
    } catch (e) {
      debugPrint('Error loading launcher apps: $e');
      isLoading.value = false;
    }
  }

  Future<void> loadLocalAppsFromCache() async {
    try {
      // Load all apps directly from SQLite
      List<AppInfo> apps = await AppDbHelper.instance.getApps(excludeSystemApps: false);

      // 2. Fetch limits
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      Map<String, int> tempLimitsMap = {};
      for (var app in apps) {
        final limit = prefs.getInt('limit_${app.packageName}') ?? 0;
        if (limit > 0) {
          tempLimitsMap[app.packageName] = limit;
        }
      }

      // 3. Select Desktop Shortcut Apps (Favorites) from SQLite
      List<AppInfo> tempDesktopApps = await AppDbHelper.instance.getFavoriteApps();

      allApps.assignAll(apps);
      filteredApps.assignAll(apps);
      desktopApps.assignAll(tempDesktopApps);
      limitsMap.assignAll(tempLimitsMap);
      isLoading.value = false;
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

