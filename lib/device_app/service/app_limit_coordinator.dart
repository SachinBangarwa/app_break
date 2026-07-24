import 'dart:async';
import '../localSaver/db_helper.dart';
import '../localSaver/active_apps_manager.dart';
import 'polling_app_monitor.dart';
import 'usage_helper.dart';

/// App Limit Coordinator:
/// Service State Manager aur Orchestrator.
/// System me Accessibility Service check karta hai aur AccessibilityAppMonitor (Real-Time)
/// ya PollingAppMonitor (4-Second Periodic Polling) ko select karke execute karta hai.
class AppLimitCoordinator {

  /// Service state inspect aur re-configure karta hai (Accessibility Mode vs 4-Second Polling Mode)
  static Future<void> checkAndConfigureServiceState() async {
    try {
      print("[AppLimitCoordinator] === [START] Re-configuring service state ===");

      final activeApps = await AppDbHelper.instance.getActiveAppsFromDb();
      ActiveAppsManager.activeAppsList.clear();
      ActiveAppsManager.activeAppsList.addAll(activeApps);

      // MODE 2: Accessibility DISABLED hai -> 4-Second Polling loop activate karo
      final List<String> appsToInitialize = [];

      for (final app in ActiveAppsManager.activeAppsList) {
        final pkg = app.packageName;
        final limitMs = app.todayLimit;
        if (limitMs <= 0) {
          continue;
        }

        appsToInitialize.add(pkg);

        final todayUsageMs = await calculateSystemUsageForPackage(pkg);
        final timeLeft = (limitMs - todayUsageMs).clamp(0, limitMs);

        ActiveAppsManager.updateApp(
          packageName: pkg,
          displayName: app.displayName,
          isSystemApp: app.isSystemApp,
          todayUsage: todayUsageMs,
          isServiceIsolate: true,
        );

        await AppDbHelper.instance.updateAppUsage(pkg, todayUsageMs);

        print("[AppLimitCoordinator] App: $pkg | Limit: ${limitMs / 60000} min | Today Usage: ${todayUsageMs / 1000}s | Time Left: ${timeLeft / 1000}s");
      }

      PollingAppMonitor.setPollingActive(true);
      print("[AppLimitCoordinator] [DECISION] Accessibility is OFF. Activating 4-second Polling Mode.");

      await PollingAppMonitor.initializePollingApps(appsToInitialize);
      PollingAppMonitor.startPollingLoop();

      print("[AppLimitCoordinator] === [END] Re-configuration completed. (4-Second Polling Mode Active) ===");
    } catch (e) {
      print("[AppLimitCoordinator] Error in checkAndConfigureServiceState: $e");
    }
  }

  /// Midnight (Raat 12 Baje) automatic daily usage reset schedule karta hai
  static void scheduleMidnightReset() {
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    final msUntilMidnight = tomorrow.difference(now).inMilliseconds;

    Timer(Duration(milliseconds: msUntilMidnight), () async {
      print("[AppLimitCoordinator] Midnight reached! Resetting usage for new day.");
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
