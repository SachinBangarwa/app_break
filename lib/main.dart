import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:usage_stats/usage_stats.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:testproject/device_app/screens/home_screen.dart';
import 'package:testproject/device_app/screens/onboarding_screen.dart';
import 'package:testproject/screens/main_tab_screen.dart';
import 'package:testproject/device_app/service/app_limit_service.dart';
import 'package:testproject/device_app/screens/overlay_dispatcher.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  //await AppLimitService.initializeService();

  // Check initial permissions
  final hasNotification = await Permission.notification.isGranted;
  final hasUsage = await UsageStats.checkUsagePermission() ?? false;
  final hasOverlay = await FlutterOverlayWindow.isPermissionGranted();

  final showOnboarding = !hasNotification || !hasUsage || !hasOverlay;

  runApp(MyApp(showOnboarding: showOnboarding));
}

// Overlay Entry Point
@pragma("vm:entry-point")
void overlayMain() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: OverlayDispatcher(),
    ),
  );
}

class MyApp extends StatelessWidget {
  final bool showOnboarding;
  const MyApp({super.key, required this.showOnboarding});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'Device Hub',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: showOnboarding ? const OnboardingScreen() : const MainTabScreen(),
    );
  }
}

