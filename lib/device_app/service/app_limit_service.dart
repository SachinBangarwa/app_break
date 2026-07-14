

import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:usage_stats/usage_stats.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../localSaver/localSaver.dart';
import '../localSaver/db_helper.dart';
import '../localSaver/active_apps_manager.dart';

// ---------------------------------------------------------------------------

// Event type codes returned by usage_stats (Android UsageEvents constants).
const String _eventForeground = '1'; // MOVE_TO_FOREGROUND
const String _eventBackground = '2'; // MOVE_TO_BACKGROUND
const String _eventScreenNonInteractive = '16'; // Android 10+ screen off-ish
const String _eventScreenShutdown = '17';

const Duration _pollInterval = Duration(seconds: 4);
const Duration _shareDataDelay = Duration(milliseconds: 400);
const int _pollingThresholdMs = 3 * 60 * 1000; // 3 minutes

final Map<String, Timer> _appTimers = {};

// No in-memory state variables here, using SharedPreferences for persistence and synchronization

bool _isIgnoredPackage(String pkg) {
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

Future<bool> _isPackageBlocked(String pkg, int now) async {
  final limitMs = await UsageDataSaver.getLimit(pkg);
  if (limitMs <= 0) return false;

  final snoozeUntil = await UsageDataSaver.getSnoozeUntil(pkg);
  if (now < snoozeUntil) return false;

  final committedUsage = await UsageDataSaver.getCommittedUsage(pkg);
  if (committedUsage >= limitMs) return true;
  
  return false;
}

Future<void> _triggerRestrictOverlay(String packageName) async {
  final appName = await UsageDataSaver.getAppName(packageName);
  
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('active_overlay_type', 'restrict');
  await prefs.setString('active_restrict_package', packageName);
  final delaySeconds = prefs.getInt('delay_seconds_$packageName') ?? 10;
  
  print("[AppLimitService] Showing restrict overlay for $appName.");

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
}

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

  // Startup पर SQLite से सक्रिय (active) ऐप्स की लिस्ट रैम में लोड करें
  try {
    final activeApps = await AppDbHelper.instance.getActiveAppsFromDb();
    ActiveAppsManager.activeAppsList.clear();
    ActiveAppsManager.activeAppsList.addAll(activeApps);
    print("[AppLimitService] Loaded active apps into RAM on service start: ${activeApps.length} apps");

    // UI को ताज़ा लिस्ट सिंक करें
    final listData = activeApps.map((app) => {
      'packageName': app.packageName,
      'displayName': app.displayName,
      'isSystemApp': app.isSystemApp,
      'isFavorite': app.isFavorite,
      'countdown': app.countdown,
      'todayLimit': app.todayLimit,
      'todayUsage': app.todayUsage,
      'lastOpened': app.lastOpened,
      'icon': app.icon,
    }).toList();
    service.invoke('syncFullList', {'apps': listData});
  } catch (e) {
    print("[AppLimitService] Error loading active apps on service start: $e");
  }

  // UI से आने वाली लिस्ट सिंक रिक्वेस्ट का लिसनर
  service.on('requestActiveAppsSync').listen((event) {
    print("[AppLimitService] UI requested active apps sync. Sending list...");
    final listData = ActiveAppsManager.activeAppsList.map((app) => {
      'packageName': app.packageName,
      'displayName': app.displayName,
      'isSystemApp': app.isSystemApp,
      'isFavorite': app.isFavorite,
      'countdown': app.countdown,
      'todayLimit': app.todayLimit,
      'todayUsage': app.todayUsage,
      'lastOpened': app.lastOpened,
      'icon': app.icon,
    }).toList();
    service.invoke('syncFullList', {'apps': listData});
  });

  // UI से आने वाले लाइव बदलावों को रैम लिस्ट में सिंक करने का लिसनर
  service.on('syncActiveApp').listen((event) {
    if (event != null) {
      final pkg = event['packageName'] as String?;
      if (pkg != null && pkg.isNotEmpty) {
        final displayName = event['displayName'] as String? ?? '';
        final isSystemApp = event['isSystemApp'] as int? ?? 0;
        final isFavorite = event['isFavorite'] as int?;
        final countdown = event['countdown'] as int?;
        final todayLimit = event['todayLimit'] as int?;
        final todayUsage = event['todayUsage'] as int?;
        final lastOpened = event['lastOpened'] as int?;
        
        dynamic iconData = event['icon'];
        Uint8List? iconBytes;
        if (iconData != null) {
          if (iconData is Uint8List) {
            iconBytes = iconData;
          } else if (iconData is List) {
            iconBytes = Uint8List.fromList(List<int>.from(iconData));
          }
        }

        print("[AppLimitService] Live syncActiveApp received for $pkg: Favorite: $isFavorite, Limit: $todayLimit, Countdown: $countdown");
        ActiveAppsManager.updateApp(
          packageName: pkg,
          displayName: displayName,
          isSystemApp: isSystemApp,
          isFavorite: isFavorite,
          countdown: countdown,
          todayLimit: todayLimit,
          todayUsage: todayUsage,
          lastOpened: lastOpened,
          icon: iconBytes,
          isServiceIsolate: true,
        );
      }
    }
  });

  // Limit changed notifications from Settings/Overlay
  service.on('limitChanged').listen((event) async {
    if (event != null) {
      final pkg = event['packageName'] as String?;
      if (pkg != null && pkg.isNotEmpty) {
        print("[AppLimitService] Received limitChanged event for $pkg. Re-configuring...");
        
        final snoozeUntil = event['snoozeUntil'] as int?;
        if (snoozeUntil != null) {
          await UsageDataSaver.saveSnoozeUntil(pkg, snoozeUntil);
        }
        
        final newLimitMs = event['newLimitMs'] as int?;
        if (newLimitMs != null) {
          await UsageDataSaver.saveLimit(pkg, newLimitMs);
        }

        await _checkAndConfigureServiceState();
      }
    }
  });

  // Accessibility package changes (foreground app switched)
  service.on('packageNameChanged').listen((event) async {
    if (event != null) {
      final pkg = event['packageName'] as String?;
      print("[AppLimitService] [EVENT] packageNameChanged to: $pkg");
      await _handleAccessibilityPackageChange(pkg ?? '');
    }
  });

  // Accessibility Service itself turned ON or OFF (permission toggled by
  // the user, or the service got connected/disconnected/destroyed).
  // Re-configure immediately instead of waiting for the next poll tick,
  // so we switch between polling mode and accessibility mode with no gap.
  service.on('accessibilityStatusChanged').listen((event) async {
    print("[AppLimitService] [EVENT] accessibilityStatusChanged. Re-configuring immediately...");
    await _checkAndConfigureServiceState();
  });

  await _checkAndConfigureServiceState();
  _scheduleMidnightReset();
}

// ---------------------------------------------------------------------------
// SHARED CORE: used by BOTH polling mode and accessibility mode.
// Given the currently active package and when its session started,
// this computes usage, saves it, and triggers the blocker if needed.
// Returns the remaining timeLeft in ms, or null if there's no limit
// to enforce (no limit set, or currently snoozed).
// ---------------------------------------------------------------------------
Future<int?> _processUsageAndCheckLimit(String activePackage, int openAppStart) async {
  final now = DateTime.now().millisecondsSinceEpoch;

  final limitMs = await UsageDataSaver.getLimit(activePackage);
  if (limitMs <= 0) {
    print("[AppLimitService] [PROCESS] $activePackage has no active limit set.");
    return null;
  }

  final snoozeUntil = await UsageDataSaver.getSnoozeUntil(activePackage);
  if (now < snoozeUntil) {
    print("[AppLimitService] [PROCESS] Blocker for $activePackage is currently snoozed.");
    return null;
  }

  final committedUsage = await UsageDataSaver.getCommittedUsage(activePackage);
  final liveExtra = now - openAppStart;
  final todayUsageMs = committedUsage + (liveExtra > 0 ? liveExtra : 0);

  print("[AppLimitService] [PROCESS] Active App: $activePackage | Committed: ${committedUsage / 1000}s | Live: ${liveExtra / 1000}s | Total: ${todayUsageMs / 1000}s");

  await UsageDataSaver.saveUsage(activePackage, todayUsageMs);

  final timeLeft = (limitMs - todayUsageMs).clamp(0, limitMs);
  await UsageDataSaver.saveTimeLeft(activePackage, timeLeft);

  if (todayUsageMs >= limitMs) {
    print("[AppLimitService] [DECISION] Limit exceeded for $activePackage (Usage: ${todayUsageMs / 1000}s >= Limit: ${limitMs / 1000}s). Triggering Blocker.");
    await _blockApp(activePackage, limitMs);
  } else {
    print("[AppLimitService] [PROCESS] $activePackage has ${timeLeft / 1000}s left before blocking.");
  }

  return timeLeft;
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

    final isAccessibilityEnabled = prefs.getBool('is_accessibility_enabled') ?? false;

    if (isAccessibilityEnabled) {
      print("[AppLimitService] [DECISION] Accessibility is ENABLED. POLLING LOOP IS COMPLETELY DISABLED.");
      _isPollingActive = false;
      _isPollingLoopRunning = false;

      for (final timer in _appTimers.values) {
        timer.cancel();
      }
      _appTimers.clear();

      final activePackage = prefs.getString('active_foreground_package') ?? '';
      if (activePackage.isNotEmpty) {
        print("[AppLimitService] Current active package is: $activePackage");
        await _handleAccessibilityPackageChange(activePackage);
      }
      print("[AppLimitService] === [END] Re-configuration completed. (Accessibility Mode) ===");
      return;
    }

    bool hasActiveLimits = false;
    final List<String> appsToInitialize = [];

    for (final key in limitKeys) {
      final pkg = key.replaceFirst('limit_', '');
      final limitMs = prefs.getInt(key) ?? 0;
      if (limitMs <= 0) {
        print("[AppLimitService] Skip $pkg: limit is 0 or invalid ($limitMs ms)");
        continue;
      }

      hasActiveLimits = true;
      appsToInitialize.add(pkg);

      final todayUsageMs = await _calculateSystemUsageForPackage(pkg);
      final timeLeft = (limitMs - todayUsageMs).clamp(0, limitMs);
      await UsageDataSaver.saveTimeLeft(pkg, timeLeft);
      print("[AppLimitService] App: $pkg | Limit: ${limitMs / 60000} min | Today Usage (from OS Events): ${todayUsageMs / 1000}s | Time Left: ${timeLeft / 1000}s");
    }

    _isPollingActive = hasActiveLimits;

    if (_isPollingActive) {
      print("[AppLimitService] [DECISION] Accessibility is OFF and limits exist. Activating 4-second Polling Mode permanently.");
      for (final pkg in appsToInitialize) {
        await _initializePollingBaseline(pkg);
      }
      _startPollingLoop();
    } else {
      print("[AppLimitService] [DECISION] No active limits set. Polling loop deactivated.");
    }

    print("[AppLimitService] === [END] Re-configuration completed. Polling active: $_isPollingActive ===");
  } catch (e) {
    print("[AppLimitService] Error in _checkAndConfigureServiceState: $e");
  }
}

// ---------------------------------------------------------------------------
// ACCESSIBILITY MODE: triggered by 'packageNameChanged' events.
// No 4-sec loop here — reacts only when the foreground app actually changes.
// Uses the SAME _processUsageAndCheckLimit() core as polling mode.
// ---------------------------------------------------------------------------
// ---------------------------------------------------------------------------
// Schedules the next check for a given package in accessibility mode.
// Handles TWO cases:
//   1. App is currently snoozed -> schedules a Timer to re-check exactly
//      when the snooze ends (this was previously missing, causing the app
//      to never get re-checked until the next accessibility event).
//   2. App is not snoozed -> schedules a precise block Timer for when the
//      limit will be hit (same as before).
// This function can safely be called again by its own snooze-expiry timer
// without being blocked by the dedup guard in _handleAccessibilityPackageChange.
// ---------------------------------------------------------------------------
Future<void> _scheduleAccessibilityCheck(String pkg, int openAppStart) async {
  if (pkg.isEmpty) return;

  final now = DateTime.now().millisecondsSinceEpoch;

  final limitMs = await UsageDataSaver.getLimit(pkg);
  if (limitMs <= 0) {
    if (_appTimers.containsKey(pkg)) {
      _appTimers[pkg]?.cancel();
      _appTimers.remove(pkg);
    }
    return;
  }

  final snoozeUntil = await UsageDataSaver.getSnoozeUntil(pkg);
  if (now < snoozeUntil) {
    final snoozeRemaining = snoozeUntil - now;
    print("[AppLimitService] [ACCESSIBILITY] $pkg is snoozed for ${snoozeRemaining / 1000}s more. Scheduling re-check.");

    if (_appTimers.containsKey(pkg)) {
      _appTimers[pkg]?.cancel();
    }
    _appTimers[pkg] = Timer(Duration(milliseconds: snoozeRemaining), () async {
      print("[AppLimitService] [ACCESSIBILITY] Snooze expired for $pkg. Re-checking.");
      await _scheduleAccessibilityCheck(pkg, openAppStart);
    });
    return;
  }

  final timeLeft = await _processUsageAndCheckLimit(pkg, openAppStart);

  if (timeLeft == null || timeLeft <= 0) {
    if (_appTimers.containsKey(pkg)) {
      _appTimers[pkg]?.cancel();
      _appTimers.remove(pkg);
    }
    return;
  }

  if (_appTimers.containsKey(pkg)) {
    _appTimers[pkg]?.cancel();
  }

  print("[AppLimitService] [ACCESSIBILITY] Scheduling block timer for $pkg in ${timeLeft / 1000}s.");
  _appTimers[pkg] = Timer(Duration(milliseconds: timeLeft), () async {
    print("[AppLimitService] [ACCESSIBILITY] Precise Timer fired! Re-checking $pkg.");
    await _scheduleAccessibilityCheck(pkg, openAppStart);
  });
}

Future<void> _handleAccessibilityPackageChange(String newPackage) async {
  try {
    await UsageDataSaver.reload();
    final now = DateTime.now().millisecondsSinceEpoch;

    // 1. Handle ignored package detection and resetting restrict state
    if (_isIgnoredPackage(newPackage)) {
      final prefs = await SharedPreferences.getInstance();
      if (newPackage == 'com.example.testproject') {
        final isLauncherResumed = prefs.getBool('is_launcher_foreground') ?? false;
        if (isLauncherResumed) {
          await prefs.remove('last_restricted_package');
          await prefs.remove('last_restricted_time');
          print("[AppLimitService] [ACCESSIBILITY] Reset last restricted package on launcher return.");
        }
      } else {
        await prefs.remove('last_restricted_package');
        await prefs.remove('last_restricted_time');
        print("[AppLimitService] [ACCESSIBILITY] Reset last restricted package on system/other app return: $newPackage");
      }
    }

    String? openApp = await UsageDataSaver.getOpenApp();
    if (openApp != null && openApp.isEmpty) openApp = null;
    int openAppStart = await UsageDataSaver.getOpenAppStart() ?? now;

    // Nothing changed and timer already scheduled — nothing to do.
    if (newPackage == openApp && openApp != null && _appTimers.containsKey(openApp)) {
      return;
    }

    if (newPackage == openApp && openApp != null && !_appTimers.containsKey(openApp)) {
      openApp = null;
    }

    if (newPackage != openApp) {
      print("[AppLimitService] [ACCESSIBILITY] App changed from $openApp to $newPackage");

      if (openApp != null && _appTimers.containsKey(openApp)) {
        _appTimers[openApp]?.cancel();
        _appTimers.remove(openApp);
      }

      if (openApp != null && openApp.isNotEmpty) {
        await _commitOpenSession(openApp, openAppStart, now);
      }

      // Sync today's usage from the OS for the newly opened app to ensure committedUsage is accurate!
      if (newPackage.isNotEmpty && !_isIgnoredPackage(newPackage)) {
        final hasUsagePermission = await UsageStats.checkUsagePermission() ?? false;
        if (hasUsagePermission) {
          final systemUsageToday = await _calculateSystemUsageForPackage(newPackage);
          await UsageDataSaver.saveCommittedUsage(newPackage, systemUsageToday);
          await UsageDataSaver.saveUsage(newPackage, systemUsageToday);
          
          final limitMs = await UsageDataSaver.getLimit(newPackage);
          if (limitMs > 0) {
            final timeLeft = (limitMs - systemUsageToday).clamp(0, limitMs);
            await UsageDataSaver.saveTimeLeft(newPackage, timeLeft);
          }
          
          print("[AppLimitService] [ACCESSIBILITY] Synced system usage for $newPackage: ${systemUsageToday / 1000}s today.");
        }
      }

      // Trigger overlays if it is a user app (not ignored)
      if (newPackage.isNotEmpty && !_isIgnoredPackage(newPackage)) {
        final isBlocked = await _isPackageBlocked(newPackage, now);
        if (isBlocked) {
          final limitMs = await UsageDataSaver.getLimit(newPackage);
          await _blockApp(newPackage, limitMs);
        } else {
          // Trigger Focus Pause (AppRestrictOverlay) ONLY if delay is enabled
          final prefs = await SharedPreferences.getInstance();
          final isDelayEnabled = prefs.getBool('delay_enabled_$newPackage') ?? false;

          if (isDelayEnabled) {
            final lastRestrictedPackage = prefs.getString('last_restricted_package') ?? '';
            final lastRestrictTime = prefs.getInt('last_restricted_time') ?? 0;

            if (newPackage == lastRestrictedPackage && (now - lastRestrictTime) < 15000) {
              print("[AppLimitService] [ACCESSIBILITY] Skipping restrict overlay for $newPackage (recently restricted).");
            } else {
              print("[AppLimitService] [ACCESSIBILITY] Triggering restrict overlay for $newPackage.");
              await prefs.setString('last_restricted_package', newPackage);
              await prefs.setInt('last_restricted_time', now);
              await _triggerRestrictOverlay(newPackage);
            }
          }
        }
      }

      openApp = newPackage.isNotEmpty ? newPackage : null;
      openAppStart = now;

      await UsageDataSaver.saveOpenApp(openApp ?? '');
      await UsageDataSaver.saveOpenAppStart(openAppStart);
      await UsageDataSaver.saveLastPollTime(now);
    }

    if (openApp == null || openApp.isEmpty || _isIgnoredPackage(openApp)) return;

    // Handles both snooze-expiry rescheduling and block-timer scheduling.
    await _scheduleAccessibilityCheck(openApp, openAppStart);
  } catch (e) {
    print("[AppLimitService] Error in _handleAccessibilityPackageChange: $e");
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

// ---------------------------------------------------------------------------
// POLLING MODE: runs every 4 seconds via _pollTick().
// Detects the foreground app itself using UsageStats events, then hands off
// to the SAME shared _processUsageAndCheckLimit() core as accessibility mode.
// ---------------------------------------------------------------------------
Future<void> _runPollCycle() async {
  await UsageDataSaver.reload();

  final prefs = await SharedPreferences.getInstance();
  final isAccessibilityEnabled = prefs.getBool('is_accessibility_enabled') ?? false;
  if (isAccessibilityEnabled) {
    print("[AppLimitService] [POLL_CYCLE] Failsafe: Accessibility is enabled. Stopping polling loop.");
    await _checkAndConfigureServiceState();
    return;
  }

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

  // SAME shared logic as accessibility mode.
  final timeLeft = await _processUsageAndCheckLimit(activePackage, openAppStart);

  // Polling-mode-specific extra: if the app now has plenty of time again
  // (e.g. user extended the limit), re-check state to possibly stop polling.
  if (timeLeft != null && timeLeft > _pollingThresholdMs) {
    await _checkAndConfigureServiceState();
  }
}

Future<void> _blockApp(String activePackage, int limitMs) async {
  final prefs = await SharedPreferences.getInstance();
  final isLauncherForeground = prefs.getBool('is_launcher_foreground') ?? false;
  if (isLauncherForeground) {
    print("[AppLimitService] Blocker skipped: Launcher is currently in the foreground.");
    return;
  }

  final isOverlayActive = await FlutterOverlayWindow.isActive();
  final activeBlocked = await UsageDataSaver.getActiveBlockedPackage() ?? '';

  if (!isOverlayActive || activeBlocked != activePackage) {
    final appName = await UsageDataSaver.getAppName(activePackage);
    print("[AppLimitService] Blocker triggered! Showing overlay for $appName.");

    await prefs.setString('active_overlay_type', 'block');
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
        'overlayType': 'block',
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