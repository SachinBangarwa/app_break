import 'package:usage_stats/usage_stats.dart';

// Event type codes returned by usage_stats (Android UsageEvents constants).
const String eventForeground = '1';
const String eventBackground = '2';
const String eventScreenNonInteractive = '16';
const String eventScreenShutdown = '17';

bool isIgnoredPackage(String pkg) {
  if (pkg.isEmpty) return true;
  
  final lowerPkg = pkg.toLowerCase();
  
  if (lowerPkg == 'android') return true;
  if (lowerPkg == 'com.example.testproject') return true;
  
  if (lowerPkg.contains('launcher') ||
      lowerPkg.contains('home') ||
      lowerPkg.contains('systemui') ||
      lowerPkg.contains('settings') ||
      lowerPkg.contains('packageinstaller') ||
      lowerPkg.contains('permissioncontroller') ||
      lowerPkg.contains('inputmethod') ||
      lowerPkg.contains('keyboard') ||
      lowerPkg.contains('ime')) {
    return true;
  }
  
  return false;
}

List<EventUsageInfo> sortedByTime(List<EventUsageInfo> events) {
  events.sort((a, b) {
    final aTime = int.tryParse(a.timeStamp ?? '0') ?? 0;
    final bTime = int.tryParse(b.timeStamp ?? '0') ?? 0;
    return aTime.compareTo(bTime);
  });
  return events;
}

class BaselineResult {
  final int todayUsageMs;
  final bool isForeground;
  final int lastForegroundTime;
  BaselineResult(this.todayUsageMs, this.isForeground, this.lastForegroundTime);
}


/// today usage
Future<int> getTodayUsageForPackage(String packageName) async {
  if (packageName.isEmpty) return 0;

  final now = DateTime.now();
  final startOfDay = DateTime(now.year, now.month, now.day);

  try {
    Map<String, UsageInfo> aggregatedStats = await UsageStats.queryAndAggregateUsageStats(startOfDay, now);

    if (aggregatedStats.containsKey(packageName)) {
      final totalTimeStr = aggregatedStats[packageName]?.totalTimeInForeground ?? '0';
      return int.tryParse(totalTimeStr) ?? 0;
    }
  } catch (e) {
    print("Error getting usage: $e");
  }

  return 0;
}
Future<BaselineResult> calculatePollingBaseline(String pkg) async {
  final startOfDay = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
  final todayUsageMs = await calculateSystemUsageForPackage(pkg);

  List<EventUsageInfo> events = await UsageStats.queryEvents(startOfDay, DateTime.now());
  events = sortedByTime(events);

  bool isForeground = false;
  int lastForegroundTime = 0;

  for (var event in events) {
    if (event.packageName == pkg) {
      if (event.eventType == '1') {
        isForeground = true;
        lastForegroundTime = int.tryParse(event.timeStamp ?? '0') ?? 0;
      } else if (event.eventType == '2' || event.eventType == '16' || event.eventType == '17') {
        isForeground = false;
      }
    }
  }

  return BaselineResult(todayUsageMs, isForeground, lastForegroundTime);
}

Future<int> calculateSystemUsageForPackage(String packageName) async {
  final now = DateTime.now();
  final startOfDay = DateTime(now.year, now.month, now.day);

  List<EventUsageInfo> events = await UsageStats.queryEvents(startOfDay, now);
  events = sortedByTime(events);

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
}
