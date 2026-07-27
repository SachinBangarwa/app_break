import 'dart:async';
import 'dart:typed_data';
import 'package:get/get.dart';
import 'package:usage_stats/usage_stats.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'custom_app_model.dart';
import 'db_helper.dart';

class ActiveAppsManager {
  static final RxList<CustomAppModel> activeAppsList = <CustomAppModel>[].obs;
  static final Map<String, int> sessionLimitMap = {};
  static final Map<String, int> sessionStartTimeMap = {};
  static int reminderOptionSetting = 0;

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
    int? extraLimit,
    int? sessionLimit,
    int? sessionUsage,
    bool isServiceIsolate = false,
  }) {
    int index = activeAppsList.indexWhere(
      (app) => app.packageName == packageName,
    );

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
        extraLimit: extraLimit ?? existing.extraLimit,
        sessionLimit: sessionLimit ?? existing.sessionLimit,
        sessionUsage: sessionUsage ?? existing.sessionUsage,
      );

      if (updated.isFavorite == 0 &&
          updated.countdown == 0 &&
          updated.todayLimit == 0 &&
          updated.extraLimit == 0) {
        activeAppsList.removeAt(index);
      } else {
        activeAppsList[index] = updated;
      }
    } else {
      bool shouldAdd =
          (isFavorite == 1) ||
          (countdown != null && countdown > 0) ||
          (todayLimit != null && todayLimit > 0) ||
          (extraLimit != null && extraLimit > 0) ||
          (sessionLimit != null && sessionLimit > 0);

      if (shouldAdd) {
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
            extraLimit: extraLimit ?? 0,
            sessionLimit: sessionLimit ?? 0,
            sessionUsage: sessionUsage ?? 0,
          ),
        );
      }
    }


    if (!isServiceIsolate) {
      if (isFavorite != null) {
        AppDbHelper.instance.updateFavoriteStatus(packageName, isFavorite == 1);
        _notifyLimitChanged(packageName);
      }

      if (countdown != null) {
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
    final usageMs = await calculateTodaySystemUsage(packageName);

    int index = activeAppsList.indexWhere(
      (app) => app.packageName == packageName,
    );
    if (index != -1) {
      var existing = activeAppsList[index];
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
        extraLimit: existing.extraLimit,
      );
    }

    await AppDbHelper.instance.updateAppLimit(packageName, limitMs, usageMs);

    _notifyLimitChanged(packageName);
  }

  static void _notifyLimitChanged(String packageName) {
    try {
      final service = FlutterBackgroundService();
      service.invoke('limitChanged', {'packageName': packageName});

      int index = activeAppsList.indexWhere(
        (app) => app.packageName == packageName,
      );
      if (index != -1) {
        final app = activeAppsList[index];
        service.invoke('syncActiveApp', {
          'packageName': app.packageName,
          'displayName': app.displayName,
          'isSystemApp': app.isSystemApp,
          'isFavorite': app.isFavorite,
          'countdown': app.countdown,
          'todayLimit': app.todayLimit,
          'todayUsage': app.todayUsage,
          'lastOpened': app.lastOpened,
          'extraLimit': app.extraLimit,
          'sessionLimit': app.sessionLimit,
          'sessionUsage': app.sessionUsage,
          'icon': app.icon,
        });
      } else {
        service.invoke('syncActiveApp', {
          'packageName': packageName,
          'displayName': '',
          'isSystemApp': 0,
          'isFavorite': 0,
          'countdown': 0,
          'todayLimit': 0,
          'todayUsage': 0,
          'lastOpened': 0,
          'extraLimit': 0,
        });
      }
    } catch (e) {
    }
  }

  static Future<int> calculateTodaySystemUsage(String packageName) async {
    try {
      final now = DateTime.now();
      final startOfDay = DateTime(now.year, now.month, now.day);

      List<EventUsageInfo> events = await UsageStats.queryEvents(
        startOfDay,
        now,
      );
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
            final startTime =
                activeStartTime < startBoundary
                    ? startBoundary
                    : activeStartTime;
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
              final startTime =
                  activeStartTime < startBoundary
                      ? startBoundary
                      : activeStartTime;
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
            final startTime =
                activeStartTime < startBoundary
                    ? startBoundary
                    : activeStartTime;
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
        final startTime =
            activeStartTime < startBoundary ? startBoundary : activeStartTime;
        final endTime = endBoundary;
        final duration = endTime - startTime;
        if (duration > 0) {
          totalDurationMs += duration;
        }
      }

      return totalDurationMs;
    } catch (e) {
      return 0;
    }
  }
}
