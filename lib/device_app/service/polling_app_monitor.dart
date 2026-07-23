import 'dart:async';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:usage_stats/usage_stats.dart';
import '../localSaver/db_helper.dart';
import '../localSaver/active_apps_manager.dart';
import '../localSaver/custom_app_model.dart';
import 'usage_helper.dart';
import 'accessibility_app_monitor.dart';
import 'overlay_helper.dart';

/// Polling App Monitor:
/// Jab Accessibility Service OFF hoti hai, tab ye class har 4 second me OS se Usage Events
/// query karke active foreground app, screen time aur usage limits check/enforce karti hai.
class PollingAppMonitor {
  static bool _isPollingActive = false;
  static bool _isPollingLoopRunning = false;
  static const Duration _pollInterval = Duration(seconds: 4);

  static String? _openApp;
  static int _openAppStart = 0;
  static int _lastPollTimeMs = 0;
  static final Map<String, int> _sessionStartUsage = {};

  static final Map<String, int> _allowedUntilMap = {};

  static bool get isPollingActive => _isPollingActive;
  static bool get isPollingLoopRunning => _isPollingLoopRunning;

  /// Extended 2-minute time window set karta hai
  static void setAllowedExtendWindow(String pkg, int extendMinutes) {
    final now = DateTime.now().millisecondsSinceEpoch;
    _allowedUntilMap[pkg] = now + (extendMinutes * 60000);
    _openAppStart = now;
    _openApp = pkg;
  }

  /// Polling state set karta hai (Active / Inactive)
  static void setPollingActive(bool active) {
    _isPollingActive = active;
  }

  /// 4-Second Periodic Polling Loop ko shuru karta hai
  static void startPollingLoop() {
    if (_isPollingLoopRunning) return;
    _isPollingLoopRunning = true;
    print("🚀 [PollingAppMonitor] 4-Second Polling Loop STARTED.");
    pollTick();
  }

  /// Polling loop ko stop karta hai
  static void stopPollingLoop() {
    _isPollingActive = false;
    _isPollingLoopRunning = false;
    print("🛑 [PollingAppMonitor] 4-Second Polling Loop STOPPED.");
  }

  /// Har 4 second par recursive timer se pollTick call hota hai
  static void pollTick() {
    if (!_isPollingActive) {
      _isPollingLoopRunning = false;
      print("🛑 [PollingAppMonitor] Polling loop inactive. Terminating tick.");
      return;
    }

    Future.delayed(_pollInterval, () async {
      try {
        await runPollCycle();
      } catch (e) {
        print("❌ [PollingAppMonitor] Error in poll cycle: $e");
      }
      pollTick();
    });
  }

  /// Har 4 second cycle me OS events fetch aur process karta hai
  static Future<void> runPollCycle() async {
    final prefs = await SharedPreferences.getInstance();
    final isAccessibilityEnabled =
        prefs.getBool('is_accessibility_enabled') ?? false;

    // Failsafe: Agar accessibility enable ho gayi hai toh polling turant stop kar deta hai
    if (isAccessibilityEnabled) {
      print(
        "🛡️ [PollingAppMonitor] Failsafe: Accessibility is ENABLED -> Stopping Polling Loop.",
      );
      stopPollingLoop();
      return;
    }

    bool? hasPermission = await UsageStats.checkUsagePermission();
    if (hasPermission != true) {
      return;
    }

    bool? hasOverlayPermission =
        await FlutterOverlayWindow.isPermissionGranted();
    if (hasOverlayPermission != true) {
      return;
    }

    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final todayKey = "${startOfDay.year}-${startOfDay.month}-${startOfDay.day}";

    final lastResetDay = prefs.getString('last_reset_day') ?? '';
    final isFirstRunEver = _lastPollTimeMs == 0;
    final isNewDay = lastResetDay != todayKey;

    // Naya din hone par daily usage reset karta hai
    if (isFirstRunEver || isNewDay) {
      print(
        "🎯 [TRACK] 🌙 [NEW_DAY_RESET] New Day Detected ($todayKey)! Resetting daily usages & extra limits to 0...",
      );
      if (isNewDay && !isFirstRunEver) {
        for (final app in ActiveAppsManager.activeAppsList) {
          ActiveAppsManager.updateApp(
            packageName: app.packageName,
            displayName: app.displayName,
            isSystemApp: app.isSystemApp,
            todayUsage: 0,
            extraLimit: 0,
            isServiceIsolate: true,
          );
          await AppDbHelper.instance.updateAppUsage(app.packageName, 0);
          await AppDbHelper.instance.updateAppExtraLimit(app.packageName, 0);
        }
      }
      await prefs.setString('last_reset_day', todayKey);
      _lastPollTimeMs = startOfDay.millisecondsSinceEpoch;
    }

    final lastPollTimeMs =
        _lastPollTimeMs > 0
            ? _lastPollTimeMs
            : startOfDay.millisecondsSinceEpoch;
    final queryStart = DateTime.fromMillisecondsSinceEpoch(lastPollTimeMs);

    List<EventUsageInfo> newEvents = await UsageStats.queryEvents(
      queryStart,
      now,
    );

    final isOverlayActive = await FlutterOverlayWindow.isActive();
    if (isOverlayActive) {
      _openApp = null;
      _openAppStart = 0;
      _lastPollTimeMs = now.millisecondsSinceEpoch;
      return;
    }

    String? openApp = _openApp;
    int openAppStart = _openAppStart > 0 ? _openAppStart : lastPollTimeMs;

    EventUsageInfo? latestPackageEntry;

    // Direct OS events read karke foreground / background app status updates compute karta hai
    if (newEvents.isNotEmpty) {
      newEvents = sortedByTime(newEvents);

      // Reverse order me iterate karke sabse latest eType == '1' or '2' entry dhundhenge
      for (int i = newEvents.length - 1; i >= 0; i--) {
        final ev = newEvents[i];
        if (ev.eventType == '1' || ev.eventType == '2') {
          latestPackageEntry = ev;
          break; // Latest event milte hi loop se nikal jayenge
        }
      }
    }

    if (latestPackageEntry != null) {
      // manager logic: eType 1 or 2 event mila hai
      final pName = latestPackageEntry.packageName ?? '';
      final eventTime = int.tryParse(latestPackageEntry.timeStamp ?? '0') ?? 0;
      final eType = latestPackageEntry.eventType;

      if (eType == '1') {
        print(
          "🎯 [TRACK] 📱 [APP_OPENED] MOVE_TO_FOREGROUND (eType 1) -> Package: $pName | Time: ${DateTime.fromMillisecondsSinceEpoch(eventTime)}",
        );
      } else if (eType == '2') {
        print(
          "🎯 [TRACK] 🔙 [APP_CLOSED] MOVE_TO_BACKGROUND (eType 2) -> Package: $pName | Time: ${DateTime.fromMillisecondsSinceEpoch(eventTime)}",
        );
      }

      if (pName.isNotEmpty && eventTime > 0) {
        // Agar koi app pehle se khula tha, toh uska session close aur save karenge
        if (openApp != null && openApp.isNotEmpty) {
          final duration = eventTime - openAppStart;
          print(
            "🎯 [TRACK] ⏳ [SESSION_CLOSED] Closing session for $openApp -> Active Session Duration: ${duration / 1000}s",
          );
          await AccessibilityAppMonitor.commitOpenSession(
            openApp,
            openAppStart,
            eventTime,
          );
          openApp = null;
          openAppStart = 0;
        }

        // Agar latest entry eType == '1' (Foreground) hai aur ignored package nahi hai
        if (eType == '1' && !isIgnoredPackage(pName)) {
          CustomAppModel? trackedApp;
          for (final a in ActiveAppsManager.activeAppsList) {
            if (a.packageName == pName) {
              trackedApp = a;
              break;
            }
          }

          final systemUsageToday = await calculateSystemUsageForPackage(pName);

          if (trackedApp != null) {
            ActiveAppsManager.updateApp(
              packageName: pName,
              displayName: trackedApp.displayName,
              isSystemApp: trackedApp.isSystemApp,
              todayUsage: systemUsageToday,
              isServiceIsolate: true,
            );

            for (final a in ActiveAppsManager.activeAppsList) {
              if (a.packageName == pName) {
                trackedApp = a;
                break;
              }
            }
          }

          final todayLimit = trackedApp?.todayLimit ?? 0;
          final extraLimit = trackedApp?.extraLimit ?? 0;
          final todayUsage = trackedApp?.todayUsage ?? systemUsageToday;
          final allowedLimit = todayLimit + extraLimit;

          print(
            "🎯 [TRACK] 📊 [USAGE_SYNC] App: $pName | RAM Usage: ${todayUsage / 1000}s | Daily Limit: ${todayLimit / 60000}m | Extra Limit: ${extraLimit / 1000}s | Allowed Total: ${allowedLimit / 1000}s",
          );

          final isBlocked = todayLimit > 0 && todayUsage >= allowedLimit;
          if (isBlocked) {
            print(
              "🎯 [TRACK] 🚨 [DAILY_BLOCK_TRIGGER] Daily Limit Exceeded for $pName! (Usage: ${todayUsage / 1000}s >= Allowed Daily: ${allowedLimit / 1000}s) -> Triggering Overlay Blocker!",
            );
            await blockApp(pName, todayLimit, todayUsage);
            openApp = null;
            openAppStart = 0;
          } else {
            final reminderOpt = ActiveAppsManager.reminderOptionSetting;

            if (reminderOpt == -1) {
              print(
                "🎯 [TRACK] 🚫 [NO_REMINDER_MODE] Reminder setting is 'No reminder' (-1). Starting session directly for $pName",
              );
              openApp = pName;
              openAppStart = eventTime;
              _sessionStartUsage[pName] = todayUsage;
            } else if (reminderOpt > 0) {
              final preSetMs = reminderOpt * 60000;
              final nowMs = now.millisecondsSinceEpoch;

              int sessionStart =
                  ActiveAppsManager.sessionStartTimeMap[pName] ?? 0;
              if (sessionStart <= 0) {
                ActiveAppsManager.sessionLimitMap[pName] = preSetMs;
                ActiveAppsManager.sessionStartTimeMap[pName] = nowMs;
                sessionStart = nowMs;
              }

              final elapsedSession = nowMs - sessionStart;
              final isSessionActive = elapsedSession < preSetMs;

              if (isSessionActive) {
                print(
                  "🎯 [TRACK] ✅ [AUTO_REMINDER_ACTIVE] App $pName in auto ${reminderOpt}m session! Elapsed: ${elapsedSession / 1000}s / ${preSetMs / 60000}m",
                );
                openApp = pName;
                openAppStart = eventTime;
                _sessionStartUsage[pName] = todayUsage;
              } else {
                ActiveAppsManager.sessionLimitMap.remove(pName);
                ActiveAppsManager.sessionStartTimeMap.remove(pName);
                print(
                  "🎯 [TRACK] 💡 [AUTO_REMINDER_EXPIRED] Auto ${reminderOpt}m session expired for $pName! Triggering Session Prompt Overlay!",
                );
                await triggerSessionPromptOverlay(
                  pName,
                  todayUsage,
                  sessionLimitMs: preSetMs,
                  sessionUsageMs: elapsedSession,
                );
                openApp = null;
                openAppStart = 0;
              }
            } else {
              final nowMs = now.millisecondsSinceEpoch;
              final sessionLimit =
                  ActiveAppsManager.sessionLimitMap[pName] ?? 0;
              final sessionStart =
                  ActiveAppsManager.sessionStartTimeMap[pName] ?? 0;
              final elapsedSession =
                  (sessionStart > 0) ? (nowMs - sessionStart) : 0;
              final isSessionActive =
                  sessionLimit > 0 &&
                  sessionStart > 0 &&
                  elapsedSession < sessionLimit;

              if (isSessionActive) {
                print(
                  "🎯 [TRACK] ✅ [SESSION_ACTIVE_RUN] App $pName inside active session! Elapsed: ${elapsedSession / 1000}s / Session Limit: ${sessionLimit / 60000}m | Daily Usage: ${todayUsage / 1000}s / Daily Limit: ${allowedLimit / 60000}m",
                );
                openApp = pName;
                openAppStart = eventTime;
                _sessionStartUsage[pName] = todayUsage;
              } else {
                if (sessionLimit > 0) {
                  ActiveAppsManager.sessionLimitMap.remove(pName);
                  ActiveAppsManager.sessionStartTimeMap.remove(pName);
                }
                print(
                  "🎯 [TRACK] 💡 [SESSION_PROMPT_TRIGGER] Session limit not active/expired for $pName! (Session Limit: ${sessionLimit / 60000}m, Elapsed: ${elapsedSession / 1000}s) -> Triggering Mindful Intent Overlay!",
                );
                await triggerSessionPromptOverlay(
                  pName,
                  todayUsage,
                  sessionLimitMs: sessionLimit,
                  sessionUsageMs: elapsedSession,
                );
                openApp = null;
                openAppStart = 0;
              }
            }
          }
        }
      }
    } else {
      // manager logic: eType 1 or 2 event nahi mila
      // Check karenge ki kya screen off (16) ya shutdown (17) event aaya hai
      bool isScreenOffOrShutdown = false;
      int systemEventTime = now.millisecondsSinceEpoch;

      for (var ev in newEvents) {
        if (ev.eventType == '16' || ev.eventType == '17') {
          isScreenOffOrShutdown = true;
          systemEventTime =
              int.tryParse(ev.timeStamp ?? '0') ?? now.millisecondsSinceEpoch;
          break;
        }
      }

      if (isScreenOffOrShutdown) {
        print("🎯 [TRACK] 🔒 [SCREEN_OFF] Committing session for $openApp");
        if (openApp != null && openApp.isNotEmpty) {
          await AccessibilityAppMonitor.commitOpenSession(
            openApp,
            openAppStart,
            systemEventTime,
          );
          openApp = null;
          openAppStart = 0;
        }
      } else {
        // Kuch nahi hua (user same app use kar raha hai)
        if (openApp != null &&
            openApp.isNotEmpty &&
            !isIgnoredPackage(openApp)) {
          CustomAppModel? trackedApp;
          for (final a in ActiveAppsManager.activeAppsList) {
            if (a.packageName == openApp) {
              trackedApp = a;
              break;
            }
          }

          final limitMs = trackedApp?.todayLimit ?? 0;
          final extraMs = trackedApp?.extraLimit ?? 0;
          final allowedMs = limitMs + extraMs;

          final startUsage =
              _sessionStartUsage[openApp] ?? trackedApp?.todayUsage ?? 0;
          final liveExtra = now.millisecondsSinceEpoch - openAppStart;
          final liveUsage = startUsage + liveExtra;

          final sessionLimit = ActiveAppsManager.sessionLimitMap[openApp] ?? 0;
          final sessionStart =
              ActiveAppsManager.sessionStartTimeMap[openApp] ?? 0;
          final liveSessionUsage =
              (sessionStart > 0)
                  ? (now.millisecondsSinceEpoch - sessionStart)
                  : liveExtra;

          print(
            "🎯 [TRACK] ▶️ [LIVE_RUNNING] App: $openApp | Live Session: ${liveSessionUsage / 1000}s / ${sessionLimit / 60000}m | Total Daily Usage: ${liveUsage / 1000}s / ${allowedMs / 60000}m",
          );

          final isDailyBlocked = allowedMs > 0 && liveUsage >= allowedMs;
          final isSessionFinished =
              sessionLimit > 0 && liveSessionUsage >= sessionLimit;

          if (isDailyBlocked) {
            print(
              "🎯 [TRACK] 🚨 [DAILY_BLOCK_TRIGGER] Daily Limit Exceeded for $openApp during continuous run! (Live Daily: ${liveUsage / 1000}s >= Allowed Daily: ${allowedMs / 1000}s) -> Triggering Overlay Blocker!",
            );
            await blockApp(openApp, limitMs, liveUsage);

            openApp = null;
            openAppStart = 0;
          } else if (isSessionFinished) {
            print(
              "🎯 [TRACK] ⌛ [SESSION_FINISHED] Session time finished for $openApp (${liveSessionUsage / 1000}s >= ${sessionLimit / 1000}s) -> Triggering Session Prompt!",
            );

            ActiveAppsManager.sessionLimitMap.remove(openApp);
            ActiveAppsManager.sessionStartTimeMap.remove(openApp);

            await triggerSessionPromptOverlay(
              openApp,
              liveUsage,
              sessionLimitMs: sessionLimit,
              sessionUsageMs: liveSessionUsage,
            );

            openApp = null;
            openAppStart = 0;
          } else {
            if (trackedApp != null) {
              ActiveAppsManager.updateApp(
                packageName: openApp,
                displayName: trackedApp.displayName,
                isSystemApp: trackedApp.isSystemApp,
                todayUsage: liveUsage,
                sessionUsage: liveSessionUsage,
                isServiceIsolate: true,
              );
            }
          }
        } else {}
      }
    }

    _openApp = openApp;
    _openAppStart = openAppStart;
    _lastPollTimeMs = now.millisecondsSinceEpoch;

    // Only close overlay if user explicitly navigated to Launcher or Home Screen
    if (_openApp != null && _openApp!.isNotEmpty) {
      final lowerPkg = _openApp!.toLowerCase();
      final isLauncherOrHome =
          lowerPkg.contains('launcher') || lowerPkg.contains('home');

      if (isLauncherOrHome) {
        final isOverlayActive = await FlutterOverlayWindow.isActive();
        if (isOverlayActive) {
          print(
            "🎯 [TRACK] 🚪 [OVERLAY_DISMISS] User returned to Home/Launcher. Closing blocker overlay.",
          );
          await FlutterOverlayWindow.closeOverlay();
        }
      }
    }
  }

  /// Initial baseline usage initialize aur active foreground session detect karta hai
  static Future<void> initializePollingApps(
    List<String> appsToInitialize,
  ) async {
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

        final liveExtra =
            DateTime.now().millisecondsSinceEpoch - baseline.lastForegroundTime;
        final committed = (baseline.todayUsageMs - liveExtra).clamp(
          0,
          baseline.todayUsageMs,
        );
        _sessionStartUsage[pkg] = committed;
      } else {
        if (_openApp == pkg) {
          _openApp = null;
          _openAppStart = 0;
        }
      }
    }
  }

  /// Limit extend hone par session start time ko current time par reset karta hai
  /// taaki extended time (e.g. 2 minutes) bilkul full 120 seconds tak chale.
  static void resetSessionStartForExtend(String pkg) {
    final now = DateTime.now().millisecondsSinceEpoch;
    CustomAppModel? app;
    for (final a in ActiveAppsManager.activeAppsList) {
      if (a.packageName == pkg) {
        app = a;
        break;
      }
    }
    _sessionStartUsage[pkg] = app?.todayUsage ?? 0;
    _openAppStart = now;
    _openApp = pkg;
  }
}
