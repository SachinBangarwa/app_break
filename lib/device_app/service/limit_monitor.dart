import 'dart:async';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:usage_stats/usage_stats.dart';
import '../localSaver/db_helper.dart';
import '../localSaver/active_apps_manager.dart';
import '../localSaver/custom_app_model.dart';
import 'usage_helper.dart';
import 'overlay_helper.dart';

class LimitMonitor {
  static final Map<String, Timer> _appTimers = {};
  static bool _isPollingActive = false;
  static bool _isPollingLoopRunning = false;

  static const Duration _pollInterval = Duration(seconds: 4);
  static const int _pollingThresholdMs = 3 * 60 * 1000; // 3 minutes

  static String? _openApp;
  static int _openAppStart = 0;
  static int _lastPollTimeMs = 0;
  static final Map<String, int> _sessionStartUsage = {};

  static Future<bool> isPackageBlocked(String pkg, int now) async {
    CustomAppModel? app;
    for (final a in ActiveAppsManager.activeAppsList) {
      if (a.packageName == pkg) {
        app = a;
        break;
      }
    }
    if (app == null) return false;
    final limitMs = app.todayLimit;
    if (limitMs <= 0) return false;

    // No snooze or SharedPreferences reads needed!
    if (app.todayUsage >= limitMs) return true;
    
    return false;
  }

  static Future<void> checkAndConfigureServiceState() async {
    try {
      print("[LimitMonitor] === [START] Re-configuring service state ===");

      // Cancel all existing timers
      for (final timer in _appTimers.values) {
        timer.cancel();
      }
      _appTimers.clear();

      final prefs = await SharedPreferences.getInstance();
      final isAccessibilityEnabled = prefs.getBool('is_accessibility_enabled') ?? false;

      if (isAccessibilityEnabled) {
        print("[LimitMonitor] [DECISION] Accessibility is ENABLED. POLLING LOOP IS COMPLETELY DISABLED.");
        _isPollingActive = false;
        _isPollingLoopRunning = false;

        for (final timer in _appTimers.values) {
          timer.cancel();
        }
        _appTimers.clear();

        final activePackage = prefs.getString('active_foreground_package') ?? '';
        if (activePackage.isNotEmpty) {
          print("[LimitMonitor] Current active package is: $activePackage");
          await handleAccessibilityPackageChange(activePackage);
        }
        print("[LimitMonitor] === [END] Re-configuration completed. (Accessibility Mode) ===");
        return;
      }

      final List<String> appsToInitialize = [];

      // Check limits from memory activeAppsList instead of SharedPreferences keys
      for (final app in ActiveAppsManager.activeAppsList) {
        final pkg = app.packageName;
        final limitMs = app.todayLimit;
        if (limitMs <= 0) {
          continue;
        }

        appsToInitialize.add(pkg);

        final todayUsageMs = await calculateSystemUsageForPackage(pkg);
        final timeLeft = (limitMs - todayUsageMs).clamp(0, limitMs);

        // Keep memory list in sync
        ActiveAppsManager.updateApp(
          packageName: pkg,
          displayName: app.displayName,
          isSystemApp: app.isSystemApp,
          todayUsage: todayUsageMs,
          isServiceIsolate: true,
        );

        // Update database as well to keep in sync
        await AppDbHelper.instance.updateAppUsage(pkg, todayUsageMs);

        print("[LimitMonitor] App: $pkg | Limit: ${limitMs / 60000} min | Today Usage (from OS Events): ${todayUsageMs / 1000}s | Time Left: ${timeLeft / 1000}s");
      }

      // ALWAYS keep polling loop active if accessibility is disabled and permission is granted!
      _isPollingActive = true;

      print("[LimitMonitor] [DECISION] Accessibility is OFF. Activating 4-second Polling Mode permanently.");
      for (final pkg in appsToInitialize) {
        final baseline = await calculatePollingBaseline(pkg);
        
        CustomAppModel? existingApp;
        for (final a in ActiveAppsManager.activeAppsList) {
          if (a.packageName == pkg) {
            existingApp = a;
            break;
          }
        }
        final isSystem = existingApp?.isSystemApp ?? 0;
        final dName = existingApp?.displayName ?? pkg;

        // Update memory list
        ActiveAppsManager.updateApp(
          packageName: pkg,
          displayName: dName,
          isSystemApp: isSystem,
          todayUsage: baseline.todayUsageMs,
          isServiceIsolate: true,
        );
        
        await AppDbHelper.instance.updateAppUsage(pkg, baseline.todayUsageMs);

        if (baseline.isForeground && baseline.lastForegroundTime > 0) {
          _openApp = pkg;
          _openAppStart = baseline.lastForegroundTime;
          
          final liveExtra = DateTime.now().millisecondsSinceEpoch - baseline.lastForegroundTime;
          final committed = (baseline.todayUsageMs - liveExtra).clamp(0, baseline.todayUsageMs);
          _sessionStartUsage[pkg] = committed;
        } else {
          if (_openApp == pkg) {
            _openApp = null;
            _openAppStart = 0;
          }
        }
      }
      startPollingLoop();

      print("[LimitMonitor] === [END] Re-configuration completed. Polling active: $_isPollingActive ===");
    } catch (e) {
      print("[LimitMonitor] Error in checkAndConfigureServiceState: $e");
    }
  }

  static Future<void> scheduleAccessibilityCheck(String pkg, int openAppStart) async {
    if (pkg.isEmpty) return;

    CustomAppModel? app;
    for (final a in ActiveAppsManager.activeAppsList) {
      if (a.packageName == pkg) {
        app = a;
        break;
      }
    }
    final limitMs = app?.todayLimit ?? 0;
    if (limitMs <= 0) {
      if (_appTimers.containsKey(pkg)) {
        _appTimers[pkg]?.cancel();
        _appTimers.remove(pkg);
      }
      return;
    }

    final timeLeft = await processUsageAndCheckLimit(pkg, openAppStart);

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

    print("[LimitMonitor] [ACCESSIBILITY] Scheduling block timer for $pkg in ${timeLeft / 1000}s.");
    _appTimers[pkg] = Timer(Duration(milliseconds: timeLeft), () async {
      print("[LimitMonitor] [ACCESSIBILITY] Precise Timer fired! Re-checking $pkg.");
      await scheduleAccessibilityCheck(pkg, openAppStart);
    });
  }

  static Future<void> commitOpenSession(String pkg, int startTime, int endTime) async {
    final duration = endTime - startTime;
    if (duration <= 0) return;

    CustomAppModel? app;
    for (final a in ActiveAppsManager.activeAppsList) {
      if (a.packageName == pkg) {
        app = a;
        break;
      }
    }
    if (app != null) {
      final startUsage = _sessionStartUsage[pkg] ?? app.todayUsage;
      final finalUsage = startUsage + duration;

      print("[LimitMonitor] Committing session for $pkg: duration ${duration / 1000}s, final usage ${finalUsage / 1000}s");

      // Update memory list
      ActiveAppsManager.updateApp(
        packageName: pkg,
        displayName: app.displayName,
        isSystemApp: app.isSystemApp,
        todayUsage: finalUsage,
        isServiceIsolate: true,
      );

      // Update SQLite DB
      await AppDbHelper.instance.updateAppUsage(pkg, finalUsage);
    }

    _sessionStartUsage.remove(pkg);
  }

  static Future<void> handleAccessibilityPackageChange(String newPackage) async {
    try {
      final now = DateTime.now().millisecondsSinceEpoch;

      // 1. Handle ignored package detection and resetting restrict state
      if (isIgnoredPackage(newPackage)) {
        final isOverlayActive = await FlutterOverlayWindow.isActive();
        if (isOverlayActive) {
          await FlutterOverlayWindow.closeOverlay();
        }
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('last_restricted_package');
        await prefs.remove('last_restricted_time');
        print("[LimitMonitor] [ACCESSIBILITY] Reset last restricted package on ignored package return: $newPackage");
      }

      String? openApp = _openApp;
      int openAppStart = _openAppStart > 0 ? _openAppStart : now;

      // Nothing changed and timer already scheduled — nothing to do.
      if (newPackage == openApp && openApp != null && _appTimers.containsKey(openApp)) {
        return;
      }

      if (newPackage == openApp && openApp != null && !_appTimers.containsKey(openApp)) {
        openApp = null;
      }

      if (newPackage != openApp) {
        print("[LimitMonitor] [ACCESSIBILITY] App changed from $openApp to $newPackage");

        if (openApp != null && _appTimers.containsKey(openApp)) {
          _appTimers[openApp]?.cancel();
          _appTimers.remove(openApp);
        }

        if (openApp != null && openApp.isNotEmpty) {
          await commitOpenSession(openApp, openAppStart, now);
        }

        // Sync today's usage from the OS for the newly opened app to ensure committedUsage is accurate!
        if (newPackage.isNotEmpty && !isIgnoredPackage(newPackage)) {
          final hasUsagePermission = await UsageStats.checkUsagePermission() ?? false;
          if (hasUsagePermission) {
            final systemUsageToday = await calculateSystemUsageForPackage(newPackage);
            
            // Update memory list
            CustomAppModel? app;
            for (final a in ActiveAppsManager.activeAppsList) {
              if (a.packageName == newPackage) {
                app = a;
                break;
              }
            }
            ActiveAppsManager.updateApp(
              packageName: newPackage,
              displayName: app?.displayName ?? '',
              isSystemApp: app?.isSystemApp ?? 0,
              todayUsage: systemUsageToday,
              isServiceIsolate: true,
            );
            
            await AppDbHelper.instance.updateAppUsage(newPackage, systemUsageToday);
            
            print("[LimitMonitor] [ACCESSIBILITY] Synced system usage for $newPackage: ${systemUsageToday / 1000}s today.");
          }
        }

        // Trigger overlays if it is a user app (not ignored)
        if (newPackage.isNotEmpty && !isIgnoredPackage(newPackage)) {
          CustomAppModel? app;
          for (final a in ActiveAppsManager.activeAppsList) {
            if (a.packageName == newPackage) {
              app = a;
              break;
            }
          }

          final isBlocked = await isPackageBlocked(newPackage, now);
          if (isBlocked) {
            final limitMs = app?.todayLimit ?? 0;
            await blockApp(newPackage, limitMs, app?.todayUsage ?? 0);
          } else {
            // Trigger Focus Pause (AppRestrictOverlay) ONLY if delay (countdown) is enabled in list
            final isDelayEnabled = app != null && app.countdown > 0;

            if (isDelayEnabled) {
              final prefs = await SharedPreferences.getInstance();
              final lastRestrictedPackage = prefs.getString('last_restricted_package') ?? '';
              final lastRestrictTime = prefs.getInt('last_restricted_time') ?? 0;

              if (newPackage == lastRestrictedPackage && (now - lastRestrictTime) < 15000) {
                print("[LimitMonitor] [ACCESSIBILITY] Skipping restrict overlay for $newPackage (recently restricted).");
              } else {
                print("[LimitMonitor] [ACCESSIBILITY] Triggering restrict overlay for $newPackage.");
                await prefs.setString('last_restricted_package', newPackage);
                await prefs.setInt('last_restricted_time', now);
                await triggerRestrictOverlay(newPackage, app.countdown);
              }
            }
          }
        }

        _openApp = newPackage.isNotEmpty ? newPackage : null;
        _openAppStart = now;

        if (_openApp != null) {
          CustomAppModel? app;
          for (final a in ActiveAppsManager.activeAppsList) {
            if (a.packageName == _openApp) {
              app = a;
              break;
            }
          }
          _sessionStartUsage[_openApp!] = app?.todayUsage ?? 0;
        }
      }

      if (_openApp == null || _openApp!.isEmpty || isIgnoredPackage(_openApp!)) return;

      await scheduleAccessibilityCheck(_openApp!, _openAppStart);
    } catch (e) {
      print("[LimitMonitor] Error in handleAccessibilityPackageChange: $e");
    }
  }

  static void startPollingLoop() {
    if (_isPollingLoopRunning) return;
    _isPollingLoopRunning = true;
    print("[LimitMonitor] Starting 4-second polling loop.");
    pollTick();
  }

  static void pollTick() {
    if (!_isPollingActive) {
      _isPollingLoopRunning = false;
      print("[LimitMonitor] Stopping 4-second polling loop (all apps safe).");
      return;
    }

    Future.delayed(_pollInterval, () async {
      try {
        print("[LimitMonitor] [POLL_TICK] Running 4-second poll cycle...");
        await runPollCycle();
      } catch (e) {
        print("[LimitMonitor] Error in poll cycle: $e");
      }
      pollTick();
    });
  }

  static Future<void> runPollCycle() async {
    final prefs = await SharedPreferences.getInstance();
    final isAccessibilityEnabled = prefs.getBool('is_accessibility_enabled') ?? false;
    if (isAccessibilityEnabled) {
      print("[LimitMonitor] [POLL_CYCLE] Failsafe: Accessibility is enabled. Stopping polling loop.");
      await checkAndConfigureServiceState();
      return;
    }

    bool? hasPermission = await UsageStats.checkUsagePermission();
    if (hasPermission != true) {
      print("[LimitMonitor] [POLL_CYCLE] Missing UsageStats permission.");
      return;
    }

    bool? hasOverlayPermission = await FlutterOverlayWindow.isPermissionGranted();
    if (hasOverlayPermission != true) {
      print("[LimitMonitor] [POLL_CYCLE] Missing Overlay Window permission.");
      return;
    }

    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final todayKey = "${startOfDay.year}-${startOfDay.month}-${startOfDay.day}";

    final lastResetDay = prefs.getString('last_reset_day') ?? '';
    final isFirstRunEver = _lastPollTimeMs == 0;
    final isNewDay = lastResetDay != todayKey;

    if (isFirstRunEver || isNewDay) {
      print("[LimitMonitor] [ROLLOVER] New day detected ($todayKey). Resetting daily usages...");
      if (isNewDay && !isFirstRunEver) {
        for (final app in ActiveAppsManager.activeAppsList) {
          ActiveAppsManager.updateApp(
            packageName: app.packageName,
            displayName: app.displayName,
            isSystemApp: app.isSystemApp,
            todayUsage: 0,
            isServiceIsolate: true,
          );
          await AppDbHelper.instance.updateAppUsage(app.packageName, 0);
        }
        await checkAndConfigureServiceState();
      }
      await prefs.setString('last_reset_day', todayKey);
      _lastPollTimeMs = startOfDay.millisecondsSinceEpoch;
    }

    final lastPollTimeMs = _lastPollTimeMs > 0 ? _lastPollTimeMs : startOfDay.millisecondsSinceEpoch;
    final queryStart = DateTime.fromMillisecondsSinceEpoch(lastPollTimeMs);

    List<EventUsageInfo> newEvents = await UsageStats.queryEvents(queryStart, now);

    String? openApp = _openApp;
    int openAppStart = _openAppStart > 0 ? _openAppStart : lastPollTimeMs;

    if (newEvents.isNotEmpty) {
      newEvents = sortedByTime(newEvents);
      print("[LimitMonitor] [POLL_CYCLE] Queried ${newEvents.length} new OS events since last check.");

      for (var event in newEvents) {
        final pName = event.packageName ?? '';
        if (pName.isEmpty) continue;
        final eventTime = int.tryParse(event.timeStamp ?? '0') ?? 0;
        if (eventTime == 0) continue;
        final eType = event.eventType;

        if (eType == '1') {
          print("[LimitMonitor] [OS_EVENT] $pName moved to FOREGROUND");
          await commitOpenSession(openApp ?? '', openAppStart, eventTime);
          openApp = pName;
          openAppStart = eventTime;
          
          CustomAppModel? app;
          for (final a in ActiveAppsManager.activeAppsList) {
            if (a.packageName == pName) {
              app = a;
              break;
            }
          }
          _sessionStartUsage[pName] = app?.todayUsage ?? 0;
        } else if (eType == '2') {
          print("[LimitMonitor] [OS_EVENT] $pName moved to BACKGROUND");
          if (openApp == pName) {
            await commitOpenSession(openApp!, openAppStart, eventTime);
            openApp = null;
          }
        } else if (eType == '16' || eType == '17') {
          print("[LimitMonitor] [OS_EVENT] SCREEN OFF / SHUTDOWN");
          if (openApp != null) {
            await commitOpenSession(openApp!, openAppStart, eventTime);
            openApp = null;
          }
        }
      }
    }

    _openApp = openApp;
    _openAppStart = openAppStart;
    _lastPollTimeMs = now.millisecondsSinceEpoch;

    final activePackage = _openApp ?? '';
    if (activePackage.isEmpty || isIgnoredPackage(activePackage)) {
      final isOverlayActive = await FlutterOverlayWindow.isActive();
      if (isOverlayActive) {
        print("[LimitMonitor] [POLL_CYCLE] Ignored app in foreground and overlay active. Closing overlay.");
        await FlutterOverlayWindow.closeOverlay();
      }
      return;
    }

    final timeLeft = await processUsageAndCheckLimit(activePackage, _openAppStart);

    if (timeLeft != null && timeLeft > _pollingThresholdMs) {
      await checkAndConfigureServiceState();
    }
  }

  static Future<int?> processUsageAndCheckLimit(String activePackage, int openAppStart) async {
    final now = DateTime.now().millisecondsSinceEpoch;

    CustomAppModel? app;
    for (final a in ActiveAppsManager.activeAppsList) {
      if (a.packageName == activePackage) {
        app = a;
        break;
      }
    }
    final limitMs = app?.todayLimit ?? 0;
    if (limitMs <= 0) {
      print("[LimitMonitor] [PROCESS] $activePackage has no active limit set.");
      return null;
    }

    final startUsage = _sessionStartUsage[activePackage] ?? app?.todayUsage ?? 0;
    final liveExtra = now - openAppStart;
    final todayUsageMs = startUsage + (liveExtra > 0 ? liveExtra : 0);

    print("[LimitMonitor] [PROCESS] Active App: $activePackage | Start Usage: ${startUsage / 1000}s | Live Extra: ${liveExtra / 1000}s | Total Today: ${todayUsageMs / 1000}s");

    // Keep memory list in sync
    if (app != null) {
      ActiveAppsManager.updateApp(
        packageName: activePackage,
        displayName: app.displayName,
        isSystemApp: app.isSystemApp,
        todayUsage: todayUsageMs,
        isServiceIsolate: true,
      );

      // Persist usage to SQLite DB
      await AppDbHelper.instance.updateAppUsage(activePackage, todayUsageMs);
    }

    final timeLeft = (limitMs - todayUsageMs).clamp(0, limitMs);

    if (todayUsageMs >= limitMs) {
      print("[LimitMonitor] [DECISION] Limit exceeded for $activePackage (Usage: ${todayUsageMs / 1000}s >= Limit: ${limitMs / 1000}s). Triggering Blocker.");
      await blockApp(activePackage, limitMs, todayUsageMs);
    } else {
      print("[LimitMonitor] [PROCESS] $activePackage has ${timeLeft / 1000}s left.");
    }

    return timeLeft;
  }

  static void scheduleMidnightReset() {
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    final msUntilMidnight = tomorrow.difference(now).inMilliseconds;

    Timer(Duration(milliseconds: msUntilMidnight), () async {
      print("[LimitMonitor] Midnight reached! Resetting usage for new day.");
      for (final app in ActiveAppsManager.activeAppsList) {
        ActiveAppsManager.updateApp(
          packageName: app.packageName,
          displayName: app.displayName,
          isSystemApp: app.isSystemApp,
          todayUsage: 0,
          isServiceIsolate: true,
        );
        await AppDbHelper.instance.updateAppUsage(app.packageName, 0);
      }
      await checkAndConfigureServiceState();
      scheduleMidnightReset();
    });
  }
}
