import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:usage_stats/usage_stats.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:testproject/device_app/screens/home_screen.dart';

class OnboardingController extends GetxController with WidgetsBindingObserver {
  final hasNotificationPermission = false.obs;
  final hasUsagePermission = false.obs;
  final hasOverlayPermission = false.obs;
  final isLoading = true.obs;

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

    hasNotificationPermission.value = notifGranted;
    hasUsagePermission.value = usageGranted;
    hasOverlayPermission.value = overlayGranted;
    isLoading.value = false;
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
    
    Get.offAll(() => const HomeScreen());
  }
}
