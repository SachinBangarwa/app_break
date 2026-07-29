import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:get/get.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:usage_stats/usage_stats.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:testproject/screens/main_tab_screen.dart';

class OnboardingController extends GetxController with WidgetsBindingObserver {
  final hasNotificationPermission = false.obs;
  final hasUsagePermission = false.obs;
  final hasOverlayPermission = false.obs;
  final hasAccessibilityPermission = false.obs;
  final isLoading = true.obs;

  static const _channel = MethodChannel(
    'com.example.testproject/package_change',
  );

  @override
  void onInit() {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);
    checkPermissions();
  }

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    super.onClose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      checkPermissions();
    }
  }

  Future<void> checkPermissions() async {
    isLoading.value = true;
    final notifGranted = await Permission.notification.isGranted;
    final usageGranted = await UsageStats.checkUsagePermission() ?? false;
    final overlayGranted = await FlutterOverlayWindow.isPermissionGranted();

    bool accessibilityGranted = false;
    try {
      accessibilityGranted =
          await _channel.invokeMethod<bool>('checkAccessibilityPermission') ??
          false;
    } catch (e) {}

    hasNotificationPermission.value = notifGranted;
    hasUsagePermission.value = usageGranted;
    hasOverlayPermission.value = overlayGranted;
    hasAccessibilityPermission.value = accessibilityGranted;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('is_accessibility_enabled', accessibilityGranted);
    } catch (e) {}

    isLoading.value = false;
  }

  Future<void> requestAccessibility() async {
    try {
      await _channel.invokeMethod('openAccessibilitySettings');
    } catch (e) {}
  }

  Future<void> requestNotification() async {
    final status = await Permission.notification.request();
    hasNotificationPermission.value = status.isGranted;
    await checkPermissions();
  }

  Future<void> requestUsage() async {
    await UsageStats.grantUsagePermission();
  }

  Future<void> requestOverlay() async {
    await FlutterOverlayWindow.requestPermission();
  }

  bool get allPermissionsGranted =>
      hasNotificationPermission.value &&
      hasUsagePermission.value &&
      hasOverlayPermission.value;

  Future<void> finishSetup() async {
    if (!allPermissionsGranted) return;

    isLoading.value = true;
    final service = FlutterBackgroundService();
    await service.startService();

    Get.offAll(() => const MainTabScreen());
  }
}
