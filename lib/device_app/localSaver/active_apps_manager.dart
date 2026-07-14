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
        activeAppsList.removeAt(index);
      } else {
        activeAppsList[index] = updated;
      }
    } else {
      // यदि ऐप लिस्ट में नहीं है, तो चेक करेंगे कि क्या कोई पैरामीटर सक्रिय है
      bool shouldAdd = (isFavorite == 1) || 
                       (countdown != null && countdown > 0) || 
                       (todayLimit != null && todayLimit > 0);

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
          ),
        );
      }
    }

    // =========================================================================
    // BACKGROUND UPDATES (डेटाबेस और स्टोरेज का काम पीछे बैकग्राउंड में चलेगा)
    // =========================================================================
    
    // 1. अगर Favorite स्टेटस अपडेट किया गया है
    if (isFavorite != null) {
      AppDbHelper.instance.updateFavoriteStatus(packageName, isFavorite == 1);
    }

    // 2. अगर Countdown Delay अपडेट किया गया है
    if (countdown != null) {
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
    final usageMs = await calculateTodaySystemUsage(packageName);

    // B. रैम (इन-मेमोरी) लिस्ट को दोबारा अपडेटेड यूसेज के साथ रिफ्रेश करें
    int index = activeAppsList.indexWhere((app) => app.packageName == packageName);
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
      );
    }

    // C. SQLite डेटाबेस में लिमिट और यूसेज दोनों सेव करें
    await AppDbHelper.instance.updateAppLimit(packageName, limitMs, usageMs);

    // D. बैकग्राउंड सर्विस को नोटिफ़ाई करें
    _notifyLimitChanged(packageName);
  }

  // बैकग्राउंड सर्विस को लिमिट चेंज के बारे में नोटिफ़ाई करने का हेल्पर
  static void _notifyLimitChanged(String packageName) {
    try {
      final service = FlutterBackgroundService();
      service.invoke('limitChanged', {'packageName': packageName});
    } catch (_) {}
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
