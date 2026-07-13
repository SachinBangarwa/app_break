import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:installed_apps/installed_apps.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../localSaver/localSaver.dart';

class AppRestrictOverlay extends StatefulWidget {
  final String initialPackageName;
  final String initialAppName;
  final int initialDelaySeconds;

  const AppRestrictOverlay({
    super.key,
    this.initialPackageName = "",
    this.initialAppName = "this application",
    this.initialDelaySeconds = 10,
  });

  @override
  State<AppRestrictOverlay> createState() => _AppRestrictOverlayState();
}

class _AppRestrictOverlayState extends State<AppRestrictOverlay> {
  int _secondsRemaining = 10;
  Timer? _timer;
  String _appName = "this application";
  String _launchOnDismissPackage = "";

  @override
  void initState() {
    super.initState();
    _appName = widget.initialAppName;
    _secondsRemaining = widget.initialDelaySeconds;
    _loadOverlayData();
    _startCountdown();
  }

  @override
  void didUpdateWidget(covariant AppRestrictOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialAppName != oldWidget.initialAppName) {
      setState(() {
        _appName = widget.initialAppName;
      });
    }
  }

  Future<void> _loadOverlayData() async {
    await UsageDataSaver.reload();
    final prefs = await SharedPreferences.getInstance();
    final activePackage = prefs.getString('active_restrict_package') ?? '';
    final activeName = await UsageDataSaver.getAppName(activePackage);
    final launchPkg = prefs.getString('launch_on_dismiss_package') ?? '';
    final delaySeconds = prefs.getInt('delay_seconds_$activePackage') ?? widget.initialDelaySeconds;

    setState(() {
      _launchOnDismissPackage = launchPkg;
      _secondsRemaining = delaySeconds;
      if (activeName.isNotEmpty && activeName != activePackage) {
        _appName = activeName;
      }
    });
  }

  void _startCountdown() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsRemaining <= 1) {
        timer.cancel();
        _closeOverlay();
      } else {
        setState(() {
          _secondsRemaining--;
        });
      }
    });
  }

  Future<void> _closeOverlay() async {
    _timer?.cancel();
    if (_launchOnDismissPackage.isNotEmpty) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('launch_on_dismiss_package');
        await InstalledApps.startApp(_launchOnDismissPackage);
      } catch (e) {
        debugPrint("Error starting app on dismiss: $e");
      }
    }
    await FlutterOverlayWindow.closeOverlay();
  }

  Future<void> _goHome() async {
    _timer?.cancel();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('last_restricted_package');
      await prefs.remove('last_restricted_time');
    } catch (e) {
      debugPrint("Error clearing restrict package on close: $e");
    }

    if (_launchOnDismissPackage.isNotEmpty) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('launch_on_dismiss_package');
      } catch (e) {
        debugPrint("Error clearing launch package: $e");
      }
    } else {
      try {
        await InstalledApps.startApp("com.example.testproject");
        await Future.delayed(const Duration(milliseconds: 300));
      } catch (e) {
        debugPrint("Error going home from restrict close: $e");
      }
    }
    await FlutterOverlayWindow.closeOverlay();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0C1D), // Solid background, nothing visible underneath
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Spacer(),

            // Circular Glowing Progress Timer
            Stack(
              alignment: Alignment.center,
              children: [
                // Outer Glow effect
                Container(
                  width: 140,
                  height: 140,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.deepPurpleAccent.withValues(alpha: 0.2),
                        blurRadius: 30,
                        spreadRadius: 10,
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  width: 130,
                  height: 130,
                  child: CircularProgressIndicator(
                    value: _secondsRemaining / 10,
                    strokeWidth: 8,
                    backgroundColor: Colors.white.withValues(alpha: 0.05),
                    valueColor: const AlwaysStoppedAnimation<Color>(Colors.deepPurpleAccent),
                  ),
                ),
                Text(
                  '$_secondsRemaining',
                  style: const TextStyle(
                    fontSize: 48,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: -1,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 48),

            // Warning Title
            const Text(
              'Focus Pause',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 16),

            // Description
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Text(
                'Taking a mindful 10-second break before opening $_appName.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey.shade400,
                  height: 1.5,
                ),
              ),
            ),

            const Spacer(),

            // Action Buttons at the bottom
            Row(
              children: [
                // Close Button
                Expanded(
                  child: OutlinedButton(
                    onPressed: _goHome,
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 18),
                    ),
                    child: const Text(
                      'Close',
                      style: TextStyle(
                        color: Colors.white70,
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),

                // OK Button
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Colors.deepPurpleAccent, Colors.purpleAccent],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.deepPurpleAccent.withValues(alpha: 0.3),
                          blurRadius: 15,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: ElevatedButton(
                      onPressed: _closeOverlay,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 18),
                      ),
                      child: const Text(
                        'OK',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
