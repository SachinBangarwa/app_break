import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:testproject/device_app/localSaver/localSaver.dart';
import 'package:testproject/device_app/service/usage_helper.dart';
import '../localSaver/db_helper.dart';
import '../localSaver/active_apps_manager.dart';
import '../localSaver/custom_app_model.dart';
import 'app_limit_coordinator.dart';
import 'polling_app_monitor.dart';

/// App Limit Service:
/// Background Foreground Service initialization aur IPC events handle karta hai.
class AppLimitService {
  /// Background Service ko initialize aur configure karta hai
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

/// Background Isolate Entry Point:
/// Isolate initialize hone par active apps load karta hai aur UI se aane wale events ko listen karta hai.
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

  try {
    // Database se active apps RAM memory me load karta hai
    final activeApps = await AppDbHelper.instance.getActiveAppsFromDb();
    ActiveAppsManager.activeAppsList.clear();
    ActiveAppsManager.activeAppsList.addAll(activeApps);
    ActiveAppsManager.reminderOptionSetting = await UsageDataSaver.getReminderOption();

    // Dynamic app usage sync karta hai
    for (final app in activeApps) {
      if (app.todayLimit > 0) {
        final todayUsageMs = await getTodayUsageForPackage(app.packageName);

        ActiveAppsManager.updateApp(
          packageName: app.packageName,
          displayName: app.displayName,
          isSystemApp: app.isSystemApp,
          todayUsage: todayUsageMs,
          isServiceIsolate: true,
        );

        await AppDbHelper.instance.updateAppUsage(
          app.packageName,
          todayUsageMs,
        );
      }
    }

    final listData =
        ActiveAppsManager.activeAppsList
            .map(
              (app) => {
                'packageName': app.packageName,
                'displayName': app.displayName,
                'isSystemApp': app.isSystemApp,
                'isFavorite': app.isFavorite,
                'countdown': app.countdown,
                'todayLimit': app.todayLimit,
                'todayUsage': app.todayUsage,
                'lastOpened': app.lastOpened,
                'icon': app.icon,
              },
            )
            .toList();
    service.invoke('syncFullList', {'apps': listData});
  } catch (e) {
  }

  // Single app RAM/DB update event listener
  service.on('syncActiveApp').listen((event) async {
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
        final extraLimit = event['extraLimit'] as int?;

        final sessionLimit = event['sessionLimit'] as int?;
        final sessionUsage = event['sessionUsage'] as int?;

        dynamic iconData = event['icon'];
        Uint8List? iconBytes;
        if (iconData != null) {
          if (iconData is Uint8List) {
            iconBytes = iconData;
          } else if (iconData is List) {
            iconBytes = Uint8List.fromList(List<int>.from(iconData));
          }
        }

        ActiveAppsManager.updateApp(
          packageName: pkg,
          displayName: displayName,
          isSystemApp: isSystemApp,
          isFavorite: isFavorite,
          countdown: countdown,
          todayLimit: todayLimit,
          todayUsage: todayUsage,
          lastOpened: lastOpened,
          extraLimit: extraLimit,
          sessionLimit: sessionLimit,
          sessionUsage: sessionUsage,
          icon: iconBytes,
          isServiceIsolate: true,
        );

        await AppLimitCoordinator.checkAndConfigureServiceState();
      }
    }
  });

  // User dwara bottom sheet se session limit set karne par IPC event listener
  service.on('setSessionLimit').listen((event) async {
    if (event != null) {
      final pkg = event['packageName'] as String?;
      final sessionMinutes = (event['sessionMinutes'] as int?) ?? 5;
      final now = DateTime.now().millisecondsSinceEpoch;

      if (pkg != null && pkg.isNotEmpty) {
        final sessionMs = sessionMinutes == -1
            ? -1
            : sessionMinutes * 60000;

        ActiveAppsManager.sessionLimitMap[pkg] = sessionMs;
        ActiveAppsManager.sessionStartTimeMap[pkg] = now;


        CustomAppModel? existing;
        for (final app in ActiveAppsManager.activeAppsList) {
          if (app.packageName == pkg) {
            existing = app;
            break;
          }
        }

        ActiveAppsManager.updateApp(
          packageName: pkg,
          displayName: existing?.displayName ?? '',
          isSystemApp: existing?.isSystemApp ?? 0,
          sessionLimit: sessionMs,
          sessionUsage: 0,
          isServiceIsolate: true,
        );

        await AppLimitCoordinator.checkAndConfigureServiceState();
      }
    }
  });

  // User dwara Reminder setting change karne par RAM setting update listener
  service.on('syncReminderOption').listen((event) async {
    if (event != null) {
      final option = event['option'] as int? ?? 0;
      final oldOption = ActiveAppsManager.reminderOptionSetting;
      ActiveAppsManager.reminderOptionSetting = option;
      if (oldOption != option) {
        ActiveAppsManager.sessionStartTimeMap.clear();
        ActiveAppsManager.sessionLimitMap.clear();
      }
    }
  });

  // App limit update hone par re-configuration trigger karta hai
  service.on('limitChanged').listen((event) async {
    await AppLimitCoordinator.checkAndConfigureServiceState();
  });

  // Limit extend hone par updated time limit saves/syncs karta hai
  service.on('extendLimit').listen((event) async {
    if (event != null) {
      final pkg = event['packageName'] as String?;
      final extendMinutes = (event['extendMinutes'] as int?) ?? 2;
      final extendMs = extendMinutes * 60000;

      if (pkg != null && pkg.isNotEmpty) {
        CustomAppModel? existing;
        for (final app in ActiveAppsManager.activeAppsList) {
          if (app.packageName == pkg) {
            existing = app;
            break;
          }
        }

        final currentUsage = existing?.todayUsage ?? 0;
        final currentLimit = existing?.todayLimit ?? 0;
        final newExtraMs = (currentUsage - currentLimit) + extendMs;


        ActiveAppsManager.updateApp(
          packageName: pkg,
          displayName: existing?.displayName ?? '',
          isSystemApp: existing?.isSystemApp ?? 0,
          todayLimit: currentLimit,
          extraLimit: newExtraMs,
          todayUsage: currentUsage,
          isServiceIsolate: true,
        );

        await AppDbHelper.instance.updateAppExtraLimit(pkg, newExtraMs);

        PollingAppMonitor.setAllowedExtendWindow(pkg, extendMinutes);

        service.invoke('syncActiveApp', {
          'packageName': pkg,
          'displayName': existing?.displayName ?? '',
          'isSystemApp': existing?.isSystemApp ?? 0,
          'isFavorite': existing?.isFavorite,
          'countdown': existing?.countdown,
          'todayLimit': currentLimit,
          'extraLimit': newExtraMs,
          'todayUsage': currentUsage,
          'lastOpened': existing?.lastOpened,
          'icon': existing?.icon,
        });

        await AppLimitCoordinator.checkAndConfigureServiceState();
      }
    }
  });

  // Mindful delay setting change event listener
  service.on('delayChanged').listen((event) async {
    await AppLimitCoordinator.checkAndConfigureServiceState();
  });

  // Accessibility event listeners removed (now using only 4-second polling loop)

  // UI dwara full active apps list sync request listener
  service.on('requestActiveAppsSync').listen((event) async {
    try {
      final activeApps = await AppDbHelper.instance.getActiveAppsFromDb();
      ActiveAppsManager.activeAppsList.clear();
      ActiveAppsManager.activeAppsList.addAll(activeApps);

      final listData =
          activeApps
              .map(
                (app) => {
                  'packageName': app.packageName,
                  'displayName': app.displayName,
                  'isSystemApp': app.isSystemApp,
                  'isFavorite': app.isFavorite,
                  'countdown': app.countdown,
                  'todayLimit': app.todayLimit,
                  'todayUsage': app.todayUsage,
                  'lastOpened': app.lastOpened,
                  'icon': app.icon,
                },
              )
              .toList();
      service.invoke('syncFullList', {'apps': listData});
    } catch (e) {
    }
  });

  // Overlay status data query listener
  service.on('requestOverlayStatus').listen((event) async {
    final type = event?['type'] as String? ?? 'block';
    final pkg = event?['packageName'] as String? ?? '';

    final prefs = await SharedPreferences.getInstance();
    final activeType = prefs.getString('active_overlay_type') ?? '';

    if (type == 'restrict' && activeType == 'restrict') {
      final activeRestrictPkg =
          prefs.getString('active_restrict_package') ?? '';
      if (activeRestrictPkg.isNotEmpty && activeRestrictPkg == pkg) {
        final appName = await UsageDataSaver.getAppName(pkg);
        CustomAppModel? ramApp;
        for (final a in ActiveAppsManager.activeAppsList) {
          if (a.packageName == pkg) {
            ramApp = a;
            break;
          }
        }
        final delaySeconds =
            ramApp != null && ramApp.countdown > 0 ? ramApp.countdown : 10;

        FlutterOverlayWindow.shareData({
          'overlayType': 'restrict',
          'packageName': pkg,
          'appName': appName,
          'delaySeconds': delaySeconds,
        });
      }
    } else if (type == 'block' && activeType == 'block') {
      final activeBlockPkg =
          await UsageDataSaver.getActiveBlockedPackage() ?? '';
      if (activeBlockPkg.isNotEmpty && activeBlockPkg == pkg) {
        final appName = await UsageDataSaver.getActiveBlockedName() ?? '';
        final limitMs = await UsageDataSaver.getLimit(pkg);

        FlutterOverlayWindow.shareData({
          'overlayType': 'block',
          'packageName': pkg,
          'appName': appName,
          'limitMinutes': (limitMs / 60000).round(),
        });
      }
    }
  });

  // Coordinator start aur midnight reset setup
  await AppLimitCoordinator.checkAndConfigureServiceState();
  AppLimitCoordinator.scheduleMidnightReset();
}
