
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:installed_apps/installed_apps.dart';
import 'package:installed_apps/app_info.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:testproject/device_app/localSaver/localSaver.dart';
import 'package:testproject/device_app/localSaver/db_helper.dart';

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

  @override
  void onInit() {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);
    _startClock();
    loadLauncherData();
  }

  @override
  void onClose() {
    _clockTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.onClose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      loadLauncherData();
    }
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
      debugPrint('Error loading launcher apps: $e');
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
    await UsageDataSaver.saveLimit(packageName, limitMs);
    await UsageDataSaver.saveAppName(packageName, appName);

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
    final isFav = await AppDbHelper.instance.isAppFavorite(packageName);
    await AppDbHelper.instance.updateFavoriteStatus(packageName, !isFav);
    await loadLauncherData();
  }
}

