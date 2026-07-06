
import 'dart:async';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:usage_stats/usage_stats.dart';
import '../localSaver/localSaver.dart';

// ---------------------------------------------------------------------------
// TODO: replace with your actual app's package id (from AndroidManifest /
// applicationId). The placeholder below is a Flutter template default and
// almost certainly wrong for a real app — keeping it wrong means the
// service could try to "monitor and block itself".
// ---------------------------------------------------------------------------
const String _selfPackageName = "com.example.testproject";

// Event type codes returned by usage_stats (Android UsageEvents constants).
const String _eventForeground = '1'; // MOVE_TO_FOREGROUND
const String _eventBackground = '2'; // MOVE_TO_BACKGROUND
const String _eventScreenNonInteractive = '16'; // Android 10+ screen off-ish
const String _eventScreenShutdown = '17';

const Duration _pollInterval = Duration(seconds: 4);
const Duration _recheckDelay = Duration(milliseconds: 1500);
const Duration _shareDataDelay = Duration(milliseconds: 400);

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

  // Self-scheduling loop: guarantees only one poll cycle is ever in
  // flight, so we never get two overlapping showOverlay() calls.
  bool isPolling = false;

  Future<void> pollOnce() async {
    if (isPolling) {
      print("[AppLimitService] Skipped overlapping poll tick.");
      return;
    }
    isPolling = true;
    try {
      await _runPollCycle();
    } catch (e) {
      print("[AppLimitService] Error in polling loop: $e");
    } finally {
      isPolling = false;
    }
  }

  void scheduleNextPoll() {
    Future.delayed(_pollInterval, () async {
      await pollOnce();
      scheduleNextPoll();
    });
  }

  scheduleNextPoll();
}

/// Sorts usage events chronologically. Used on small delta batches in more
/// than one place (main loop + recheck).
List<EventUsageInfo> _sortedByTime(List<EventUsageInfo> events) {
  events.sort((a, b) {
    final aTime = int.tryParse(a.timeStamp ?? '0') ?? 0;
    final bTime = int.tryParse(b.timeStamp ?? '0') ?? 0;
    return aTime.compareTo(bTime);
  });
  return events;
}

/// Closes out whatever app is currently "open", adding its elapsed time to
/// that package's committed total via UsageDataSaver. Called whenever we
/// hit an event that ends a session: background, screen off, or a new
/// foreground event replacing the previous one.
Future<void> _commitOpenSession(
    String? openApp,
    int openAppStart,
    int endTime,
    ) async {
  if (openApp == null || openApp.isEmpty) return;
  final duration = endTime - openAppStart;
  if (duration <= 0) return;
  await UsageDataSaver.addCommittedUsage(openApp, duration);
}

Future<void> _runPollCycle() async {
  await UsageDataSaver.reload();

  bool? hasPermission = await UsageStats.checkUsagePermission();
  if (hasPermission != true) {
    print("[AppLimitService] Usage stats permission not granted.");
    return;
  }

  bool? hasOverlayPermission = await FlutterOverlayWindow.isPermissionGranted();
  if (hasOverlayPermission != true) {
    print("[AppLimitService] Overlay permission not granted.");
    return;
  }

  final now = DateTime.now();
  final startOfDay = DateTime(now.year, now.month, now.day);
  final todayKey = "${startOfDay.year}-${startOfDay.month}-${startOfDay.day}";

  // -------------------------------------------------------------------
  // Detect day rollover / very first run ever, and reset the running
  // counters — otherwise usage would silently carry over across days.
  // -------------------------------------------------------------------
  final lastResetDay = await UsageDataSaver.getLastResetDay() ?? '';
  final isFirstRunEver = !(await UsageDataSaver.hasLastPollTime());
  final isNewDay = lastResetDay != todayKey;

  if (isFirstRunEver || isNewDay) {
    if (isNewDay && !isFirstRunEver) {
      await UsageDataSaver.resetAllUsageForNewDay();
    }
    await UsageDataSaver.saveLastResetDay(todayKey);

    // First poll of the day (or first ever) does a one-time catch-up
    // query of the full day, in case the current app was opened before
    // the service started polling. Every poll after this is a small
    // delta only.
    await UsageDataSaver.saveLastPollTime(startOfDay.millisecondsSinceEpoch);
  }

  final lastPollTimeMs =
      await UsageDataSaver.getLastPollTime() ?? startOfDay.millisecondsSinceEpoch;
  final queryStart = DateTime.fromMillisecondsSinceEpoch(lastPollTimeMs);

  // ---- DELTA QUERY: only events since the last poll, not the whole day ----
  List<EventUsageInfo> newEvents = await UsageStats.queryEvents(queryStart, now);

  if (newEvents.isNotEmpty) {
    print("[AppLimitService] newEvents: ${newEvents.map((e) => {
      'packageName': e.packageName,
      'eventType': e.eventType,
      'timeStamp': e.timeStamp,
      'className': e.className,
    }).toList()}");
  }

  // Restore in-progress session state (persisted so an isolate restart
  // doesn't lose track of "what app is currently open").
  String? openApp = await UsageDataSaver.getOpenApp();
  if (openApp != null && openApp.isEmpty) openApp = null;
  int openAppStart = await UsageDataSaver.getOpenAppStart() ?? lastPollTimeMs;

  if (newEvents.isNotEmpty) {
    newEvents = _sortedByTime(newEvents);

    for (var event in newEvents) {
      final pName = event.packageName ?? '';
      if (pName.isEmpty) continue;
      final eventTime = int.tryParse(event.timeStamp ?? '0') ?? 0;
      if (eventTime == 0) continue;
      final eType = event.eventType;

      if (eType == _eventForeground) {
        // A new app came to foreground: close out whatever was open
        // before it (also correctly handles a missed/duplicate
        // background event — a new foreground always implies the
        // previous session ended, even if we never saw its type-2).
        await _commitOpenSession(openApp, openAppStart, eventTime);
        openApp = pName;
        openAppStart = eventTime;
      } else if (eType == _eventBackground) {
        if (openApp == pName) {
          await _commitOpenSession(openApp, openAppStart, eventTime);
          openApp = null;
        }
      } else if (eType == _eventScreenNonInteractive || eType == _eventScreenShutdown) {
        // Screen off / device sleep ends any open session.
        await _commitOpenSession(openApp, openAppStart, eventTime);
        openApp = null;
      }
    }
  }

  // Persist state for the next poll BEFORE any early returns below, so
  // we never lose track of "what's open" even if we bail out early.
  await UsageDataSaver.saveOpenApp(openApp ?? '');
  await UsageDataSaver.saveOpenAppStart(openAppStart);
  await UsageDataSaver.saveLastPollTime(now.millisecondsSinceEpoch);

  final activePackage = openApp ?? '';
  if (activePackage.isEmpty) {
    print("[AppLimitService] No active foreground app detected.");
    return;
  }

  if (activePackage == _selfPackageName) return;

  final limitMs = await UsageDataSaver.getLimit(activePackage);
  if (limitMs <= 0) {
    print("[AppLimitService] Active app: $activePackage | No limit set.");
    return;
  }

  final snoozeUntil = await UsageDataSaver.getSnoozeUntil(activePackage);
  if (now.millisecondsSinceEpoch < snoozeUntil) {
    final remainingSec = ((snoozeUntil - now.millisecondsSinceEpoch) / 1000).round();
    print("[AppLimitService] $activePackage is snoozed for ${remainingSec}s more, skipping check.");
    return;
  }

  // committed = time from sessions that have already ended today.
  // liveExtra = time in the CURRENT still-open session, computed on the
  //             fly (now - openAppStart). We deliberately do NOT write
  //             (committed + liveExtra) back into committed_usage — that
  //             only advances at real session boundaries via
  //             _commitOpenSession, so we never double-count.
  final committedUsage = await UsageDataSaver.getCommittedUsage(activePackage);
  final liveExtra = now.millisecondsSinceEpoch - openAppStart;
  final todayUsageMs = committedUsage + (liveExtra > 0 ? liveExtra : 0);

  // usage_<pkg> stays live-updating every poll, purely so any other
  // screen in the app reading it for a "today's usage" UI keeps working.
  await UsageDataSaver.saveUsage(activePackage, todayUsageMs);

  final limitMinutes = (limitMs / 60000).toStringAsFixed(1);
  final usageMinutes = (todayUsageMs / 60000).toStringAsFixed(1);
  print("[AppLimitService] Active: $activePackage | Limit: ${limitMinutes}m | Today Usage: ${usageMinutes}m");

  if (todayUsageMs >= limitMs) {
    final isOverlayActive = await FlutterOverlayWindow.isActive();
    final activeBlocked = await UsageDataSaver.getActiveBlockedPackage() ?? '';

    if (!isOverlayActive || activeBlocked != activePackage) {
      // Short settle-delay to dodge Android's brief event-stream lag
      // right after an app switch.
      await Future.delayed(_recheckDelay);

      final recheckNow = DateTime.now();
      // Recheck is also a small delta query: only the window between the
      // previous "now" and this recheck, not the whole day.
      final recheckEvents = _sortedByTime(
        await UsageStats.queryEvents(now, recheckNow),
      );

      String reconfirmedPackage = activePackage; // default: nothing changed
      for (var i = recheckEvents.length - 1; i >= 0; i--) {
        final eType = recheckEvents[i].eventType;
        if (eType == _eventForeground) {
          reconfirmedPackage = recheckEvents[i].packageName ?? '';
          break;
        } else if (eType == _eventBackground ||
            eType == _eventScreenNonInteractive ||
            eType == _eventScreenShutdown) {
          reconfirmedPackage = '';
          break;
        }
      }

      if (reconfirmedPackage != activePackage) {
        print("[AppLimitService] Skipped blocking $activePackage — "
            "re-check shows '$reconfirmedPackage' is actually active now "
            "(stale detection avoided).");
        if (reconfirmedPackage.isNotEmpty) {
          await UsageDataSaver.saveOpenApp(reconfirmedPackage);
          await UsageDataSaver.saveOpenAppStart(recheckNow.millisecondsSinceEpoch);
        }
        return;
      }

      final appName = await UsageDataSaver.getAppName(activePackage);
      print("[AppLimitService] Triggering overlay blocker for $appName");

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

      // Direct hand-off to the overlay isolate, to avoid the
      // SharedPreferences read race that showed a stale app name.
      Future.delayed(_shareDataDelay, () {
        FlutterOverlayWindow.shareData({
          'packageName': activePackage,
          'appName': appName,
          'limitMinutes': (limitMs / 60000).round(),
        });
      });
    }
  }
}