
import 'dart:async';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:usage_stats/usage_stats.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../localSaver/localSaver.dart';

// ---------------------------------------------------------------------------


// Event type codes returned by usage_stats (Android UsageEvents constants).
const String _eventForeground = '1'; // MOVE_TO_FOREGROUND
const String _eventBackground = '2'; // MOVE_TO_BACKGROUND
const String _eventScreenNonInteractive = '16'; // Android 10+ screen off-ish
const String _eventScreenShutdown = '17';

const Duration _pollInterval = Duration(seconds: 4);
const Duration _shareDataDelay = Duration(milliseconds: 400);

final Map<String, Timer> _appTimers = {};

class AppLimitService {
  static Future<void> initializeService() async {
    final service = FlutterBackgroundService();

    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        autoStart: true,
        isForegroundMode: true,
        initialNotificationTitle: 'App Usage Monitor',
        initialNotificationContent: 'Monitoring app limits in the background',
        foregroundServiceTypes: [AndroidForegroundType.specialUse],
      ),
      iosConfiguration: IosConfiguration(
        autoStart: true,
        onForeground: (service) {},
        onBackground: (service) => true,
      ),
    );
  }
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((event) {
      service.setAsForegroundService();
    });

    service.on('setAsBackground').listen((event) {
      service.setAsBackgroundService();
    });
  }

  service.on('stopService').listen((event) {
    service.stopSelf();
  });

  // Listen to limit changed notifications from Settings/Overlay
  service.on('limitChanged').listen((event) async {
    if (event != null) {
      final pkg = event['packageName'] as String?;
      if (pkg != null && pkg.isNotEmpty) {
        print("[AppLimitService] Received limitChanged event for $pkg. Re-configuring timers...");
        await _checkAndConfigureServiceState();
      }
    }
  });

  // Initialize service state and configure timers/polling
  await _checkAndConfigureServiceState();

  // Schedule the midnight rollover reset
  _scheduleMidnightReset();
}

List<EventUsageInfo> _sortedByTime(List<EventUsageInfo> events) {
  events.sort((a, b) {
    final aTime = int.tryParse(a.timeStamp ?? '0') ?? 0;
    final bTime = int.tryParse(b.timeStamp ?? '0') ?? 0;
    return aTime.compareTo(bTime);
  });
  return events;
}

bool _isPollingActive = false;
bool _isPollingLoopRunning = false;

Future<void> _initializePollingBaseline(String pkg) async {
  final now = DateTime.now().millisecondsSinceEpoch;
  final startOfDay = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
  final todayUsageMs = await _calculateSystemUsageForPackage(pkg);
  
  List<EventUsageInfo> events = await UsageStats.queryEvents(startOfDay, DateTime.now());
  events = _sortedByTime(events);
  
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
  
  if (isForeground && lastForegroundTime > 0) {
    final activeSessionDuration = now - lastForegroundTime;
    final committed = (todayUsageMs - activeSessionDuration).clamp(0, todayUsageMs);
    
    await UsageDataSaver.saveCommittedUsage(pkg, committed);
    await UsageDataSaver.saveUsage(pkg, todayUsageMs);
    await UsageDataSaver.saveOpenApp(pkg);
    await UsageDataSaver.saveOpenAppStart(lastForegroundTime);
    print("[AppLimitService] [BASELINE] $pkg is in FOREGROUND. Set openAppStart to $lastForegroundTime, committed to $committed ms, total to $todayUsageMs ms.");
  } else {
    await UsageDataSaver.saveCommittedUsage(pkg, todayUsageMs);
    await UsageDataSaver.saveUsage(pkg, todayUsageMs);
    await UsageDataSaver.saveOpenApp('');
    await UsageDataSaver.saveOpenAppStart(0);
    print("[AppLimitService] [BASELINE] $pkg is in BACKGROUND. Set committed and total to $todayUsageMs ms.");
  }
  await UsageDataSaver.saveLastPollTime(now);
}

Future<void> _checkAndConfigureServiceState() async {
  try {
    print("[AppLimitService] === [START] Re-configuring service state ===");
    await UsageDataSaver.reload();
    
    // Cancel all existing timers
    for (final timer in _appTimers.values) {
      timer.cancel();
    }
    _appTimers.clear();

    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys();
    final limitKeys = keys.where((k) => k.startsWith('limit_')).toList();
    print("[AppLimitService] Found limit keys in SharedPreferences: $limitKeys");
    
    bool needsPolling = false;
    final Map<String, int> activeLimits = {};

    for (final key in limitKeys) {
      final pkg = key.replaceFirst('limit_', '');
      final limitMs = prefs.getInt(key) ?? 0;
      if (limitMs <= 0) {
        print("[AppLimitService] Skip $pkg: limit is 0 or invalid ($limitMs ms)");
        continue;
      }

      final todayUsageMs = await _calculateSystemUsageForPackage(pkg);
      final timeLeft = (limitMs - todayUsageMs).clamp(0, limitMs);
      await UsageDataSaver.saveTimeLeft(pkg, timeLeft);
      print("[AppLimitService] App: $pkg | Limit: ${limitMs / 60000} min | Today Usage (from OS Events): ${todayUsageMs / 1000}s | Time Left: ${timeLeft / 1000}s");

      activeLimits[pkg] = timeLeft;

      if (timeLeft <= 3 * 60 * 1000) {
        needsPolling = true;
      }
    }

    _isPollingActive = needsPolling;

    if (_isPollingActive) {
      print("[AppLimitService] [DECISION] At least one app is near limit (<= 180s left). Activating 4-sec Polling Mode. NO TIMERS will be scheduled.");
      for (final pkg in activeLimits.keys) {
        if (activeLimits[pkg]! <= 3 * 60 * 1000) {
          await _initializePollingBaseline(pkg);
        }
      }
      _startPollingLoop();
    } else {
      print("[AppLimitService] [DECISION] All apps have plenty of time (> 180s left). Polling Mode DEACTIVATED. Scheduling quiet timers.");
      for (final entry in activeLimits.entries) {
        final pkg = entry.key;
        final timeLeft = entry.value;
        final timerDuration = timeLeft - 3 * 60 * 1000;
        _appTimers[pkg] = Timer(Duration(milliseconds: timerDuration), () async {
          print("[AppLimitService] [WAKE_UP] Timer fired for $pkg. Remaining time hits 3-minute threshold. Re-configuring state.");
          await _checkAndConfigureServiceState();
        });
        print("[AppLimitService] Scheduled quiet timer for $pkg to wake up in ${timerDuration / 1000}s.");
      }
    }
    
    print("[AppLimitService] === [END] Re-configuration completed. Polling active: $_isPollingActive ===");
  } catch (e) {
    print("[AppLimitService] Error in _checkAndConfigureServiceState: $e");
  }
}

void _startPollingLoop() {
  if (_isPollingLoopRunning) return;
  _isPollingLoopRunning = true;
  print("[AppLimitService] Starting 4-second polling loop.");
  _pollTick();
}

void _pollTick() {
  if (!_isPollingActive) {
    _isPollingLoopRunning = false;
    print("[AppLimitService] Stopping 4-second polling loop (all apps safe).");
    return;
  }
  
  Future.delayed(_pollInterval, () async {
    try {
      print("[AppLimitService] [POLL_TICK] Running 4-second poll cycle...");
      await _runPollCycle();
    } catch (e) {
      print("[AppLimitService] Error in poll cycle: $e");
    }
    _pollTick();
  });
}

Future<void> _commitOpenSession(
  String? openApp,
  int openAppStart,
  int endTime,
) async {
  if (openApp == null || openApp.isEmpty) return;
  final duration = endTime - openAppStart;
  if (duration <= 0) return;
  print("[AppLimitService] [SESSION_COMMIT] Committing $duration ms of usage to database for $openApp.");
  await UsageDataSaver.addCommittedUsage(openApp, duration);
}

Future<void> _runPollCycle() async {
  await UsageDataSaver.reload();

  bool? hasPermission = await UsageStats.checkUsagePermission();
  if (hasPermission != true) {
    print("[AppLimitService] [POLL_CYCLE] Missing UsageStats permission.");
    return;
  }

  bool? hasOverlayPermission = await FlutterOverlayWindow.isPermissionGranted();
  if (hasOverlayPermission != true) {
    print("[AppLimitService] [POLL_CYCLE] Missing Overlay Window permission.");
    return;
  }

  final now = DateTime.now();
  final startOfDay = DateTime(now.year, now.month, now.day);
  final todayKey = "${startOfDay.year}-${startOfDay.month}-${startOfDay.day}";

  // Rollover check
  final lastResetDay = await UsageDataSaver.getLastResetDay() ?? '';
  final isFirstRunEver = !(await UsageDataSaver.hasLastPollTime());
  final isNewDay = lastResetDay != todayKey;

  if (isFirstRunEver || isNewDay) {
    print("[AppLimitService] [ROLLOVER] New day detected ($todayKey). Resetting daily usages...");
    if (isNewDay && !isFirstRunEver) {
      await UsageDataSaver.resetAllUsageForNewDay();
      await _checkAndConfigureServiceState();
    }
    await UsageDataSaver.saveLastResetDay(todayKey);
    await UsageDataSaver.saveLastPollTime(startOfDay.millisecondsSinceEpoch);
  }

  final lastPollTimeMs =
      await UsageDataSaver.getLastPollTime() ?? startOfDay.millisecondsSinceEpoch;
  final queryStart = DateTime.fromMillisecondsSinceEpoch(lastPollTimeMs);

  List<EventUsageInfo> newEvents = await UsageStats.queryEvents(queryStart, now);

  String? openApp = await UsageDataSaver.getOpenApp();
  if (openApp != null && openApp.isEmpty) openApp = null;
  int openAppStart = await UsageDataSaver.getOpenAppStart() ?? lastPollTimeMs;

  if (newEvents.isNotEmpty) {
    newEvents = _sortedByTime(newEvents);
    print("[AppLimitService] [POLL_CYCLE] Queried ${newEvents.length} new OS events since last check.");

    for (var event in newEvents) {
      final pName = event.packageName ?? '';
      if (pName.isEmpty) continue;
      final eventTime = int.tryParse(event.timeStamp ?? '0') ?? 0;
      if (eventTime == 0) continue;
      final eType = event.eventType;

      if (eType == _eventForeground) {
        print("[AppLimitService] [OS_EVENT] $pName moved to FOREGROUND");
        await _commitOpenSession(openApp, openAppStart, eventTime);
        openApp = pName;
        openAppStart = eventTime;
      } else if (eType == _eventBackground) {
        print("[AppLimitService] [OS_EVENT] $pName moved to BACKGROUND");
        if (openApp == pName) {
          await _commitOpenSession(openApp, openAppStart, eventTime);
          openApp = null;
        }
      } else if (eType == _eventScreenNonInteractive || eType == _eventScreenShutdown) {
        print("[AppLimitService] [OS_EVENT] SCREEN OFF / SHUTDOWN");
        await _commitOpenSession(openApp, openAppStart, eventTime);
        openApp = null;
      }
    }
  }

  await UsageDataSaver.saveOpenApp(openApp ?? '');
  await UsageDataSaver.saveOpenAppStart(openAppStart);
  await UsageDataSaver.saveLastPollTime(now.millisecondsSinceEpoch);

  final activePackage = openApp ?? '';
  if (activePackage.isEmpty) {
    print("[AppLimitService] [POLL_CYCLE] No active app currently in foreground.");
    return;
  }

  final limitMs = await UsageDataSaver.getLimit(activePackage);
  if (limitMs <= 0) {
    print("[AppLimitService] [POLL_CYCLE] Current active app $activePackage has no active limit set.");
    return;
  }

  final snoozeUntil = await UsageDataSaver.getSnoozeUntil(activePackage);
  if (now.millisecondsSinceEpoch < snoozeUntil) {
    print("[AppLimitService] [POLL_CYCLE] Blocker for $activePackage is currently snoozed.");
    return;
  }

  final committedUsage = await UsageDataSaver.getCommittedUsage(activePackage);
  final liveExtra = now.millisecondsSinceEpoch - openAppStart;
  final todayUsageMs = committedUsage + (liveExtra > 0 ? liveExtra : 0);

  print("[AppLimitService] [POLL_CYCLE] Active App: $activePackage | Committed: ${committedUsage / 1000}s | Live Active Session: ${liveExtra / 1000}s | Total: ${todayUsageMs / 1000}s");

  await UsageDataSaver.saveUsage(activePackage, todayUsageMs);

  final timeLeft = (limitMs - todayUsageMs).clamp(0, limitMs);
  await UsageDataSaver.saveTimeLeft(activePackage, timeLeft);

  if (todayUsageMs >= limitMs) {
    print("[AppLimitService] [DECISION] Limit exceeded for $activePackage (Usage: ${todayUsageMs / 1000}s >= Limit: ${limitMs / 1000}s). Triggering Blocker.");
    await _blockApp(activePackage, limitMs);
  } else {
    print("[AppLimitService] [POLL_CYCLE] $activePackage has ${timeLeft / 1000}s left before blocking.");
    // If user got more time, re-check state to maybe stop polling
    if (timeLeft > 3 * 60 * 1000) {
      await _checkAndConfigureServiceState();
    }
  }
}

Future<void> _blockApp(String activePackage, int limitMs) async {
  final isOverlayActive = await FlutterOverlayWindow.isActive();
  final activeBlocked = await UsageDataSaver.getActiveBlockedPackage() ?? '';

  if (!isOverlayActive || activeBlocked != activePackage) {
    final appName = await UsageDataSaver.getAppName(activePackage);
    print("[AppLimitService] Blocker triggered! Showing overlay for $appName.");

    await UsageDataSaver.saveActiveBlockedPackage(activePackage);
    await UsageDataSaver.saveActiveBlockedName(appName);

    await FlutterOverlayWindow.showOverlay(
      alignment: OverlayAlignment.center,
      height: WindowSize.matchParent,
      width: WindowSize.matchParent,
      overlayTitle: "Time Limit Reached",
      overlayContent: "You have spent too much time on $appName today.",
      enableDrag: false,
    );

    Future.delayed(_shareDataDelay, () {
      FlutterOverlayWindow.shareData({
        'packageName': activePackage,
        'appName': appName,
        'limitMinutes': (limitMs / 60000).round(),
      });
    });
  }
}

void _scheduleMidnightReset() {
  final now = DateTime.now();
  final tomorrow = DateTime(now.year, now.month, now.day + 1);
  final msUntilMidnight = tomorrow.difference(now).inMilliseconds;

  Timer(Duration(milliseconds: msUntilMidnight), () async {
    print("[AppLimitService] Midnight reached! Resetting usage for new day.");
    await UsageDataSaver.resetAllUsageForNewDay();
    await _checkAndConfigureServiceState();
    _scheduleMidnightReset();
  });
}



Future<int> _calculateSystemUsageForPackage(String packageName) async {
  final now = DateTime.now();
  final startOfDay = DateTime(now.year, now.month, now.day);
  
  List<EventUsageInfo> events = await UsageStats.queryEvents(startOfDay, now);
  events = _sortedByTime(events);
  
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