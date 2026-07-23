import 'dart:async';
import 'dart:typed_data';
import 'package:get/get.dart';
import 'package:usage_stats/usage_stats.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'custom_app_model.dart';
import 'db_helper.dart';

class ActiveAppsManager {
  static final RxList<CustomAppModel> activeAppsList = <CustomAppModel>[].obs;

  static void updateApp({
    required String packageName,
    required String displayName,
    required int isSystemApp,
    Uint8List? icon,
    int? isFavorite,
    int? countdown,
    int? todayLimit,
    int? todayUsage,
    int? lastOpened,
    bool isServiceIsolate = false,
  }) {
    int index = activeAppsList.indexWhere((app) => app.packageName == packageName);

    if (index != -1) {
      var existing = activeAppsList[index];
      var updated = CustomAppModel(
        packageName: packageName,
        displayName: displayName,
        icon: icon ?? existing.icon,
        isSystemApp: isSystemApp,
        isFavorite: isFavorite ?? existing.isFavorite,
        countdown: countdown ?? existing.countdown,
        todayLimit: todayLimit ?? existing.todayLimit,
        todayUsage: todayUsage ?? existing.todayUsage,
        lastOpened: lastOpened ?? existing.lastOpened,
      );

      if (updated.isFavorite == 0 && updated.countdown == 0 && updated.todayLimit == 0) {
        print("[ActiveAppsManager] REMOVED app from memory list: $packageName (All parameters became 0/inactive)");
        activeAppsList.removeAt(index);
      } else {
        print("[ActiveAppsManager] UPDATED app in memory list: $packageName -> Favorite: ${updated.isFavorite}, Countdown: ${updated.countdown}s, Limit: ${updated.todayLimit}ms");
        activeAppsList[index] = updated;
      }
    } else {
      bool shouldAdd = (isFavorite == 1) ||
                       (countdown != null && countdown > 0) || 
                       (todayLimit != null && todayLimit > 0);

      if (shouldAdd) {
        print("[ActiveAppsManager] ADDED new app to memory list: $packageName -> Favorite: ${isFavorite ?? 0}, Countdown: ${countdown ?? 0}s, Limit: ${todayLimit ?? 0}ms");
        activeAppsList.add(
          CustomAppModel(
            packageName: packageName,
            displayName: displayName,
            icon: icon,
            isSystemApp: isSystemApp,
            isFavorite: isFavorite ?? 0,
            countdown: countdown ?? 0,
            todayLimit: todayLimit ?? 0,
            todayUsage: todayUsage ?? 0,
            lastOpened: lastOpened ?? 0,
          ),
        );
      }
    }

    print("[ActiveAppsManager] Current Active Apps in RAM: $activeAppsList");


    if (!isServiceIsolate) {
      if (isFavorite != null) {
        print("[ActiveAppsManager] DATABASE UPDATE: Saving Favorite status = $isFavorite for $packageName in background");
        AppDbHelper.instance.updateFavoriteStatus(packageName, isFavorite == 1);
        _notifyLimitChanged(packageName);
      }

      if (countdown != null) {
        print("[ActiveAppsManager] DATABASE UPDATE: Saving Countdown Delay = ${countdown}s for $packageName in background");
        AppDbHelper.instance.updateAppCountdown(packageName, countdown);
        _notifyLimitChanged(packageName);
      }

      if (todayLimit != null) {
        _updateLimitAndFetchUsageBackground(
          packageName: packageName,
          displayName: displayName,
          isSystemApp: isSystemApp,
          icon: icon,
          limitMs: todayLimit,
        );
      }
    }
  }

  // =========================================================================
  // BACKEND/DATABASE HELPER METHODS
  // =========================================================================


  static void _updateLimitAndFetchUsageBackground({
    required String packageName,
    required String displayName,
    required int isSystemApp,
    Uint8List? icon,
    required int limitMs,
  }) async {
    print("[ActiveAppsManager] Fetching live system usage for $packageName...");
    final usageMs = await calculateTodaySystemUsage(packageName);
    print("[ActiveAppsManager] Live system usage for $packageName fetched: ${usageMs / 1000} seconds");

    int index = activeAppsList.indexWhere((app) => app.packageName == packageName);
    if (index != -1) {
      var existing = activeAppsList[index];
      print("[ActiveAppsManager] UPDATING usage in memory list for $packageName to ${usageMs}ms");
      activeAppsList[index] = CustomAppModel(
        packageName: packageName,
        displayName: displayName,
        icon: icon ?? existing.icon,
        isSystemApp: isSystemApp,
        isFavorite: existing.isFavorite,
        countdown: existing.countdown,
        todayLimit: limitMs,
        todayUsage: usageMs,
        lastOpened: existing.lastOpened,
      );
    }

    print("[ActiveAppsManager] DATABASE UPDATE: Saving todayLimit = ${limitMs}ms and todayUsage = ${usageMs}ms for $packageName in background");
    await AppDbHelper.instance.updateAppLimit(packageName, limitMs, usageMs);

    _notifyLimitChanged(packageName);
  }

  static void _notifyLimitChanged(String packageName) {
    try {
      final service = FlutterBackgroundService();
      service.invoke('limitChanged', {'packageName': packageName});

      int index = activeAppsList.indexWhere((app) => app.packageName == packageName);
      if (index != -1) {
        final app = activeAppsList[index];
        print("[ActiveAppsManager] Sending syncActiveApp to background service for ${app.packageName} (Favorite: ${app.isFavorite}, Limit: ${app.todayLimit}ms, Countdown: ${app.countdown}s)");
        service.invoke('syncActiveApp', {
          'packageName': app.packageName,
          'displayName': app.displayName,
          'isSystemApp': app.isSystemApp,
          'isFavorite': app.isFavorite,
          'countdown': app.countdown,
          'todayLimit': app.todayLimit,
          'todayUsage': app.todayUsage,
          'lastOpened': app.lastOpened,
          'icon': app.icon,
        });
      } else {
        print("[ActiveAppsManager] Sending syncActiveApp (REMOVE/RESET) to background service for $packageName");
        service.invoke('syncActiveApp', {
          'packageName': packageName,
          'displayName': '',
          'isSystemApp': 0,
          'isFavorite': 0,
          'countdown': 0,
          'todayLimit': 0,
          'todayUsage': 0,
          'lastOpened': 0,
        });
      }
    } catch (e) {
      print("[ActiveAppsManager] Error syncing active app to background service: $e");
    }
  }

  static Future<int> calculateTodaySystemUsage(String packageName) async {
    try {
      final now = DateTime.now();
      final startOfDay = DateTime(now.year, now.month, now.day);

      List<EventUsageInfo> events = await UsageStats.queryEvents(startOfDay, now);
      events.sort((a, b) {
        final aTime = int.tryParse(a.timeStamp ?? '0') ?? 0;
        final bTime = int.tryParse(b.timeStamp ?? '0') ?? 0;
        return aTime.compareTo(bTime);
      });

      int totalDurationMs = 0;
      String? activeApp;
      int activeStartTime = 0;

      final startBoundary = startOfDay.millisecondsSinceEpoch;
      final endBoundary = now.millisecondsSinceEpoch;

      for (var event in events) {
        final pName = event.packageName ?? '';
        if (pName.isEmpty) continue;

        final eventTime = int.tryParse(event.timeStamp ?? '0') ?? 0;
        if (eventTime == 0) continue;

        final eType = event.eventType;

        if (eType == '1') {
          if (activeApp == packageName) {
            final startTime = activeStartTime < startBoundary ? startBoundary : activeStartTime;
            final endTime = eventTime > endBoundary ? endBoundary : eventTime;
            final duration = endTime - startTime;
            if (duration > 0) {
              totalDurationMs += duration;
            }
          }
          activeApp = pName;
          activeStartTime = eventTime;
        } else if (eType == '2') {
          if (activeApp == pName) {
            if (pName == packageName) {
              final startTime = activeStartTime < startBoundary ? startBoundary : activeStartTime;
              final endTime = eventTime > endBoundary ? endBoundary : eventTime;
              final duration = endTime - startTime;
              if (duration > 0) {
                totalDurationMs += duration;
              }
            }
            activeApp = null;
          }
        } else if (eType == '16' || eType == '17') {
          if (activeApp == packageName) {
            final startTime = activeStartTime < startBoundary ? startBoundary : activeStartTime;
            final endTime = eventTime > endBoundary ? endBoundary : eventTime;
            final duration = endTime - startTime;
            if (duration > 0) {
              totalDurationMs += duration;
            }
          }
          activeApp = null;
        }
      }

      if (activeApp == packageName) {
        final startTime = activeStartTime < startBoundary ? startBoundary : activeStartTime;
        final endTime = endBoundary;
        final duration = endTime - startTime;
        if (duration > 0) {
          totalDurationMs += duration;
        }
      }

      return totalDurationMs;
    } catch (e) {
      print("[ActiveAppsManager] Error calculating system usage: $e");
      return 0;
    }
  }
}
