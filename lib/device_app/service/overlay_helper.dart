import 'dart:async';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import '../localSaver/localSaver.dart';
import '../localSaver/active_apps_manager.dart';

const Duration shareDataDelay = Duration(milliseconds: 400);

Future<void> triggerRestrictOverlay(String packageName, int delaySeconds) async {
  final appName = await UsageDataSaver.getAppName(packageName);
  

  await FlutterOverlayWindow.showOverlay(
    alignment: OverlayAlignment.center,
    height: WindowSize.matchParent,
    width: WindowSize.matchParent,
    overlayTitle: "Focus Pause",
    overlayContent: "Taking a mindful break.",
    enableDrag: false,
    flag: OverlayFlag.defaultFlag,
  );

  Future.delayed(shareDataDelay, () {
    FlutterOverlayWindow.shareData({
      'overlayType': 'restrict',
      'packageName': packageName,
      'appName': appName,
      'delaySeconds': delaySeconds,
    });
  });
}

Future<void> blockApp(String activePackage, int limitMs, int todayUsageMs) async {
  final isOverlayActive = await FlutterOverlayWindow.isActive();

  if (!isOverlayActive) {
    final appName = await UsageDataSaver.getAppName(activePackage);

    await FlutterOverlayWindow.showOverlay(
      alignment: OverlayAlignment.center,
      height: WindowSize.matchParent,
      width: WindowSize.matchParent,
      overlayTitle: "Time Limit Reached",
      overlayContent: "You have spent too much time on $activePackage today.",
      enableDrag: false,
      flag: OverlayFlag.defaultFlag,
    );

    Future.delayed(shareDataDelay, () {
      FlutterOverlayWindow.shareData({
        'overlayType': 'block',
        'packageName': activePackage,
        'appName': appName,
        'limitMs': limitMs,
        'todayUsageMs': todayUsageMs,
        'limitMinutes': (limitMs / 60000).round(),
      });
    });
  }
}

Future<void> triggerSessionPromptOverlay(
  String activePackage,
  int todayUsageMs, {
  int sessionLimitMs = 0,
  int sessionUsageMs = 0,
}) async {
  final hasLimit = ActiveAppsManager.activeAppsList.any(
    (app) => app.packageName == activePackage && app.todayLimit > 0,
  );

  if (!hasLimit) {
    return;
  }

  final isOverlayActive = await FlutterOverlayWindow.isActive();

  if (!isOverlayActive) {
    final appName = await UsageDataSaver.getAppName(activePackage);

    await FlutterOverlayWindow.showOverlay(
      alignment: OverlayAlignment.center,
      height: WindowSize.matchParent,
      width: WindowSize.matchParent,
      overlayTitle: "Mindful Pause",
      overlayContent: "Do you really need it now?",
      enableDrag: false,
      flag: OverlayFlag.defaultFlag,
    );

    Future.delayed(shareDataDelay, () {
      FlutterOverlayWindow.shareData({
        'overlayType': 'session_prompt',
        'packageName': activePackage,
        'appName': appName,
        'todayUsageMs': todayUsageMs,
        'sessionLimitMs': sessionLimitMs,
        'sessionUsageMs': sessionUsageMs,
      });
    });
  }
}
