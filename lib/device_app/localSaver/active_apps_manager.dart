import 'dart:async';
import 'dart:typed_data';
import 'package:get/get.dart';
import 'package:usage_stats/usage_stats.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'custom_app_model.dart';
import 'db_helper.dart';

class ActiveAppsManager {
  // इन-मेमोरी रिएक्टिव लिस्ट (GetX RxList) जिसे ऐप में कहीं भी एक्सेस किया जा सकता है
  static final RxList<CustomAppModel> activeAppsList = <CustomAppModel>[].obs;

  // ऐप के पैरामीटर्स बदलने पर लिस्ट को मेमोरी में ही अपडेट/ऐड/डिलीट करने का फ़ंक्शन
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
      // यदि ऐप पहले से लिस्ट में मौजूद है
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

      // यदि अपडेट के बाद कोई भी पैरामीटर सक्रिय नहीं बचता, तो इसे लिस्ट से हटा देंगे
      if (updated.isFavorite == 0 && updated.countdown == 0 && updated.todayLimit == 0) {
        print("[ActiveAppsManager] REMOVED app from memory list: $packageName (All parameters became 0/inactive)");
        activeAppsList.removeAt(index);
      } else {
        print("[ActiveAppsManager] UPDATED app in memory list: $packageName -> Favorite: ${updated.isFavorite}, Countdown: ${updated.countdown}s, Limit: ${updated.todayLimit}ms");
        activeAppsList[index] = updated;
      }
    } else {
      // यदि ऐप लिस्ट में नहीं है, तो चेक करेंगे कि क्या कोई पैरामीटर सक्रिय है
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

    // प्रिंट करें कि अभी रैम लिस्ट में कौन-कौन सी एक्टिव ऐप्स हैं
    print("[ActiveAppsManager] Current Active Apps in RAM: $activeAppsList");

    // =========================================================================
    // BACKGROUND UPDATES (डेटाबेस और स्टोरेज का काम पीछे बैकग्राउंड में चलेगा)
    // =========================================================================
    
    // सर्विस आइसोलेट के अंदर बैकग्राउंड अपडेट (DB लिखना और लूप्स चलाना) छोड़ देंगे क्योंकि वह पहले ही UI थ्रेड से किया जा चुका है।
    if (!isServiceIsolate) {
      // 1. अगर Favorite स्टेटस अपडेट किया गया है
      if (isFavorite != null) {
        print("[ActiveAppsManager] DATABASE UPDATE: Saving Favorite status = $isFavorite for $packageName in background");
        AppDbHelper.instance.updateFavoriteStatus(packageName, isFavorite == 1);
        _notifyLimitChanged(packageName);
      }

      // 2. अगर Countdown Delay अपडेट किया गया है
      if (countdown != null) {
        print("[ActiveAppsManager] DATABASE UPDATE: Saving Countdown Delay = ${countdown}s for $packageName in background");
        AppDbHelper.instance.updateAppCountdown(packageName, countdown);
        _notifyLimitChanged(packageName);
      }

      // 3. अगर Limit अपडेट की गई है
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

  // पीछे बैकग्राउंड में आज का यूसेज निकालकर लिस्ट और डेटाबेस दोनों जगह अपडेट करने का लॉजिक
  static void _updateLimitAndFetchUsageBackground({
    required String packageName,
    required String displayName,
    required int isSystemApp,
    Uint8List? icon,
    required int limitMs,
  }) async {
    // A. सिस्टम से आज का लाइव उपयोग (todayUsage) निकालें
    print("[ActiveAppsManager] Fetching live system usage for $packageName...");
    final usageMs = await calculateTodaySystemUsage(packageName);
    print("[ActiveAppsManager] Live system usage for $packageName fetched: ${usageMs / 1000} seconds");

    // B. रैम (इन-मेमोरी) लिस्ट को दोबारा अपडेटेड यूसेज के साथ रिफ्रेश करें
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

    // C. SQLite डेटाबेस में लिमिट और यूसेज दोनों सेव करें
    print("[ActiveAppsManager] DATABASE UPDATE: Saving todayLimit = ${limitMs}ms and todayUsage = ${usageMs}ms for $packageName in background");
    await AppDbHelper.instance.updateAppLimit(packageName, limitMs, usageMs);

    // D. बैकग्राउंड सर्विस को नोटिफ़ाई करें
    _notifyLimitChanged(packageName);
  }

  // बैकग्राउंड सर्विस को लिमिट चेंज के बारे में नोटिफ़ाई करने का हेल्पर
  static void _notifyLimitChanged(String packageName) {
    try {
      final service = FlutterBackgroundService();
      service.invoke('limitChanged', {'packageName': packageName});

      // UI की लिस्ट की स्थिति को बैकग्राउंड सर्विस की लिस्ट के साथ सिंक करें
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
        // अगर रैम लिस्ट में नहीं है, तो सर्विस को बताएं कि इसके सभी वैल्यूज़ 0/inactive हैं (ताकि सर्विस भी इसे अपनी लिस्ट से हटा दे)
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

  // सिस्टम से आज का लाइव यूसेज निकालने का हेल्पर
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
