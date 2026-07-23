import 'dart:async';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:usage_stats/usage_stats.dart';
import '../localSaver/db_helper.dart';
import '../localSaver/active_apps_manager.dart';
import '../localSaver/custom_app_model.dart';
import 'usage_helper.dart';
import 'overlay_helper.dart';

/// Accessibility App Monitor:
/// Jab user dwara Accessibility Service enable hoti hai, tab ye class real-time 
/// accessibility events ke zariye open/closed apps track aur check karti hai.
class AccessibilityAppMonitor {
  static final Map<String, Timer> _appTimers = {};
  static String? _openApp;
  static int _openAppStart = 0;
  static final Map<String, int> _sessionStartUsage = {};
  static final Map<String, int> _allowedUntilMap = {};

  static String? get openApp => _openApp;
  static int get openAppStart => _openAppStart;
  static Map<String, int> get sessionStartUsage => _sessionStartUsage;
  static Map<String, Timer> get appTimers => _appTimers;

  /// Extended 2-minute time window set karta hai
  static void setAllowedExtendWindow(String pkg, int extendMinutes) {
    final now = DateTime.now().millisecondsSinceEpoch;
    _allowedUntilMap[pkg] = now + (extendMinutes * 60000);
    _openAppStart = now;
    _openApp = pkg;
    print("[AccessibilityAppMonitor] Extended window set for $pkg: $extendMinutes mins from now (until ${_allowedUntilMap[pkg]}).");
  }

  /// Pure app session ko database aur memory me commit karta hai
  /// (User ne app kitni der chalaya uska total count calculate karke SQLite aur RAM me update karta hai)
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

      print("[AccessibilityAppMonitor] Committing session for $pkg: duration ${duration / 1000}s, final usage ${finalUsage / 1000}s");

      // Memory (RAM) list ko update karta hai
      ActiveAppsManager.updateApp(
        packageName: pkg,
        displayName: app.displayName,
        isSystemApp: app.isSystemApp,
        todayUsage: finalUsage,
        isServiceIsolate: true,
      );
    }

    _sessionStartUsage.remove(pkg);
  }

  /// Package name check karke dekhta hai ki app ka daily limit exhaust/reach hua hai ya nahi
  static Future<bool> isPackageBlocked(String pkg, int now) async {
    if (pkg.isEmpty || isIgnoredPackage(pkg)) return false;

    CustomAppModel? app;
    for (final a in ActiveAppsManager.activeAppsList) {
      if (a.packageName == pkg) {
        app = a;
        break;
      }
    }
    app ??= await AppDbHelper.instance.getApp(pkg);

    if (app == null) return false;
    final limitMs = app.todayLimit;
    if (limitMs <= 0) return false;

    final allowedLimit = limitMs + app.extraLimit;
    if (app.todayUsage >= allowedLimit) return true;

    return false;
  }

  /// Jab accessibility service se naye app opening ka event milta hai,
  /// tab ye function usage sync karta hai, overlays trigger karta hai aur precise limit timer schedule karta hai.
  static Future<void> handleAccessibilityPackageChange(String newPackage) async {
    try {
      final now = DateTime.now().millisecondsSinceEpoch;

      // System apps ya launcher wapas aane par overlay remove aur restrict state clear karta hai
      if (isIgnoredPackage(newPackage)) {
        final lowerPkg = newPackage.toLowerCase();
        final isLauncherOrHome = lowerPkg.contains('launcher') || lowerPkg.contains('home');

        if (isLauncherOrHome) {
          final isOverlayActive = await FlutterOverlayWindow.isActive();
          if (isOverlayActive) {
            await FlutterOverlayWindow.closeOverlay();
          }
          final prefs = await SharedPreferences.getInstance();
          await prefs.remove('last_restricted_package');
          await prefs.remove('last_restricted_time');
          print("[AccessibilityAppMonitor] Reset on Home/Launcher return: $newPackage");

          if (_openApp != null && _openApp!.isNotEmpty) {
            await commitOpenSession(_openApp!, _openAppStart, now);
            if (_appTimers.containsKey(_openApp!)) {
              _appTimers[_openApp!]?.cancel();
              _appTimers.remove(_openApp!);
            }
            _openApp = null;
            _openAppStart = 0;
          }
        }
        return;
      }

      final isOverlayActive = await FlutterOverlayWindow.isActive();
      if (isOverlayActive) {
        _openApp = null;
        _openAppStart = 0;
        return;
      }

      String? currentOpenApp = _openApp;
      int currentOpenStart = _openAppStart > 0 ? _openAppStart : now;

      // Agar same app fir se trigger ho (e.g. limit extend ho ya window refocus ho), toh session commit nahi karenge
      if (newPackage == currentOpenApp && currentOpenApp != null && currentOpenApp.isNotEmpty) {
        if (_openApp != null) {
          await scheduleAccessibilityCheck(_openApp!, _openAppStart);
        }
        return;
      }

      // App switch hone par pichhle app ki session timing calculate aur save karta hai
      if (newPackage != currentOpenApp) {
        print("[AccessibilityAppMonitor] App changed from $currentOpenApp to $newPackage");

        if (currentOpenApp != null && _appTimers.containsKey(currentOpenApp)) {
          _appTimers[currentOpenApp]?.cancel();
          _appTimers.remove(currentOpenApp);
        }

        if (currentOpenApp != null && currentOpenApp.isNotEmpty) {
          await commitOpenSession(currentOpenApp, currentOpenStart, now);
        }

        // Naye opened app ka OS usage fetch karke RAM aur DB sync karta hai
        if (newPackage.isNotEmpty && !isIgnoredPackage(newPackage)) {
          final hasUsagePermission = await UsageStats.checkUsagePermission() ?? false;
          if (hasUsagePermission) {
            final systemUsageToday = await calculateSystemUsageForPackage(newPackage);

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

            print("[AccessibilityAppMonitor] Synced system usage for $newPackage: ${systemUsageToday / 1000}s today.");
          }
        }

        // App blocked hai toh blocker overlay dikhata hai, varna delay overlay trigger karta hai
        if (newPackage.isNotEmpty && !isIgnoredPackage(newPackage)) {
          CustomAppModel? app;
          for (final a in ActiveAppsManager.activeAppsList) {
            if (a.packageName == newPackage) {
              app = a;
              break;
            }
          }
          app ??= await AppDbHelper.instance.getApp(newPackage);

          final isBlocked = await isPackageBlocked(newPackage, now);
          if (isBlocked) {
            final limitMs = app?.todayLimit ?? 0;
            await blockApp(newPackage, limitMs, app?.todayUsage ?? 0);
            _openApp = null;
            _openAppStart = 0;
            return;
          } else {
            final reminderOpt = ActiveAppsManager.reminderOptionSetting;

            if (reminderOpt == -1) {
              // Mode -1: No reminder -> Proceed directly
              print("[AccessibilityAppMonitor] Reminder disabled (-1). Proceeding without session prompt for $newPackage.");
              _openApp = newPackage;
              _openAppStart = now;
              _sessionStartUsage[newPackage] = app?.todayUsage ?? 0;
            } else if (reminderOpt > 0) {
              // Mode > 0: Pre-set duration (e.g. 5m)
              final preSetMs = reminderOpt * 60000;
              int sessionStart = ActiveAppsManager.sessionStartTimeMap[newPackage] ?? 0;
              if (sessionStart <= 0) {
                ActiveAppsManager.sessionLimitMap[newPackage] = preSetMs;
                ActiveAppsManager.sessionStartTimeMap[newPackage] = now;
                sessionStart = now;
              }

              final elapsedSession = now - sessionStart;
              final isSessionActive = elapsedSession < preSetMs;

              if (isSessionActive) {
                _openApp = newPackage;
                _openAppStart = now;
                _sessionStartUsage[newPackage] = app?.todayUsage ?? 0;
              } else {
                ActiveAppsManager.sessionLimitMap.remove(newPackage);
                ActiveAppsManager.sessionStartTimeMap.remove(newPackage);
                print("🎯 [TRACK] 💡 [AUTO_REMINDER_EXPIRED] (Accessibility) Session expired for $newPackage -> Triggering Prompt!");
                await triggerSessionPromptOverlay(
                  newPackage,
                  app?.todayUsage ?? 0,
                  sessionLimitMs: preSetMs,
                  sessionUsageMs: elapsedSession,
                );
                _openApp = null;
                _openAppStart = 0;
                return;
              }
            } else {
              // Mode 0: Always ask reminder time
              final sessionLimit = ActiveAppsManager.sessionLimitMap[newPackage] ?? 0;
              final sessionStart = ActiveAppsManager.sessionStartTimeMap[newPackage] ?? 0;
              final elapsedSession = (sessionStart > 0) ? (now - sessionStart) : 0;
              final isSessionActive = sessionLimit > 0 && sessionStart > 0 && elapsedSession < sessionLimit;

              if (isSessionActive) {
                _openApp = newPackage;
                _openAppStart = now;
                _sessionStartUsage[newPackage] = app?.todayUsage ?? 0;

                final isDelayEnabled = app != null && app.countdown > 0;
                if (isDelayEnabled) {
                  final prefs = await SharedPreferences.getInstance();
                  final lastRestrictedPackage = prefs.getString('last_restricted_package') ?? '';
                  final lastRestrictTime = prefs.getInt('last_restricted_time') ?? 0;

                  if (newPackage == lastRestrictedPackage && (now - lastRestrictTime) < 15000) {
                    print("[AccessibilityAppMonitor] Skipping restrict overlay for $newPackage (recently restricted).");
                  } else {
                    print("[AccessibilityAppMonitor] Triggering restrict overlay for $newPackage.");
                    await prefs.setString('last_restricted_package', newPackage);
                    await prefs.setInt('last_restricted_time', now);
                    await triggerRestrictOverlay(newPackage, app.countdown);
                  }
                }
              } else {
                if (sessionLimit > 0) {
                  ActiveAppsManager.sessionLimitMap.remove(newPackage);
                  ActiveAppsManager.sessionStartTimeMap.remove(newPackage);
                }
                print("🎯 [TRACK] 💡 [SESSION_PROMPT] (Accessibility) Triggering Mindful Intent Overlay for $newPackage");
                await triggerSessionPromptOverlay(
                  newPackage,
                  app?.todayUsage ?? 0,
                  sessionLimitMs: sessionLimit,
                  sessionUsageMs: elapsedSession,
                );
                _openApp = null;
                _openAppStart = 0;
                return;
              }
            }
          }
        }
      }

      if (_openApp == null || _openApp!.isEmpty || isIgnoredPackage(_openApp!)) return;

      await scheduleAccessibilityCheck(_openApp!, _openAppStart);
    } catch (e) {
      print("[AccessibilityAppMonitor] Error in handleAccessibilityPackageChange: $e");
    }
  }

  /// App limit kab khatam hogi us exact remaining millisecond duration ka precise Timer schedule karta hai
  static Future<void> scheduleAccessibilityCheck(String pkg, int openAppStart) async {
    if (pkg.isEmpty) return;

    CustomAppModel? app;
    for (final a in ActiveAppsManager.activeAppsList) {
      if (a.packageName == pkg) {
        app = a;
        break;
      }
    }
    app ??= await AppDbHelper.instance.getApp(pkg);
    final limitMs = app?.todayLimit ?? 0;
    final sessionLimit = ActiveAppsManager.sessionLimitMap[pkg] ?? 0;
    if (limitMs <= 0 && sessionLimit <= 0) {
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

    print("[AccessibilityAppMonitor] Scheduling block timer for $pkg in ${timeLeft / 1000}s.");
    _appTimers[pkg] = Timer(Duration(milliseconds: timeLeft), () async {
      print("[AccessibilityAppMonitor] Precise Timer fired! Re-checking $pkg.");
      await scheduleAccessibilityCheck(pkg, openAppStart);
    });
  }

  /// Live usage calculate karta hai aur time duration exceed hone par app block karta hai
  static Future<int?> processUsageAndCheckLimit(String activePackage, int openAppStart) async {
    final now = DateTime.now().millisecondsSinceEpoch;

    CustomAppModel? app;
    for (final a in ActiveAppsManager.activeAppsList) {
      if (a.packageName == activePackage) {
        app = a;
        break;
      }
    }
    app ??= await AppDbHelper.instance.getApp(activePackage);

    if (_allowedUntilMap.containsKey(activePackage)) {
      final allowedUntil = _allowedUntilMap[activePackage]!;
      final timeLeft = allowedUntil - now;

      if (timeLeft <= 0) {
        _allowedUntilMap.remove(activePackage);
        print("[AccessibilityAppMonitor] Extended 2-min limit expired for $activePackage. Triggering Blocker.");
        final limitMs = app?.todayLimit ?? 0;
        await blockApp(activePackage, limitMs, app?.todayUsage ?? 0);
        return 0;
      }

      print("[AccessibilityAppMonitor] Extended window active for $activePackage: ${timeLeft / 1000}s remaining.");
      return timeLeft;
    }

    final limitMs = app?.todayLimit ?? 0;
    final extraLimit = app?.extraLimit ?? 0;
    final allowedLimit = limitMs + extraLimit;

    final startUsage = _sessionStartUsage[activePackage] ?? app?.todayUsage ?? 0;
    final liveExtra = now - openAppStart;
    final todayUsageMs = startUsage + (liveExtra > 0 ? liveExtra : 0);

    if (app != null) {
      ActiveAppsManager.updateApp(
        packageName: activePackage,
        displayName: app.displayName,
        isSystemApp: app.isSystemApp,
        todayUsage: todayUsageMs,
        isServiceIsolate: true,
      );
    }

    final sessionLimit = ActiveAppsManager.sessionLimitMap[activePackage] ?? 0;
    final sessionStart = ActiveAppsManager.sessionStartTimeMap[activePackage] ?? 0;
    final liveSessionUsage = (sessionStart > 0) ? (now - sessionStart) : liveExtra;
    final isSessionFinished = sessionLimit > 0 && liveSessionUsage >= sessionLimit;

    final isDailyBlocked = allowedLimit > 0 && todayUsageMs >= allowedLimit;

    if (isDailyBlocked) {
      print("🎯 [TRACK] 🚨 [DAILY_BLOCK_TRIGGER] (Accessibility) Daily limit exceeded for $activePackage. Triggering Blocker.");
      await blockApp(activePackage, limitMs, todayUsageMs);
      _openApp = null;
      _openAppStart = 0;
      return 0;
    } else if (isSessionFinished) {
      print("🎯 [TRACK] ⌛ [SESSION_FINISHED] (Accessibility) Live session finished for $activePackage (${liveSessionUsage / 1000}s >= ${sessionLimit / 1000}s). Triggering Session Prompt.");
      ActiveAppsManager.sessionLimitMap.remove(activePackage);
      ActiveAppsManager.sessionStartTimeMap.remove(activePackage);
      await triggerSessionPromptOverlay(
        activePackage,
        todayUsageMs,
        sessionLimitMs: sessionLimit,
        sessionUsageMs: liveSessionUsage,
      );
      _openApp = null;
      _openAppStart = 0;
      return 0;
    }

    int? dailyTimeLeft = (allowedLimit > 0) ? (allowedLimit - todayUsageMs).clamp(0, allowedLimit) : null;
    int? sessionTimeLeft = (sessionLimit > 0) ? (sessionLimit - liveSessionUsage).clamp(0, sessionLimit) : null;

    if (dailyTimeLeft != null && sessionTimeLeft != null) {
      return dailyTimeLeft < sessionTimeLeft ? dailyTimeLeft : sessionTimeLeft;
    }
    return dailyTimeLeft ?? sessionTimeLeft;
  }

  /// Sabhi active accessibility timers ko cancel aur clear karta hai
  static void cancelAllTimers() {
    for (final timer in _appTimers.values) {
      timer.cancel();
    }
    _appTimers.clear();
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
