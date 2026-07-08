import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:testproject/device_app/localSaver/db_helper.dart';
import 'package:testproject/device_app/localSaver/localSaver.dart';

class NotificationsController extends GetxController with WidgetsBindingObserver {
  static const _channel = MethodChannel('com.example.testproject/package_change');

  final hasPermission = false.obs;
  final isSaverEnabled = true.obs;
  final notifications = <Map<String, dynamic>>[].obs;
  final isLoading = false.obs;

  @override
  void onInit() {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);
    checkPermissionStatus();
    loadSaverState();
    loadNotifications();
  }

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    super.onClose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      checkPermissionStatus();
      loadNotifications();
    }
  }

  Future<void> checkPermissionStatus() async {
    try {
      final bool granted = await _channel.invokeMethod('checkNotificationListenerPermission') ?? false;
      hasPermission.value = granted;
    } catch (e) {
      print("Error checking notification permission: $e");
    }
  }

  Future<void> requestPermission() async {
    try {
      await _channel.invokeMethod('openNotificationListenerSettings');
    } catch (e) {
      print("Error requesting notification permission: $e");
    }
  }

  Future<void> loadSaverState() async {
    isSaverEnabled.value = await UsageDataSaver.isNotificationSaverEnabled();
  }

  Future<void> toggleSaver(bool value) async {
    isSaverEnabled.value = value;
    await UsageDataSaver.saveNotificationSaverEnabled(value);
  }

  Future<void> loadNotifications() async {
    isLoading.value = true;
    try {
      final list = await AppDbHelper.instance.getNotifications();
      notifications.assignAll(list);
    } catch (e) {
      print("Error loading notifications: $e");
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> clearNotifications() async {
    try {
      await AppDbHelper.instance.clearAllNotifications();
      notifications.clear();
    } catch (e) {
      print("Error clearing notifications: $e");
    }
  }

  Future<void> launchNotification(int id, String packageName) async {
    try {
      await _channel.invokeMethod('launchNotificationIntent', {
        'id': id,
        'packageName': packageName,
      });
    } catch (e) {
      print("Error launching notification: $e");
    }
  }
}
