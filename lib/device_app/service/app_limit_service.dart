import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../localSaver/localSaver.dart';
import '../localSaver/db_helper.dart';
import '../localSaver/active_apps_manager.dart';
import '../localSaver/custom_app_model.dart';
import 'limit_monitor.dart';

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

  // Load active apps into memory at start from SQLite DB
  try {
    final activeApps = await AppDbHelper.instance.getActiveAppsFromDb();
    ActiveAppsManager.activeAppsList.clear();
    ActiveAppsManager.activeAppsList.addAll(activeApps);
    print("[AppLimitService] Loaded active apps into RAM on service start: ${activeApps.length} apps");



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

  // Event Listeners from UI
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
          icon: iconBytes,
          isServiceIsolate: true,
        );
      }
    }
  });

  service.on('limitChanged').listen((event) async {
    print("[AppLimitService] limitChanged event received in background");
    await LimitMonitor.checkAndConfigureServiceState();
  });

  service.on('extendLimit').listen((event) async {
    if (event != null) {
      final pkg = event['packageName'] as String?;
      final newLimitMs = event['newLimitMs'] as int?;
      if (pkg != null && pkg.isNotEmpty && newLimitMs != null) {
        print("[AppLimitService] extendLimit event received: $pkg -> $newLimitMs ms");
        
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
          todayLimit: newLimitMs,
          isServiceIsolate: true,
        );

        await AppDbHelper.instance.updateAppLimit(pkg, newLimitMs, existing?.todayUsage ?? 0);

        service.invoke('syncActiveApp', {
          'packageName': pkg,
          'displayName': existing?.displayName ?? '',
          'isSystemApp': existing?.isSystemApp ?? 0,
          'isFavorite': existing?.isFavorite,
          'countdown': existing?.countdown,
          'todayLimit': newLimitMs,
          'todayUsage': existing?.todayUsage ?? 0,
          'lastOpened': existing?.lastOpened,
          'icon': existing?.icon,
        });

        await LimitMonitor.checkAndConfigureServiceState();
      }
    }
  });

  service.on('delayChanged').listen((event) async {
    print("[AppLimitService] delayChanged event received in background");
    await LimitMonitor.checkAndConfigureServiceState();
  });

  service.on('packageNameChanged').listen((event) async {
    final newPackage = event?['packageName'] as String? ?? '';
    print("[AppLimitService] packageNameChanged: foreground app is now -> $newPackage");
    
    final prefs = await SharedPreferences.getInstance();
    final isAccessibilityEnabled = prefs.getBool('is_accessibility_enabled') ?? false;
    
    if (isAccessibilityEnabled) {
      await LimitMonitor.handleAccessibilityPackageChange(newPackage);
    }
  });

  service.on('accessibilityStatusChanged').listen((event) async {
    final enabled = event?['enabled'] as bool? ?? false;
    print("[AppLimitService] accessibilityStatusChanged: enabled = $enabled");
    await LimitMonitor.checkAndConfigureServiceState();
  });

  service.on('requestActiveAppsSync').listen((event) async {
    print("[AppLimitService] requestActiveAppsSync event received in background");
    try {
      final activeApps = await AppDbHelper.instance.getActiveAppsFromDb();
      ActiveAppsManager.activeAppsList.clear();
      ActiveAppsManager.activeAppsList.addAll(activeApps);

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
      print("[AppLimitService] Error syncing active apps: $e");
    }
  });

  service.on('requestOverlayStatus').listen((event) async {
    final type = event?['type'] as String? ?? 'block';
    final pkg = event?['packageName'] as String? ?? '';
    print("[AppLimitService] requestOverlayStatus: type = $type, pkg = $pkg");

    final prefs = await SharedPreferences.getInstance();
    final activeType = prefs.getString('active_overlay_type') ?? '';
    
    if (type == 'restrict' && activeType == 'restrict') {
      final activeRestrictPkg = prefs.getString('active_restrict_package') ?? '';
      if (activeRestrictPkg.isNotEmpty && activeRestrictPkg == pkg) {
        final appName = await UsageDataSaver.getAppName(pkg);
        CustomAppModel? ramApp;
        for (final a in ActiveAppsManager.activeAppsList) {
          if (a.packageName == pkg) {
            ramApp = a;
            break;
          }
        }
        final delaySeconds = ramApp != null && ramApp.countdown > 0 ? ramApp.countdown : 10;
        
        FlutterOverlayWindow.shareData({
          'overlayType': 'restrict',
          'packageName': pkg,
          'appName': appName,
          'delaySeconds': delaySeconds,
        });
      }
    } else if (type == 'block' && activeType == 'block') {
      final activeBlockPkg = await UsageDataSaver.getActiveBlockedPackage() ?? '';
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

  await LimitMonitor.checkAndConfigureServiceState();
  LimitMonitor.scheduleMidnightReset();
}